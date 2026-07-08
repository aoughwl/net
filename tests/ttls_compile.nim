## Compile-smoke for net/tls: exercises the type + proc surface so nimony
## semchecks and links the OpenSSL FFI. No network required.
import std/syncio
import net
import net/tls

proc main =
  initNet()
  var cctx = newTlsClientContext(verify = false)
  if not cctx.isValid:
    echo "client ctx invalid"
    quit(1)
  discard cctx.setMinVersion(TLS1_2_VERSION)
  discard cctx.setAlpnProtocols(@["h2", "http/1.1"])
  echo "client ctx ok"
  cctx.close()

  var sctx = newTlsServerContext("/nonexistent-cert.pem", "/nonexistent-key.pem")
  # Expected invalid: the files don't exist. Proves the load path is wired.
  if sctx.isValid:
    echo "unexpected: server ctx valid"
  else:
    echo "server ctx correctly invalid for missing files"
  echo "tls surface ok"

main()
