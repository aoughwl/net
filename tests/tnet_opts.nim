## tnet_opts.nim — socket policy, reached through `net` alone.
##
## The point of this file is what it does *not* import. `net` wraps `tcp` and
## for a long time did not re-export it, so `import net` gave a caller none of
## the socket options: they had to import `tcp` separately and reach into
## `socket.handle`. Every option below is named and applied without `tcp`
## appearing anywhere, and read back off the descriptor to prove it landed.

import std/syncio
import net

proc check(cond: bool; label: string) =
  if not cond:
    echo "FAIL: ", label
    quit(1)

proc main() =
  initNet()

  # TcpOpts, its constructors, the TriOpt values and the by-name option reader
  # are all in scope from `import net` alone. If the re-export regresses, this
  # file stops compiling — which is the assertion.
  var policy = defaultListenerOpts()
  policy.keepAlive = optOn
  policy.recvBufferSize = 131072

  var report = TcpOptsReport(applied: 0, failed: 0, firstFailure: "")
  let server = listen(localhostIpv4(), 0, policy, report)
  check(server.isValid, "listener created through net")
  check(report.failed == 0, "policy applied: " & report.firstFailure)

  var value = 0
  check(getTcpOptionByName(server.handle, "keepalive", value), "read keepalive")
  check(value != 0, "keepAlive reached the socket through net")
  check(getTcpOptionByName(server.handle, "rcvbuf", value), "read rcvbuf")
  check(value >= 131072, "recvBufferSize reached the socket through net")

  let port = localEndpoint(server).port
  check(port > 0, "listener bound to an ephemeral port")

  # A policy applied to an accepted connection. A listener's options do not
  # all carry over to the sockets it accepts, so this is a distinct operation
  # and not a nicety.
  var clientPolicy = defaultClientOpts()
  clientPolicy.noDelay = optOn
  var clientReport = TcpOptsReport(applied: 0, failed: 0, firstFailure: "")
  let client = connect(localhostIpv4(), port, clientPolicy, clientReport)
  check(client.isValid, "client connected: " & clientReport.firstFailure)
  check(clientReport.failed == 0, "client policy applied")

  let accepted = accept(server)
  check(accepted.isValid, "connection accepted")

  var acceptedPolicy = defaultTcpOpts()
  acceptedPolicy.noDelay = optOn
  acceptedPolicy.writeTimeoutMillis = 5000
  let acceptedReport = applyOpts(accepted, acceptedPolicy)
  check(ok(acceptedReport),
        "policy applied to an accepted socket: " & acceptedReport.firstFailure)
  check(acceptedReport.applied == 2, "exactly the two set fields were applied")
  check(getTcpOptionByName(accepted.handle, "nodelay", value), "read nodelay")
  check(value != 0, "noDelay reached the accepted socket")

  close(accepted)
  close(client)
  close(server)
  shutdownNet()
  echo "ok"

main()
