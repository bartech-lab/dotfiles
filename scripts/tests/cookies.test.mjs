import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../bin/cookies');
const IS_MAC = os.platform() === 'darwin';
const HEADER = '# Netscape HTTP Cookie File';
const WEBKIT_EPOCH = 11644473600;
const FAR = 4102444800;

const tmpDirs = [];

afterEach(() => {
  while (tmpDirs.length) {
    fs.rmSync(tmpDirs.pop(), { recursive: true, force: true });
  }
});

function sh(body) {
  return `#!/bin/sh\n${body}\n`;
}

function writeBin(dir, name, body) {
  const p = path.join(dir, name);
  fs.writeFileSync(p, sh(body), { mode: 0o755 });
  fs.chmodSync(p, 0o755);
}

function fakeTool(dir, name, log, { out = '', code = 0 } = {}) {
  const lines = [`echo "$@" >> '${log}'`];
  if (out) lines.push(`printf '%s\\n' '${out}'`);
  lines.push(`exit ${code}`);
  writeBin(dir, name, lines.join('\n'));
}

function mkEnv({ password = 'fakepass', secCode = 0, kwallet, secretTool } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cookies-test-'));
  tmpDirs.push(root);
  const home = path.join(root, 'home');
  const bin = path.join(root, 'bin');
  fs.mkdirSync(home, { recursive: true });
  fs.mkdirSync(bin, { recursive: true });
  const logs = {
    security: path.join(root, 'security.log'),
    kwallet: path.join(root, 'kwallet.log'),
    secret: path.join(root, 'secret.log'),
  };
  if (IS_MAC) {
    fakeTool(bin, 'security', logs.security, { out: secCode === 0 ? password : '', code: secCode });
  } else {
    fakeTool(bin, 'kwallet-query', logs.kwallet, kwallet || { out: password, code: 0 });
    fakeTool(bin, 'secret-tool', logs.secret, secretTool || { code: 1 });
  }
  return { root, home, bin, logs };
}

function dbPath(home, browser = 'chrome') {
  if (IS_MAC) {
    const dir = browser === 'brave'
      ? path.join('BraveSoftware', 'Brave-Browser')
      : path.join('Google', 'Chrome');
    return path.join(home, 'Library', 'Application Support', dir, 'Default', 'Cookies');
  }
  const dir = browser === 'brave'
    ? path.join('BraveSoftware', 'Brave-Browser')
    : 'google-chrome';
  return path.join(home, '.config', dir, 'Default', 'Cookies');
}

function encrypt(plain, password, iterations) {
  const key = crypto.pbkdf2Sync(password, 'saltysalt', iterations, 16, 'sha1');
  const cipher = crypto.createCipheriv('aes-128-cbc', key, Buffer.alloc(16, 0x20));
  return Buffer.concat([Buffer.from('v10'), cipher.update(plain), cipher.final()]);
}

function q(s) {
  return `'${String(s).replace(/'/g, "''")}'`;
}

function micros(unix, extra = 0) {
  return ((BigInt(unix) + BigInt(WEBKIT_EPOCH)) * 1000000n + BigInt(extra)).toString();
}

