## tnet.aowl — compile-time API smoke for net.

import net

var s = invalidSocket()
discard s.isValid()
discard recv(s, 16)
discard send(s, "")
discard sendAll(s, "")
s.closeAndInvalidate()
let c4: proc(hostOrderAddr: uint32; port: int): Socket = connect
let cl: proc(port: int): Socket = connectLocalhost
discard c4
discard cl
