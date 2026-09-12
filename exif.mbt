///|
priv enum TiffEndian {
  LittleEndian
  BigEndian
}

///|
priv enum ExifIfdKind {
  Ifd0
  ExifIfd
  GpsIfd
} derive(Eq)

///|
priv struct IfdPointers {
  orientation : Int?
  exif_ifd : Int?
  gps_ifd : Int?
}

///|
fn tiff_u16(data : Bytes, offset : Int, end : Int, endian : TiffEndian) -> Int? {
  if offset < 0 ||
    offset > end ||
    2 > end - offset ||
    !span_is_valid(data, offset, 2) {
    return None
  }
  let first = byte_int(data[offset])
  let second = byte_int(data[offset + 1])
  Some(
    match endian {
      LittleEndian => first | (second << 8)
      BigEndian => (first << 8) | second
    },
  )
}

///|
fn tiff_u32(data : Bytes, offset : Int, end : Int, endian : TiffEndian) -> Int? {
  if offset < 0 ||
    offset > end ||
    4 > end - offset ||
    !span_is_valid(data, offset, 4) {
    return None
  }
  let a = byte_int(data[offset])
  let b = byte_int(data[offset + 1])
  let c = byte_int(data[offset + 2])
  let d = byte_int(data[offset + 3])
  match endian {
    LittleEndian =>
      if d >= 0x80 {
        None
      } else {
        Some(a | (b << 8) | (c << 16) | (d << 24))
      }
    BigEndian =>
      if a >= 0x80 {
        None
      } else {
        Some((a << 24) | (b << 16) | (c << 8) | d)
      }
  }
}

///|
fn exif_diagnostic(
  diagnostics : Array[ParseDiagnostic],
  code : String,
  message : String,
  offset : Int?,
) -> Unit {
  diagnostics.push(ParseDiagnostic::{
    code,
    message,
    offset,
    severity: Warning,
  })
}

///|
fn tiff_type_size(field_type : Int) -> Int? {
  match field_type {
    1 | 2 | 7 => Some(1)
    3 => Some(2)
    4 | 9 => Some(4)
    5 | 10 => Some(8)
    _ => None
  }
}

///|
fn tiff_value_offset(
  data : Bytes,
  base : Int,
  end : Int,
  entry : Int,
  field_type : Int,
  count : Int,
  endian : TiffEndian,
) -> (Int, Int)? {
  guard tiff_type_size(field_type) is Some(unit_size) else { return None }
  if count < 0 || (unit_size > 0 && count > 1048576 / unit_size) {
    return None
  }
  let byte_count = count * unit_size
  let absolute = if byte_count <= 4 {
    entry + 8
  } else {
    guard tiff_u32(data, entry + 8, end, endian) is Some(relative) else {
      return None
    }
    if relative > end - base {
      return None
    }
    base + relative
  }
  if absolute < base || absolute > end || byte_count > end - absolute {
    None
  } else {
    Some((absolute, byte_count))
  }
}

///|
fn exif_ascii(data : Bytes, offset : Int, byte_count : Int) -> String {
  bounded_text(data, offset, byte_count)
}

///|
fn rational_text(
  data : Bytes,
  offset : Int,
  count : Int,
  end : Int,
  endian : TiffEndian,
) -> String? {
  if count <= 0 || count > 8 {
    return None
  }
  let builder = StringBuilder()
  for index in 0..<count {
    let current = offset + index * 8
    guard tiff_u32(data, current, end, endian) is Some(numerator) else {
      return None
    }
    guard tiff_u32(data, current + 4, end, endian) is Some(denominator) else {
      return None
    }
    if index > 0 {
      builder.write_string(", ")
    }
    builder.write_string(numerator.to_string())
    builder.write_char('/')
    builder.write_string(denominator.to_string())
  }
  Some(builder.to_string())
}

///|
fn numeric_text(
  data : Bytes,
  offset : Int,
  count : Int,
  field_type : Int,
  end : Int,
  endian : TiffEndian,
) -> String? {
  if count <= 0 || count > 8 {
    return None
  }
  let builder = StringBuilder()
  for index in 0..<count {
    let value = if field_type == 3 {
      tiff_u16(data, offset + index * 2, end, endian)
    } else if field_type == 4 {
      tiff_u32(data, offset + index * 4, end, endian)
    } else {
      None
    }
    guard value is Some(number) else { return None }
    if index > 0 {
      builder.write_string(", ")
    }
    builder.write_string(number.to_string())
  }
  Some(builder.to_string())
}

