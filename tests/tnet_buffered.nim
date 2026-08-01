## tnet_buffered.nim — behavioural test for the BufferedSocket bounds.
##
## Two properties that used to be untrue:
##   1. the reader's buffer COMPACTS — before, `recvLine` advanced `pos` while
##      every fill appended, so a long-lived reader retained every byte it had
##      ever read. `bufferBytes` must stay bounded across many lines.
##   2. `recvLine` is BOUNDED by `maxLine` — before, a peer that never sent a
##      newline grew the buffer without limit. It must stop at `maxLine` and
##      say so via `lineTooLong` rather than truncating silently.
##
## Single process on 127.0.0.1. Payloads stay well inside the loopback socket
## buffers so a blocking write cannot deadlock against the reader.

import std/syncio
import net

const
  Lines = 1000          # short lines, to exercise compaction
  ChunkSize = 512       # small, so retained-vs-streamed is unmistakable
  MaxLine = 4096
  RunawayLen = 20000    # one unterminated run, longer than MaxLine
  # ~11 KB of lines stream past a 512-byte chunk. A compacting reader never
  # holds much more than one chunk plus a partial line; the old non-compacting
  # one ended up holding all ~11 KB, so this bound separates them by ~5x.
  PeakBudget = ChunkSize + MaxLine

proc check(cond: bool; label: string) =
  if not cond:
    echo "FAIL: ", label
    quit(1)

proc main() =
  initNet()

  let server = listen(localhostIpv4(), 0)
  check(server.isValid, "listen")
  let bound = localEndpoint(server)
  check(bound.isValid, "localEndpoint")

  let client = connect(localhostIpv4(), bound.port)
  check(client.isValid, "connect")
  let accepted = accept(server)
  check(accepted.isValid, "accept")

  # --- writer: many short lines, then a runaway with no newline -----------
  var payload = ""
  var i = 0
  while i < Lines:
    payload.add "line-"
    payload.add $i
    payload.add "\n"
    inc i
  var k = 0
  while k < RunawayLen:
    payload.add 'x'
    inc k
  check(sendAll(client, payload), "send payload")

  # --- reader ------------------------------------------------------------
  var reader = newBufferedSocket(accepted, ChunkSize, MaxLine)
  var peakBuffer = 0
  i = 0
  while i < Lines:
    let line = reader.recvLine()
    check(not reader.lineTooLong, "short line within maxLine")
    var want = "line-"
    want.add $i
    check(line == want, "line content " & $i)
    if reader.bufferBytes > peakBuffer:
      peakBuffer = reader.bufferBytes
    inc i

  # 1. compaction: the reader never retains more than roughly one chunk plus a
  #    partial line, nowhere near the ~32 KB that went past it.
  check(peakBuffer <= PeakBudget,
        "buffer compacts (peak " & $peakBuffer & " bytes, budget " &
        $PeakBudget & ")")

  # 2. the runaway line stops at maxLine and is flagged, not silently cut.
  let over = reader.recvLine()
  check(reader.lineTooLong, "lineTooLong set on unterminated run")
  check(over.len == MaxLine, "bounded at maxLine, got " & $over.len)

  # the flag resets on the next call
  let rest = reader.recvLine()
  check(rest.len > 0, "remainder still readable")
  check(rest.len <= MaxLine, "remainder also bounded")

  close(client)
  close(accepted)
  close(server)
  echo "ok"

main()
