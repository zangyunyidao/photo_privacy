///|
test "read integers in both byte orders" {
  let reader = BinaryReader::new(b"\x01\x02\x03\x04\x05\x06\x07\x08")
  assert_eq(reader.read_u16_be().unwrap(), 0x0102U)
  assert_eq(reader.read_u16_le().unwrap(), 0x0403U)
  assert_eq(reader.read_u32_be().unwrap(), 0x05060708U)
  assert_eq(reader.position(), 8)
  assert_eq(reader.remaining(), 0)
}

///|
test "read little-endian 32-bit value" {
  let reader = BinaryReader::new(b"\x78\x56\x34\x12")
  assert_eq(reader.read_u32_le().unwrap(), 0x12345678U)
}

///|
test "read views, skip, and seek" {
  let reader = BinaryReader::new(b"abcdef")
  assert_true(reader.read_view(2).unwrap().equal_to_bytes(b"ab"))
  assert_eq(reader.skip(2), Ok(()))
  assert_eq(reader.read_u8().unwrap().to_int(), 0x65)
  assert_eq(reader.seek(1), Ok(()))
  assert_true(reader.read_view(2).unwrap().equal_to_bytes(b"bc"))
}

///|
test "failed reads do not move the cursor" {
  let reader = BinaryReader::new(b"\x01\x02")
  assert_eq(reader.read_u32_be(), Err(UnexpectedEnd(0, 4, 2)))
  assert_eq(reader.position(), 0)
  assert_eq(reader.read_u8().unwrap().to_int(), 1)
}

///|
test "reject invalid lengths and positions" {
  let reader = BinaryReader::new(b"\x01\x02")
  assert_eq(reader.read_view(-1), Err(InvalidLength(-1)))
  assert_eq(reader.seek(3), Err(InvalidPosition(3, 2)))
  assert_eq(reader.skip(3), Err(UnexpectedEnd(0, 3, 2)))
  assert_eq(reader.position(), 0)
}

///|
test "empty and oversized reads fail safely" {
  let empty = BinaryReader::new(b"")
  assert_eq(empty.read_u8(), Err(UnexpectedEnd(0, 1, 0)))
  assert_eq(empty.read_view(0).unwrap().length(), 0)
  assert_eq(empty.position(), 0)
  let reader = BinaryReader::new(b"\x01")
  assert_eq(reader.read_view(0x7fffffff), Err(UnexpectedEnd(0, 0x7fffffff, 1)))
  assert_eq(reader.position(), 0)
}

///|
test "image reports own their metadata arrays" {
  let items = [
    MetadataItem::{
      source: "Exif.GPS",
      name: "GPSLatitude",
      value: "22.5",
      category: Location,
      risk: High,
      disposition: Removable,
    },
  ]
  let diagnostics : Array[ParseDiagnostic] = []
  let info = ImageInfo::new(
    Jpeg,
    128,
    Some({ width: 16, height: 8, }),
    Some(false),
    Some(false),
    items,
    diagnostics,
  )
  items.push(MetadataItem::{
    source: "Exif",
    name: "Model",
    value: "Example",
    category: Device,
    risk: Medium,
    disposition: Removable,
  })
  assert_eq(info.metadata().length(), 1)
  let exported = info.metadata()
  exported.clear()
  assert_eq(info.metadata().length(), 1)
  assert_eq(info.format(), Jpeg)
  assert_eq(info.file_size(), 128)
  assert_eq(info.dimensions(), Some({ width: 16, height: 8, }))
}