///|
fn exif_tag_spec(
  kind : ExifIfdKind,
  tag : Int,
) -> (String, MetadataCategory, PrivacyRisk, MetadataDisposition)? {
  match (kind, tag) {
    (Ifd0, 0x010F) => Some(("Camera maker", Device, Medium, Removable))
    (Ifd0, 0x0110) => Some(("Camera model", Device, Medium, Removable))
    (Ifd0, 0x0112) =>
      Some(("Orientation", Orientation, NoRisk, DisplayRequired))
    (Ifd0, 0x0131) => Some(("Software", Software, Low, Removable))
    (Ifd0, 0x0132) => Some(("Date and time", CaptureTime, Medium, Removable))
    (Ifd0, 0x013B) => Some(("Artist", Author, Medium, Removable))
    (Ifd0, 0x8298) => Some(("Copyright", Author, Medium, Removable))
    (ExifIfd, 0x9003) =>
      Some(("Original capture time", CaptureTime, High, Removable))
    (ExifIfd, 0x9004) =>
      Some(("Digitized time", CaptureTime, Medium, Removable))
    (ExifIfd, 0x9286) => Some(("User comment", Description, Medium, Removable))
    (ExifIfd, 0xA431) => Some(("Body serial number", Device, High, Removable))
    (ExifIfd, 0xA433) => Some(("Lens maker", Device, Low, Removable))
    (ExifIfd, 0xA434) => Some(("Lens model", Device, Medium, Removable))
    (GpsIfd, 0x0001) => Some(("Latitude reference", Location, High, Removable))
    (GpsIfd, 0x0002) => Some(("Latitude", Location, High, Removable))
    (GpsIfd, 0x0003) => Some(("Longitude reference", Location, High, Removable))
    (GpsIfd, 0x0004) => Some(("Longitude", Location, High, Removable))
    (GpsIfd, 0x0005) => Some(("Altitude reference", Location, High, Removable))
    (GpsIfd, 0x0006) => Some(("Altitude", Location, High, Removable))
    (GpsIfd, 0x0007) => Some(("GPS time", CaptureTime, High, Removable))
    (GpsIfd, 0x001D) => Some(("GPS date", CaptureTime, High, Removable))
    _ => None
  }
}

///|
fn exif_source(kind : ExifIfdKind) -> String {
  match kind {
    Ifd0 => "Exif/IFD0"
    ExifIfd => "Exif/ExifIFD"
    GpsIfd => "Exif/GPS"
  }
}

