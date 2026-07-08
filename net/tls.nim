## net/tls.nim — TLS/SSL for `net`, over OpenSSL 3 (libssl.so.3 / libcrypto.so.3).
##
## A `TlsSocket` wraps a connected blocking `Socket` and drives the handshake
## and record layer through OpenSSL. Both roles are supported: a client context
## (`newTlsClientContext`, SNI + certificate verification + ALPN + hostname
## checking) and a server context (`newTlsServerContext`, certificate + key).
##
## Design in the aoughwl idiom: status-based returns (`TlsStatus`), no
## exceptions, caller-owned buffers, opaque handles as `pointer` (nil-checked).
## The context holds the long-lived `SSL_CTX`; each connection gets its own
## `SSL`. Works with blocking or non-blocking sockets — on a non-blocking socket
## the handshake / read / write surface `tlsWantRead` / `tlsWantWrite` so a
## caller can drive it from a poll loop.

import tcpnet
import tcp

const
  sslLib = "libssl.so.3"
  cryptoLib = "libcrypto.so.3"

type
  TlsMode* = enum
    tlsClient, tlsServer

  TlsContext* = object
    ## A long-lived TLS configuration (wraps `SSL_CTX`). Reuse across many
    ## connections. `handle` is nil when construction failed.
    handle*: nil pointer
    mode*: TlsMode

  TlsSocket* = object
    ## One TLS connection over a `Socket` (wraps `SSL`). `ssl` is nil when
    ## invalid.
    socket*: Socket
    ssl*: nil pointer
    handshakeDone*: bool

  TlsStatus* = enum
    tlsOk,          ## operation completed
    tlsWantRead,    ## non-blocking: retry after the socket is readable
    tlsWantWrite,   ## non-blocking: retry after the socket is writable
    tlsClosed,      ## peer sent close_notify / clean EOF
    tlsError        ## fatal protocol or transport error

# ---------------------------------------------------------------------------
# OpenSSL FFI.  Opaque structs are `pointer`; we only ever pass them around.
# ---------------------------------------------------------------------------

const
  SSL_FILETYPE_PEM = cint(1)
  SSL_VERIFY_NONE = cint(0)
  SSL_VERIFY_PEER = cint(1)
  # SSL_get_error return codes.
  SSL_ERROR_NONE = cint(0)
  SSL_ERROR_SSL = cint(1)
  SSL_ERROR_WANT_READ = cint(2)
  SSL_ERROR_WANT_WRITE = cint(3)
  SSL_ERROR_SYSCALL = cint(5)
  SSL_ERROR_ZERO_RETURN = cint(6)
  # SSL_CTX_ctrl / SSL_ctrl command numbers (openssl/ssl.h).
  SSL_CTRL_SET_TLSEXT_HOSTNAME = cint(55)
  SSL_CTRL_SET_MIN_PROTO_VERSION = cint(123)
  SSL_CTRL_SET_MAX_PROTO_VERSION = cint(124)
  TLSEXT_NAMETYPE_host_name = clong(0)
  # X509_V_OK.
  X509_V_OK = clong(0)

const
  TLS1_VERSION* = 0x0301
  TLS1_1_VERSION* = 0x0302
  TLS1_2_VERSION* = 0x0303
  TLS1_3_VERSION* = 0x0304