function makeDb(env, cookies, { browser = 'chrome', version = 24, password = 'fakepass', iterations } = {}) {
  const iter = iterations ?? (IS_MAC ? 1003 : 1);
  const file = dbPath(env.home, browser);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const stmts = [
    'CREATE TABLE meta(key TEXT, value TEXT);',
    `INSERT INTO meta VALUES('version', '${version}');`,
    'CREATE TABLE cookies(creation_utc INTEGER, host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, last_access_utc INTEGER, has_expires INTEGER, samesite INTEGER, source_scheme INTEGER, source_port INTEGER);',
  ];
  for (const c of cookies) {
    const host = c.host;
    let enc = c.enc;
    if (!enc) {
      const prefix = version >= 24 ? crypto.createHash('sha256').update(host).digest() : Buffer.alloc(0);
      enc = encrypt(Buffer.concat([prefix, Buffer.from(c.value)]), password, iter);
    }
    const session = c.expires === undefined || c.expires === null;
    const exp = session ? '0' : micros(c.expires, c.extra || 0);
    stmts.push(
      `INSERT INTO cookies VALUES(${micros(FAR - 1000)}, ${q(host)}, ${q(c.name)}, '', X'${enc.toString('hex')}', ${q(c.path ?? '/')}, ${exp}, ${c.secure ? 1 : 0}, ${c.httponly ? 1 : 0}, ${micros(FAR - 500)}, ${session ? 0 : 1}, 0, 2, 443);`,
    );
  }
  const r = spawnSync('sqlite3', [file], { input: stmts.join('\n'), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  return file;
}

function run(env, args) {
  const e = { ...process.env, HOME: env.home, PATH: `${env.bin}${path.delimiter}${process.env.PATH}` };
  delete e.XDG_CONFIG_HOME;
  const r = spawnSync(process.execPath, [SCRIPT, ...args], { env: e, encoding: 'utf8' });
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

function rows(stdout) {
  const lines = stdout.split('\n').filter((l) => l !== '');
  assert.equal(lines[0], HEADER);
  return lines.slice(1).map((l) => l.split('\t'));
}

function hosts(stdout) {
  return rows(stdout).map((r) => r[0]);
}

test('netscape output has header and exact fields per cookie in host_key,name order', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.example.org', name: 'b', value: 'v2', path: '/app', expires: FAR + 1, secure: false },
    { host: '.example.com', name: 'z', value: 'v3', path: '/z', expires: FAR + 2, secure: true },
    { host: '.example.com', name: 'a', value: 'v1', path: '/', expires: FAR, extra: 500000, secure: true },
  ]);
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.split('\n')[0], HEADER);
  assert.deepEqual(rows(r.stdout), [
    ['.example.com', 'TRUE', '/', 'TRUE', String(FAR), 'a', 'v1'],
    ['.example.com', 'TRUE', '/z', 'TRUE', String(FAR + 2), 'z', 'v3'],
    ['.example.org', 'TRUE', '/app', 'FALSE', String(FAR + 1), 'b', 'v2'],
  ]);
});

test('netscape include-subdomains flag follows the leading dot', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.dotted.com', name: 'a', value: 'v1', expires: FAR },
    { host: 'plain.com', name: 'a', value: 'v2', expires: FAR },
    { host: '.sub.plain.com', name: 'a', value: 'v3', expires: FAR },
  ]);
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  const flags = Object.fromEntries(rows(r.stdout).map((x) => [x[0], x[1]]));
  assert.deepEqual(flags, { '.dotted.com': 'TRUE', 'plain.com': 'FALSE', '.sub.plain.com': 'TRUE' });
});

test('session cookie is included by default with expiry 0', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.s.com', name: 'a', value: 'v1', expires: FAR },
    { host: '.s.com', name: 'sess', value: 'v2', expires: null },
  ]);
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout), [
    ['.s.com', 'TRUE', '/', 'FALSE', String(FAR), 'a', 'v1'],
    ['.s.com', 'TRUE', '/', 'FALSE', '0', 'sess', 'v2'],
  ]);
});

test('expired cookies are excluded by default and included with -e', () => {
  const env = mkEnv();
  const now = Math.floor(Date.now() / 1000);
  makeDb(env, [
    { host: '.t.com', name: 'future', value: 'v1', expires: now + 3600 },
    { host: '.t.com', name: 'past', value: 'v2', expires: now - 3600 },
  ]);
  const def = run(env, []);
  assert.equal(def.status, 0, def.stderr);
  assert.deepEqual(rows(def.stdout).map((x) => x[5]), ['future']);
  const all = run(env, ['-e']);
  assert.equal(all.status, 0, all.stderr);
  assert.deepEqual(rows(all.stdout).map((x) => x[5]), ['future', 'past']);
  const long = run(env, ['--expired']);
  assert.deepEqual(rows(long.stdout).map((x) => x[5]), ['future', 'past']);
});