///|
fn parse_ifd(
  data : Bytes,
  base : Int,
  end : Int,
  relative_offset : Int,
  endian : TiffEndian,
  kind : ExifIfdKind,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> IfdPointers {
  let empty = IfdPointers::{ orientation: None, exif_ifd: None, gps_ifd: None, }
  if relative_offset < 0 || relative_offset > end - base {
    exif_diagnostic(
      diagnostics,
      "exif.invalid-ifd-offset",
      "IFD offset is outside the Exif payload",
      Some(base),
    )
    return empty
  }
  let ifd = base + relative_offset
  guard tiff_u16(data, ifd, end, endian) is Some(entry_count) else {
    exif_diagnostic(
      diagnostics,
      "exif.truncated-ifd",
      "IFD entry count is truncated",
      Some(ifd),
    )
    return empty
  }
  if entry_count > 256 {
    exif_diagnostic(
      diagnostics,
      "exif.too-many-entries",
      "IFD entry limit exceeded",
      Some(ifd),
    )
    return empty
  }
  if ifd + 2 > end || entry_count > (end - ifd - 2) / 12 {
    exif_diagnostic(
      diagnostics,
      "exif.truncated-ifd",
      "IFD entries extend beyond the Exif payload",
      Some(ifd),
    )
    return empty
  }
  let mut orientation : Int? = None
  let mut exif_ifd : Int? = None
  let mut gps_ifd : Int? = None
  for index in 0..<entry_count {
    let entry = ifd + 2 + index * 12
    guard tiff_u16(data, entry, end, endian) is Some(tag) else { continue }
    guard tiff_u16(data, entry + 2, end, endian) is Some(field_type) else {
      continue
    }
    guard tiff_u32(data, entry + 4, end, endian) is Some(count) else {
      continue
    }
    if kind == Ifd0 && (tag == 0x8769 || tag == 0x8825) {
      match tiff_u32(data, entry + 8, end, endian) {
        Some(pointer) =>
          if tag == 0x8769 {
            exif_ifd = Some(pointer)
          } else {
            gps_ifd = Some(pointer)
          }
        None => ()
      }
      continue
    }
    guard exif_tag_spec(kind, tag) is Some((name, category, risk, disposition)) else {
      continue
    }
    guard tiff_value_offset(data, base, end, entry, field_type, count, endian)
      is Some((value_offset, byte_count)) else {
      exif_diagnostic(
        diagnostics,
        "exif.invalid-value-offset",
        "Exif value is outside the payload or too large",
        Some(entry),
      )
      continue
    }
    let value = if field_type == 2 || field_type == 7 || field_type == 1 {
      Some(exif_ascii(data, value_offset, byte_count))
    } else if field_type == 3 || field_type == 4 {
      numeric_text(data, value_offset, count, field_type, end, endian)
    } else if field_type == 5 {
      rational_text(data, value_offset, count, end, endian)
    } else {
      None
    }
    match value {
      Some(text) => {
        metadata.push(MetadataItem::{
          source: exif_source(kind),
          name,
          value: text,
          category,
          risk,
          disposition,
        })
        if kind == Ifd0 && tag == 0x0112 && field_type == 3 {
          orientation = tiff_u16(data, value_offset, end, endian)
        }
      }
      None => ()
    }
  }
  { orientation, exif_ifd, gps_ifd, }
}

///|
fn parse_exif_metadata(
  data : Bytes,
  base : Int,
  end : Int,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> Int? {
  if base < 0 || end > data.length() || end - base < 8 {
    exif_diagnostic(
      diagnostics,
      "exif.truncated-header",
      "Exif TIFF header is truncated",
      Some(base),
    )
    return None
  }
  let endian = if bytes_at(data, base, b"II") {
    LittleEndian
  } else if bytes_at(data, base, b"MM") {
    BigEndian
  } else {
    exif_diagnostic(
      diagnostics,
      "exif.invalid-byte-order",
      "Exif byte order must be II or MM",
      Some(base),
    )
    return None
  }
  guard tiff_u16(data, base + 2, end, endian) is Some(42) else {
    exif_diagnostic(
      diagnostics,
      "exif.invalid-magic",
      "Exif TIFF magic number is invalid",
      Some(base + 2),
    )
    return None
  }
  guard tiff_u32(data, base + 4, end, endian) is Some(ifd0_offset) else {
    exif_diagnostic(
      diagnostics,
      "exif.invalid-ifd-offset",
      "Exif IFD0 offset is invalid",
      Some(base + 4),
    )
    return None
  }
  let root = parse_ifd(
    data,
    base,
    end,
    ifd0_offset,
    endian,
    Ifd0,
    metadata,
    diagnostics,
  )
  match root.exif_ifd {
    Some(offset) =>
      ignore(
        parse_ifd(
          data,
          base,
          end,
          offset,
          endian,
          ExifIfd,
          metadata,
          diagnostics,
        ),
      )
    None => ()
  }
  match root.gps_ifd {
    Some(offset) =>
      ignore(
        parse_ifd(
          data,
          base,
          end,
          offset,
          endian,
          GpsIfd,
          metadata,
          diagnostics,
        ),
      )
    None => ()
  }
  root.orientation
}

///|
/// Build the smallest TIFF payload that preserves only display orientation.
fn minimal_orientation_tiff(orientation : Int) -> Bytes {
  Bytes::from_array([
    b'M',
    b'M',
    b'\x00',
    b'\x2A',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x08',
    b'\x00',
    b'\x01',
    b'\x01',
    b'\x12',
    b'\x00',
    b'\x03',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x01',
    ((orientation >> 8) & 0xFF).to_byte(),
    (orientation & 0xFF).to_byte(),
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
    b'\x00',
  ])
}
