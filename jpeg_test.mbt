///|
fn sample_jpeg_with_metadata() -> Bytes {
  b"\xFF\xD8" +
  b"\xFF\xE1\x00\x34Exif\x00\x00" +
  b"II\x2A\x00\x08\x00\x00\x00" +
  b"\x02\x00" +
  b"\x12\x01\x03\x00\x01\x00\x00\x00\x06\x00\x00\x00" +
  b"\x0F\x01\x02\x00\x06\x00\x00\x00\x26\x00\x00\x00" +
  b"\x00\x00\x00\x00Canon\x00" +
  b"\xFF\xED\x00\x0BPhotoshop" +
  b"\xFF\xFE\x00\x07hello" +
  b"\xFF\xC0\x00\x0B\x08\x00\x08\x00\x10\x01\x01\x11\x00" +
  b"\xFF\xDA\x00\x08\x01\x01\x00\x00\x3F\x00" +
  b"\x11\x22\xFF\x00\x33\xFF\xD0\x44" +
  b"\xFF\xD9trailing"
}

///|
fn metadata_named(items : Array[MetadataItem], name : String) -> MetadataItem? {
  for item in items {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn removal_named(items : Array[JpegRemoval], name : String) -> JpegRemoval? {
  for item in items {
    if item.name == name {
      return Some(item)
    }
  }
  None
}

///|
fn sample_jpeg_with_nested_exif() -> Bytes {
  b"\xFF\xD8" +
  b"\xFF\xE1\x00\x8AExif\x00\x00" +
  b"II\x2A\x00\x08\x00\x00\x00" +
  b"\x02\x00" +
  b"\x69\x87\x04\x00\x01\x00\x00\x00\x26\x00\x00\x00" +
  b"\x25\x88\x04\x00\x01\x00\x00\x00\x38\x00\x00\x00" +
  b"\x00\x00\x00\x00" +
  b"\x01\x00" +
  b"\x03\x90\x02\x00\x14\x00\x00\x00\x56\x00\x00\x00" +
  b"\x00\x00\x00\x00" +
  b"\x02\x00" +
  b"\x01\x00\x02\x00\x02\x00\x00\x00N\x00\x00\x00" +
  b"\x02\x00\x05\x00\x03\x00\x00\x00\x6A\x00\x00\x00" +
  b"\x00\x00\x00\x00" +
  b"2026:09:11 12:34:56\x00" +
  b"\x16\x00\x00\x00\x01\x00\x00\x00" +
  b"\x1E\x00\x00\x00\x01\x00\x00\x00" +
  b"\x00\x00\x00\x00\x01\x00\x00\x00" +
  b"\xFF\xD9"
}

///|
test "inspect JPEG structure, dimensions, and Exif" {
  let report = inspect_jpeg(sample_jpeg_with_metadata()).unwrap()
  assert_eq(report.info().format(), Jpeg)
  assert_eq(report.info().dimensions(), Some({ width: 16, height: 8, }))
  assert_eq(report.info().has_alpha(), Some(false))
  assert_eq(report.info().is_animated(), Some(false))
  assert_eq(report.orientation(), Some(6))
  assert_true(report.segments().length() >= 7)
  let metadata = report.info().metadata()
  assert_true(metadata_named(metadata, "Camera maker") is Some(_))
  assert_true(metadata_named(metadata, "Orientation") is Some(_))
  assert_true(metadata_named(metadata, "Comment") is Some(_))
  assert_true(metadata_named(metadata, "IPTC/Photoshop resources") is Some(_))
  assert_true(report.info().diagnostics().length() == 1)
}

///|
test "inspect nested Exif and GPS IFDs" {
  let report = inspect_jpeg(sample_jpeg_with_nested_exif()).unwrap()
  let metadata = report.info().metadata()
  guard metadata_named(metadata, "Original capture time") is Some(captured) else {
    fail("missing Exif capture time")
  }
  assert_eq(captured.value, "2026:09:11 12:34:56")
  guard metadata_named(metadata, "Latitude reference") is Some(latitude_ref) else {
    fail("missing GPS latitude reference")
  }
  assert_eq(latitude_ref.value, "N")
  guard metadata_named(metadata, "Latitude") is Some(latitude) else {
    fail("missing GPS latitude")
  }
  assert_eq(latitude.value, "22/1, 30/1, 0/1")
  assert_eq(latitude.risk, High)
  assert_eq(latitude.disposition, Removable)
}

///|
test "report malformed Exif offsets without crashing" {
  let jpeg = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x10Exif\x00\x00II\x2A\x00\xFF\xFF\xFF\x7F" +
    b"\xFF\xD9"
  let report = inspect_jpeg(jpeg).unwrap()
  assert_eq(report.info().diagnostics().length(), 1)
  assert_eq(report.info().diagnostics()[0].code, "exif.invalid-ifd-offset")
  let cleaned = sanitize_jpeg(jpeg).unwrap()
  assert_true(cleaned.verified())
}

///|
test "diagnose malformed Exif headers and entries" {
  let invalid_order = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x10Exif\x00\x00ZZ\x2A\x00\x08\x00\x00\x00" +
    b"\xFF\xD9"
  let order_report = inspect_jpeg(invalid_order).unwrap()
  assert_eq(
    order_report.info().diagnostics()[0].code,
    "exif.invalid-byte-order",
  )
  let invalid_magic = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x10Exif\x00\x00II\x00\x00\x08\x00\x00\x00" +
    b"\xFF\xD9"
  let magic_report = inspect_jpeg(invalid_magic).unwrap()
  assert_eq(magic_report.info().diagnostics()[0].code, "exif.invalid-magic")
  let too_many = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x12Exif\x00\x00II\x2A\x00\x08\x00\x00\x00\x01\x01" +
    b"\xFF\xD9"
  let count_report = inspect_jpeg(too_many).unwrap()
  assert_eq(count_report.info().diagnostics()[0].code, "exif.too-many-entries")
  let invalid_value = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x22Exif\x00\x00II\x2A\x00\x08\x00\x00\x00" +
    b"\x01\x00\x0F\x01\x02\x00\x06\x00\x00\x00\xFF\xFF\xFF\x7F" +
    b"\x00\x00\x00\x00\xFF\xD9"
  let value_report = inspect_jpeg(invalid_value).unwrap()
  assert_eq(
    value_report.info().diagnostics()[0].code,
    "exif.invalid-value-offset",
  )
}

///|
test "sanitize JPEG metadata and preserve image scan bytes" {
  let original = sample_jpeg_with_metadata()
  let result = sanitize_jpeg(original).unwrap()
  assert_true(result.verified())
  assert_eq(result.removed().length(), 4)
  assert_true(result.removed_bytes() > 0)
  guard removal_named(result.removed(), "Data after EOI") is Some(trailing) else {
    fail("missing trailing-data removal report")
  }
  assert_eq(trailing.original_length, 8)
  assert_eq(trailing.replacement_length, 0)
  assert_true(result.output().find(b"\x11\x22\xFF\x00\x33") is Some(_))
  assert_true(result.output().find(b"Canon") is None)
  assert_true(result.output().find(b"Photoshop") is None)
  assert_true(result.output().find(b"hello") is None)
  let cleaned = inspect_jpeg(result.output()).unwrap()
  assert_eq(cleaned.orientation(), Some(6))
  assert_eq(cleaned.info().dimensions(), Some({ width: 16, height: 8, }))
  assert_true(metadata_named(cleaned.info().metadata(), "Camera maker") is None)
}

///|
test "JPEG sanitization is idempotent" {
  let first = sanitize_jpeg(sample_jpeg_with_metadata()).unwrap().output()
  let second = sanitize_jpeg(first).unwrap().output()
  assert_eq(first, second)
}

///|
test "reject malformed JPEG segment lengths" {
  assert_true(
    inspect_jpeg(b"\xFF\xD8\xFF\xE1\x00\x01") is Err(InvalidSegmentLength(2, 1)),
  )
  assert_true(
    inspect_jpeg(b"\xFF\xD8\xFF\xE1\x00\x10abc") is Err(UnexpectedEof(4, 16, 5)),
  )
  assert_true(inspect_jpeg(b"\xFF\xD8\xFF\xD8") is Err(MissingEoi))
}

///|
test "reject invalid and truncated JPEG marker structure" {
  assert_true(inspect_jpeg(b"not a jpeg") is Err(NotJpeg))
  assert_true(inspect_jpeg(b"\xFF\xD8\x00") is Err(InvalidMarker(2, 0)))
  assert_true(inspect_jpeg(b"\xFF\xD8\xFF") is Err(UnexpectedEof(2, 2, 1)))
  assert_true(inspect_jpeg(b"\xFF\xD8\xFF\x00") is Err(InvalidMarker(2, 0)))
  assert_true(
    inspect_jpeg(b"\xFF\xD8\xFF\xE1\x00") is Err(UnexpectedEof(4, 2, 1)),
  )
  assert_true(
    inspect_jpeg(b"\xFF\xD8\xFF\xC0\x00\x07abcde\xFF\xD9")
    is Err(InvalidSegmentLength(2, 7)),
  )
  assert_true(
    inspect_jpeg(b"\xFF\xD8\xFF\xDA\x00\x08\x01\x01\x00\x00\x3F\x00\x11\x22")
    is Err(MissingEoi),
  )
  assert_true(sanitize_jpeg(b"not a jpeg") is Err(NotJpeg))
}

///|
test "retain unknown APP1 while removing XMP" {
  let jpeg = b"\xFF\xD8" +
    b"\xFF\xE1\x00\x06test" +
    b"\xFF\xE1\x00\x20http://ns.adobe.com/xap/1.0/\x00x" +
    b"\xFF\xD9"
  let result = sanitize_jpeg(jpeg).unwrap()
  assert_true(result.output().find(b"test") is Some(_))
  assert_true(result.output().find(b"adobe.com") is None)
  assert_true(result.verified())
}
