# net

Small blocking network API for Nimony.

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
| `Ipv4Address`, `ipv4`, `parseIpv4`, `localhostIpv4` | IPv4 address helpers |
| `invalidSocket`, `isValid` | socket state helpers |
| `initNet`, `shutdownNet` | platform lifecycle |
| `listen`, `accept`, `connect`, `connectLocalhost` | socket operations |
| `setNoDelay`, `setKeepAlive` | common TCP socket options |
| `recvInto`, `sendFrom`, `sendAllFrom` | pointer-buffer I/O |
| `recv`, `send`, `sendAll` | string convenience I/O |
| `close`, `closeAndInvalidate` | close a socket |

## Notes

* Blocking API by design.
* Built on the `tcp` package.
* No framework runtime.

## License

MIT.
