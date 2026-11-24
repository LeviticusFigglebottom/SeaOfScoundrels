#!/usr/bin/env python3
"""Lint GDScript through Godot's built-in language server (headless).

Usage: tools/lint.py [files or dirs...]   (default: src scenes tests)
Prints every diagnostic as path:line: severity [CODE] message.
Exit code 1 if any error-severity diagnostic is found, else 0.
`godot --check-only` cannot do this: it reports parse errors only and fails on autoload names.
"""
import json, os, random, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", "godot")

def gather(args):
    out = []
    for a in args or ["src", "scenes", "tests"]:
        p = os.path.join(ROOT, a)
        if os.path.isfile(p):
            out.append(p)
        for d, _, fs in os.walk(p):
            out += [os.path.join(d, f) for f in fs if f.endswith(".gd")]
    return sorted(set(out))

def main():
    files = gather(sys.argv[1:])
    port = random.randint(20000, 30000)
    srv = subprocess.Popen([GODOT, "--headless", "--path", ROOT, "--editor", "--lsp-port", str(port)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        s = None
        for _ in range(120):
            try:
                s = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except OSError:
                time.sleep(0.5)
        if s is None:
            sys.exit("lint: could not reach the language server")
        buf = b""

        def send(o):
            b = json.dumps(o).encode()
            s.sendall(b"Content-Length: %d\r\n\r\n" % len(b) + b)

        def recv(timeout):
            nonlocal buf
            s.settimeout(timeout)
            try:
                while b"\r\n\r\n" not in buf:
                    d = s.recv(65536)
                    if not d:
                        return None
                    buf += d
                head, rest = buf.split(b"\r\n\r\n", 1)
                n = int([l for l in head.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
                while len(rest) < n:
                    rest += s.recv(65536)
                buf = rest[n:]
                return json.loads(rest[:n])
            except socket.timeout:
                return None

        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"processId": None, "rootUri": "file://" + ROOT, "capabilities": {}}})
        while True:
            m = recv(30)
            if m is None or m.get("id") == 1:
                break
        send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        pending = set()
        for f in files:
            uri = "file://" + f
            pending.add(uri)
            send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {
                "uri": uri, "languageId": "gdscript", "version": 1, "text": open(f).read()}}})
        errors = warnings = 0
        deadline = time.time() + 20 + len(files) * 0.5
        while pending and time.time() < deadline:
            m = recv(3)
            if m is None:
                continue
            if m.get("method") == "textDocument/publishDiagnostics":
                p = m["params"]
                pending.discard(p["uri"])
                rel = os.path.relpath(p["uri"][7:], ROOT)
                for d in p["diagnostics"]:
                    sev = d.get("severity", 2)
                    errors += sev == 1
                    warnings += sev != 1
                    print("%s:%d: %s [%s] %s" % (rel, d["range"]["start"]["line"] + 1,
                          "error" if sev == 1 else "warning", d.get("code", ""), d["message"].splitlines()[0]))
        print("lint: %d files, %d errors, %d warnings%s" % (
            len(files), errors, warnings, ", %d files got no reply" % len(pending) if pending else ""))
        return 1 if errors else 0
    finally:
        srv.kill()

if __name__ == "__main__":
    sys.exit(main())