proc TLS_client_method(): pointer {.cdecl, importc: "TLS_client_method", dynlib: sslLib.}
proc TLS_server_method(): pointer {.cdecl, importc: "TLS_server_method", dynlib: sslLib.}
proc SSL_CTX_new(meth: pointer): pointer {.cdecl, importc: "SSL_CTX_new", dynlib: sslLib.}
proc SSL_CTX_free(ctx: nil pointer) {.cdecl, importc: "SSL_CTX_free", dynlib: sslLib.}
proc SSL_CTX_set_verify(ctx: nil pointer; mode: cint; cb: nil pointer) {.cdecl, importc: "SSL_CTX_set_verify", dynlib: sslLib.}
proc SSL_CTX_set_default_verify_paths(ctx: nil pointer): cint {.cdecl, importc: "SSL_CTX_set_default_verify_paths", dynlib: sslLib.}
proc SSL_CTX_load_verify_locations(ctx: nil pointer; caFile: cstring; caPath: nil cstring): cint {.cdecl, importc: "SSL_CTX_load_verify_locations", dynlib: sslLib.}
proc SSL_CTX_use_certificate_chain_file(ctx: nil pointer; file: cstring): cint {.cdecl, importc: "SSL_CTX_use_certificate_chain_file", dynlib: sslLib.}
proc SSL_CTX_use_PrivateKey_file(ctx: nil pointer; file: cstring; typ: cint): cint {.cdecl, importc: "SSL_CTX_use_PrivateKey_file", dynlib: sslLib.}
proc SSL_CTX_check_private_key(ctx: nil pointer): cint {.cdecl, importc: "SSL_CTX_check_private_key", dynlib: sslLib.}
proc SSL_CTX_set_cipher_list(ctx: nil pointer; str: cstring): cint {.cdecl, importc: "SSL_CTX_set_cipher_list", dynlib: sslLib.}
proc SSL_CTX_set_ciphersuites(ctx: nil pointer; str: cstring): cint {.cdecl, importc: "SSL_CTX_set_ciphersuites", dynlib: sslLib.}
proc SSL_CTX_set_alpn_protos(ctx: nil pointer; protos: pointer; len: cuint): cint {.cdecl, importc: "SSL_CTX_set_alpn_protos", dynlib: sslLib.}
proc SSL_CTX_ctrl(ctx: nil pointer; cmd: cint; larg: clong; parg: nil pointer): clong {.cdecl, importc: "SSL_CTX_ctrl", dynlib: sslLib.}

proc SSL_new(ctx: nil pointer): pointer {.cdecl, importc: "SSL_new", dynlib: sslLib.}
proc SSL_free(ssl: nil pointer) {.cdecl, importc: "SSL_free", dynlib: sslLib.}
proc SSL_set_fd(ssl: nil pointer; fd: cint): cint {.cdecl, importc: "SSL_set_fd", dynlib: sslLib.}
proc SSL_ctrl(ssl: nil pointer; cmd: cint; larg: clong; parg: pointer): clong {.cdecl, importc: "SSL_ctrl", dynlib: sslLib.}
proc SSL_set1_host(ssl: nil pointer; host: cstring): cint {.cdecl, importc: "SSL_set1_host", dynlib: sslLib.}
proc SSL_set_connect_state(ssl: nil pointer) {.cdecl, importc: "SSL_set_connect_state", dynlib: sslLib.}
proc SSL_set_accept_state(ssl: nil pointer) {.cdecl, importc: "SSL_set_accept_state", dynlib: sslLib.}
proc SSL_connect(ssl: nil pointer): cint {.cdecl, importc: "SSL_connect", dynlib: sslLib.}
proc SSL_accept(ssl: nil pointer): cint {.cdecl, importc: "SSL_accept", dynlib: sslLib.}
proc SSL_do_handshake(ssl: nil pointer): cint {.cdecl, importc: "SSL_do_handshake", dynlib: sslLib.}
proc SSL_read(ssl: nil pointer; buf: pointer; num: cint): cint {.cdecl, importc: "SSL_read", dynlib: sslLib.}
proc SSL_write(ssl: nil pointer; buf: pointer; num: cint): cint {.cdecl, importc: "SSL_write", dynlib: sslLib.}
proc SSL_get_error(ssl: nil pointer; ret: cint): cint {.cdecl, importc: "SSL_get_error", dynlib: sslLib.}
proc SSL_shutdown(ssl: nil pointer): cint {.cdecl, importc: "SSL_shutdown", dynlib: sslLib.}
proc SSL_pending(ssl: nil pointer): cint {.cdecl, importc: "SSL_pending", dynlib: sslLib.}
proc SSL_get_verify_result(ssl: nil pointer): clong {.cdecl, importc: "SSL_get_verify_result", dynlib: sslLib.}
proc SSL_get_version(ssl: nil pointer): cstring {.cdecl, importc: "SSL_get_version", dynlib: sslLib.}
proc SSL_get_current_cipher(ssl: nil pointer): pointer {.cdecl, importc: "SSL_get_current_cipher", dynlib: sslLib.}
proc SSL_CIPHER_get_name(c: pointer): cstring {.cdecl, importc: "SSL_CIPHER_get_name", dynlib: sslLib.}
proc SSL_get0_alpn_selected(ssl: nil pointer; data: ptr pointer; len: ptr cuint) {.cdecl, importc: "SSL_get0_alpn_selected", dynlib: sslLib.}

