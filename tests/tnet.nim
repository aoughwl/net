## tnet.aowl — compile-time API smoke for net.

import ../net

var s = invalidSocket()
discard s.isValid()
discard recv(s, 16)
discard send(s, "")
discard sendAll(s, "")
s.closeAndInvalidate()

var loopback = anyIpv4()
discard parseIpv4("127.0.0.1", loopback)
discard ipv4Value(loopback) == ipv4Value(localhostIpv4())

proc typecheckConnectApi() =
  discard listen(ipv4(127, 0, 0, 1), 1)
  discard listen(localhostIpv4(), 1, 16)
  discard connect(ipv4(127, 0, 0, 1), 1)
  discard connect(0x7f000001'u32, 1)
  discard connectLocalhost(1)
