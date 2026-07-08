## tnet_loopback.nim — real single-process loopback behavioral test for net.
##
## Exercises the higher-level net API end to end: address formatting and parse
## round-trips, a nonblocking connect + poll + accept handshake, and a small
## line-oriented request/response using the buffered reader (recvLine) plus
## readAll for the body. Runs in one process on 127.0.0.1.

import std/syncio
import net

proc check(cond: bool; label: string) =
  if not cond:
    echo "FAIL: ", label
    quit(1)

proc main() =
  initNet()

  # --- Address helpers ---------------------------------------------------
  check($ipv4(127, 0, 0, 1) == "127.0.0.1", "$ ipv4 loopback")
  check($ipv4(0, 0, 0, 0) == "0.0.0.0", "$ ipv4 any")
  check($ipv4(255, 255, 255, 255) == "255.255.255.255", "$ ipv4 broadcast")
  check($ipv4(10, 20, 30, 40) == "10.20.30.40", "$ ipv4 mixed")
  check(formatIpv4(localhostIpv4()) == "127.0.0.1", "formatIpv4 localhost")

  # Endpoint string form "a.b.c.d:port".
  let ep = Endpoint(address: ipv4(127, 0, 0, 1), port: 8080)
  check($ep == "127.0.0.1:8080", "$ endpoint format")

  # parseIpv4 round-trip and rejection.
  var parsed = anyIpv4()
  check(parseIpv4("127.0.0.1", parsed), "parseIpv4 ok")
  check(ipv4Value(parsed) == ipv4Value(localhostIpv4()), "parseIpv4 value")
  var rt = anyIpv4()
  check(parseIpv4($ipv4(10, 20, 30, 40), rt) and $rt == "10.20.30.40",
        "parseIpv4 round-trip via $")
  var junk = anyIpv4()
  check(not parseIpv4("256.0.0.1", junk), "reject octet > 255")

  # --- Loopback request/response ----------------------------------------
  let port = 34568
  let listener = listen(ipv4(127, 0, 0, 1), port)
  check(listener.isValid, "listener created")
  check(setNonBlocking(listener), "listener nonblocking")

  # Nonblocking connect to the listener.
  let conn = connectNonBlocking(ipv4(127, 0, 0, 1), port)
  check(conn.status != socketConnectFailed, "connect not failed")
  let client = conn.socket
  check(client.isValid, "client handle valid")
  check(setNoDelay(client), "setNoDelay client")

  # Poll listener until readable, then accept.
  check(waitReadable(listener, 2000), "listener became readable")
  let server = accept(listener)
  check(server.isValid, "accepted server socket")

  # Finish the client-side connect.
  if conn.status == socketConnectInProgress:
    check(waitWritable(client, 2000), "client became writable")
  check(finishConnect(client), "finishConnect")

  # Peer introspection reports loopback, and $ endpoint round-trips it.
  let peer = peerEndpoint(server)
  check(peer.address.ipv4Value == ipv4(127, 0, 0, 1).ipv4Value,
        "peer address is loopback")

  # Client sends an HTTP-ish request: request line + a header, ending CRLFCRLF.
  let request = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"
  check(sendAll(client, request), "client sent request")

  # Server reads the request line with the buffered reader.
  var serverReader = newBufferedSocket(server)
  let requestLine = recvLine(serverReader)
  check(requestLine == "GET /hello HTTP/1.1", "server read request line")
  let hostHeader = recvLine(serverReader)
  check(hostHeader == "Host: localhost", "server read host header")
  let blankLine = recvLine(serverReader)
  check(blankLine == "", "server read blank header terminator")

  # Server echoes an HTTP-ish response, then closes its write side so the
  # client's readAll sees EOF.
  let body = "hello, loopback"
  var response = "HTTP/1.1 200 OK\r\n"
  response.add("Content-Length: 15\r\n")
  response.add("\r\n")
  response.add(body)
  check(sendAll(server, response), "server sent response")
  check(shutdownWrite(server), "server shutdown write")

  # Client reads the status line via recvLine, drains headers, then readAll body.
  var clientReader = newBufferedSocket(client)
  let statusLine = recvLine(clientReader)
  check(statusLine == "HTTP/1.1 200 OK", "client read status line")
  # Drain header lines until the blank line.
  var header = recvLine(clientReader)
  check(header == "Content-Length: 15", "client read content-length")
  header = recvLine(clientReader)
  check(header == "", "client read blank line")
  let received = readAll(clientReader)
  check(received == body, "client read response body")

  # --- Teardown ----------------------------------------------------------
  close(client)
  close(server)
  close(listener)
  shutdownNet()
  echo "ok"

main()
