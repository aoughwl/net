## net/tcpnet.nim — stdlib-style blocking TCP wrapper over `tcp`.

import tcp
import address

type
  Socket* = object
    handle*: TcpHandle

  Endpoint* = object
    address*: Ipv4Address
    port*: int

  SocketConnectStatus* = enum
    socketConnectFailed,
    socketConnectInProgress,
    socketConnectConnected

  SocketPollRequest* = object
    read*: bool
    write*: bool

  SocketPollResult* = object
    read*: bool
    write*: bool
    error*: bool
    hangup*: bool
    invalid*: bool

  SocketConnectResult* = object
    socket*: Socket
    status*: SocketConnectStatus
    errorCode*: int

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

proc appendInt(s: var string; value: int) =
  ## Append the decimal digits of a (possibly negative) integer.
  if value == 0:
    s.add('0')
    return
  var v = value
  var negative = false
  if v < 0:
    negative = true
    v = -v
  var digits = default(array[24, char])
  var n = 0
  while v > 0:
    digits[n] = char(ord('0') + int(v mod 10))
    v = v div 10
    inc n
  if negative:
    s.add('-')
  var i = n - 1
  while i >= 0:
    s.add digits[i]
    dec i

proc `$`*(endpoint: Endpoint): string =
  ## Format an endpoint as "a.b.c.d:port", e.g. "127.0.0.1:8080".
  result = formatIpv4(endpoint.address)
  result.add(':')
  appendInt(result, endpoint.port)

proc initNet*() =
  initTcp()

proc shutdownNet*() =
  shutdownTcp()

proc lastNetErrorCode*(): int =
  ## Return the last platform socket error code for the current thread.
  lastTcpErrorCode()

proc lastNetErrorKind*(): TcpErrorKind =
  lastTcpErrorKind()

proc classifyNetErrorCode*(code: int): TcpErrorKind =
  classifyTcpErrorCode(code)

proc netErrorWouldRetry*(code: int): bool =
  tcpErrorWouldRetry(code)

proc netErrorTimedOut*(code: int): bool =
  tcpErrorTimedOut(code)

proc netErrorInterrupted*(code: int): bool =
  tcpErrorInterrupted(code)

proc netErrorDisconnected*(code: int): bool =
  tcpErrorDisconnected(code)

proc listen*(port: int; backlog = 128): Socket =
  Socket(handle: listenTcp(port, backlog))

proc listen*(ip: Ipv4Address; port: int; backlog = 128): Socket =
  Socket(handle: listenTcp4(ipv4Value(ip), port, backlog))

proc listen6*(port: int; backlog = 128; dualStack = true): Socket =
  ## Listen on an IPv6 socket. With `dualStack` (default) the same socket also
  ## accepts IPv4-mapped connections, so one listener serves both families.
  Socket(handle: listenTcp6(port, backlog, dualStack))

proc connect*(hostOrderAddr: uint32; port: int): Socket =
  Socket(handle: connectTcp4(hostOrderAddr, port))

proc connect*(ip: Ipv4Address; port: int): Socket =
  Socket(handle: connectTcp4(ipv4Value(ip), port))

proc connectLocalhost*(port: int): Socket =
  Socket(handle: connectLocalhostTcp(port))

proc socketConnectResultFromTcp(tcpResult: TcpConnectResult): SocketConnectResult =
  var status = socketConnectFailed
  if tcpResult.status == tcpConnectInProgress:
    status = socketConnectInProgress
  elif tcpResult.status == tcpConnectConnected:
    status = socketConnectConnected
  SocketConnectResult(
    socket: Socket(handle: tcpResult.handle),
    status: status,
    errorCode: tcpResult.errorCode
  )

proc connectNonBlocking*(hostOrderAddr: uint32; port: int): SocketConnectResult =
  socketConnectResultFromTcp(connectTcp4NonBlocking(hostOrderAddr, port))

proc connectNonBlocking*(ip: Ipv4Address; port: int): SocketConnectResult =
  socketConnectResultFromTcp(connectTcp4NonBlocking(ipv4Value(ip), port))

proc connectLocalhostNonBlocking*(port: int): SocketConnectResult =
  socketConnectResultFromTcp(connectLocalhostTcpNonBlocking(port))

