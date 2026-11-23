#!/usr/bin/env python3
"""RTC signaling scope smoke: three WS clients (host / member / outsider).

The host sends a 1004 SendSignalMsg through the room; assertions:
  - the room member receives it,
  - an outsider (authenticated, not in the room) does NOT,
  - the sender gets its own echo back.

Requires a running zim backend (:10000 HTTP, :10001 WS).
Exit 1 on any assertion failure.

Note: the server decodes the JSON envelope's `data` field with a URL-safe
base64 decoder — standard-alphabet `+/` padding in long payloads will fail
the decode. We encode with urlsafe_b64encode to match.
"""
import base64
import json
import os
import socket
import sys
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
from ws_smoke import ws_connect, ws_send_text, ws_recv_text  # noqa: E402

HTTP, WS = 10000, 10001


def http_post(path, tok, body):
    req = urllib.request.Request(
        "http://localhost:%d%s" % (HTTP, path),
        json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "token": tok},
    )
    return json.load(urllib.request.urlopen(req, timeout=10))


def login(acct):
    http_post("/account/register", "", {
        "platform": 1,
        "user": {"nickname": acct, "account": acct, "password": "test1234"},
    })
    return http_post("/account/login", "", {
        "account": acct, "password": "test1234", "platform": 1,
    })["data"]["imToken"]


def listen(tok, uid):
    sock = ws_connect("localhost", WS, f"sendID={uid}&token={tok}&platformID=1")
    sock.settimeout(2)
    return sock


def pb_bytes(field, val):
    b = val.encode() if isinstance(val, str) else val
    return bytes([(field << 3) | 2, len(b)]) + b


def pb_varint(field, v):
    out = bytearray()
    while True:
        b7 = v & 0x7F
        v >>= 7
        out.append(b7 | (0x80 if v else 0))
        if not v:
            break
    return bytes([(field << 3) | 0]) + bytes(out)


def recv_matching(sock, marker, frames=8):
    """Drain queued frames (the server sends a 2100 config frame right
    after handshake) until one contains `marker` or the socket goes quiet."""
    sock.settimeout(2)
    for _ in range(frames):
        try:
            text = ws_recv_text(sock)
        except (socket.timeout, OSError, RuntimeError):
            return None
        if marker in text:
            return text
    return None


def drain_no_match(sock, marker, frames=4):
    """Assert-style drain: no queued frame may contain `marker`."""
    sock.settimeout(1)
    for _ in range(frames):
        try:
            text = ws_recv_text(sock)
        except (socket.timeout, OSError, RuntimeError):
            return True
        if marker in text:
            return False
    return True


def main():
    a_tok, b_tok, c_tok = login("sigsmk_a"), login("sigsmk_b"), login("sigsmk_c")

    room = http_post("/rtc-meeting/create", a_tok, {
        "hostUserID": "sigsmk_a", "meetingName": "signal smoke",
    })["data"]["roomID"]
    http_post("/rtc-meeting/join", b_tok, {"roomID": room, "userID": "sigsmk_b"})

    sa = listen(a_tok, "sigsmk_a")
    sb = listen(b_tok, "sigsmk_b")
    sc = listen(c_tok, "sigsmk_c")

    # host → room: SignalReq protobuf (1=roomID, 2=signalType varint,
    # 3=userID, 4=data payload), url-safe base64 in the JSON envelope.
    inner = pb_bytes(1, room) + pb_varint(2, 1) + pb_bytes(3, "sigsmk_a") + pb_bytes(4, "ready")
    sig = {"reqIdentifier": 1004, "sendID": "sigsmk_a",
           "data": base64.urlsafe_b64encode(inner).decode()}
    ws_send_text(sa, json.dumps(sig))

    b_got = recv_matching(sb, "1004")
    a_got = recv_matching(sa, "1004")
    ok_member = b_got is not None
    ok_echo = a_got is not None
    ok_outsider = drain_no_match(sc, "1004")

    print("room member received:", ok_member)
    print("outsider suppressed:", ok_outsider)
    print("sender echo received:", ok_echo)
    if not (ok_member and ok_outsider and ok_echo):
        raise SystemExit("SIGNAL SMOKE FAIL")

    for s in (sa, sb, sc):
        s.close()

    # cleanup: host close removes the meeting + participants rows (0-residue)
    http_post("/rtc-meeting/close", a_tok, {"roomID": room, "userID": "sigsmk_a"})

    print("SIGNAL SMOKE PASS")


if __name__ == "__main__":
    main()
