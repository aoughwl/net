import std/syncio
import net
import net/tls

proc main =
  initNet()
  var cctx = newTlsClientContext(verify = true)
  # One-call resolve + connect + TLS handshake with SNI/verify against the host.
  var c = connectTls(cctx, "example.com", 443)
  if not c.isValid:
    echo "SKIP: no network / DNS"
    quit(0)
  echo "handshakeDone=", c.handshakeDone
  echo "verifyOk=", c.verifyOk()
  echo "proto=", c.protocolVersion(), " cipher=", c.cipherName()
  discard c.sendAll("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")
  let resp = c.recv(200)
  echo "response bytes: ", resp.len
  var pref = ""
  var i = 0
  while i < resp.len and resp[i] != '\r' and resp[i] != '\n':
    pref.add resp[i]
    inc i
  echo "status line: ", pref
  c.closeTls()
  cctx.close()
  shutdownNet()
  echo "done"

main()
