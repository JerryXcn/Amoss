#!/usr/bin/env python3
"""Explicit USB smoke test: synthetic text, no windows/input/power changes.

Compile Integrations/Clipboard/ClipboardSmoke.swift with AmossCore and the store
first. Only PASS/FAIL metadata is logged. The phone's original text is kept in
memory and restored; the user's Mac pasteboard is never touched.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import time

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("--serial", required=True)
parser.add_argument("--tools", default=str(root / "dist/Amoss.app/Contents/Resources/Tools"))
args = parser.parse_args()
tools = Path(args.tools)
adb = tools / "adb"
environment = os.environ.copy()
for key in ["ADB_SERVER_SOCKET", "ANDROID_SERIAL", "ANDROID_ADB_SERVER_PORT", "ADB_SERVER_PORT", "ADB_TRACE"]:
    environment.pop(key, None)

def command(*argv):
    return subprocess.check_output([str(adb), "-s", args.serial, *argv], stderr=subprocess.PIPE, env=environment, timeout=10).decode().strip()

def wait_for(check, description, seconds=12):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            print("PASS " + description, flush=True)
            return
        time.sleep(0.15)
    raise AssertionError(description)

sock = server = harness = None
port = original = None
token = f"{secrets.randbelow(0x7ffffffe) + 1:08x}"
remote = f"/data/local/tmp/amoss-clipboard-test-{token}.jar"
sequence = 1

def exact(count):
    result = b""
    while len(result) < count:
        data = sock.recv(count - len(result))
        if not data:
            raise RuntimeError("Reference connection closed")
        result += data
    return result

def read_message():
    kind = exact(1)[0]
    if kind == 0:
        length = struct.unpack(">I", exact(4))[0]
        assert length <= 262144
        return kind, exact(length).decode()
    if kind == 1:
        return kind, struct.unpack(">Q", exact(8))[0]
    raise RuntimeError("Invalid reference message")

def get_text():
    sock.sendall(bytes([8, 0]))  # GET_CLIPBOARD; no key injection
    try:
        kind, value = read_message()
    except TimeoutError:
        return None  # scrcpy sends no frame for an empty/non-text clipboard.
    assert kind == 0
    return value

def set_text(text):
    global sequence
    raw = text.encode()
    sock.sendall(bytes([9]) + struct.pack(">QB I", sequence, 0, len(raw)) + raw)
    kind, value = read_message()
    assert kind == 1 and value == sequence
    sequence += 1

def ask(action, **values):
    harness.stdin.write(json.dumps(dict(action=action, **values), ensure_ascii=False) + "\n")
    harness.stdin.flush()
    response = harness.stdout.readline()
    if not response:
        raise RuntimeError("Clipboard harness exited")
    return json.loads(response)

try:
    command("push", str(tools / "scrcpy-server"), remote)
    port = int(command("forward", "tcp:0", "localabstract:scrcpy_" + token))
    server = subprocess.Popen([str(adb), "-s", args.serial, "shell", f"CLASSPATH={remote}", "app_process", "/",
        "com.genymobile.scrcpy.Server", "5.0.1", f"scid={token}", "log_level=warn", "video=false", "audio=false",
        "control=true", "tunnel_forward=true", "send_device_meta=false", "clipboard_autosync=false",
        "power_on=false", "cleanup=true"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=environment)
    for attempt in range(35):
        try:
            sock = socket.create_connection(("127.0.0.1", port), timeout=3)
            assert exact(1) == b"\0"
            break
        except (OSError, AssertionError, RuntimeError):
            if sock: sock.close()
            sock = None
            time.sleep(0.25)
    assert sock is not None, "Reference connection failed"
    original = get_text()
    harness = subprocess.Popen([str(root / "build/clipboard-smoke"), str(tools), args.serial],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=environment)
    wait_for(lambda: ask("status")["ready"], "background connection without mirroring")
    a, b, c = "Amoss Mac 后台复制🙂\n第二行", "Amoss Android 后台复制🎉\n第二行", "Amoss 开关隔离"
    ask("copy", text=a)
    wait_for(lambda: get_text() == a, "Mac → Android Chinese / emoji / multiline")
    set_text(b)
    wait_for(lambda: ask("expect", text=b)["matches"], "Android → Mac without a mirror")
    changes = ask("status")["changes"]
    time.sleep(1.2)
    assert ask("status")["changes"] == changes
    print("PASS no clipboard echo loop", flush=True)
    ask("enabled", value=False)
    wait_for(lambda: not ask("status")["pending"], "disable stops its server and removes forwarding")
    ask("copy", text=c)
    time.sleep(0.5)
    assert get_text() == b
    set_text(a)
    time.sleep(0.5)
    assert ask("expect", text=c)["matches"]
    print("PASS disabled device blocked in both directions", flush=True)
    ask("enabled", value=True)
    wait_for(lambda: ask("status")["ready"], "re-enable reconnects")
    assert get_text() == a and ask("expect", text=c)["matches"]
    print("PASS enabling does not overwrite existing clipboards", flush=True)
    ask("copy", text=b)
    wait_for(lambda: get_text() == b, "next copy synchronizes after enabling")
    ask("disconnect")
    wait_for(lambda: not ask("status")["pending"], "disconnect cleanup")
    ask("connect")
    wait_for(lambda: ask("status")["ready"], "device reconnect restores enabled preference")
    set_text(c)
    wait_for(lambda: ask("expect", text=c)["matches"], "phone copy after reconnect")
    ask("shutdown")
    wait_for(lambda: not ask("status")["pending"], "quit cleanup")
finally:
    if harness:
        try:
            ask("shutdown")
            wait_for(lambda: not ask("status")["pending"], "final cleanup", seconds=8)
            ask("exit")
            harness.wait(timeout=3)
        except Exception:
            harness.terminate()
    if sock:
        if original is not None:
            try: set_text(original)
            except Exception: pass
        sock.close()
    if server:
        server.terminate()
        try: server.wait(timeout=3)
        except subprocess.TimeoutExpired: server.kill()
    if port:
        try: command("forward", "--remove", f"tcp:{port}")
        except Exception: pass
    try: command("shell", "rm", "-f", remote)
    except Exception: pass
