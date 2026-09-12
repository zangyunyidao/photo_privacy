///|
fn test_webp_append_u24(output : Array[Byte], value : Int) -> Unit {
  output.push((value & 0xFF).to_byte())
  output.push(((value >> 8) & 0xFF).to_byte())
  output.push(((value >> 16) & 0xFF).to_byte())
}

///|
fn test_webp_append_u32(output : Array[Byte], value : UInt) -> Unit {
  output.push((value & 0xFFU).to_byte())
  output.push(((value >> 8) & 0xFFU).to_byte())
  output.push(((value >> 16) & 0xFFU).to_byte())
  output.push(((value >> 24) & 0xFFU).to_byte())
}

///|
fn test_webp_chunk(
  name : String,
  payload : Bytes,
  bad_padding? : Bool = false,
) -> Bytes {
  let output : Array[Byte] = []
  for character in name {
    output.push(character.to_int().to_byte())
  }
  test_webp_append_u32(output, payload.length().reinterpret_as_uint())
  for byte in payload {
    output.push(byte)
  }
  if payload.length() % 2 == 1 {
    output.push(if bad_padding { b'\x01' } else { b'\x00' })
  }
  Bytes::from_array(output)
}

///|
fn test_webp_riff(chunks : Array[Bytes], trailing? : Bytes = b"") -> Bytes {
  let output : Array[Byte] = []
  for byte in b"RIFF\x00\x00\x00\x00WEBP" {
    output.push(byte)
  }
  for chunk in chunks {
    for byte in chunk {
      output.push(byte)
    }
  }
  let size = (output.length() - 8).reinterpret_as_uint()
  output[4] = (size & 0xFFU).to_byte()
  output[5] = ((size >> 8) & 0xFFU).to_byte()
  output[6] = ((size >> 16) & 0xFFU).to_byte()
  output[7] = ((size >> 24) & 0xFFU).to_byte()
  for byte in trailing {
    output.push(byte)
  }
  Bytes::from_array(output)
}

///|
fn test_vp8_payload(width : Int, height : Int) -> Bytes {
  Bytes::from_array([
    b'\x10',
    b'\x00',
    b'\x00',
    b'\x9D',
    b'\x01',
    b'\x2A',
    (width & 0xFF).to_byte(),
    ((width >> 8) & 0x3F).to_byte(),
    (height & 0xFF).to_byte(),
    ((height >> 8) & 0x3F).to_byte(),
  ])
}

///|
fn test_vp8l_payload(width : Int, height : Int, alpha : Bool) -> Bytes {
  let mut bits = (width - 1).reinterpret_as_uint() |
    ((height - 1).reinterpret_as_uint() << 14)
  if alpha {
    bits = bits | (1U << 28)
  }
  let output : Array[Byte] = [b'\x2F']
  test_webp_append_u32(output, bits)
  Bytes::from_array(output)
}

///|
fn test_vp8x_payload(flags : Int, width : Int, height : Int) -> Bytes {
  let output : Array[Byte] = [flags.to_byte(), b'\x00', b'\x00', b'\x00']
  test_webp_append_u24(output, width - 1)
  test_webp_append_u24(output, height - 1)
  Bytes::from_array(output)
}