proc ERR_get_error(): culong {.cdecl, importc: "ERR_get_error", dynlib: cryptoLib.}
proc ERR_error_string_n(e: culong; buf: pointer; len: csize_t) {.cdecl, importc: "ERR_error_string_n", dynlib: cryptoLib.}
proc ERR_clear_error() {.cdecl, importc: "ERR_clear_error", dynlib: cryptoLib.}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc cstrToString(cs: cstring): string =
  ## nimony has no `$`(cstring); walk the NUL-terminated bytes ourselves.
  result = ""
  if cast[pointer](cs) == nil: return
  let p = cast[ptr UncheckedArray[char]](cs)
  var i = 0
  while p[i] != '\0':
    result.add p[i]
    inc i

proc isValid*(ctx: TlsContext): bool =
  ctx.handle != nil

proc isValid*(t: TlsSocket): bool =
  t.ssl != nil

proc lastTlsError*(): string =
  ## Pop and format the most recent OpenSSL error, or "" when the queue is
  ## empty. Useful for logging a failed handshake.
  let e = ERR_get_error()
  if e == culong(0):
    return ""
  var buf = default(array[256, char])
  ERR_error_string_n(e, addr buf[0], csize_t(buf.len))
  result = ""
  var i = 0
  while i < buf.len and buf[i] != '\0':
    result.add buf[i]
    inc i

proc classify(ssl: nil pointer; ret: cint): TlsStatus =
  ## Map an OpenSSL return value + SSL_get_error into a TlsStatus.
  let err = SSL_get_error(ssl, ret)
  if err == SSL_ERROR_NONE:
    tlsOk
  elif err == SSL_ERROR_WANT_READ:
    tlsWantRead
  elif err == SSL_ERROR_WANT_WRITE:
    tlsWantWrite
  elif err == SSL_ERROR_ZERO_RETURN:
    tlsClosed
  elif err == SSL_ERROR_SYSCALL:
    # A clean transport EOF before close_notify shows up here with ret == 0.
    if ret == cint(0): tlsClosed else: tlsError
  else:
    tlsError

# ---------------------------------------------------------------------------
# Context construction / configuration
# ---------------------------------------------------------------------------

proc newTlsClientContext*(verify = true): TlsContext =
  ## A client context. When `verify` is true (default) the server certificate
  ## chain is validated against the system trust store; set false only for
  ## testing against self-signed certs (or call `setVerify`/`loadVerifyLocations`).
  let meth = TLS_client_method()
  let ctx = SSL_CTX_new(meth)
  result = TlsContext(handle: ctx, mode: tlsClient)
  if ctx == nil:
    return result
  if verify:
    discard SSL_CTX_set_default_verify_paths(ctx)
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, nil)
  else:
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nil)

proc newTlsServerContext*(certChainFile: string; keyFile: string): TlsContext =
  ## A server context loading a PEM certificate chain and its private key.
  ## Returns an invalid context (`isValid` false) if either file fails to load
  ## or the key does not match the certificate.
  var certc = certChainFile
  var keyc = keyFile
  let meth = TLS_server_method()
  let ctx = SSL_CTX_new(meth)
  result = TlsContext(handle: ctx, mode: tlsServer)
  if ctx == nil:
    return result
  if SSL_CTX_use_certificate_chain_file(ctx, toCString(certc)) != cint(1):
    SSL_CTX_free(ctx)
    result.handle = nil
    return result
  if SSL_CTX_use_PrivateKey_file(ctx, toCString(keyc), SSL_FILETYPE_PEM) != cint(1):
    SSL_CTX_free(ctx)
    result.handle = nil
    return result
  if SSL_CTX_check_private_key(ctx) != cint(1):
    SSL_CTX_free(ctx)
    result.handle = nil
    return result

