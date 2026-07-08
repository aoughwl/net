## tnet_ipv6.nim — IPv6 loopback through the net-level API: `listen6`, family-
## agnostic `dial`/`connectHost`, and send/recv over both IPv6 and v4-mapped.

import std/syncio
import net

proc check(cond: bool; msg: string) =
  if not cond:
    echo "FAIL: ", msg
    quit(1)

proc exchange(server: Socket; client: Socket; tag: string) =
  let peer = accept(server)
  check(peer.isValid, "accept failed for " & tag)
  check(sendAll(client, tag & "\n"), "client send failed for " & tag)
  let got = recv(peer, tag.len + 1)
  check(got == tag & "\n", "payload mismatch for " & tag & ": '" & got & "'")
  client.close()
  peer.close()

proc main =
  initNet()
  var server = listen6(0, 128, true)
  check(server.isValid, "listen6 failed")
  let port = localEndpoint(server).port
  check(port > 0, "no ephemeral port")

  # dial() is now family-agnostic: ::1 resolves to an AAAA address.
  block:
    let r = dial("::1", port)
    check(r.status == socketConnectConnected, "dial ::1 failed")
    exchange(server, r.socket, "v6-dial")

  # connectHost() over the v4-mapped path against the same dual-stack listener.
  block:
    let c = connectHost("127.0.0.1", port)
    check(c.isValid, "connectHost 127.0.0.1 failed")
    exchange(server, c, "v4-mapped")

  server.close()
  shutdownNet()
  echo "tnet_ipv6: all checks passed (port ", port, ")"

main()
