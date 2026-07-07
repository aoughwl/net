## tnet.nim — compile-time API smoke for net.

import net

var s = invalidSocket()
discard lastNetErrorCode()
discard lastNetErrorKind()
discard classifyNetErrorCode(0)
discard netErrorWouldRetry(0)
discard netErrorTimedOut(0)
discard netErrorInterrupted(0)
discard netErrorDisconnected(0)
discard s.isValid()
discard recv(s, 16)
discard send(s, "")
discard sendAll(s, "")
discard setNoDelay(s)
discard setKeepAlive(s)
discard setReadTimeoutMillis(s, 0)
discard setWriteTimeoutMillis(s, 0)
discard setTimeoutMillis(s, 0)
discard setBlocking(s, true)
discard setNonBlocking(s)
var pollRequest = SocketPollRequest(read: true, write: false)
var pollResult = default(SocketPollResult)
discard poll(s, pollRequest, 0, pollResult)
discard waitReadable(s, 0)
discard waitWritable(s, 0)
var socketError = 0
discard socketErrorCode(s, socketError)
discard socketErrorCode(s)
discard finishConnect(s, socketError)
discard finishConnect(s)
discard shutdownRead(s)
discard shutdownWrite(s)
discard shutdownBoth(s)
let endpoint = invalidEndpoint()
discard endpoint.isValid()
discard endpoint.address
discard endpoint.port
discard localEndpoint(s)
discard peerEndpoint(s)
var peer = invalidEndpoint()
discard acceptWithPeer(s, peer)
s.closeAndInvalidate()

var loopback = anyIpv4()
discard parseIpv4("127.0.0.1", loopback)
discard resolveIpv4("localhost", loopback)
discard ipv4Value(loopback) == ipv4Value(localhostIpv4())

proc typecheckConnectApi() =
  discard listen(ipv4(127, 0, 0, 1), 1)
  discard listen(localhostIpv4(), 1, 16)
  discard connect(ipv4(127, 0, 0, 1), 1)
  discard connect(0x7f000001'u32, 1)
  discard connectLocalhost(1)
  discard connectHost("localhost", 1)
  discard connectNonBlocking(ipv4(127, 0, 0, 1), 1)
  discard connectNonBlocking(0x7f000001'u32, 1)
  discard connectLocalhostNonBlocking(1)
  discard connectHostNonBlocking("localhost", 1)

discard socketConnectFailed
discard socketConnectInProgress
discard socketConnectConnected
let connectResult = SocketConnectResult(socket: s, status: socketConnectFailed, errorCode: 0)
discard connectResult.socket
discard connectResult.status
discard connectResult.errorCode
