#!/usr/bin/env python3
"""Request shim for local Bonsai (llama-server).

Fixes two client/server protocol gaps:

1. Claude Code (Anthropic /v1/messages) — see normalize() below.
2. OMP (OpenAI /v1/responses) — see normalize_responses() below.

Claude Code injects its system reminders as a `system`-role entry inside
`messages`, after the first user turn. The Qwen3.8 chat template that
Ternary-Bonsai-2-27B ships raises "System message must be at the beginning"
and llama-server answers 500. This proxy lifts every stray system-role
message into the request's top-level `system` field, then forwards
everything else untouched, streaming included.

Listens on 127.0.0.1:8090 by default; forwards to $BONSAI_UPSTREAM.
"""
import http.server
import hmac
import io
import json
import os
import socketserver
import sys
import threading
import time
import urllib.error
import urllib.request

UPSTREAM = os.environ.get("BONSAI_UPSTREAM", "http://127.0.0.1:8080").rstrip("/")
KEY = os.environ.get("BONSAI_KEY", "")
LISTEN = (os.environ.get("BONSAI_PROXY_HOST", "127.0.0.1"),
          int(os.environ.get("BONSAI_PROXY_PORT", "8090")))

# ---- KV pool admission control ---------------------------------------------
# llama-server runs ONE unified KV pool (-c 200000 -kvu) shared by every slot,
# while each slot advertises the full size. Two large sessions oversubscribe it
# and llama.cpp then kills BOTH in-flight requests with
# "Context size has been exceeded." Measured 2026-09-19: a 38930-token request
# died beside a 163842-token one, 202772 against a 200192-cell pool.
#
# Rather than capping any client's context, gate admission here: hold a request
# until its tokens fit alongside what is already in flight. Requests that fit
# together still run in parallel, so subagent fan-out is unaffected.
BUDGET = int(os.environ.get("BONSAI_KV_BUDGET", "196000"))
WAIT_TIMEOUT = float(os.environ.get("BONSAI_KV_WAIT", "900"))
# `gaming on` stops llama-server and leaves this proxy up. While its state file
# exists, every request gets 503 with a game_mode error, so clients on both
# machines learn why Bonsai is down instead of seeing a refused port.
GAMING_STATE = os.environ.get("BONSAI_GAMING_STATE") or os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid(), "gaming", "state")
INFER_PATHS = ("/v1/chat/completions", "/v1/messages", "/v1/completions",
               "/v1/responses", "/chat/completions", "/completion")


class KVBudget:
    """Token budget for the shared KV pool.

    Not a mutex: several small requests hold it at once. A request larger than
    the whole budget waits for an empty pool and then runs alone, so it can
    never deadlock against itself.
    """

    def __init__(self, total):
        self.total = total
        self.used = 0
        self.cond = threading.Condition()

    def acquire(self, cost):
        deadline = time.monotonic() + WAIT_TIMEOUT
        with self.cond:
            while True:
                if self.used == 0 or self.used + cost <= self.total:
                    self.used += cost
                    return True
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    # Never hang a client forever. Admit and let llama-server
                    # arbitrate, which is the pre-patch behaviour.
                    self.used += cost
                    sys.stderr.write(
                        "kv-budget: wait timeout, admitting %d (used %d/%d)\n"
                        % (cost, self.used, self.total))
                    return False
                self.cond.wait(remaining)

    def release(self, cost):
        with self.cond:
            self.used = max(0, self.used - cost)
            self.cond.notify_all()


BUDGET_GATE = KVBudget(BUDGET)


class InFlight:
    """Gated requests between arrival and the end of their relay.

    With -np 1 llama-server decodes one request at a time and queues the rest
    itself, so the oldest in-flight request is taken as the running one.
    """

    def __init__(self):
        self.lock = threading.Lock()
        self.started = {}
        self.next_id = 0

    def enter(self):
        with self.lock:
            self.next_id += 1
            self.started[self.next_id] = time.monotonic()
            return self.next_id

    def leave(self, rid):
        with self.lock:
            self.started.pop(rid, None)

    def snapshot(self):
        now = time.monotonic()
        with self.lock:
            ages = sorted((now - t for t in self.started.values()), reverse=True)
        return {"depth": max(0, len(ages) - 1),
                "running_age_s": round(ages[0], 1) if ages else None,
                "oldest_waiting_age_s": round(ages[1], 1) if len(ages) > 1 else None}


