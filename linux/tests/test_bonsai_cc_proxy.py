"""Behavior tests for bonsai-cc-proxy. Run: python3 -m unittest linux/tests/test_bonsai_cc_proxy.py"""

import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROXY = Path(__file__).resolve().parents[1] / "bin" / "bonsai-cc-proxy.py"
KEY = "sekret-key"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def wait_until(cond, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if cond():
            return True
        time.sleep(0.02)
    return cond()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, body, ctype="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        srv = self.server
        path = self.path.split("?")[0]
        with srv.lock:
            srv.records.append(
                {"method": self.command, "path": path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body}
            )
        if self.command == "POST" and path == "/tokenize":
            self.reply(200, json.dumps({"tokens": [1] * srv.tokens}).encode())
            return
        if self.command == "GET" and path == "/health":
            self.reply(srv.health_status, b'{"status":"x"}')
            return
        with srv.lock:
            idx = srv.inference_count
            srv.inference_count += 1
        if srv.hook is not None and srv.hook(self, body, idx):
            return
        self.reply(200, json.dumps({"ok": True, "path": path}).encode())

    do_GET = handle_any
    do_POST = handle_any


class Upstream(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.lock = threading.Lock()
        self.records = []
        self.inference_count = 0
        self.tokens = 10
        self.health_status = 200
        self.hook = None
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self.server_address[1]

    def inference(self):
        with self.lock:
            return [r for r in self.records if r["path"] not in ("/tokenize", "/health")]


def call(port, method, path, body=None, headers=None, key=KEY, style="bearer"):
    h = dict(headers or {})
    if key is not None:
        if style == "bearer":
            h["Authorization"] = "Bearer " + key
        else:
            h["x-api-key"] = key
    if isinstance(body, (dict, list)):
        body = json.dumps(body).encode()
        h.setdefault("Content-Type", "application/json")
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    try:
        conn.request(method, path, body=body, headers=h)
        resp = conn.getresponse()
        data = resp.read()
        return resp.status, resp, data
    finally:
        conn.close()


class ProxyCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = os.path.join(self.tmp.name, "gaming-state")
        self.up = Upstream()
        self.addCleanup(self.stop_upstream)

    def stop_upstream(self):
        self.up.shutdown()
        self.up.server_close()

    def start(self, upstream_url=None, **extra):
        port = free_port()
        env = {
            "PATH": os.environ.get("PATH", ""),
            "HOME": self.tmp.name,
            "BONSAI_UPSTREAM": upstream_url or self.up.url,
            "BONSAI_KEY": KEY,
            "BONSAI_PROXY_HOST": "127.0.0.1",
            "BONSAI_PROXY_PORT": str(port),
            "BONSAI_KV_BUDGET": "1000000",
            "BONSAI_KV_WAIT": "5",
            "BONSAI_GAMING_STATE": self.state,
        }
        env.update(extra)
        log = open(os.path.join(self.tmp.name, "proxy-%d.log" % port), "w+")
        self.addCleanup(log.close)
        proc = subprocess.Popen(["python3", str(PROXY)], env=env, stdout=subprocess.DEVNULL, stderr=log)

        def stop():
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

        self.addCleanup(stop)
        end = time.time() + 5
        while time.time() < end:
            try:
                socket.create_connection(("127.0.0.1", port), timeout=0.2).close()
                return port
            except OSError:
                if proc.poll() is not None:
                    break
                time.sleep(0.05)
        log.seek(0)
        self.fail("proxy did not listen: " + log.read()[-2000:])

    def forwarded_json(self, port, path, body):
        status, _, _ = call(port, "POST", path, body)
        self.assertEqual(status, 200)
        recs = [r for r in self.up.inference() if r["path"] == path]
        self.assertEqual(len(recs), 1)
        return json.loads(recs[0]["body"])


class AuthTest(ProxyCase):
    def test_missing_key_gets_401_authentication_error_and_upstream_sees_nothing(self):
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []}, key=None)
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(data)["error"]["type"], "authentication_error")
        self.assertEqual(self.up.inference(), [])

    def test_wrong_key_gets_401_authentication_error_and_upstream_sees_nothing(self):
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []}, key="nope")
        self.assertEqual(status, 401)
        self.assertEqual(json.loads(data)["error"]["type"], "authentication_error")
        self.assertEqual(self.up.inference(), [])

    def test_wrong_key_on_get_is_rejected_without_reaching_upstream(self):
        port = self.start()
        status, _, _ = call(port, "GET", "/v1/models", key="nope")
        self.assertEqual(status, 401)
        self.assertEqual(self.up.inference(), [])

    def test_bearer_client_request_carries_bearer_upstream(self):
        port = self.start()
        status, _, _ = call(port, "POST", "/v1/chat/completions", {"messages": []}, style="bearer")
        self.assertEqual(status, 200)
        self.assertEqual(self.up.inference()[0]["headers"]["authorization"], "Bearer " + KEY)

    def test_x_api_key_client_is_accepted_and_upstream_gets_bearer(self):
        port = self.start()
        status, _, _ = call(port, "POST", "/v1/messages", {"messages": []}, style="x-api-key")
        self.assertEqual(status, 200)
        self.assertEqual(self.up.inference()[0]["headers"]["authorization"], "Bearer " + KEY)

    def test_two_wrong_key_posts_on_one_keepalive_connection_never_get_other_status(self):
        port = self.start()
        body = json.dumps({"messages": [{"role": "user", "content": "hi"}]}).encode()
        headers = {"Content-Type": "application/json", "Authorization": "Bearer wrong"}
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
        self.addCleanup(conn.close)
        for _ in range(2):
            try:
                conn.request("POST", "/v1/chat/completions", body=body, headers=headers)
                resp = conn.getresponse()
                resp.read()
                status = resp.status
            except (http.client.RemoteDisconnected, ConnectionError, http.client.BadStatusLine):
                conn.close()
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
                self.addCleanup(conn.close)
                conn.request("POST", "/v1/chat/completions", body=body, headers=headers)
                resp = conn.getresponse()
                resp.read()
                status = resp.status
            self.assertEqual(status, 401)
        self.assertEqual(self.up.inference(), [])

    def test_a_wrong_key_answer_closes_the_connection(self):
        port = self.start()
        status, resp, _ = call(port, "POST", "/v1/chat/completions", {"messages": []}, key="wrong")
        self.assertEqual(status, 401)
        self.assertEqual(resp.getheader("Connection"), "close")