test('meta version 24 strips the 32-byte hash prefix', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.v.com', name: 'a', value: 'abc', expires: FAR },
    { host: '.v.com', name: 'b', value: 'second-value', expires: FAR },
  ], { version: 24 });
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[6]), ['abc', 'second-value']);
});

test('meta version 23 does not strip any prefix', () => {
  const env = mkEnv();
  const long = '0123456789012345678901234567890123456789';
  makeDb(env, [
    { host: '.v.com', name: 'a', value: long, expires: FAR },
    { host: '.v.com', name: 'b', value: 'abc', expires: FAR },
  ], { version: 23 });
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[6]), [long, 'abc']);
});

test('-d example.com matches the host and its dotted form only', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: 'example.com', name: 'a', value: 'v1', expires: FAR },
    { host: '.example.com', name: 'a', value: 'v2', expires: FAR },
    { host: 'other.com', name: 'a', value: 'v3', expires: FAR },
    { host: '.notexample.com', name: 'a', value: 'v4', expires: FAR },
  ]);
  const r = run(env, ['-d', 'example.com']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(hosts(r.stdout), ['.example.com', 'example.com']);
});

test('-d .example.com matches the dotted host only', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: 'example.com', name: 'a', value: 'v1', expires: FAR },
    { host: '.example.com', name: 'a', value: 'v2', expires: FAR },
    { host: '.notexample.com', name: 'a', value: 'v4', expires: FAR },
  ]);
  const r = run(env, ['-d', '.example.com']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(hosts(r.stdout), ['.example.com']);
});

test('positional names filter cookies by name', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.p.com', name: 'a', value: '1', expires: FAR },
    { host: '.p.com', name: 'b', value: '2', expires: FAR },
    { host: '.p.com', name: 'c', value: '3', expires: FAR },
    { host: '.q.com', name: 'c', value: '4', expires: FAR },
    { host: '.q.com', name: 'd', value: '5', expires: FAR },
  ]);
  const r = run(env, ['a', 'c']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => [x[0], x[5], x[6]]), [
    ['.p.com', 'a', '1'],
    ['.p.com', 'c', '3'],
    ['.q.com', 'c', '4'],
  ]);
});

test('a domain containing a single quote does not error', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: "o'reilly.com", name: 'a', value: 'v1', expires: FAR },
    { host: 'other.com', name: 'a', value: 'v2', expires: FAR },
  ]);
  const r = run(env, ['-d', "o'reilly.com"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => [x[0], x[6]]), [["o'reilly.com", 'v1']]);
});

test('json output has documented fields, types and decrypted values', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.j.com', name: 'second', value: 'v2', path: '/x', expires: null, secure: false, httponly: false },
    { host: '.j.com', name: 'first', value: 'v1', path: '/', expires: FAR, secure: true, httponly: true },
  ]);
  const r = run(env, ['-f', 'json']);
  assert.equal(r.status, 0, r.stderr);
  const data = JSON.parse(r.stdout);
  assert.ok(Array.isArray(data));
  assert.equal(data.length, 2);
  const [first, second] = data;
  assert.equal(first.host_key, '.j.com');
  assert.equal(first.name, 'first');
  assert.equal(first.value, 'v1');
  assert.equal(first.path, '/');
  assert.equal(first.is_secure, true);
  assert.equal(first.is_httponly, true);
  assert.equal(first.has_expires, true);
  assert.ok('expires_utc' in first);
  assert.equal(second.name, 'second');
  assert.equal(second.value, 'v2');
  assert.equal(second.path, '/x');
  assert.equal(second.is_secure, false);
  assert.equal(second.is_httponly, false);
  assert.equal(second.has_expires, false);
  assert.ok('expires_utc' in second);
});