proc setVerifyPeer*(ctx: TlsContext; enabled: bool) =
  ## Turn peer certificate verification on or off.
  if not ctx.isValid: return
  if enabled:
    SSL_CTX_set_verify(ctx.handle, SSL_VERIFY_PEER, nil)
  else:
    SSL_CTX_set_verify(ctx.handle, SSL_VERIFY_NONE, nil)

proc loadVerifyLocations*(ctx: TlsContext; caFile: string): bool =
  ## Trust an extra CA bundle / cert file (PEM). Returns success.
  if not ctx.isValid: return false
  var f = caFile
  SSL_CTX_load_verify_locations(ctx.handle, toCString(f), nil) == cint(1)

proc useDefaultVerifyPaths*(ctx: TlsContext): bool =
  ## (Re)load the system default trust store. Returns success.
  if not ctx.isValid: return false
  SSL_CTX_set_default_verify_paths(ctx.handle) == cint(1)

proc setCipherList*(ctx: TlsContext; ciphers: string): bool =
  ## Restrict the TLS 1.2-and-below cipher list (OpenSSL cipher string).
  if not ctx.isValid: return false
  var c = ciphers
  SSL_CTX_set_cipher_list(ctx.handle, toCString(c)) == cint(1)

proc setCipherSuites*(ctx: TlsContext; suites: string): bool =
  ## Restrict the TLS 1.3 cipher suites (colon-separated suite names).
  if not ctx.isValid: return false
  var s = suites
  SSL_CTX_set_ciphersuites(ctx.handle, toCString(s)) == cint(1)

proc setMinVersion*(ctx: TlsContext; version: int): bool =
  ## Floor the negotiated protocol version (e.g. `TLS1_2_VERSION`).
  if not ctx.isValid: return false
  SSL_CTX_ctrl(ctx.handle, SSL_CTRL_SET_MIN_PROTO_VERSION, clong(version), nil) == clong(1)

proc setMaxVersion*(ctx: TlsContext; version: int): bool =
  ## Cap the negotiated protocol version.
  if not ctx.isValid: return false
  SSL_CTX_ctrl(ctx.handle, SSL_CTRL_SET_MAX_PROTO_VERSION, clong(version), nil) == clong(1)

proc setAlpnProtocols*(ctx: TlsContext; protocols: seq[string]): bool =
  ## Advertise an ALPN protocol list, e.g. `@["h2", "http/1.1"]`. The wire
  ## format is a sequence of length-prefixed protocol names.
  if not ctx.isValid: return false
  if protocols.len == 0: return false
  var wire = ""
  var i = 0
  while i < protocols.len:
    let p = protocols[i]
    if p.len == 0 or p.len > 255:
      inc i
      continue
    wire.add char(p.len)
    var j = 0
    while j < p.len:
      wire.add p[j]
      inc j
    inc i
  if wire.len == 0: return false
  # SSL_CTX_set_alpn_protos returns 0 on success (note: inverted convention).
  # `toCString` yields a pointer to the string's bytes; the length is passed
  # explicitly so NUL-termination is irrelevant (and the wire has no NULs:
  # length prefixes are 1..255 and protocol names are ASCII).
  SSL_CTX_set_alpn_protos(ctx.handle, cast[pointer](toCString(wire)), cuint(wire.len)) == cint(0)

proc close*(ctx: var TlsContext) =
  ## Free the underlying `SSL_CTX`.
  if ctx.handle != nil:
    SSL_CTX_free(ctx.handle)
    ctx.handle = nil

# ---------------------------------------------------------------------------
# Handshake
# ---------------------------------------------------------------------------