class UpstreamFailureTest(ProxyCase):
    def test_closed_upstream_port_gives_502_upstream_unavailable_for_post_and_get(self):
        dead = "http://127.0.0.1:%d" % free_port()
        port = self.start(upstream_url=dead)
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []})
        self.assertEqual(status, 502)
        self.assertEqual(json.loads(data)["error"]["type"], "upstream_unavailable")
        status, _, data = call(port, "GET", "/v1/models")
        self.assertEqual(status, 502)
        self.assertEqual(json.loads(data)["error"]["type"], "upstream_unavailable")

    def test_upstream_500_body_passes_through_unchanged(self):
        def hook(h, body, idx):
            h.reply(500, b'{"error":"boom"}')
            return True

        self.up.hook = hook
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []})
        self.assertEqual(status, 500)
        self.assertEqual(json.loads(data), {"error": "boom"})


class AnthropicSystemTest(ProxyCase):
    def test_system_messages_move_into_system_blocks_after_string_system(self):
        port = self.start()
        body = {
            "model": "m",
            "system": "base",
            "messages": [
                {"role": "user", "content": "hello"},
                {"role": "system", "content": "s1"},
                {
                    "role": "system",
                    "content": [
                        {"type": "text", "text": "a"},
                        {"type": "image", "source": {}},
                        {"type": "text", "text": "b"},
                    ],
                },
                {"role": "assistant", "content": "yo"},
            ],
        }
        got = self.forwarded_json(port, "/v1/messages", body)
        self.assertEqual(
            got["system"],
            [
                {"type": "text", "text": "base"},
                {"type": "text", "text": "s1"},
                {"type": "text", "text": "a\nb"},
            ],
        )
        self.assertEqual(
            got["messages"],
            [{"role": "user", "content": "hello"}, {"role": "assistant", "content": "yo"}],
        )
        self.assertEqual(got["model"], "m")

    def test_system_messages_append_after_existing_block_list_system(self):
        port = self.start()
        body = {
            "system": [{"type": "text", "text": "first"}, {"type": "text", "text": "second"}],
            "messages": [{"role": "system", "content": "extra"}, {"role": "user", "content": "q"}],
        }
        got = self.forwarded_json(port, "/v1/messages", body)
        self.assertEqual(
            got["system"],
            [
                {"type": "text", "text": "first"},
                {"type": "text", "text": "second"},
                {"type": "text", "text": "extra"},
            ],
        )
        self.assertEqual(got["messages"], [{"role": "user", "content": "q"}])

    def test_system_message_without_top_level_system_creates_it(self):
        port = self.start()
        body = {"messages": [{"role": "system", "content": "only"}, {"role": "user", "content": "q"}]}
        got = self.forwarded_json(port, "/v1/messages", body)
        self.assertEqual(got["system"], [{"type": "text", "text": "only"}])
        self.assertEqual(got["messages"], [{"role": "user", "content": "q"}])

    def test_body_without_system_messages_reaches_upstream_unchanged(self):
        port = self.start()
        body = {
            "model": "m",
            "system": "keep as string",
            "max_tokens": 50,
            "messages": [{"role": "user", "content": [{"type": "text", "text": "hi"}]}],
        }
        got = self.forwarded_json(port, "/v1/messages", body)
        self.assertEqual(got, body)


