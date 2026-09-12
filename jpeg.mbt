///|
/// Failures that make a JPEG container unsafe to continue parsing.
pub(all) suberror JpegError {
  NotJpeg
  UnexpectedEof(Int, Int, Int)
  InvalidMarker(Int, Int)
  InvalidSegmentLength(Int, Int)
  MissingEoi
  SegmentLimitExceeded(Int)
} derive(Eq, Debug)

///|
/// The structural role of a JPEG marker segment.
pub(all) enum JpegSegmentRole {
  Structure
  ImageData
  Metadata
  UnknownRole
} derive(Eq, Debug)

///|
/// A bounded JPEG marker segment. Offsets use half-open ranges.
pub(all) struct JpegSegment {
  marker : Int
  name : String
  offset : Int
  payload_offset : Int
  payload_length : Int
  end_offset : Int
  role : JpegSegmentRole
} derive(Eq, Debug)

///|
/// The complete structural and normalized report for one JPEG file.
pub struct JpegInspection {
  priv info : ImageInfo
  priv segments : Array[JpegSegment]
  priv eoi_end : Int
  priv orientation : Int?
}

///|
pub fn JpegInspection::info(self : JpegInspection) -> ImageInfo {
  self.info
}

///|
pub fn JpegInspection::segments(self : JpegInspection) -> Array[JpegSegment] {
  self.segments.copy()
}

///|
pub fn JpegInspection::eoi_end(self : JpegInspection) -> Int {
  self.eoi_end
}

///|
pub fn JpegInspection::orientation(self : JpegInspection) -> Int? {
  self.orientation
}

///|
/// One removed or replaced JPEG metadata segment.
pub(all) struct JpegRemoval {
  name : String
  offset : Int
  original_length : Int
  replacement_length : Int
} derive(Eq, Debug)

///|
/// Result of losslessly rewriting JPEG container metadata.
pub struct JpegSanitizeResult {
  priv output : Bytes
  priv removed : Array[JpegRemoval]
  priv removed_bytes : Int
  priv verified : Bool
}

///|
pub fn JpegSanitizeResult::output(self : JpegSanitizeResult) -> Bytes {
  self.output
}

///|
pub fn JpegSanitizeResult::removed(
  self : JpegSanitizeResult,
) -> Array[JpegRemoval] {
  self.removed.copy()
}

///|
pub fn JpegSanitizeResult::removed_bytes(self : JpegSanitizeResult) -> Int {
  self.removed_bytes
}

///|
pub fn JpegSanitizeResult::verified(self : JpegSanitizeResult) -> Bool {
  self.verified
}

///|
fn byte_int(value : Byte) -> Int {
  value.to_int()
}

///|
fn span_is_valid(data : Bytes, offset : Int, length : Int) -> Bool {
  offset >= 0 &&
  length >= 0 &&
  offset <= data.length() &&
  length <= data.length() - offset
}

///|
fn bytes_at(data : Bytes, offset : Int, expected : Bytes) -> Bool {
  if !span_is_valid(data, offset, expected.length()) {
    return false
  }
  for i in 0..<expected.length() {
    if data[offset + i] != expected[i] {
      return false
    }
  }
  true
}

///|
fn read_be_u16_at(data : Bytes, offset : Int) -> Int? {
  if !span_is_valid(data, offset, 2) {
    return None
  }
  Some((byte_int(data[offset]) << 8) | byte_int(data[offset + 1]))
}

///|
fn jpeg_marker_name(marker : Int) -> String {
  match marker {
    0xD8 => "SOI"
    0xD9 => "EOI"
    0xDA => "SOS"
    0xDB => "DQT"
    0xC4 => "DHT"
    0xCC => "DAC"
    0xDD => "DRI"
    0xFE => "COM"
    0xC0 => "SOF0"
    0xC1 => "SOF1"
    0xC2 => "SOF2"
    0xC3 => "SOF3"
    0xC5 => "SOF5"
    0xC6 => "SOF6"
    0xC7 => "SOF7"
    0xC9 => "SOF9"
    0xCA => "SOF10"
    0xCB => "SOF11"
    0xCD => "SOF13"
    0xCE => "SOF14"
    0xCF => "SOF15"
    _ =>
      if marker >= 0xE0 && marker <= 0xEF {
        "APP" + (marker - 0xE0).to_string()
      } else if marker >= 0xD0 && marker <= 0xD7 {
        "RST" + (marker - 0xD0).to_string()
      } else {
        "Marker " + marker.to_string()
      }
  }
}