test('header output joins name=value pairs with "; " in host_key,name order', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.y.com', name: 'c', value: '3', expires: FAR },
    { host: '.x.com', name: 'b', value: '2', expires: FAR },
    { host: '.x.com', name: 'a', value: '1', expires: FAR },
  ]);
  const r = run(env, ['-f', 'header']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.replace(/\n$/, ''), 'a=1; b=2; c=3');
});

function badCookieDb(env) {
  makeDb(env, [
    { host: '.bad.com', name: 'good1', value: 'g1', expires: FAR },
    { host: '.bad.com', name: 'garbage', enc: Buffer.concat([Buffer.from('v10'), Buffer.alloc(17, 0x7f)]), expires: FAR },
    { host: '.bad.com', name: 'noprefix', enc: Buffer.from('xyz123'), expires: FAR },
    { host: '.good.com', name: 'good2', value: 'g2', expires: FAR },
  ]);
}

test('undecryptable cookies are skipped silently without -v', () => {
  const env = mkEnv();
  badCookieDb(env);
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => [x[0], x[5], x[6]]), [
    ['.bad.com', 'good1', 'g1'],
    ['.good.com', 'good2', 'g2'],
  ]);
  assert.equal(r.stderr, '');
});

test('-v reports undecryptable cookies on stderr with host_key and name', () => {
  const env = mkEnv();
  badCookieDb(env);
  const r = run(env, ['-v']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[5]), ['good1', 'good2']);
  const lines = r.stderr.split('\n');
  assert.ok(lines.some((l) => l.includes('.bad.com') && l.includes('garbage')), r.stderr);
  assert.ok(lines.some((l) => l.includes('.bad.com') && l.includes('noprefix')), r.stderr);
});

test('-o creates missing parent directories and writes a 0600 file', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.o.com', name: 'a', value: 'v1', expires: FAR }]);
  const out = path.join(env.root, 'nested', 'dir', 'out.txt');
  const r = run(env, ['-o', out]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.includes('v1'), false);
  assert.equal(r.stdout.includes('.o.com'), false);
  assert.equal(fs.statSync(out).mode & 0o777, 0o600);
  const text = fs.readFileSync(out, 'utf8');
  assert.equal(text.split('\n')[0], HEADER);
  assert.ok(text.includes('.o.com\tTRUE\t/\tFALSE\t' + FAR + '\ta\tv1'));
});

test('-o - writes to stdout', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.o.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, ['-o', '-']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout), [['.o.com', 'TRUE', '/', 'FALSE', String(FAR), 'a', 'v1']]);
  assert.equal(fs.existsSync(path.join(env.root, '-')), false);
  assert.equal(fs.existsSync(path.join(process.cwd(), '-')), false);
});

test('unknown option exits 1 with a message on stderr', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.e.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, ['--nope']);
  assert.equal(r.status, 1);
  assert.notEqual(r.stderr.trim(), '');
});

test('unknown browser exits 1 with a message on stderr', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.e.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, ['-b', 'firefox']);
  assert.equal(r.status, 1);
  assert.notEqual(r.stderr.trim(), '');
});

test('unknown format exits 1 with a message on stderr', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.e.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, ['-f', 'xml']);
  assert.equal(r.status, 1);
  assert.notEqual(r.stderr.trim(), '');
});

test('missing cookie database exits 1 and says it was not found', () => {
  const env = mkEnv();
  const r = run(env, []);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /not found/i);
});

