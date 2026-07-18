## tnet_ipv6endpoint.nim — IPv6 addressing ergonomics at the net level.
##
## Two parts:
##   1. Pure round-trips of the `Ipv6Address` text layer ($ / parseIpv6).
##   2. A real ::1 loopback: connect over IPv6 and assert the local/peer
##      endpoints report the v6 family and stringify to the bracketed
##      "[::1]:port" form (proving peer/local endpoint can represent a v6 peer).

import std/syncio
import net

proc check(cond: bool; label: string) =
  if not cond:
    echo "FAIL: ", label
    quit(1)

proc startsWith(s, prefix: string): bool =
  if s.len < prefix.len:
    return false
  var i = 0
  while i < prefix.len:
    if s[i] != prefix[i]:
      return false
    inc i
  true

proc main() =
  initNet()

  # --- Pure Ipv6Address text layer --------------------------------------
  check($localhostIpv6() == "::1", "$ ::1")
  check($anyIpv6() == "::", "$ ::")

  var ip = anyIpv6()
  check(parseIpv6("2001:db8::1", ip), "parseIpv6 ok")
  check($ip == "2001:db8::1", "parseIpv6 round-trip via $")
  check(parseIpv6("::ffff:127.0.0.1", ip) and $ip == "::ffff:127.0.0.1",
        "parseIpv6 v4-mapped round-trip")
  var junk = anyIpv6()
  check(not parseIpv6("1:2:3:4:5:6:7", junk), "reject short v6")
  check(not parseIpv6("nope", junk), "reject garbage")

  # A v6 endpoint stringifies bracketed.
  let synthetic = Endpoint(family: familyV6, v6: localhostIpv6(), port: 8080)
  check($synthetic == "[::1]:8080", "$ v6 endpoint bracketed")
  check(synthetic.isIpv6, "synthetic endpoint isIpv6")
  # The IPv4 fast path is untouched.
  let v4ep = Endpoint(address: ipv4(127, 0, 0, 1), port: 8080)
  check($v4ep == "127.0.0.1:8080", "$ v4 endpoint unchanged")
  check(not v4ep.isIpv6, "v4 endpoint not isIpv6")

  # --- Real ::1 loopback -------------------------------------------------
  var server = listen6(0, 128, true)
  check(server.isValid, "listen6 failed")
  let listenEp = localEndpoint(server)
  check(listenEp.isIpv6, "listener local endpoint is v6")
  let port = listenEp.port
  check(port > 0, "no ephemeral port")

  let r = dial("::1", port)
  check(r.status == socketConnectConnected, "dial ::1 failed")
  let client = r.socket

  let peer = accept(server)
  check(peer.isValid, "accept failed")

  # The accepted socket's peer is the client, over ::1.
  let peerEp = peerEndpoint(peer)
  check(peerEp.isIpv6, "peer endpoint is v6")
  check(startsWith($peerEp, "[::1]:"), "peer endpoint bracketed v6: " & $peerEp)

  # And its local side is also the ::1 listener address on the listen port.
  let localEp = localEndpoint(peer)
  check(localEp.isIpv6, "accepted local endpoint is v6")
  check($localEp == "[::1]:" & $port, "accepted local endpoint form: " & $localEp)

  # The client's own view: peer is the ::1 listener on `port`.
  let clientPeer = peerEndpoint(client)
  check(clientPeer.isIpv6, "client peer endpoint is v6")
  check($clientPeer == "[::1]:" & $port, "client peer endpoint form: " & $clientPeer)

  client.close()
  peer.close()
  server.close()
  shutdownNet()
  echo "tnet_ipv6endpoint: all checks passed (port ", port, ")"

main()