class ChatCompletionsSystemTest(ProxyCase):
    def test_scattered_system_messages_merge_into_one_leading_message_keeping_other_order(self):
        port = self.start()
        body = {
            "messages": [
                {"role": "user", "content": "u1"},
                {"role": "system", "content": "s1"},
                {"role": "assistant", "content": "a1"},
                {"role": "system", "content": "s2"},
                {"role": "user", "content": "u2"},
            ]
        }
        got = self.forwarded_json(port, "/v1/chat/completions", body)
        self.assertEqual(
            got["messages"],
            [
                {"role": "system", "content": "s1\n\ns2"},
                {"role": "user", "content": "u1"},
                {"role": "assistant", "content": "a1"},
                {"role": "user", "content": "u2"},
            ],
        )

    def test_leading_system_plus_later_system_merge_in_order(self):
        port = self.start()
        body = {
            "messages": [
                {"role": "system", "content": "first"},
                {"role": "user", "content": "u"},
                {"role": "system", "content": "late"},
            ]
        }
        got = self.forwarded_json(port, "/v1/chat/completions", body)
        self.assertEqual(
            got["messages"],
            [{"role": "system", "content": "first\n\nlate"}, {"role": "user", "content": "u"}],
        )

    def test_single_leading_system_message_is_left_as_is(self):
        port = self.start()
        body = {
            "model": "m",
            "messages": [{"role": "system", "content": "only"}, {"role": "user", "content": "u"}],
        }
        got = self.forwarded_json(port, "/v1/chat/completions", body)
        self.assertEqual(got, body)


class ResponsesTest(ProxyCase):
    def test_non_text_parts_removed_and_count_note_appended_when_text_remains(self):
        port = self.start()
        body = {
            "input": [
                {
                    "type": "function_call_output",
                    "call_id": "c1",
                    "output": [
                        {"type": "input_text", "text": "hello"},
                        {"type": "input_image", "image_url": "x"},
                        {"type": "input_image", "image_url": "y"},
                    ],
                }
            ]
        }
        got = self.forwarded_json(port, "/v1/responses", body)
        item = got["input"][0]
        self.assertEqual(item["call_id"], "c1")
        self.assertEqual(
            item["output"],
            [
                {"type": "input_text", "text": "hello"},
                {"type": "input_text", "text": "[2 non-text part(s) of this tool output omitted]"},
            ],
        )

    def test_binary_wording_used_when_no_text_part_remains(self):
        port = self.start()
        body = {
            "input": [
                {
                    "type": "function_call_output",
                    "call_id": "c1",
                    "output": [{"type": "input_image", "image_url": "x"}],
                }
            ]
        }
        got = self.forwarded_json(port, "/v1/responses", body)
        self.assertEqual(
            got["input"][0]["output"],
            [
                {
                    "type": "input_text",
                    "text": "[1 non-text part(s) of this tool binary or image output omitted]",
                }
            ],
        )

    def test_other_item_types_and_string_outputs_are_untouched(self):
        port = self.start()
        body = {
            "input": [
                {
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_image", "image_url": "keep"}],
                },
                {"type": "function_call_output", "call_id": "c2", "output": "plain string"},
                {
                    "type": "function_call_output",
                    "call_id": "c3",
                    "output": [{"type": "input_text", "text": "all text"}],
                },
            ]
        }
        got = self.forwarded_json(port, "/v1/responses", body)
        self.assertEqual(got, body)