test('keychain entry not found (security exit 44) exits 1 with a message', { skip: !IS_MAC }, () => {
  const env = mkEnv({ secCode: 44 });
  makeDb(env, [{ host: '.k.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, []);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /keychain/i);
  assert.match(r.stderr, /not found/i);
});

test('chrome requests the Chrome Safe Storage keychain entry', { skip: !IS_MAC }, () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.k.com', name: 'a', value: 'v1', expires: FAR }]);
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  const log = fs.readFileSync(env.logs.security, 'utf8');
  assert.match(log, /find-generic-password/);
  assert.match(log, /-a Chrome\b/);
  assert.match(log, /-s Chrome Safe Storage/);
  assert.match(log, /-w/);
});

test('-L lists each distinct host_key once without needing the keychain', () => {
  const env = mkEnv({ secCode: 1 });
  makeDb(env, [
    { host: '.a.com', name: 'x', value: 'v1', expires: FAR },
    { host: '.a.com', name: 'y', value: 'v2', expires: FAR },
    { host: 'b.com', name: 'x', value: 'v3', expires: FAR },
    { host: '.c.com', name: 'x', value: 'v4', expires: FAR },
    { host: '.c.com', name: 'z', value: 'v5', expires: FAR },
  ]);
  const r = run(env, ['-L']);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n').filter((l) => l !== '');
  assert.deepEqual([...lines].sort(), ['.a.com', '.c.com', 'b.com']);
  assert.equal(r.stdout.includes('v1'), false);
});

test('no matching cookies prints only the netscape header', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.a.com', name: 'x', value: 'v1', expires: FAR }]);
  const r = run(env, ['-d', 'nomatch.com']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), HEADER);
});

test('no matching cookies prints [] for json', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.a.com', name: 'x', value: 'v1', expires: FAR }]);
  const r = run(env, ['-f', 'json', '-d', 'nomatch.com']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), []);
});

test('-b brave reads the Brave database', () => {
  const env = mkEnv({ password: 'bravepass' });
  makeDb(env, [{ host: '.brave.com', name: 'a', value: 'bv', expires: FAR }], { browser: 'brave', password: 'bravepass' });
  const r = run(env, ['-b', 'brave']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout), [['.brave.com', 'TRUE', '/', 'FALSE', String(FAR), 'a', 'bv']]);
});

test('-b brave does not read the Chrome database', () => {
  const env = mkEnv();
  makeDb(env, [{ host: '.chrome.com', name: 'a', value: 'cv', expires: FAR }]);
  const r = run(env, ['-b', 'brave']);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /not found/i);
});

test('-b brave requests the Brave Safe Storage keychain entry', { skip: !IS_MAC }, () => {
  const env = mkEnv({ password: 'bravepass' });
  makeDb(env, [{ host: '.brave.com', name: 'a', value: 'bv', expires: FAR }], { browser: 'brave', password: 'bravepass' });
  const r = run(env, ['-b', 'brave']);
  assert.equal(r.status, 0, r.stderr);
  const log = fs.readFileSync(env.logs.security, 'utf8');
  assert.match(log, /-a Brave\b/);
  assert.match(log, /-s Brave Safe Storage/);
  assert.doesNotMatch(log, /Chrome/);
});

test('kwallet "Failed" output falls through to secret-tool password', { skip: IS_MAC }, () => {
  const env = mkEnv({
    kwallet: { out: 'Failed to read entry', code: 0 },
    secretTool: { out: 'stpass', code: 0 },
  });
  makeDb(env, [{ host: '.l.com', name: 'a', value: 'lv', expires: FAR }], { password: 'stpass', iterations: 1 });
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[6]), ['lv']);
  const kw = fs.readFileSync(env.logs.kwallet, 'utf8');
  assert.match(kw, /--read-password/);
  assert.match(kw, /Chrome Safe Storage/);
  assert.match(kw, /Chrome Keys/);
  assert.match(kw, /kdewallet/);
  const st = fs.readFileSync(env.logs.secret, 'utf8');
  assert.match(st, /lookup application Chrome/);
});

test('kwallet password is used when kwallet answers', { skip: IS_MAC }, () => {
  const env = mkEnv({
    kwallet: { out: 'kwpass', code: 0 },
    secretTool: { out: 'stpass', code: 0 },
  });
  makeDb(env, [{ host: '.l.com', name: 'a', value: 'lv', expires: FAR }], { password: 'kwpass', iterations: 1 });
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[6]), ['lv']);
});

