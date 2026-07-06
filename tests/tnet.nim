## tnet.aowl — compile-time API smoke for net.

import net

var s = invalidSocket()
discard s.isValid()
discard recv(s, 16)
discard send(s, "")
discard sendAll(s, "")
s.closeAndInvalidate()