///|
fn test_webp_metadata_named(
  items : Array[MetadataItem],
  name : String,
) -> MetadataItem? {
  for item in items {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn test_webp_removal_named(
  items : Array[WebpRemoval],
  name : String,
) -> WebpRemoval? {
  for item in items {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn test_webp_exif() -> Bytes {
  b"II\x2A\x00\x08\x00\x00\x00" +
  b"\x02\x00" +
  b"\x12\x01\x03\x00\x01\x00\x00\x00\x06\x00\x00\x00" +
  b"\x0F\x01\x02\x00\x06\x00\x00\x00\x26\x00\x00\x00" +
  b"\x00\x00\x00\x00Canon\x00"
}

///|
fn test_extended_webp(trailing? : Bytes = b"") -> Bytes {
  test_webp_riff(
    [
      test_webp_chunk("VP8X", test_vp8x_payload(0x3C, 16, 8)),
      test_webp_chunk("ICCP", b"color-profile"),
      test_webp_chunk("ALPH", b"\x00"),
      test_webp_chunk("VP8 ", test_vp8_payload(16, 8)),
      test_webp_chunk("EXIF", test_webp_exif()),
      test_webp_chunk("XMP ", b"<xmp>private</xmp>"),
      test_webp_chunk("META", b"private application data"),
    ],
    trailing~,
  )
}

///|
test "inspect simple lossy WebP" {
  let data = test_webp_riff([test_webp_chunk("VP8 ", test_vp8_payload(16, 8))])
  let report = inspect_webp(data).unwrap()
  assert_eq(report.info().format(), Webp)
  assert_eq(report.info().dimensions(), Some({ width: 16, height: 8, }))
  assert_eq(report.encoding(), Lossy)
  assert_eq(report.info().has_alpha(), Some(false))
  assert_eq(report.info().is_animated(), Some(false))
  assert_eq(report.chunks().length(), 1)
}

///|
test "inspect simple lossless WebP with alpha" {
  let data = test_webp_riff([
    test_webp_chunk("VP8L", test_vp8l_payload(9, 7, true)),
  ])
  let report = inspect_webp(data).unwrap()
  assert_eq(report.encoding(), Lossless)
  assert_eq(report.info().dimensions(), Some({ width: 9, height: 7, }))
  assert_eq(report.info().has_alpha(), Some(true))
}

///|
test "inspect extended WebP metadata and flags" {
  let report = inspect_webp(test_extended_webp()).unwrap()
  assert_eq(report.encoding(), Extended)
  assert_eq(report.info().dimensions(), Some({ width: 16, height: 8, }))
  assert_eq(report.info().has_alpha(), Some(true))
  assert_eq(report.orientation(), Some(6))
  let metadata = report.info().metadata()
  assert_true(test_webp_metadata_named(metadata, "Color profile") is Some(_))
  assert_true(test_webp_metadata_named(metadata, "Camera maker") is Some(_))
  assert_true(test_webp_metadata_named(metadata, "XMP") is Some(_))
  assert_true(
    test_webp_metadata_named(metadata, "Unknown RIFF chunk") is Some(_),
  )
}

///|
test "sanitize WebP metadata, unknown chunks, and trailing data" {
  let original = test_extended_webp(trailing=b"trailing")
  let result = sanitize_webp(original).unwrap()
  assert_true(result.verified())
  assert_true(result.output().find(b"private") is None)
  assert_true(result.output().find(b"Canon") is None)
  assert_true(result.output().find(b"ICCP") is Some(_))
  assert_true(result.output().find(b"ALPH") is Some(_))
  assert_true(result.output().find(test_vp8_payload(16, 8)) is Some(_))
  assert_true(
    test_webp_removal_named(result.removed(), "WebP Exif (EXIF)") is Some(_),
  )
  assert_true(
    test_webp_removal_named(result.removed(), "WebP XMP (XMP )") is Some(_),
  )
  assert_true(
    test_webp_removal_named(result.removed(), "WebP unknown chunk (META)")
    is Some(_),
  )
  assert_true(
    test_webp_removal_named(result.removed(), "Data after RIFF") is Some(_),
  )
  let cleaned = inspect_webp(result.output()).unwrap()
  assert_eq(cleaned.orientation(), Some(6))
  assert_true(
    test_webp_metadata_named(cleaned.info().metadata(), "Camera maker") is None,
  )
  assert_eq(sanitize_webp(result.output()).unwrap().output(), result.output())
}

///|
test "preserve animated WebP while removing nested unknown chunks" {
  let frame_header : Array[Byte] = []
  test_webp_append_u24(frame_header, 0)
  test_webp_append_u24(frame_header, 0)
  test_webp_append_u24(frame_header, 1)
  test_webp_append_u24(frame_header, 1)
  test_webp_append_u24(frame_header, 100)
  frame_header.push(b'\x00')
  let frame : Array[Byte] = frame_header
  for byte in test_webp_chunk("VP8 ", test_vp8_payload(2, 2)) {
    frame.push(byte)
  }
  for byte in test_webp_chunk("JUNK", b"secret") {
    frame.push(byte)
  }
  let data = test_webp_riff([
    test_webp_chunk("VP8X", test_vp8x_payload(0x02, 2, 2)),
    test_webp_chunk("ANIM", b"\x00\x00\x00\xFF\x00\x00"),
    test_webp_chunk("ANMF", Bytes::from_array(frame)),
  ])
  let report = inspect_webp(data).unwrap()
  assert_eq(report.info().is_animated(), Some(true))
  assert_eq(report.frame_count(), 1)
  assert_eq(report.loop_count(), Some(0))
  let result = sanitize_webp(data).unwrap()
  assert_true(result.verified())
  assert_true(result.output().find(b"ANIM") is Some(_))
  assert_true(result.output().find(b"ANMF") is Some(_))
  assert_true(result.output().find(b"JUNK") is None)
  assert_true(result.output().find(test_vp8_payload(2, 2)) is Some(_))
}

///|
test "reject malformed WebP RIFF structures" {
  assert_true(inspect_webp(b"not webp") is Err(NotWebp))
  assert_true(
    inspect_webp(b"RIFF\x20\x00\x00\x00WEBP") is Err(UnexpectedEof(_, _, _)),
  )
  let bad_padding = test_webp_riff([
    test_webp_chunk("VP8L", test_vp8l_payload(1, 1, false), bad_padding=true),
  ])
  assert_true(inspect_webp(bad_padding) is Err(InvalidPadding(_, _)))
  let missing = test_webp_riff([
    test_webp_chunk("VP8X", test_vp8x_payload(0, 2, 2)),
  ])
  assert_true(inspect_webp(missing) is Err(MissingImageData))
  let reserved = test_webp_riff([
    test_webp_chunk("VP8X", test_vp8x_payload(0x80, 2, 2)),
  ])
  assert_true(inspect_webp(reserved) is Err(InvalidChunkLength(_, _, _)))
}