///|
fn is_sof_marker(marker : Int) -> Bool {
  marker == 0xC0 ||
  marker == 0xC1 ||
  marker == 0xC2 ||
  marker == 0xC3 ||
  marker == 0xC5 ||
  marker == 0xC6 ||
  marker == 0xC7 ||
  marker == 0xC9 ||
  marker == 0xCA ||
  marker == 0xCB ||
  marker == 0xCD ||
  marker == 0xCE ||
  marker == 0xCF
}

///|
fn is_standalone_marker(marker : Int) -> Bool {
  marker == 0xD8 ||
  marker == 0xD9 ||
  marker == 0x01 ||
  (marker >= 0xD0 && marker <= 0xD7)
}

///|
fn segment_role(
  marker : Int,
  data : Bytes,
  payload_offset : Int,
) -> JpegSegmentRole {
  if marker == 0xDA {
    ImageData
  } else if marker == 0xFE ||
    marker == 0xED ||
    (
      marker == 0xE1 &&
      (
        bytes_at(data, payload_offset, b"Exif\x00\x00") ||
        bytes_at(data, payload_offset, b"http://ns.adobe.com/xap/1.0/\x00") ||
        bytes_at(
          data, payload_offset, b"http://ns.adobe.com/xmp/extension/\x00",
        )
      )
    ) {
    Metadata
  } else if marker == 0xD8 ||
    marker == 0xD9 ||
    marker == 0xDB ||
    marker == 0xC4 ||
    marker == 0xCC ||
    marker == 0xDD ||
    is_sof_marker(marker) ||
    (marker >= 0xE0 && marker <= 0xEF) {
    Structure
  } else {
    UnknownRole
  }
}

///|
fn find_marker_after_scan(data : Bytes, start : Int) -> Int? {
  let mut position = start
  while position < data.length() {
    if data[position] != b'\xFF' {
      position += 1
      continue
    }
    let marker_start = position
    position += 1
    while position < data.length() && data[position] == b'\xFF' {
      position += 1
    }
    if position >= data.length() {
      return None
    }
    let marker = byte_int(data[position])
    if marker == 0x00 || (marker >= 0xD0 && marker <= 0xD7) {
      position += 1
      continue
    }
    return Some(marker_start)
  }
  None
}

///|
fn add_generic_metadata(
  metadata : Array[MetadataItem],
  source : String,
  name : String,
  value : String,
  category : MetadataCategory,
  risk : PrivacyRisk,
) -> Unit {
  metadata.push(MetadataItem::{
    source,
    name,
    value,
    category,
    risk,
    disposition: Removable,
  })
}

///|
fn bounded_text(data : Bytes, start : Int, length : Int) -> String {
  let available = if span_is_valid(data, start, length) { length } else { 0 }
  let limit = if available > 1024 { 1024 } else { available }
  let mut end = start
  while end < start + limit && data[end] != b'\x00' {
    end += 1
  }
  @utf8.decode_lossy(data[start:end])
}