proc handshake*(t: var TlsSocket): TlsStatus =
  ## Drive (or resume) the handshake. On a blocking socket this returns `tlsOk`
  ## once complete; on a non-blocking socket it may return `tlsWantRead` /
  ## `tlsWantWrite`, in which case call again after the socket is ready.
  if not t.isValid: return tlsError
  if t.handshakeDone: return tlsOk
  ERR_clear_error()
  let rc = SSL_do_handshake(t.ssl)
  if rc == cint(1):
    t.handshakeDone = true
    return tlsOk
  result = classify(t.ssl, rc)
  if result == tlsOk:
    t.handshakeDone = true

proc wrapClient*(ctx: TlsContext; socket: Socket; serverName: string): TlsSocket =
  ## Begin a client TLS session over an already-connected `socket`. Sets SNI and
  ## the verification hostname to `serverName`, then runs the handshake (blocking
  ## sockets complete here; use `handshake` to resume a non-blocking one). Check
  ## `handshakeDone` / `isValid` on the result.
  result = TlsSocket(socket: socket, ssl: nil, handshakeDone: false)
  if not ctx.isValid or not socket.isValid: return result
  let ssl = SSL_new(ctx.handle)
  if ssl == nil: return result
  if SSL_set_fd(ssl, cint(socket.handle)) != cint(1):
    SSL_free(ssl)
    return result
  SSL_set_connect_state(ssl)
  # SNI + hostname verification.
  var host = serverName
  if host.len > 0:
    discard SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name,
                     cast[pointer](toCString(host)))
    discard SSL_set1_host(ssl, toCString(host))
  result.ssl = ssl
  discard handshake(result)

proc connectTls*(ctx: TlsContext; host: string; port: int): TlsSocket =
  ## Ergonomic client entry: resolve `host`, open a TCP connection, and run the
  ## client TLS handshake with SNI + hostname verification set to `host`.
  ## Blocking; check `handshakeDone` / `isValid` on the result. The returned
  ## socket keeps `ctx` alive via OpenSSL's refcount, so `ctx` may be closed
  ## afterwards without tearing down live connections.
  result = TlsSocket(socket: invalidSocket(), ssl: nil, handshakeDone: false)
  if not ctx.isValid: return result
  var raw = 0'u32
  if not resolveTcp4(host, raw): return result
  let sock = Socket(handle: connectTcp4(raw, port))
  if not sock.isValid: return result
  result = wrapClient(ctx, sock, host)

proc wrapServer*(ctx: TlsContext; socket: Socket): TlsSocket =
  ## Begin a server TLS session over an accepted `socket` and run the handshake.
  result = TlsSocket(socket: socket, ssl: nil, handshakeDone: false)
  if not ctx.isValid or not socket.isValid: return result
  let ssl = SSL_new(ctx.handle)
  if ssl == nil: return result
  if SSL_set_fd(ssl, cint(socket.handle)) != cint(1):
    SSL_free(ssl)
    return result
  SSL_set_accept_state(ssl)
  result.ssl = ssl
  discard handshake(result)

# ---------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------

proc tlsReadInto*(t: var TlsSocket; buf: pointer; len: int; status: var TlsStatus): int =
  ## Read up to `len` bytes of plaintext. Returns the count (>0) with
  ## `status == tlsOk`; returns 0 with `tlsClosed` at end of stream, or with
  ## `tlsWantRead`/`tlsWantWrite` on a non-blocking socket, or `tlsError`.
  if not t.isValid:
    status = tlsError
    return -1
  if len <= 0:
    status = tlsOk
    return 0
  ERR_clear_error()
  let n = SSL_read(t.ssl, buf, cint(len))
  if n > cint(0):
    status = tlsOk
    return int(n)
  status = classify(t.ssl, n)
  0

proc tlsWriteFrom*(t: var TlsSocket; buf: pointer; len: int; status: var TlsStatus): int =
  ## Write up to `len` bytes of plaintext. Returns the count accepted (>0) with
  ## `status == tlsOk`, or 0 with a want/closed/error status.
  if not t.isValid:
    status = tlsError
    return -1
  if len <= 0:
    status = tlsOk
    return 0
  ERR_clear_error()
  let n = SSL_write(t.ssl, buf, cint(len))
  if n > cint(0):
    status = tlsOk
    return int(n)
  status = classify(t.ssl, n)
  0