class ResponsesItemTypeTest(ProxyCase):
    def test_only_function_call_outputs_lose_their_non_text_parts(self):
        image = {"type": "input_image", "image_url": "data:image/png;base64,AAAA"}
        body = {"input": [{"type": "custom_tool_call_output", "output": [image]}]}
        port = self.start()
        got = self.forwarded_json(port, "/v1/responses", body)
        self.assertEqual(got["input"][0]["output"], [image])


class OddMessagesTest(ProxyCase):
    def test_a_message_list_with_a_non_object_keeps_that_element(self):
        body = {"messages": ["hi", {"role": "system", "content": "be brief"}]}
        port = self.start()
        got = self.forwarded_json(port, "/v1/messages", body)
        self.assertIn("hi", got["messages"])


class PassthroughTest(ProxyCase):
    def test_non_json_body_is_forwarded_byte_for_byte(self):
        port = self.start()
        raw = b"\xff\xfe not json \x00\r\n{broken"
        status, _, _ = call(
            port, "POST", "/v1/chat/completions", raw, headers={"Content-Type": "application/json"}
        )
        self.assertEqual(status, 200)
        self.assertEqual(self.up.inference()[0]["body"], raw)

    def test_json_that_is_not_an_object_is_forwarded_byte_for_byte(self):
        port = self.start()
        for path, raw in (("/v1/chat/completions", b"[]"), ("/v1/responses", b"null"), ("/v1/completions", b"[1, 2]")):
            with self.subTest(path=path):
                status, _, _ = call(port, "POST", path, raw, headers={"Content-Type": "application/json"})
                self.assertEqual(status, 200)
                self.assertEqual(self.up.inference()[-1]["body"], raw)

    def test_get_is_forwarded_to_same_path_upstream(self):
        port = self.start()
        status, _, data = call(port, "GET", "/v1/models")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data)["path"], "/v1/models")
        rec = self.up.inference()[0]
        self.assertEqual((rec["method"], rec["path"]), ("GET", "/v1/models"))


class StreamingTest(ProxyCase):
    def test_sse_chunks_all_arrive_in_order_and_response_is_chunked(self):
        def hook(h, body, idx):
            h.send_response(200)
            h.send_header("Content-Type", "text/event-stream")
            h.send_header("Transfer-Encoding", "chunked")
            h.end_headers()
            for text in ("data: one\n\n", "data: two\n\n", "data: three\n\n"):
                data = text.encode()
                h.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))
                h.wfile.flush()
                time.sleep(0.1)
            h.wfile.write(b"0\r\n\r\n")
            h.wfile.flush()
            return True

        self.up.hook = hook
        port = self.start()
        status, resp, data = call(port, "POST", "/v1/chat/completions", {"stream": True, "messages": []})
        self.assertEqual(status, 200)
        self.assertEqual(resp.getheader("Transfer-Encoding"), "chunked")
        self.assertIn("text/event-stream", resp.getheader("Content-Type"))
        self.assertEqual(data, b"data: one\n\ndata: two\n\ndata: three\n\n")

    def test_first_sse_chunk_reaches_the_client_before_the_upstream_sends_the_next(self):
        seen = threading.Event()

        def hook(h, body, idx):
            h.send_response(200)
            h.send_header("Content-Type", "text/event-stream")
            h.send_header("Transfer-Encoding", "chunked")
            h.end_headers()
            for text in ("data: one\n\n", "data: two\n\n"):
                data = text.encode()
                h.wfile.write(b"%x\r\n%s\r\n" % (len(data), data))
                h.wfile.flush()
                seen.wait(5)
            h.wfile.write(b"0\r\n\r\n")
            h.wfile.flush()
            return True

        self.up.hook = hook
        port = self.start()
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        self.addCleanup(conn.close)
        conn.request("POST", "/v1/chat/completions", body=json.dumps({"stream": True, "messages": []}),
                     headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
        resp = conn.getresponse()
        try:
            first = resp.read1(1024)
        finally:
            seen.set()
        self.assertEqual(first, b"data: one\n\n")
        self.assertEqual(resp.read(), b"data: two\n\n")


class GameModeTest(ProxyCase):
    def write_state(self):
        Path(self.state).write_text("since=1700000000\n")

    def test_state_file_with_unhealthy_upstream_gives_503_game_mode_for_post_and_get(self):
        self.write_state()
        self.up.health_status = 503
        port = self.start()
        for method, path, body in (
            ("POST", "/v1/chat/completions", {"messages": []}),
            ("GET", "/v1/models", None),
        ):
            status, resp, data = call(port, method, path, body)
            self.assertEqual(status, 503, method)
            err = json.loads(data)["error"]
            self.assertEqual(err["type"], "game_mode")
            self.assertEqual(err["since"], 1700000000)
            self.assertIsNotNone(resp.getheader("Retry-After"))
        self.assertEqual(self.up.inference(), [])

    def test_stale_state_file_with_healthy_upstream_does_not_block(self):
        self.write_state()
        self.up.health_status = 200
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []})
        self.assertEqual(status, 200)
        self.assertTrue(json.loads(data)["ok"])
        status, _, _ = call(port, "GET", "/v1/models")
        self.assertEqual(status, 200)
        self.assertEqual(len(self.up.inference()), 2)

    def test_a_state_file_without_a_since_line_reports_an_unknown_start(self):
        with open(self.state, "w") as fh:
            fh.write("on\n")
        self.up.health_status = 503
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []})
        self.assertEqual(status, 503)
        err = json.loads(data)["error"]
        self.assertIsNone(err["since"])
        self.assertIn("since unknown", err["message"])

    def test_unhealthy_upstream_without_state_file_is_not_game_mode(self):
        self.up.health_status = 503
        port = self.start()
        status, _, data = call(port, "POST", "/v1/chat/completions", {"messages": []})
        self.assertEqual(status, 200)
        self.assertEqual(len(self.up.inference()), 1)


