///|
test "ISO BMFF requires an ftyp box" {
  assert_eq(detect_format(b"\x00\x00\x00\x18xxxxavif"), Unknown)
}

///|
test "AVIF compatible brand is detected within bounded header scan" {
  assert_eq(
    detect_format(b"\x00\x00\x00\x18ftypisom\x00\x00\x00\x00avif"),
    Avif,
  )
}
