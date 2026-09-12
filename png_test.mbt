///|
fn test_png_append_u32(output : Array[Byte], value : UInt) -> Unit {
  output.push(((value >> 24) & 0xFFU).to_byte())
  output.push(((value >> 16) & 0xFFU).to_byte())
  output.push(((value >> 8) & 0xFFU).to_byte())
  output.push((value & 0xFFU).to_byte())
}

///|
fn test_png_crc32(data : Bytes, offset : Int, length : Int) -> UInt {
  let mut crc = 0xFFFFFFFFU
  for index in offset..<(offset + length) {
    crc = crc ^ data[index].to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1U) == 1U { (crc >> 1) ^ 0xEDB88320U } else { crc >> 1 }
    }
  }
  crc ^ 0xFFFFFFFFU
}

///|
fn test_png_chunk(
  name : String,
  payload : Bytes,
  corrupt_crc? : Bool = false,
) -> Bytes {
  let output : Array[Byte] = []
  test_png_append_u32(output, payload.length().reinterpret_as_uint())
  for character in name {
    output.push(character.to_int().to_byte())
  }
  for byte in payload {
    output.push(byte)
  }
  let current = Bytes::from_array(output.copy())
  let crc = test_png_crc32(current, 4, payload.length() + 4)
  test_png_append_u32(output, if corrupt_crc { crc ^ 1U } else { crc })
  Bytes::from_array(output)
}

///|
fn test_ihdr(color_type? : Byte = b'\x06') -> Bytes {
  test_png_chunk(
    "IHDR",
    b"\x00\x00\x00\x02\x00\x00\x00\x03\x08" +
    Bytes::from_array([color_type]) +
    b"\x00\x00\x00",
  )
}

///|
fn test_png(chunks : Array[Bytes], trailing? : Bytes = b"") -> Bytes {
  let output : Array[Byte] = []
  for byte in b"\x89PNG\x0D\x0A\x1A\x0A" {
    output.push(byte)
  }
  for chunk in chunks {
    for byte in chunk {
      output.push(byte)
    }
  }
  for byte in trailing {
    output.push(byte)
  }
  Bytes::from_array(output)
}

///|
fn test_minimal_png(
  extra_before_idat? : Array[Bytes] = [],
  extra_after_idat? : Array[Bytes] = [],
  color_type? : Byte = b'\x06',
  trailing? : Bytes = b"",
) -> Bytes {
  let chunks : Array[Bytes] = [test_ihdr(color_type~)]
  for chunk in extra_before_idat {
    chunks.push(chunk)
  }
  chunks.push(test_png_chunk("IDAT", b"\x78\x9C\x00"))
  for chunk in extra_after_idat {
    chunks.push(chunk)
  }
  chunks.push(test_png_chunk("IEND", b""))
  test_png(chunks, trailing~)
}