IN_FLIGHT = InFlight()


def game_mode_since():
    """Epoch when game mode went on, or None when it is off."""
    try:
        with open(GAMING_STATE) as fh:
            for line in fh:
                if line.startswith("since="):
                    return int(line[6:].strip() or 0)
        return 0
    except (OSError, ValueError):
        return None


def upstream_up():
    """A stale game mode state file must not block a running llama-server."""
    try:
        with urllib.request.urlopen(UPSTREAM + "/health", timeout=1) as resp:
            return resp.status == 200
    except Exception:
        return False


def count_tokens(raw):
    """Exact prompt size from llama-server's /tokenize.

    Measured 114 ms for 150k tokens, negligible against generation. Tokenizing
    the raw JSON slightly overcounts (role keys, punctuation), which errs toward
    queueing rather than toward a crash.
    """
    try:
        req = urllib.request.Request(
            UPSTREAM + "/tokenize",
            data=json.dumps({"content": raw.decode("utf-8", "replace")}).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": "Bearer " + KEY})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return len(json.load(resp).get("tokens", []))
    except Exception:
        return len(raw) // 3  # conservative fallback, real text is ~3.4 ch/tok


def reserve_for(payload):
    """Generated tokens occupy KV cells too, so reserve them with the prompt."""
    if isinstance(payload, dict):
        for field in ("max_tokens", "max_completion_tokens", "n_predict"):
            value = payload.get(field)
            if isinstance(value, int) and value > 0:
                return min(value, 32768)
    return 4096


def text_of(content):
    """Flatten Anthropic content (string or block list) to plain text."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text")
    return ""


def normalize_responses(payload):
    """Strip non-text parts out of function_call_output items.

    llama-server's Responses implementation accepts only `input_text` inside a
    `function_call_output` and answers 400 "Output of tool call should be
    'Input text'" for anything else. OMP emits an `input_image` part whenever a
    tool returns binary data (e.g. a shell command that cats an ELF file). The
    bad item stays in the conversation history, so once it appears every later
    turn in that session fails too, and the session is dead.

    Replace the non-text parts with a marker so the turn survives.
    """
    items = payload.get("input")
    if not isinstance(items, list):
        return payload
    for item in items:
        if not isinstance(item, dict) or item.get("type") != "function_call_output":
            continue
        out = item.get("output")
        if not isinstance(out, list):
            continue
        keep, dropped = [], 0
        for part in out:
            if isinstance(part, dict) and part.get("type") == "input_text":
                keep.append(part)
            else:
                dropped += 1
        if dropped:
            kind = "output" if keep else "binary or image output"
            keep.append({"type": "input_text",
                         "text": f"[{dropped} non-text part(s) of this tool {kind} omitted]"})
            item["output"] = keep
    return payload


def normalize(payload):
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return payload

    strays = [m for m in messages if m.get("role") == "system"]
    if not strays:
        return payload

    payload["messages"] = [m for m in messages if m.get("role") != "system"]

    system = payload.get("system")
    blocks = []
    if isinstance(system, str) and system:
        blocks.append({"type": "text", "text": system})
    elif isinstance(system, list):
        blocks.extend(system)
    for m in strays:
        t = text_of(m.get("content"))
        if t:
            blocks.append({"type": "text", "text": t})
    payload["system"] = blocks
    return payload


def normalize_chat(payload):
    """OpenAI /v1/chat/completions: merge every system message into one leading
    system message.

    normalize() lifts system messages into a top-level `system` field, which only
    the Anthropic endpoint reads, so on chat completions it dropped the system
    prompt silently. Verified 2026-09-22: `bonsai.sh -s` was ignored 2 of 2.
    The chat template accepts a system message only in first position.
    """
    messages = payload.get("messages")
    if not isinstance(messages, list):
        return payload
    systems = [m for m in messages if isinstance(m, dict) and m.get("role") == "system"]
    if not systems or (len(systems) == 1 and messages[0] is systems[0]):
        return payload
    text = "\n\n".join(t for t in (text_of(m.get("content")) for m in systems) if t)
    rest = [m for m in messages if not (isinstance(m, dict) and m.get("role") == "system")]
    payload["messages"] = ([{"role": "system", "content": text}] if text else []) + rest
    return payload


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _authed(self):
        """Require the same key llama-server requires.

        The proxy listens on the tailnet and injects the upstream key itself,
        so without this check any tailnet host could use the model unauthenticated
        -- weaker than talking to llama-server directly. Accept the OpenAI
        `Authorization: Bearer` header or the Anthropic `x-api-key` header.
        """
        if not KEY:
            return True
        sent = self.headers.get("Authorization", "")
        if sent.startswith("Bearer "):
            sent = sent[7:]
        else:
            sent = self.headers.get("x-api-key", "")
        if hmac.compare_digest(sent, KEY):
            return True
        body = b'{"error":{"message":"Invalid API Key","type":"authentication_error"}}'
        self.send_response(401)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        self.wfile.write(body)
        return False

    def _game_mode(self):
        since = game_mode_since()
        if since is None or upstream_up():
            return False
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(since)) if since else "unknown"
        msg = ("Bonsai is unavailable: the user turned on game mode on archpc "
               "(since %s), which stops llama-server to free the GPU. Use another "
               "model; Bonsai returns when the user runs `gaming off`." % when)
        body = json.dumps({"type": "error",
                           "error": {"type": "game_mode", "message": msg,
                                     "since": since or None}}).encode()
        self.send_response(503)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Retry-After", "600")
        self.end_headers()
        self.wfile.write(body)
        return True

    def _forward(self, body):
        req = urllib.request.Request(
            UPSTREAM + self.path, data=body,
            headers={"Content-Type": "application/json",
                     "Authorization": "Bearer " + KEY,
                     "Accept": self.headers.get("Accept", "*/*")},
            method=self.command)
        try:
            return urllib.request.urlopen(req, timeout=1800), None
        except urllib.error.HTTPError as exc:
            return None, exc
        except (urllib.error.URLError, OSError) as exc:
            reason = getattr(exc, "reason", exc)
            body = json.dumps({"error": {"message": "Bonsai upstream unreachable: %s" % reason,
                                         "type": "upstream_unavailable"}}).encode()
            return None, urllib.error.HTTPError(req.full_url, 502, "Bad Gateway", {}, io.BytesIO(body))

    def _relay(self, resp):
        self.send_response(resp.status)
        ctype = resp.headers.get("Content-Type", "application/json")
        self.send_header("Content-Type", ctype)
        # llama-server streams SSE with no length; relay chunked.
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        while True:
            chunk = resp.read(8192)
            if not chunk:
                break
            self.wfile.write(b"%X\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def do_POST(self):
        if not self._authed():
            return
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        if self._game_mode():
            return
        payload = None  # stays None when the body is not JSON we understand
        try:
            payload = json.loads(raw)
            if self.path.startswith("/v1/responses"):
                payload = normalize_responses(payload)
            elif self.path.startswith("/v1/chat/completions"):
                payload = normalize_chat(payload)
            else:
                payload = normalize(payload)
            raw = json.dumps(payload).encode()
        except (ValueError, TypeError):
            pass  # not JSON we understand — forward verbatim

        gated = any(self.path.startswith(p) for p in INFER_PATHS)
        cost = 0
        if gated:
            rid = IN_FLIGHT.enter()
            try:
                cost = count_tokens(raw) + reserve_for(payload)
                BUDGET_GATE.acquire(cost)
            except BaseException:
                IN_FLIGHT.leave(rid)
                raise
        try:
            resp, err = self._forward(raw)
            if err is not None:
                body = err.read()
                self.send_response(err.code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            with resp:
                self._relay(resp)
        finally:
            # Release only after the body (SSE included) is fully relayed, so
            # the slot's cells are genuinely free before the next admission.
            if gated:
                BUDGET_GATE.release(cost)
                IN_FLIGHT.leave(rid)

    def do_GET(self):
        if not self._authed():
            return
        if self._game_mode():
            return
        if self.path.rstrip("/") == "/queue":
            body = json.dumps(IN_FLIGHT.snapshot()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        resp, err = self._forward(None)
        if err is not None:
            body = err.read()
            self.send_response(err.code)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        with resp:
            body = resp.read()
        self.send_response(resp.status)
        self.send_header("Content-Type", resp.headers.get("Content-Type", "application/json"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    Server(LISTEN, Handler).serve_forever()
