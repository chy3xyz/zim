#!/usr/bin/env python3
"""ZIM WebSocket smoke test — real connection against a running server.

Verifies: HTTP login → WS handshake (token auth) → GetMaxSeq(1001) request →
protobuf response round-trip. Uses only the Python standard library.

Usage: python3 scripts/ws_smoke.py [api_port] [ws_port]
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import urllib.request

API = int(sys.argv[1]) if len(sys.argv) > 1 else 10000
WS = int(sys.argv[2]) if len(sys.argv) > 2 else 10001


def http_post(path, payload):
    req = urllib.request.Request(
        f"http://localhost:{API}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def ws_connect(host, port, query):
    sock = socket.create_connection((host, port), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode()
    handshake = (
        f"GET /?{query} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    )
    sock.sendall(handshake.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(4096)
        if not chunk:
            raise RuntimeError("connection closed during handshake")
        resp += chunk
    status = resp.split(b"\r\n", 1)[0].decode()
    if "101" not in status:
        raise RuntimeError(f"handshake failed: {status}")
    return sock


def ws_send_text(sock, text):
    # RFC 6455 §5.3: client-to-server frames MUST be masked. The server
    # rejects unmasked client frames (UnmaskedClientFrame → close).
    payload = text.encode()
    header = bytearray([0x81])
    n = len(payload)
    if n < 126:
        header.append(n | 0x80)
    elif n < 65536:
        header.append(126 | 0x80)
        header += struct.pack(">H", n)
    else:
        header.append(127 | 0x80)
        header += struct.pack(">Q", n)
    mask = list(os.urandom(4))
    header += bytes(mask)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes(header) + masked)


def ws_recv_text(sock):
    while True:
        first = sock.recv(2)
        if len(first) < 2:
            raise RuntimeError("short read")
        opcode = first[0] & 0x0F
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack(">H", sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", sock.recv(8))[0]
        payload = b""
        while len(payload) < length:
            chunk = sock.recv(length - len(payload))
            if not chunk:
                raise RuntimeError("connection closed mid-frame")
            payload += chunk
        if opcode == 0x8:  # close
            raise RuntimeError("server sent close frame")
        if opcode == 0x1:  # text
            return payload.decode()


def proto_get_max_seq_req(user_id):
    b = user_id.encode()
    return b"\x0a" + bytes([len(b)]) + b  # field 1 (string), GetMaxSeqReq.user_id


def main():
    # 1. Register + login for a token
    uid = f"wssmoke{os.getpid()}"
    try:
        http_post("/account/register", {"platform": 1, "user": {
            "nickname": "WS Smoke", "password": "test1234", "account": uid}})
    except Exception as e:
        print(f"register: {e}")
    login = http_post("/account/login", {"account": uid, "password": "test1234", "platform": 1})
    token = login["data"]["imToken"]
    print(f"login OK user={uid}")

    # 2. WS handshake with token auth
    sock = ws_connect("localhost", WS, f"sendID={uid}&token={token}&platformID=1")
    print("WS handshake OK (101)")

    # 3. GetMaxSeq (1001) request
    data_b64 = base64.b64encode(proto_get_max_seq_req(uid)).decode()
    ws_send_text(sock, json.dumps({"reqIdentifier": 1001, "sendID": uid, "data": data_b64}))
    # STRICT: drain any 2100 config frames until the actual 1001 response
    # arrives — a 2100-only read means the request was never processed.
    resp = None
    for _ in range(5):
        r = json.loads(ws_recv_text(sock))
        if r.get("reqIdentifier") == 1001:
            resp = r
            break
    if resp is None:
        raise RuntimeError("no 1001 GetMaxSeq response (request never processed)")
    print(f"WS response: reqIdentifier={resp.get('reqIdentifier')} errCode={resp.get('errCode')}")
    if resp.get("errCode") != 0:
        raise RuntimeError(f"GetMaxSeq failed: {resp}")
    sock.close()
    print("WS SMOKE PASS")


if __name__ == "__main__":
    main()