class AdmissionTest(ProxyCase):
    BODY = {"max_tokens": 100, "messages": [{"role": "user", "content": "hi"}]}

    def setup_gate(self):
        self.gate = threading.Event()
        self.arrivals = []

        def hook(h, body, idx):
            self.arrivals.append((idx, time.time()))
            if idx == 0:
                self.gate.wait(15)
            return False

        self.up.tokens = 600
        self.up.hook = hook
        self.addCleanup(self.gate.set)

    def finish(self, results, count):
        self.gate.set()
        self.assertTrue(wait_until(lambda: len(results) == count, 10))

    def send_async(self, port, results, name):
        def run():
            results[name] = call(port, "POST", "/v1/chat/completions", self.BODY)[0]

        t = threading.Thread(target=run, daemon=True)
        t.start()
        return t

    def test_second_request_waits_for_budget_then_proceeds_after_first_finishes(self):
        self.setup_gate()
        port = self.start(BONSAI_KV_BUDGET="1000", BONSAI_KV_WAIT="60")
        results = {}
        t1 = self.send_async(port, results, "first")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))
        t2 = self.send_async(port, results, "second")
        time.sleep(1.0)
        self.assertEqual(len(self.up.inference()), 1)
        self.assertNotIn("second", results)
        released = time.time()
        self.gate.set()
        self.assertTrue(wait_until(lambda: len(self.arrivals) == 2, 3))
        t1.join(10)
        t2.join(10)
        self.assertEqual(results, {"first": 200, "second": 200})
        self.assertLess(self.arrivals[1][1] - released, 10)

    def test_second_request_is_admitted_after_kv_wait_even_though_first_still_runs(self):
        self.setup_gate()
        port = self.start(BONSAI_KV_BUDGET="1000", BONSAI_KV_WAIT="0.5")
        results = {}
        self.send_async(port, results, "first")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))
        sent = time.time()
        self.send_async(port, results, "second")
        self.assertTrue(wait_until(lambda: len(self.arrivals) == 2, 5))
        elapsed = self.arrivals[1][1] - sent
        self.assertGreaterEqual(elapsed, 0.35)
        self.assertLess(elapsed, 10.0)
        self.assertFalse(self.gate.is_set())
        self.finish(results, 2)

    def test_an_upstream_error_releases_the_budget_for_the_next_request(self):
        def hook(h, body, idx):
            if idx == 0:
                h.reply(500, b'{"error":"boom"}')
                return True
            return False

        self.up.tokens = 600
        self.up.hook = hook
        port = self.start(BONSAI_KV_BUDGET="1000", BONSAI_KV_WAIT="60")
        self.assertEqual(call(port, "POST", "/v1/chat/completions", self.BODY)[0], 500)
        started = time.time()
        self.assertEqual(call(port, "POST", "/v1/chat/completions", self.BODY)[0], 200)
        self.assertLess(time.time() - started, 10)

    def test_a_request_larger_than_the_whole_budget_runs_alone_without_waiting(self):
        self.up.tokens = 600
        port = self.start(BONSAI_KV_BUDGET="100", BONSAI_KV_WAIT="60")
        started = time.time()
        self.assertEqual(call(port, "POST", "/v1/chat/completions", self.BODY)[0], 200)
        self.assertLess(time.time() - started, 10)

    def second_runs_beside_first(self, budget, second_body):
        self.setup_gate()
        self.up.tokens = 10
        port = self.start(BONSAI_KV_BUDGET=str(budget), BONSAI_KV_WAIT="60")
        results = {}
        self.send_async(port, results, "first")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))

        def run():
            results["second"] = call(port, "POST", "/v1/chat/completions", second_body)[0]

        threading.Thread(target=run, daemon=True).start()
        admitted = wait_until(lambda: len(self.up.inference()) == 2, 3)
        self.finish(results, 2)
        return admitted

    def test_max_completion_tokens_sets_the_reservation(self):
        body = {"max_completion_tokens": 100, "messages": [{"role": "user", "content": "hi"}]}
        self.assertTrue(self.second_runs_beside_first(1000, body))

    def test_n_predict_sets_the_reservation(self):
        body = {"n_predict": 100, "messages": [{"role": "user", "content": "hi"}]}
        self.assertTrue(self.second_runs_beside_first(1000, body))

    def test_a_huge_output_length_is_capped_when_reserving(self):
        body = {"max_tokens": 1000000, "messages": [{"role": "user", "content": "hi"}]}
        self.assertTrue(self.second_runs_beside_first(40000, body))

    def test_queue_reports_a_waiting_request_and_the_running_age(self):
        self.setup_gate()
        port = self.start(BONSAI_KV_BUDGET="1000", BONSAI_KV_WAIT="60")
        results = {}
        self.send_async(port, results, "first")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))
        self.send_async(port, results, "second")
        self.assertTrue(wait_until(lambda: json.loads(call(port, "GET", "/queue")[2])["depth"] == 1, 5))
        time.sleep(0.3)
        queue = json.loads(call(port, "GET", "/queue")[2])
        self.assertGreaterEqual(queue["running_age_s"], 0.2)
        self.assertIsInstance(queue["oldest_waiting_age_s"], float)
        self.finish(results, 2)

    def test_requests_that_fit_the_budget_run_concurrently(self):
        self.setup_gate()
        self.up.tokens = 100
        port = self.start(BONSAI_KV_BUDGET="1000", BONSAI_KV_WAIT="60")
        results = {}
        self.send_async(port, results, "first")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))
        self.send_async(port, results, "second")
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 2, 2))
        self.finish(results, 2)


