## net/tcpnet.aowl — stdlib-style blocking TCP wrapper over `tcp`.

import tcp
import address

type
  Socket* = object
    handle*: TcpHandle

  Endpoint* = object
    address*: Ipv4Address
    port*: int

proc invalidSocket*(): Socket =
  Socket(handle: InvalidTcpHandle)

proc isValid*(s: Socket): bool =
  isValidTcp(s.handle)

proc invalidEndpoint*(): Endpoint =
  Endpoint(address: anyIpv4(), port: -1)

proc isValid*(endpoint: Endpoint): bool =
  endpoint.port >= 0

proc endpointFromTcp(endpoint: TcpEndpoint): Endpoint =
  Endpoint(address: Ipv4Address(value: endpoint.address), port: endpoint.port)

proc initNet*() =
  initTcp()

proc shutdownNet*() =
  shutdownTcp()

proc lastNetErrorCode*(): int =
  ## Return the last platform socket error code for the current thread.
  lastTcpErrorCode()

proc listen*(port: int; backlog = 128): Socket =
  Socket(handle: listenTcp(port, backlog))

proc listen*(ip: Ipv4Address; port: int; backlog = 128): Socket =
  Socket(handle: listenTcp4(ipv4Value(ip), port, backlog))

proc connect*(hostOrderAddr: uint32; port: int): Socket =
  Socket(handle: connectTcp4(hostOrderAddr, port))

proc connect*(ip: Ipv4Address; port: int): Socket =
  Socket(handle: connectTcp4(ipv4Value(ip), port))

proc connectLocalhost*(port: int): Socket =
  Socket(handle: connectLocalhostTcp(port))

proc resolveIpv4*(host: string; dest: var Ipv4Address): bool =
  var raw = 0'u32
  if not resolveTcp4(host, raw):
    return false
  dest = Ipv4Address(value: raw)
  true

proc connectHost*(host: string; port: int): Socket =
  var ip = anyIpv4()
  if not resolveIpv4(host, ip):
    return invalidSocket()
  connect(ip, port)

proc localEndpoint*(socket: Socket): Endpoint =
  if not socket.isValid:
    return invalidEndpoint()
  endpointFromTcp(localTcpEndpoint(socket.handle))

proc peerEndpoint*(socket: Socket): Endpoint =
  if not socket.isValid:
    return invalidEndpoint()
  endpointFromTcp(peerTcpEndpoint(socket.handle))

proc setNoDelay*(socket: Socket; enabled = true): bool =
  if not socket.isValid:
    return false
  setTcpNoDelay(socket.handle, enabled)

proc setKeepAlive*(socket: Socket; enabled = true): bool =
  if not socket.isValid:
    return false
  setTcpKeepAlive(socket.handle, enabled)

proc setReadTimeoutMillis*(socket: Socket; millis: int): bool =
  if not socket.isValid:
    return false
  setTcpReadTimeoutMillis(socket.handle, millis)

proc setWriteTimeoutMillis*(socket: Socket; millis: int): bool =
  if not socket.isValid:
    return false
  setTcpWriteTimeoutMillis(socket.handle, millis)

proc setTimeoutMillis*(socket: Socket; millis: int): bool =
  if not socket.isValid:
    return false
  setTcpTimeoutMillis(socket.handle, millis)

proc shutdownRead*(socket: Socket): bool =
  if not socket.isValid:
    return false
  shutdownTcpRead(socket.handle)

proc shutdownWrite*(socket: Socket): bool =
  if not socket.isValid:
    return false
  shutdownTcpWrite(socket.handle)

proc shutdownBoth*(socket: Socket): bool =
  if not socket.isValid:
    return false
  shutdownTcpBoth(socket.handle)

proc accept*(server: Socket): Socket =
  if not server.isValid:
    return invalidSocket()
  Socket(handle: acceptTcp(server.handle))

proc recvInto*(socket: Socket; buf: pointer; len: int): int =
  if not socket.isValid:
    return -1
  readTcp(socket.handle, buf, len)

proc sendFrom*(socket: Socket; buf: pointer; len: int): int =
  if not socket.isValid:
    return -1
  writeTcp(socket.handle, buf, len)

proc sendAllFrom*(socket: Socket; buf: pointer; len: int): int =
  if not socket.isValid:
    return -1
  writeAllTcp(socket.handle, buf, len)

proc close*(socket: Socket) =
  if socket.isValid:
    closeTcp(socket.handle)

proc closeAndInvalidate*(socket: var Socket) =
  if socket.isValid:
    closeTcp(socket.handle)
  socket.handle = InvalidTcpHandle

proc recv*(socket: Socket; maxBytes: int): string =
  var buf = default(array[8192, char])
  var limit = maxBytes
  if limit > buf.len:
    limit = buf.len
  if limit < 0:
    limit = 0
  let n = recvInto(socket, addr buf[0], limit)
  result = ""
  var i = 0
  while i < n:
    result.add buf[i]
    inc i

proc send*(socket: Socket; data: string): int =
  ## Send the whole string unless the socket reports an error.
  var buf = default(array[8192, char])
  var total = 0
  while total < data.len:
    var n = 0
    while n < buf.len and total + n < data.len:
      buf[n] = data[total + n]
      inc n
    let written = sendFrom(socket, addr buf[0], n)
    if written <= 0:
      return total
    total = total + written
  return total

proc sendAll*(socket: Socket; data: string): bool =
  send(socket, data) == data.len