test('peanuts is used when no keyring answers', { skip: IS_MAC }, () => {
  const env = mkEnv({ kwallet: { code: 1 }, secretTool: { code: 1 } });
  makeDb(env, [{ host: '.l.com', name: 'a', value: 'lv', expires: FAR }], { password: 'peanuts', iterations: 1 });
  const r = run(env, []);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => x[6]), ['lv']);
});

test('a v11-prefixed value decrypts like v10', () => {
  const env = mkEnv();
  const iter = IS_MAC ? 1003 : 1;
  const prefix = crypto.createHash('sha256').update('.example.com').digest();
  const v10 = encrypt(Buffer.concat([prefix, Buffer.from('eleven')]), 'fakepass', iter);
  const v11 = Buffer.concat([Buffer.from('v11'), v10.subarray(3)]);
  makeDb(env, [{ host: '.example.com', name: 'n', enc: v11, expires: FAR }]);
  const r = run(env, ['-f', 'header']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), 'n=eleven');
});

test('an encrypted value of only the version tag is skipped', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.example.com', name: 'bare', enc: Buffer.from('v10'), expires: FAR },
    { host: '.example.com', name: 'ok', value: 'fine', expires: FAR },
  ]);
  const r = run(env, ['-f', 'header']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), 'ok=fine');
});

test('a final byte that only looks like padding is kept', () => {
  const env = mkEnv();
  const iter = IS_MAC ? 1003 : 1;
  const key = crypto.pbkdf2Sync('fakepass', 'saltysalt', iter, 16, 'sha1');
  const prefix = crypto.createHash('sha256').update('.example.com').digest();
  const plain = Buffer.concat([prefix, Buffer.from('abcdefghijklmn\x01\x02')]);
  const cipher = crypto.createCipheriv('aes-128-cbc', key, Buffer.alloc(16, 0x20));
  cipher.setAutoPadding(false);
  const enc = Buffer.concat([Buffer.from('v10'), cipher.update(plain), cipher.final()]);
  makeDb(env, [{ host: '.example.com', name: 'p', enc, expires: FAR }]);
  const r = run(env, ['-f', 'json']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout)[0].value, 'abcdefghijklmn\x01\x02');
});

test('an empty value in a version 24 database stays empty', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.example.com', name: 'empty', value: '', expires: FAR },
    { host: '.example.com', name: 'full', value: 'x', expires: FAR },
  ]);
  const r = run(env, ['-f', 'json']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).map((c) => [c.name, c.value]), [['empty', ''], ['full', 'x']]);
});

test('a domain and a name together match only that name on that domain', () => {
  const env = mkEnv();
  makeDb(env, [
    { host: '.p.com', name: 'a', value: '1', expires: FAR },
    { host: '.p.com', name: 'b', value: '2', expires: FAR },
    { host: '.q.com', name: 'a', value: '3', expires: FAR },
  ]);
  const r = run(env, ['-d', 'p.com', 'a']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(rows(r.stdout).map((x) => [x[0], x[5], x[6]]), [['.p.com', 'a', '1']]);
});

test('a run of more than 16 equal final bytes is not taken as padding', () => {
  const env = mkEnv();
  const iter = IS_MAC ? 1003 : 1;
  const key = crypto.pbkdf2Sync('fakepass', 'saltysalt', iter, 16, 'sha1');
  const prefix = crypto.createHash('sha256').update('.example.com').digest();
  const tail = 'x'.repeat(15) + '\x11'.repeat(17);
  const cipher = crypto.createCipheriv('aes-128-cbc', key, Buffer.alloc(16, 0x20));
  cipher.setAutoPadding(false);
  const enc = Buffer.concat([Buffer.from('v10'), cipher.update(Buffer.concat([prefix, Buffer.from(tail)])), cipher.final()]);
  makeDb(env, [{ host: '.example.com', name: 'p', enc, expires: FAR }]);
  const r = run(env, ['-f', 'json']);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout)[0].value, tail);
});