///|
fn test_png_metadata_named(
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
fn test_png_removal_named(
  items : Array[PngRemoval],
  name : String,
) -> PngRemoval? {
  for item in items {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
test "inspect PNG structure, dimensions, transparency, and CRC" {
  let png = test_minimal_png(
    extra_before_idat=[
      test_png_chunk("PLTE", b"\x00\x00\x00"),
      test_png_chunk("tRNS", b"\x00"),
    ],
    color_type=b'\x03',
  )
  let report = inspect_png(png).unwrap()
  assert_eq(report.info().format(), Png)
  assert_eq(report.info().dimensions(), Some({ width: 2, height: 3, }))
  assert_eq(report.info().has_alpha(), Some(true))
  assert_eq(report.info().is_animated(), Some(false))
  assert_eq(report.bit_depth(), 8)
  assert_eq(report.color_type(), 3)
  assert_eq(report.chunks().length(), 5)
}

///|
test "inspect PNG text, time, physical dimensions, and color profile" {
  let png = test_minimal_png(extra_before_idat=[
    test_png_chunk("tEXt", b"Author\x00Alice"),
    test_png_chunk("zTXt", b"Comment\x00\x00compressed"),
    test_png_chunk("iTXt", b"Description\x00\x00\x00\x00\x00Hello UTF-8"),
    test_png_chunk("tIME", b"\x07\xEA\x09\x0C\x0A\x1E\x2D"),
    test_png_chunk("pHYs", b"\x00\x00\x0E\xC4\x00\x00\x0E\xC4\x01"),
    test_png_chunk("iCCP", b"sRGB profile\x00\x00compressed"),
  ])
  let metadata = inspect_png(png).unwrap().info().metadata()
  guard test_png_metadata_named(metadata, "Author") is Some(author) else {
    fail("missing PNG author")
  }
  assert_eq(author.value, "Alice")
  assert_eq(author.disposition, Removable)
  assert_true(test_png_metadata_named(metadata, "Comment") is Some(_))
  assert_true(test_png_metadata_named(metadata, "Description") is Some(_))
  assert_true(
    test_png_metadata_named(metadata, "Last modification time") is Some(_),
  )
  assert_true(
    test_png_metadata_named(metadata, "Physical pixel dimensions") is Some(_),
  )
  guard test_png_metadata_named(metadata, "Color profile") is Some(profile) else {
    fail("missing PNG color profile")
  }
  assert_eq(profile.disposition, DisplayRequired)
}

///|
test "inspect PNG Exif and preserve only orientation" {
  let tiff = b"II\x2A\x00\x08\x00\x00\x00" +
    b"\x02\x00" +
    b"\x12\x01\x03\x00\x01\x00\x00\x00\x06\x00\x00\x00" +
    b"\x0F\x01\x02\x00\x06\x00\x00\x00\x26\x00\x00\x00" +
    b"\x00\x00\x00\x00Canon\x00"
  let original = test_minimal_png(extra_before_idat=[
    test_png_chunk("eXIf", tiff),
  ])
  let inspected = inspect_png(original).unwrap()
  assert_eq(inspected.orientation(), Some(6))
  assert_true(
    test_png_metadata_named(inspected.info().metadata(), "Camera maker")
    is Some(_),
  )
  let result = sanitize_png(original).unwrap()
  assert_true(result.verified())
  assert_true(result.output().find(b"Canon") is None)
  assert_eq(inspect_png(result.output()).unwrap().orientation(), Some(6))
}

///|
test "preserve APNG chunks and animation status" {
  let png = test_minimal_png(
    extra_before_idat=[
      test_png_chunk("acTL", b"\x00\x00\x00\x02\x00\x00\x00\x00"),
      test_png_chunk(
        "fcTL",
        b"\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x03" +
        b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x1E\x00\x00",
      ),
    ],
    extra_after_idat=[test_png_chunk("fdAT", b"\x00\x00\x00\x01data")],
  )
  let report = inspect_png(png).unwrap()
  assert_eq(report.info().is_animated(), Some(true))
  let cleaned = sanitize_png(png).unwrap()
  assert_true(cleaned.output().find(b"acTL") is Some(_))
  assert_true(cleaned.output().find(b"fcTL") is Some(_))
  assert_true(cleaned.output().find(b"fdAT") is Some(_))
}

///|
test "sanitize PNG metadata, unknown ancillary chunks, and trailing data" {
  let original = test_minimal_png(
    extra_before_idat=[
      test_png_chunk("tEXt", b"Location\x00secret"),
      test_png_chunk("vpAg", b"private"),
      test_png_chunk("gAMA", b"\x00\x00\xB1\x8F"),
    ],
    trailing=b"trailing",
  )
  let result = sanitize_png(original).unwrap()
  assert_true(result.verified())
  assert_true(result.removed_bytes() > 0)
  assert_true(result.output().find(b"secret") is None)
  assert_true(result.output().find(b"vpAg") is None)
  assert_true(result.output().find(b"gAMA") is Some(_))
  assert_true(
    test_png_removal_named(result.removed(), "PNG text (tEXt)") is Some(_),
  )
  assert_true(
    test_png_removal_named(result.removed(), "PNG ancillary chunk (vpAg)")
    is Some(_),
  )
  assert_true(
    test_png_removal_named(result.removed(), "Data after IEND") is Some(_),
  )
  assert_eq(sanitize_png(result.output()).unwrap().output(), result.output())
}

///|
test "reject unsafe PNG structures" {
  assert_true(inspect_png(b"not png") is Err(NotPng))
  assert_true(
    inspect_png(
      test_png([test_ihdr(), test_png_chunk("IDAT", b"x", corrupt_crc=true)]),
    )
    is Err(CrcMismatch(_, _, _)),
  )
  assert_true(
    inspect_png(
      test_png([test_png_chunk("IDAT", b"x"), test_png_chunk("IEND", b"")]),
    )
    is Err(MissingIhdr),
  )
  assert_true(
    inspect_png(test_png([test_ihdr(), test_png_chunk("IEND", b"")]))
    is Err(MissingIdat),
  )
  assert_true(
    inspect_png(test_png([test_ihdr(), test_png_chunk("IDAT", b"x")]))
    is Err(MissingIend),
  )
  let duplicate = test_png([
    test_ihdr(),
    test_ihdr(),
    test_png_chunk("IDAT", b"x"),
    test_png_chunk("IEND", b""),
  ])
  assert_true(inspect_png(duplicate) is Err(InvalidChunkOrder(_, _)))
}

///|
test "reject truncated, oversized, invalid, and nonconsecutive PNG chunks" {
  assert_true(
    inspect_png(test_png([b"\x00\x00\x00\x10tEXt"]))
    is Err(UnexpectedEof(_, _, _)),
  )
  assert_true(
    inspect_png(test_png([b"\x80\x00\x00\x00IHDR\x00\x00\x00\x00"]))
    is Err(InvalidChunkLength(_, _)),
  )
  assert_true(
    inspect_png(test_png([b"\x00\x00\x00\x00IHdR\x00\x00\x00\x00"]))
    is Err(InvalidChunkType(_)),
  )
  let separated_idat = test_png([
    test_ihdr(),
    test_png_chunk("IDAT", b"first"),
    test_png_chunk("tEXt", b"Comment\x00between"),
    test_png_chunk("IDAT", b"second"),
    test_png_chunk("IEND", b""),
  ])
  assert_true(inspect_png(separated_idat) is Err(InvalidChunkOrder(_, _)))
  let malformed_apng = test_minimal_png(extra_before_idat=[
    test_png_chunk("acTL", b"short"),
  ])
  assert_true(inspect_png(malformed_apng) is Err(InvalidChunkOrder(_, _)))
}

///|
test "inspect but refuse to sanitize an unknown critical PNG chunk" {
  let png = test_minimal_png(extra_before_idat=[
    test_png_chunk("ABCD", b"critical"),
  ])
  let report = inspect_png(png).unwrap()
  assert_eq(report.info().diagnostics()[0].code, "png.unknown-critical")
  assert_true(sanitize_png(png) is Err(UnknownCriticalChunk("ABCD", _)))
}