proc resolveIpv4*(host: string; dest: var Ipv4Address): bool =
  var raw = 0'u32
  if not resolveTcp4(host, raw):
    return false
  dest = Ipv4Address(value: raw)
  true

proc connectHost*(host: string; port: int): Socket =
  ## Resolve `host` (IPv4 *or* IPv6) and connect to the first address that
  ## accepts. Family-agnostic via `connectHostTcp`, so it follows AAAA records
  ## as well as A records.
  Socket(handle: connectHostTcp(host, port))

proc connectHostNonBlocking*(host: string; port: int): SocketConnectResult =
  var ip = anyIpv4()
  if not resolveIpv4(host, ip):
    return SocketConnectResult(
      socket: invalidSocket(),
      status: socketConnectFailed,
      errorCode: lastNetErrorCode()
    )
  connectNonBlocking(ip, port)

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

proc setBlocking*(socket: Socket; blocking: bool): bool =
  if not socket.isValid:
    return false
  setTcpBlocking(socket.handle, blocking)

proc setNonBlocking*(socket: Socket): bool =
  if not socket.isValid:
    return false
  setTcpNonBlocking(socket.handle)

proc poll*(socket: Socket; request: SocketPollRequest; timeoutMillis: int;
           ready: var SocketPollResult): int =
  if not socket.isValid:
    ready = SocketPollResult(read: false, write: false, error: false, hangup: false, invalid: true)
    return -1
  var tcpRequest = TcpPollRequest(read: request.read, write: request.write)
  var tcpReady = default(TcpPollResult)
  let n = pollTcp(socket.handle, tcpRequest, timeoutMillis, tcpReady)
  ready = SocketPollResult(
    read: tcpReady.read,
    write: tcpReady.write,
    error: tcpReady.error,
    hangup: tcpReady.hangup,
    invalid: tcpReady.invalid
  )
  n

proc waitReadable*(socket: Socket; timeoutMillis: int): bool =
  if not socket.isValid:
    return false
  waitTcpReadable(socket.handle, timeoutMillis)

proc waitWritable*(socket: Socket; timeoutMillis: int): bool =
  if not socket.isValid:
    return false
  waitTcpWritable(socket.handle, timeoutMillis)

proc socketErrorCode*(socket: Socket; errorCode: var int): bool =
  if not socket.isValid:
    errorCode = -1
    return false
  tcpSocketErrorCode(socket.handle, errorCode)

proc socketErrorCode*(socket: Socket): int =
  if not socket.isValid:
    return -1
  tcpSocketErrorCode(socket.handle)

proc finishConnect*(socket: Socket; errorCode: var int): bool =
  if not socket.isValid:
    errorCode = -1
    return false
  finishTcpConnect(socket.handle, errorCode)

proc finishConnect*(socket: Socket): bool =
  if not socket.isValid:
    return false
  finishTcpConnect(socket.handle)

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

proc acceptWithPeer*(server: Socket; peer: var Endpoint): Socket =
  if not server.isValid:
    peer = invalidEndpoint()
    return invalidSocket()
  var tcpPeer = invalidTcpEndpoint()
  let handle = acceptTcpWithPeer(server.handle, tcpPeer)
  peer = endpointFromTcp(tcpPeer)
  Socket(handle: handle)

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
  ## Read up to `maxBytes` bytes into a growable string, looping until `maxBytes`
  ## are read or the peer signals EOF / a nonblocking read would block. Unlike a
  ## single `recvInto`, this is not silently capped at 8192 bytes.
  result = ""
  if not socket.isValid:
    return result
  var remaining = maxBytes
  if remaining < 0:
    remaining = 0
  var buf = default(array[8192, char])
  while remaining > 0:
    var chunk = buf.len
    if chunk > remaining:
      chunk = remaining
    let n = recvInto(socket, addr buf[0], chunk)
    if n <= 0:
      break
    var i = 0
    while i < n:
      result.add buf[i]
      inc i
    remaining = remaining - n

proc readAll*(socket: Socket): string =
  ## Read the whole stream until the peer closes (EOF) or a read stops making
  ## progress. Loops `recvInto` into a growable string.
  result = ""
  if not socket.isValid:
    return result
  var buf = default(array[8192, char])
  while true:
    let n = recvInto(socket, addr buf[0], buf.len)
    if n <= 0:
      break
    var i = 0
    while i < n:
      result.add buf[i]
      inc i

