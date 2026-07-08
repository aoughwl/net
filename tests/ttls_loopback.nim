## ttls_loopback.nim — real end-to-end TLS handshake over loopback, driven on a
## single thread by pumping both ends' non-blocking handshakes.
##
## Generates a throwaway self-signed cert with the `openssl` CLI, then:
##   * listens on an ephemeral port and connects a client to it (loopback);
##   * accepts the server side;
##   * puts both sockets in non-blocking mode and alternately calls
##     `handshake` on each until both report `handshakeDone` — exercising the
##     `tlsWantRead` / `tlsWantWrite` resumable-handshake path;
##   * switches back to blocking and round-trips a plaintext message through the
##     encrypted channel.
##
## Asserts the handshake completed both ways, a protocol/cipher is negotiated,
## and the payload survives the round trip.

import std/syncio
import std/os
import net
import net/tls

const
  certPath = "/tmp/aoughwl_tls_cert.pem"
  keyPath = "/tmp/aoughwl_tls_key.pem"
  reply = "hello over tls\n"

proc check(cond: bool; msg: string) =
  if not cond:
    echo "FAIL: ", msg
    quit(1)

proc main =
  initNet()

  let cmd = "openssl req -x509 -newkey rsa:2048 -keyout " & keyPath &
            " -out " & certPath &
            " -days 1 -nodes -subj /CN=localhost >/dev/null 2>&1"
  if execShellCmd(cmd) != 0:
    echo "SKIP: openssl CLI unavailable; cannot generate test cert"
    quit(0)

  var sctx = newTlsServerContext(certPath, keyPath)
  check(sctx.isValid, "server ctx invalid: " & lastTlsError())
  var cctx = newTlsClientContext(verify = false)
  check(cctx.isValid, "client ctx invalid")

  var lsock = listen(0)
  check(lsock.isValid, "listen failed")
  let port = localEndpoint(lsock).port
  check(port > 0, "no ephemeral port")

  # Connect the client (loopback connect completes immediately), then accept.
  let craw = connectLocalhost(port)
  check(craw.isValid, "client connect failed")
  let sraw = accept(lsock)
  check(sraw.isValid, "server accept failed")

  # Non-blocking so a single thread can drive both handshakes.
  check(setNonBlocking(craw), "client nonblocking failed")
  check(setNonBlocking(sraw), "server nonblocking failed")

  var c = wrapClient(cctx, craw, "localhost")
  var s = wrapServer(sctx, sraw)
  check(c.isValid and s.isValid, "wrap failed")

  var spins = 0
  while (not c.handshakeDone or not s.handshakeDone) and spins < 10000:
    let cs = handshake(c)
    let ss = handshake(s)
    check(cs != tlsError, "client handshake error: " & lastTlsError())
    check(ss != tlsError, "server handshake error: " & lastTlsError())
    inc spins
  check(c.handshakeDone, "client handshake did not complete")
  check(s.handshakeDone, "server handshake did not complete")

  let ver = c.protocolVersion()
  let cipher = c.cipherName()
  check(ver.len >= 3 and ver[0] == 'T' and ver[1] == 'L' and ver[2] == 'S',
        "unexpected protocol version: " & ver)
  check(cipher.len > 0, "no cipher negotiated")

  # Back to blocking for the payload round trip.
  check(setBlocking(craw, true), "client reblock failed")
  check(setBlocking(sraw, true), "server reblock failed")

  let ping = "ping\n"
  check(c.sendAll(ping), "client send failed")
  # Read the exact request length; a loop-to-fill recv would block waiting for
  # bytes the peer never sends.
  let serverGot = s.recv(ping.len)
  check(serverGot == ping, "server did not receive ping: '" & serverGot & "'")
  check(s.sendAll(reply), "server send failed")
  let got = c.recv(reply.len)
  check(got == reply, "tls payload mismatch: got '" & got & "'")

  c.closeTls()
  s.closeTls()
  lsock.close()
  cctx.close()
  sctx.close()
  shutdownNet()

  echo "negotiated ", ver, " / ", cipher
  echo "ttls_loopback: all checks passed"

main()
