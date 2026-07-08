# net

Small network API.

`net` provides a stdlib-style wrapper over the lower-level `tcp` package:

```nim
import net

initNet()
let server = listen(localhostIpv4(), 8080)
let client = accept(server)
let request = recv(client, 8192)
discard send(client, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
close(client)
close(server)
shutdownNet()
```

## API

| symbol | role |
|--------|------|
| `Socket` | wrapper around a native TCP handle |
| `Endpoint` | IPv4 address and port reported by the socket stack |
| `SocketConnectStatus`, `SocketConnectResult` | nonblocking connect result state |
| `Ipv4Address`, `ipv4`, `parseIpv4`, `localhostIpv4` | IPv4 address helpers |
| `` `$`(Ipv4Address) ``, `formatIpv4(Ipv4Address)`, `` `$`(Endpoint) `` | dotted-decimal / `"a.b.c.d:port"` formatting (round-trips `parseIpv4`) |
| `invalidSocket`, `isValid` | socket state helpers |
| `initNet`, `shutdownNet` | platform lifecycle |
| `lastNetErrorCode` | last platform socket error code for the current thread |
| `lastNetErrorKind`, `classifyNetErrorCode` | portable socket error classification |
| `netErrorWouldRetry`, `netErrorTimedOut`, `netErrorInterrupted`, `netErrorDisconnected` | common socket error predicates |
| `listen`, `accept`, `acceptWithPeer`, `connect`, `connectLocalhost` | socket operations |
| `connectNonBlocking`, `connectLocalhostNonBlocking` | start a nonblocking TCP connect |
| `resolveIpv4`, `connectHost`, `dial` | hostname resolution; `dial` tries each resolved address until one connects |
| `connectTimeout` | blocking connect bounded by a millisecond timeout |
| `connectHostNonBlocking`, `finishConnect`, `socketErrorCode` | hostname nonblocking connect and completion helpers |
| `invalidEndpoint`, `localEndpoint`, `peerEndpoint` | endpoint introspection |
| `setNoDelay`, `setKeepAlive` | common TCP socket options |
| `setReadTimeoutMillis`, `setWriteTimeoutMillis`, `setTimeoutMillis` | bound blocking socket I/O |
| `setBlocking`, `setNonBlocking` | switch socket blocking mode |
| `SocketPollRequest`, `SocketPollResult`, `poll` | wait for socket readiness |
| `waitReadable`, `waitWritable` | common readiness waits |
| `shutdownRead`, `shutdownWrite`, `shutdownBoth` | half-close or fully shut down socket traffic |
| `recvInto`, `sendFrom`, `sendAllFrom` | pointer-buffer I/O |
| `recv`, `send`, `sendAll` | string convenience I/O (`recv` loops to `maxBytes`/EOF, no 8192 cap) |
| `readAll` | read a socket to EOF into a string |
| `BufferedSocket`, `newBufferedSocket`, `recvLine` | buffered reader with CRLF/LF line reads for line protocols |
| `close`, `closeAndInvalidate` | close a socket |

## Notes

* Blocking operations by default, with explicit nonblocking connect and readiness helpers.
* Built on the `tcp` package.
* No framework runtime.

## License

MIT.