///|
fn metadata_from_segment(
  data : Bytes,
  marker : Int,
  payload_offset : Int,
  payload_length : Int,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> Int? {
  if marker == 0xFE {
    add_generic_metadata(
      metadata,
      "JPEG/COM",
      "Comment",
      bounded_text(data, payload_offset, payload_length),
      Description,
      Medium,
    )
    return None
  }
  if marker == 0xED {
    add_generic_metadata(
      metadata,
      "JPEG/APP13",
      "IPTC/Photoshop resources",
      "Present",
      Other,
      High,
    )
    return None
  }
  if marker == 0xE1 && bytes_at(data, payload_offset, b"Exif\x00\x00") {
    return parse_exif_metadata(
      data,
      payload_offset + 6,
      payload_offset + payload_length,
      metadata,
      diagnostics,
    )
  }
  if marker == 0xE1 &&
    (
      bytes_at(data, payload_offset, b"http://ns.adobe.com/xap/1.0/\x00") ||
      bytes_at(data, payload_offset, b"http://ns.adobe.com/xmp/extension/\x00")
    ) {
    add_generic_metadata(
      metadata,
      "JPEG/APP1",
      "XMP",
      "Adobe XMP packet",
      Other,
      High,
    )
  }
  None
}

///|
fn build_jpeg_inspection(
  data : Bytes,
  segments : Array[JpegSegment],
  dimensions : ImageDimensions?,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
  eoi_end : Int,
  orientation : Int?,
) -> JpegInspection {
  {
    info: ImageInfo::new(
      Jpeg,
      data.length(),
      dimensions,
      Some(false),
      Some(false),
      metadata,
      diagnostics,
    ),
    segments: segments.copy(),
    eoi_end,
    orientation,
  }
}

///|
/// Inspect JPEG marker structure and normalize recognized Exif/IPTC/XMP data.
/// Pixel entropy data is scanned only for marker boundaries and never decoded.
pub fn inspect_jpeg(data : Bytes) -> Result[JpegInspection, JpegError] {
  if data.length() < 2 || data[0] != b'\xFF' || data[1] != b'\xD8' {
    return Err(NotJpeg)
  }
  let segments = [
    JpegSegment::{
      marker: 0xD8,
      name: "SOI",
      offset: 0,
      payload_offset: 2,
      payload_length: 0,
      end_offset: 2,
      role: Structure,
    },
  ]
  let metadata : Array[MetadataItem] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let mut dimensions : ImageDimensions? = None
  let mut orientation : Int? = None
  let mut position = 2
  let mut segment_count = 1
  while position < data.length() {
    if segment_count >= 4096 {
      return Err(SegmentLimitExceeded(segment_count))
    }
    if data[position] != b'\xFF' {
      return Err(InvalidMarker(position, byte_int(data[position])))
    }
    let marker_offset = position
    position += 1
    while position < data.length() && data[position] == b'\xFF' {
      position += 1
    }
    if position >= data.length() {
      return Err(UnexpectedEof(marker_offset, 2, data.length() - marker_offset))
    }
    let marker = byte_int(data[position])
    position += 1
    if marker == 0x00 {
      return Err(InvalidMarker(marker_offset, marker))
    }
    segment_count += 1
    if is_standalone_marker(marker) {
      let segment = JpegSegment::{
        marker,
        name: jpeg_marker_name(marker),
        offset: marker_offset,
        payload_offset: position,
        payload_length: 0,
        end_offset: position,
        role: Structure,
      }
      segments.push(segment)
      if marker == 0xD9 {
        if position < data.length() {
          diagnostics.push(ParseDiagnostic::{
            code: "jpeg.trailing-data",
            message: "Data after EOI will be removed during cleaning",
            offset: Some(position),
            severity: Warning,
          })
        }
        return Ok(
          build_jpeg_inspection(
            data, segments, dimensions, metadata, diagnostics, position, orientation,
          ),
        )
      }
      continue
    }
    guard read_be_u16_at(data, position) is Some(segment_length) else {
      return Err(UnexpectedEof(position, 2, data.length() - position))
    }
    if segment_length < 2 {
      return Err(InvalidSegmentLength(marker_offset, segment_length))
    }
    if !span_is_valid(data, position, segment_length) {
      return Err(
        UnexpectedEof(position, segment_length, data.length() - position),
      )
    }
    let payload_offset = position + 2
    let payload_length = segment_length - 2
    let segment_end = position + segment_length
    let role = segment_role(marker, data, payload_offset)
    segments.push(JpegSegment::{
      marker,
      name: jpeg_marker_name(marker),
      offset: marker_offset,
      payload_offset,
      payload_length,
      end_offset: segment_end,
      role,
    })
    if is_sof_marker(marker) {
      if payload_length < 6 {
        return Err(InvalidSegmentLength(marker_offset, segment_length))
      }
      guard read_be_u16_at(data, payload_offset + 1) is Some(height) else {
        return Err(UnexpectedEof(payload_offset + 1, 2, 0))
      }
      guard read_be_u16_at(data, payload_offset + 3) is Some(width) else {
        return Err(UnexpectedEof(payload_offset + 3, 2, 0))
      }
      dimensions = Some({ width, height, })
    }
    match
      metadata_from_segment(
        data, marker, payload_offset, payload_length, metadata, diagnostics,
      ) {
      Some(value) => if orientation is None { orientation = Some(value) }
      None => ()
    }
    position = segment_end
    if marker == 0xDA {
      match find_marker_after_scan(data, position) {
        Some(next_marker) => position = next_marker
        None => return Err(MissingEoi)
      }
    }
  }
  Err(MissingEoi)
}

///|
fn segment_removal_name(data : Bytes, segment : JpegSegment) -> String? {
  if segment.marker == 0xFE {
    Some("JPEG comment")
  } else if segment.marker == 0xED {
    Some("IPTC/Photoshop APP13")
  } else if segment.marker == 0xE1 &&
    bytes_at(data, segment.payload_offset, b"Exif\x00\x00") {
    Some("Exif APP1")
  } else if segment.marker == 0xE1 &&
    (
      bytes_at(
        data,
        segment.payload_offset,
        b"http://ns.adobe.com/xap/1.0/\x00",
      ) ||
      bytes_at(
        data,
        segment.payload_offset,
        b"http://ns.adobe.com/xmp/extension/\x00",
      )
    ) {
    Some("XMP APP1")
  } else {
    None
  }
}

///|
fn append_byte_range(
  output : Array[Byte],
  data : Bytes,
  start : Int,
  end : Int,
) -> Unit {
  for i in start..<end {
    output.push(data[i])
  }
}

///|
fn minimal_orientation_exif(orientation : Int) -> Bytes {
  Bytes::from_array([
    b'\xFF',
    b'\xE1',
    b'\x00',
    b'\x22',
    b'E',
    b'x',
    b'i',
    b'f',
    b'\x00',
    b'\x00',
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

///|
fn report_has_removable_metadata(info : ImageInfo) -> Bool {
  for item in info.metadata() {
    if item.disposition == Removable {
      return true
    }
  }
  false
}

///|
/// Remove recognized privacy metadata without decoding or recompressing pixels.
/// A minimal Exif block is retained when orientation is needed for display.
pub fn sanitize_jpeg(data : Bytes) -> Result[JpegSanitizeResult, JpegError] {
  let inspection = match inspect_jpeg(data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let output : Array[Byte] = []
  let removed : Array[JpegRemoval] = []
  let mut cursor = 0
  let mut removed_bytes = data.length() - inspection.eoi_end()
  for segment in inspection.segments() {
    match segment_removal_name(data, segment) {
      None => ()
      Some(name) => {
        append_byte_range(output, data, cursor, segment.offset)
        let replacement = if name == "Exif APP1" {
          match inspection.orientation() {
            Some(value) if value >= 1 && value <= 8 =>
              minimal_orientation_exif(value)
            _ => b""
          }
        } else {
          b""
        }
        append_byte_range(output, replacement, 0, replacement.length())
        let original_length = segment.end_offset - segment.offset
        removed.push(JpegRemoval::{
          name,
          offset: segment.offset,
          original_length,
          replacement_length: replacement.length(),
        })
        removed_bytes += original_length - replacement.length()
        cursor = segment.end_offset
      }
    }
  }
  let trailing_length = data.length() - inspection.eoi_end()
  if trailing_length > 0 {
    removed.push(JpegRemoval::{
      name: "Data after EOI",
      offset: inspection.eoi_end(),
      original_length: trailing_length,
      replacement_length: 0,
    })
  }
  append_byte_range(output, data, cursor, inspection.eoi_end())
  let cleaned = Bytes::from_array(output)
  let verified = match inspect_jpeg(cleaned) {
    Ok(report) => !report_has_removable_metadata(report.info())
    Err(_) => false
  }
  Ok({ output: cleaned, removed, removed_bytes, verified, })
}
