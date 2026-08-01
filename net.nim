## net — small blocking network API.

import tcp
import net/address
import net/tcpnet
export address
export tcpnet
## `tcp` is re-exported: a `Socket` is a thin wrapper over a `TcpHandle`, and
## without this every socket option `net` does not itself wrap (SO_REUSEPORT,
## SO_LINGER, buffer sizes, the generic `setTcpOption` escape hatch) would need
## a second import plus reaching into `socket.handle`.
export tcp