class QueueTest(ProxyCase):
    def test_idle_queue_reports_depth_zero_and_null_ages_and_is_not_forwarded(self):
        port = self.start()
        status, _, data = call(port, "GET", "/queue")
        self.assertEqual(status, 200)
        q = json.loads(data)
        self.assertEqual(q["depth"], 0)
        self.assertIsNone(q["running_age_s"])
        self.assertIsNone(q["oldest_waiting_age_s"])
        self.assertEqual([r for r in self.up.records if r["path"] == "/queue"], [])

    def test_running_age_is_a_number_while_a_request_is_blocked_upstream(self):
        gate = threading.Event()
        self.addCleanup(gate.set)

        def hook(h, body, idx):
            gate.wait(15)
            return False

        self.up.hook = hook
        port = self.start()
        t = threading.Thread(
            target=lambda: call(port, "POST", "/v1/chat/completions", {"messages": []}), daemon=True
        )
        t.start()
        self.assertTrue(wait_until(lambda: len(self.up.inference()) == 1))
        time.sleep(0.3)
        status, _, data = call(port, "GET", "/queue")
        self.assertEqual(status, 200)
        q = json.loads(data)
        self.assertIsInstance(q["running_age_s"], (int, float))
        self.assertNotIsInstance(q["running_age_s"], bool)
        self.assertEqual(q["depth"], 0)
        self.assertIsNone(q["oldest_waiting_age_s"])
        gate.set()
        t.join(10)
        self.assertTrue(
            wait_until(lambda: json.loads(call(port, "GET", "/queue")[2])["running_age_s"] is None, 3)
        )

    def test_queue_requires_the_key(self):
        port = self.start()
        status, _, _ = call(port, "GET", "/queue", key=None)
        self.assertEqual(status, 401)


if __name__ == "__main__":
    unittest.main()
