# net

A stdlib-style network API for [Nimony](https://github.com/nim-lang/nimony),
built on the `tcp` package — the middle layer of the
`tcp → net → serve` stack. Where `tcp` hands you raw handles and pointer buffers,
`net` wraps them in a `Socket` value with an `Ipv4Address`/`Endpoint` model,
string-convenience I/O, a buffered line reader, and higher-level connect helpers
(`dial`, `connectTimeout`). It keeps `tcp`'s stance throughout: nimony-native,
no framework runtime, status-based errors instead of exceptions, IPv4 and
blocking I/O by default.

## Contents

- [Motivation](#motivation)
- [API](#api)
- [Layout](#layout)
- [Design notes](#design-notes)
- [Limitations](#limitations)
- [Testing](#testing)
- [Requirements](#requirements)
- [License](#license)

## Motivation

`std/net` is the Nim2 ergonomic layer over `nativesockets`: a `Socket` object,
`send`/`recv`, `recvLine`, address helpers. It is also Nim-2 code that raises,
allocates, and pulls in SSL/`selectors` machinery. `net` rebuilds that
ergonomics on top of `tcp` without inheriting the exception model:

| Problem with the Nim2 stdlib path | `net`'s approach |
|-----------------------------------|------------------|
| `std/net` `recv`/`send` raise on error and `recv` is capped by the buffer size you pass | `recv`/`send` return; `recv(sock, maxBytes)` loops to `maxBytes`/EOF with no hidden 8192 cap, and `readAll` drains to EOF. |
| `newSocket`/`connect` take `Port`, `Domain`, host strings and resolve inline | `Socket` wraps a `TcpHandle`; `Ipv4Address` is a typed `uint32`; `dial` does happy-eyeballs-lite over every resolved address. |
| `recvLine` lives on a socket that buffers opaquely | `BufferedSocket` is an explicit reader with `recvLine` (CRLF/LF) and `readAll`, so line protocols compose predictably. |
| Errors are `OSError` exceptions | Same status-code + classified `NetErrorKind` model as `tcp`, re-exposed under `net*` names. |

## API

Everything is available from `import net`; the `tcp` layer is a dependency, not
re-exported. Grouped by concern; ✅ marks the current, tested surface.

### Sockets, addresses & lifecycle

| Symbol | Role | |
|--------|------|---|
| `Socket`, `invalidSocket`, `isValid` | wrapper around a native TCP handle + state helpers | ✅ |
| `Endpoint`, `invalidEndpoint`, `localEndpoint`, `peerEndpoint` | IPv4 address + port introspection | ✅ |
| `Ipv4Address`, `ipv4`, `ipv4Value`, `parseIpv4`, `localhostIpv4`, `anyIpv4` | typed IPv4 address helpers | ✅ |
| `` `$`(Ipv4Address) ``, `` `$`(Endpoint) ``, `formatIpv4(Ipv4Address)` | dotted-decimal / `"a.b.c.d:port"` formatting (round-trips `parseIpv4`) | ✅ |
| `initNet`, `shutdownNet` | platform socket subsystem lifecycle | ✅ |
| `close`, `closeAndInvalidate` | close a socket | ✅ |

### Errors

| Symbol | Role | |
|--------|------|---|
| `lastNetErrorCode` | last platform error code for the current thread | ✅ |
| `lastNetErrorKind`, `classifyNetErrorCode` | portable error classification | ✅ |
| `netErrorWouldRetry`, `netErrorTimedOut`, `netErrorInterrupted`, `netErrorDisconnected` | common error predicates | ✅ |

### Connect / listen / accept

| Symbol | Role | |
|--------|------|---|
| `listen`, `accept`, `acceptWithPeer` | server-side socket operations | ✅ |
| `connect`, `connectLocalhost` | blocking connect to an `Endpoint`/port | ✅ |
| `resolveIpv4`, `connectHost` | hostname resolution + connect | ✅ |
| `dial` | resolve a host and try each address until one connects (happy-eyeballs-lite) | ✅ |
| `connectTimeout` | blocking connect bounded by a millisecond timeout | ✅ |
| `connectNonBlocking`, `connectLocalhostNonBlocking`, `connectHostNonBlocking` | start a nonblocking connect | ✅ |
| `SocketConnectStatus`, `SocketConnectResult`, `finishConnect`, `socketErrorCode` | inspect / complete a nonblocking connect | ✅ |

### I/O

| Symbol | Role | |
|--------|------|---|
| `recvInto`, `sendFrom`, `sendAllFrom` | pointer-buffer I/O (caller-owned) | ✅ |
| `recv`, `send`, `sendAll` | string-convenience I/O (`recv` loops to `maxBytes`/EOF, no 8192 cap) | ✅ |
| `readAll` | read a socket to EOF into a string | ✅ |
| `BufferedSocket`, `bufferedSocket`, `newBufferedSocket`, `recvLine` | buffered reader with CRLF/LF line reads for line protocols | ✅ |

### Blocking mode, timeouts, readiness, shutdown

| Symbol | Role | |
|--------|------|---|
| `setNoDelay`, `setKeepAlive` | common TCP options | ✅ |
| `setBlocking`, `setNonBlocking` | switch blocking mode | ✅ |
| `setReadTimeoutMillis`, `setWriteTimeoutMillis`, `setTimeoutMillis` | bound blocking socket I/O | ✅ |
| `SocketPollRequest`, `SocketPollResult`, `poll`, `waitReadable`, `waitWritable` | wait for socket readiness | ✅ |
| `shutdownRead`, `shutdownWrite`, `shutdownBoth` | half-close or fully shut down traffic | ✅ |

```nim
import net

initNet()
let server = listen(localhostIpv4(), 8080)
let client = accept(server)

var reader = newBufferedSocket(client)
let requestLine = recvLine(reader)          # e.g. "GET / HTTP/1.1"
discard send(client, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")

close(client)
close(server)
shutdownNet()
```

## Layout

```
net/
├── net.nim             umbrella: imports and re-exports the net/ modules
├── net/
│   ├── address.nim     Ipv4Address / Endpoint types, ipv4/parseIpv4, $ formatting
│   └── tcpnet.nim      Socket over tcp: connect/listen/accept, I/O, dial,
│                       BufferedSocket/recvLine, timeouts, poll, options
├── tests/
│   ├── tnet.nim        compile-time API smoke (every symbol referenced once)
│   └── tnet_loopback.nim  real loopback test: connect/accept + recvLine + readAll
├── net.nimble          requires "tcp"
└── README.md
```

## Design notes

- **Thin wrapper, same stance.** `net` adds a `Socket`/`Endpoint`/`Ipv4Address`
  value model and convenience I/O on top of `tcp`, but keeps the status-based
  error model, caller-owned pointer buffers (`recvInto`/`sendFrom`), and
  blocking-by-default posture unchanged.
- **Uncapped, EOF-aware reads.** `recv(sock, maxBytes)` loops until `maxBytes` or
  EOF rather than returning one syscall's worth, and `readAll` drains to EOF —
  no silent 8192-byte cap like the naive stdlib pattern.
- **Explicit buffering.** `BufferedSocket` owns its own read buffer so `recvLine`
  can hand back CRLF/LF-terminated lines without losing the bytes that follow,
  which is what makes line-oriented protocols (HTTP request lines, etc.) work.
- **Char-walk parsing.** Address formatting/parsing walks characters instead of
  taking string slices, because nimony string slices are `.raises`.
- **Status-based errors.** The `net*` error names re-expose `tcp`'s classified
  error model; nothing raises.

## Limitations

The roadmap toward fully superseding `std/net`:

- **IPv4 only** — no IPv6 addresses or endpoints (`resolveIpv4`/`dial` are v4).
- **TCP only** — no UDP and no Unix-domain sockets.
- **No TLS/SSL** — plaintext transport only.
- Single-thread, blocking-first; concurrency is the caller's to build from the
  nonblocking connect + `poll` primitives.

## Testing

Two tests: a compile-time smoke that references every exported symbol, and a
real single-process loopback test that round-trips address formatting/parse,
does a nonblocking connect + `poll` + accept handshake, and runs a small
line-oriented request/response through `recvLine` plus `readAll` on `127.0.0.1`.

```bash
cd /home/savant/aoughwl-net
nimony c -r --path:/home/savant/aoughwl-tcp --path:/home/savant/aoughwl-net tests/tnet_loopback.nim   # prints: ok
nimony c -r --path:/home/savant/aoughwl-tcp --path:/home/savant/aoughwl-net tests/tnet.nim            # compiles clean
```

## Requirements

A built [Nimony](https://github.com/nim-lang/nimony) toolchain providing the
`nimony` compiler on `PATH`, and the sibling `tcp` package on
the module path (`--path`). No third-party dependencies.

## License

MIT.
