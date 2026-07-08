# net

A stdlib-style network API for [Nimony](https://github.com/nim-lang/nimony), built
on `tcp` — the middle layer of the `tcp → net → serve` stack. Wraps raw handles in a
`Socket` value with an `Ipv4Address`/`Endpoint` model, string-convenience I/O, a
buffered line reader, and connect helpers (`dial`, `connectTimeout`). Status-based
errors, no exceptions.

**📖 Full docs → [aoughwl.github.io/docs/net-stack](https://aoughwl.github.io/docs/net-stack)**

```nim
import net
```

`recv(sock, maxBytes)` loops to `maxBytes`/EOF (no hidden 8192 cap); `readAll` drains
to EOF; `BufferedSocket` gives `recvLine` (CRLF/LF). Same `NetErrorKind` model as `tcp`.