type
  BufferedSocket* = object
    ## A small buffered reader over a `Socket`. Owns a pending-byte buffer so
    ## line-oriented protocols can read a line at a time without over-reading
    ## past the terminator on the underlying socket.
    socket*: Socket
    buffer: string
    pos: int

proc newBufferedSocket*(socket: Socket): BufferedSocket =
  ## Wrap a socket in a buffered reader.
  BufferedSocket(socket: socket, buffer: "", pos: 0)

proc bufferedSocket*(socket: Socket): BufferedSocket =
  ## Alias for `newBufferedSocket`.
  newBufferedSocket(socket)

proc fillBuffer(reader: var BufferedSocket): int =
  ## Pull one chunk from the socket into the pending buffer. Returns the number
  ## of bytes appended (0 at EOF / would-block / error).
  var buf = default(array[8192, char])
  let n = recvInto(reader.socket, addr buf[0], buf.len)
  if n <= 0:
    return 0
  var i = 0
  while i < n:
    reader.buffer.add buf[i]
    inc i
  n

proc recvLine*(reader: var BufferedSocket): string =
  ## Read one CRLF- or LF-terminated line, stripping the terminator. Any bytes
  ## read past the newline stay buffered for the next call. Returns "" at EOF
  ## with no buffered data left.
  result = ""
  while true:
    var i = reader.pos
    while i < reader.buffer.len:
      if reader.buffer[i] == '\n':
        var j = reader.pos
        while j < i:
          if not (j == i - 1 and reader.buffer[j] == '\r'):
            result.add reader.buffer[j]
          inc j
        reader.pos = i + 1
        return result
      inc i
    # No newline in the buffered region; pull more bytes.
    if fillBuffer(reader) == 0:
      # EOF: return any remaining buffered bytes as a final unterminated line.
      var j = reader.pos
      while j < reader.buffer.len:
        if not (j == reader.buffer.len - 1 and reader.buffer[j] == '\r'):
          result.add reader.buffer[j]
        inc j
      reader.pos = reader.buffer.len
      return result

proc recv*(reader: var BufferedSocket; maxBytes: int): string =
  ## Read up to `maxBytes` bytes, draining any buffered bytes first (so it
  ## composes with `recvLine`), then reading from the socket.
  result = ""
  var remaining = maxBytes
  if remaining < 0:
    remaining = 0
  while remaining > 0 and reader.pos < reader.buffer.len:
    result.add reader.buffer[reader.pos]
    inc reader.pos
    remaining = remaining - 1
  if remaining > 0:
    result.add recv(reader.socket, remaining)

proc readAll*(reader: var BufferedSocket): string =
  ## Read everything left, draining the buffer first, then the socket to EOF.
  result = ""
  while reader.pos < reader.buffer.len:
    result.add reader.buffer[reader.pos]
    inc reader.pos
  result.add readAll(reader.socket)

proc dial*(host: string; port: int): SocketConnectResult =
  ## Resolve `host` and try each resolved address in turn until one connects
  ## (happy-eyeballs-lite). Now family-agnostic: `connectHostTcp` enumerates the
  ## full getaddrinfo result set — every AAAA (IPv6) and A (IPv4) address — and
  ## returns the first that accepts. Returns a connected socket, or a failed
  ## result whose `errorCode` is the last connect error.
  let h = connectHostTcp(host, port)
  if isValidTcp(h):
    return SocketConnectResult(
      socket: Socket(handle: h),
      status: socketConnectConnected,
      errorCode: 0
    )
  SocketConnectResult(
    socket: invalidSocket(),
    status: socketConnectFailed,
    errorCode: lastNetErrorCode()
  )

proc connectTimeout*(hostOrderAddr: uint32; port: int; millis: int): SocketConnectResult =
  ## Blocking connect bounded by `millis`, wrapping tcp's `connectTcp4Timeout`.
  socketConnectResultFromTcp(connectTcp4Timeout(hostOrderAddr, port, millis))

proc connectTimeout*(ip: Ipv4Address; port: int; millis: int): SocketConnectResult =
  ## Blocking connect bounded by `millis`, wrapping tcp's `connectTcp4Timeout`.
  socketConnectResultFromTcp(connectTcp4Timeout(ipv4Value(ip), port, millis))

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
