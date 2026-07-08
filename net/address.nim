## net/address.nim — small IPv4 address helpers.

import tcp

type
  Ipv4Address* = object
    value*: uint32

proc ipv4*(a, b, c, d: int): Ipv4Address =
  if a < 0 or a > 255:
    return Ipv4Address(value: 0'u32)
  if b < 0 or b > 255:
    return Ipv4Address(value: 0'u32)
  if c < 0 or c > 255:
    return Ipv4Address(value: 0'u32)
  if d < 0 or d > 255:
    return Ipv4Address(value: 0'u32)
  Ipv4Address(
    value:
      (uint32(a) shl 24) or
      (uint32(b) shl 16) or
      (uint32(c) shl 8) or
      uint32(d)
  )

proc anyIpv4*(): Ipv4Address =
  Ipv4Address(value: 0'u32)

proc localhostIpv4*(): Ipv4Address =
  Ipv4Address(value: 0x7f000001'u32)

proc ipv4Value*(ip: Ipv4Address): uint32 =
  ip.value

proc formatIpv4*(ip: Ipv4Address): string =
  ## Format an `Ipv4Address` as dotted-decimal text "a.b.c.d". Delegates to the
  ## `tcp` package's host-order `formatIpv4(uint32)`. Inverse of `parseIpv4`.
  formatIpv4(ip.value)

proc `$`*(ip: Ipv4Address): string =
  ## Dotted-decimal string form, e.g. `$ipv4(127, 0, 0, 1) == "127.0.0.1"`.
  formatIpv4(ip.value)

proc parseIpv4*(s: string; dest: var Ipv4Address): bool =
  var part = 0
  var octet = 0
  var sawDigit = false
  var value = 0'u32
  var i = 0

  while i < s.len:
    let ch = s[i]
    if ch >= '0' and ch <= '9':
      sawDigit = true
      octet = octet * 10 + (ord(ch) - ord('0'))
      if octet > 255:
        return false
    elif ch == '.':
      if not sawDigit or part >= 3:
        return false
      value = (value shl 8) or uint32(octet)
      inc part
      octet = 0
      sawDigit = false
    else:
      return false
    inc i

  if not sawDigit or part != 3:
    return false
  dest = Ipv4Address(value: (value shl 8) or uint32(octet))
  return true