proc pending*(t: TlsSocket): int =
  ## Bytes already decrypted and buffered inside OpenSSL (not yet visible to a
  ## raw socket poll). A caller polling the fd must drain these first.
  if not t.isValid: return 0
  int(SSL_pending(t.ssl))

proc recv*(t: var TlsSocket; maxBytes: int): string =
  ## Read up to `maxBytes` bytes of plaintext into a string (blocking-socket
  ## convenience). Stops at EOF or when a read makes no progress.
  result = ""
  if not t.isValid: return result
  var remaining = maxBytes
  if remaining < 0: remaining = 0
  var buf = default(array[8192, char])
  var st = tlsOk
  while remaining > 0:
    var chunk = buf.len
    if chunk > remaining: chunk = remaining
    let n = tlsReadInto(t, addr buf[0], chunk, st)
    if n <= 0: break
    var i = 0
    while i < n:
      result.add buf[i]
      inc i
    remaining = remaining - n

proc readAll*(t: var TlsSocket): string =
  ## Read plaintext until the peer closes the TLS session (blocking-socket
  ## convenience).
  result = ""
  if not t.isValid: return result
  var buf = default(array[8192, char])
  var st = tlsOk
  while true:
    let n = tlsReadInto(t, addr buf[0], buf.len, st)
    if n <= 0: break
    var i = 0
    while i < n:
      result.add buf[i]
      inc i

proc send*(t: var TlsSocket; data: string): int =
  ## Write the whole string (blocking-socket convenience). Returns bytes sent;
  ## a short return signals a closed / errored session.
  if not t.isValid: return 0
  var buf = default(array[8192, char])
  var total = 0
  var st = tlsOk
  while total < data.len:
    var n = 0
    while n < buf.len and total + n < data.len:
      buf[n] = data[total + n]
      inc n
    let written = tlsWriteFrom(t, addr buf[0], n, st)
    if written <= 0:
      return total
    total = total + written
  return total

proc sendAll*(t: var TlsSocket; data: string): bool =
  send(t, data) == data.len

# ---------------------------------------------------------------------------
# Connection info
# ---------------------------------------------------------------------------

proc protocolVersion*(t: TlsSocket): string =
  ## The negotiated protocol, e.g. "TLSv1.3".
  if not t.isValid: return ""
  cstrToString(SSL_get_version(t.ssl))

proc cipherName*(t: TlsSocket): string =
  ## The negotiated cipher suite name.
  if not t.isValid: return ""
  let c = SSL_get_current_cipher(t.ssl)
  if c == nil: return ""
  cstrToString(SSL_CIPHER_get_name(c))

proc negotiatedAlpn*(t: TlsSocket): string =
  ## The ALPN protocol the peer selected (e.g. "h2"), or "" if none.
  if not t.isValid: return ""
  var data = cast[pointer](0)
  var length = cuint(0)
  SSL_get0_alpn_selected(t.ssl, addr data, addr length)
  if data == nil or length == cuint(0): return ""
  let bytes = cast[ptr UncheckedArray[char]](data)
  result = ""
  var i = 0
  while i < int(length):
    result.add bytes[i]
    inc i

proc verifyOk*(t: TlsSocket): bool =
  ## True when the peer certificate chain verified (X509_V_OK). Meaningful only
  ## when the context requested verification.
  if not t.isValid: return false
  SSL_get_verify_result(t.ssl) == X509_V_OK

proc verifyResultCode*(t: TlsSocket): int =
  ## The raw X509 verification result code (0 == X509_V_OK).
  if not t.isValid: return -1
  int(SSL_get_verify_result(t.ssl))

# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------

proc closeTls*(t: var TlsSocket; closeSocket = true) =
  ## Send close_notify, free the `SSL`, and (by default) close the socket.
  if t.ssl != nil:
    discard SSL_shutdown(t.ssl)
    SSL_free(t.ssl)
    t.ssl = nil
  t.handshakeDone = false
  if closeSocket:
    t.socket.close()
