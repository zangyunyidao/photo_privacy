///|
/// Failures that make a PNG container unsafe to continue processing.
pub(all) suberror PngError {
  NotPng
  UnexpectedEof(Int, Int, Int)
  InvalidChunkType(Int)
  InvalidChunkLength(Int, Int)
  CrcMismatch(Int, UInt, UInt)
  InvalidChunkOrder(String, Int)
  MissingIhdr
  MissingIdat
  MissingIend
  UnknownCriticalChunk(String, Int)
  ChunkLimitExceeded(Int)
} derive(Eq, Debug)

///|
/// The role of a PNG chunk in rendering and privacy cleaning.
pub(all) enum PngChunkRole {
  Structure
  ImageData
  Metadata
  ColorData
  AnimationData
  UnknownPngRole
} derive(Eq, Debug)

///|
/// A validated PNG chunk. Offsets use half-open ranges.
pub(all) struct PngChunk {
  name : String
  offset : Int
  data_offset : Int
  data_length : Int
  end_offset : Int
  crc : UInt
  critical : Bool
  known : Bool
  role : PngChunkRole
} derive(Eq, Debug)

///|
/// The structural and normalized report for one PNG file.
pub struct PngInspection {
  priv info : ImageInfo
  priv chunks : Array[PngChunk]
  priv iend_end : Int
  priv bit_depth : Int
  priv color_type : Int
  priv orientation : Int?
}

///|
pub fn PngInspection::info(self : PngInspection) -> ImageInfo {
  self.info
}

///|
pub fn PngInspection::chunks(self : PngInspection) -> Array[PngChunk] {
  self.chunks.copy()
}

///|
pub fn PngInspection::iend_end(self : PngInspection) -> Int {
  self.iend_end
}

///|
pub fn PngInspection::bit_depth(self : PngInspection) -> Int {
  self.bit_depth
}

///|
pub fn PngInspection::color_type(self : PngInspection) -> Int {
  self.color_type
}

///|
pub fn PngInspection::orientation(self : PngInspection) -> Int? {
  self.orientation
}

///|
/// One removed or replaced PNG chunk or trailing byte range.
pub(all) struct PngRemoval {
  name : String
  offset : Int
  original_length : Int
  replacement_length : Int
} derive(Eq, Debug)

///|
/// Result of losslessly rewriting a PNG container.
pub struct PngSanitizeResult {
  priv output : Bytes
  priv removed : Array[PngRemoval]
  priv removed_bytes : Int
  priv verified : Bool
}

///|
pub fn PngSanitizeResult::output(self : PngSanitizeResult) -> Bytes {
  self.output
}

///|
pub fn PngSanitizeResult::removed(
  self : PngSanitizeResult,
) -> Array[PngRemoval] {
  self.removed.copy()
}

///|
pub fn PngSanitizeResult::removed_bytes(self : PngSanitizeResult) -> Int {
  self.removed_bytes
}

///|
pub fn PngSanitizeResult::verified(self : PngSanitizeResult) -> Bool {
  self.verified
}

///|
fn png_u32(data : Bytes, offset : Int) -> UInt? {
  if !span_is_valid(data, offset, 4) {
    return None
  }
  Some(
    (data[offset].to_uint() << 24) |
    (data[offset + 1].to_uint() << 16) |
    (data[offset + 2].to_uint() << 8) |
    data[offset + 3].to_uint(),
  )
}

///|
fn png_crc32_range(data : Bytes, offset : Int, length : Int) -> UInt {
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
fn png_chunk_name(data : Bytes, offset : Int) -> String? {
  if !span_is_valid(data, offset, 4) {
    return None
  }
  for index in offset..<(offset + 4) {
    let value = byte_int(data[index])
    if !((value >= 65 && value <= 90) || (value >= 97 && value <= 122)) {
      return None
    }
  }
  Some(@utf8.decode_lossy(data[offset:offset + 4]))
}

///|
fn png_chunk_role(name : String) -> PngChunkRole {
  match name {
    "IHDR" | "PLTE" | "IEND" | "tRNS" | "bKGD" => Structure
    "IDAT" => ImageData
    "gAMA" | "cHRM" | "sRGB" | "iCCP" | "sBIT" => ColorData
    "acTL" | "fcTL" | "fdAT" => AnimationData
    "tEXt" | "zTXt" | "iTXt" | "eXIf" | "tIME" | "pHYs" => Metadata
    _ => UnknownPngRole
  }
}

///|
fn png_chunk_known(name : String) -> Bool {
  png_chunk_role(name) != UnknownPngRole
}

///|
fn png_is_critical(data : Bytes, type_offset : Int) -> Bool {
  (byte_int(data[type_offset]) & 0x20) == 0
}

///|
fn png_diagnostic(
  diagnostics : Array[ParseDiagnostic],
  code : String,
  message : String,
  offset : Int,
) -> Unit {
  diagnostics.push(ParseDiagnostic::{
    code,
    message,
    offset: Some(offset),
    severity: Warning,
  })
}

///|
fn png_keyword_category(keyword : String) -> MetadataCategory {
  match keyword {
    "Author" | "Copyright" | "Creator" => Author
    "Creation Time" | "Date" | "Timestamp" => CaptureTime
    "Description" | "Comment" | "Title" => Description
    "Software" => Software
    _ => Other
  }
}

///|
fn png_keyword_risk(keyword : String) -> PrivacyRisk {
  match keyword {
    "Location" | "GPS" | "Address" => High
    "Author"
    | "Copyright"
    | "Creator"
    | "Creation Time"
    | "Date"
    | "Timestamp" => Medium
    _ => Low
  }
}

///|
fn png_push_metadata(
  metadata : Array[MetadataItem],
  source : String,
  name : String,
  value : String,
  category : MetadataCategory,
  risk : PrivacyRisk,
  disposition : MetadataDisposition,
) -> Unit {
  metadata.push(MetadataItem::{
    source,
    name,
    value,
    category,
    risk,
    disposition,
  })
}

///|
fn png_find_zero(data : Bytes, start : Int, end : Int) -> Int? {
  let mut position = start
  while position < end {
    if data[position] == b'\x00' {
      return Some(position)
    }
    position += 1
  }
  None
}

///|
fn png_text_metadata(
  data : Bytes,
  chunk : PngChunk,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> Unit {
  let start = chunk.data_offset
  let end = start + chunk.data_length
  guard png_find_zero(data, start, end) is Some(separator) else {
    png_diagnostic(
      diagnostics,
      "png.invalid-text",
      chunk.name + " is missing its keyword separator",
      chunk.offset,
    )
    return
  }
  let keyword = bounded_text(data, start, separator - start)
  let category = png_keyword_category(keyword)
  let risk = png_keyword_risk(keyword)
  if chunk.name == "tEXt" {
    png_push_metadata(
      metadata,
      "PNG/tEXt",
      keyword,
      bounded_text(data, separator + 1, end - separator - 1),
      category,
      risk,
      Removable,
    )
  } else if chunk.name == "zTXt" {
    png_push_metadata(
      metadata,
      "PNG/zTXt",
      keyword,
      "Compressed text present",
      category,
      risk,
      Removable,
    )
  } else {
    let control = separator + 1
    if control + 2 > end {
      png_diagnostic(
        diagnostics,
        "png.invalid-itxt",
        "iTXt compression fields are truncated",
        chunk.offset,
      )
      return
    }
    guard png_find_zero(data, control + 2, end) is Some(language_end) else {
      png_diagnostic(
        diagnostics,
        "png.invalid-itxt",
        "iTXt language tag is truncated",
        chunk.offset,
      )
      return
    }
    guard png_find_zero(data, language_end + 1, end) is Some(translated_end) else {
      png_diagnostic(
        diagnostics,
        "png.invalid-itxt",
        "iTXt translated keyword is truncated",
        chunk.offset,
      )
      return
    }
    let compressed = data[control] == b'\x01'
    png_push_metadata(
      metadata,
      "PNG/iTXt",
      keyword,
      if compressed {
        "Compressed international text present"
      } else {
        bounded_text(data, translated_end + 1, end - translated_end - 1)
      },
      category,
      risk,
      Removable,
    )
  }
}

///|
fn two_digits(value : Int) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn png_metadata_from_chunk(
  data : Bytes,
  chunk : PngChunk,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> Int? {
  let start = chunk.data_offset
  let length = chunk.data_length
  if chunk.name == "tEXt" || chunk.name == "zTXt" || chunk.name == "iTXt" {
    png_text_metadata(data, chunk, metadata, diagnostics)
  } else if chunk.name == "eXIf" {
    return parse_exif_metadata(
      data,
      start,
      start + length,
      metadata,
      diagnostics,
    )
  } else if chunk.name == "tIME" {
    if length == 7 {
      let year = (byte_int(data[start]) << 8) | byte_int(data[start + 1])
      let value = year.to_string() +
        ":" +
        two_digits(byte_int(data[start + 2])) +
        ":" +
        two_digits(byte_int(data[start + 3])) +
        " " +
        two_digits(byte_int(data[start + 4])) +
        ":" +
        two_digits(byte_int(data[start + 5])) +
        ":" +
        two_digits(byte_int(data[start + 6]))
      png_push_metadata(
        metadata,
        "PNG/tIME",
        "Last modification time",
        value,
        CaptureTime,
        Medium,
        Removable,
      )
    } else {
      png_diagnostic(
        diagnostics,
        "png.invalid-time",
        "tIME must contain seven bytes",
        chunk.offset,
      )
    }
  } else if chunk.name == "pHYs" {
    if length == 9 {
      let x = png_u32(data, start).unwrap()
      let y = png_u32(data, start + 4).unwrap()
      let unit = if data[start + 8] == b'\x01' {
        "pixels per metre"
      } else {
        "unknown unit"
      }
      png_push_metadata(
        metadata,
        "PNG/pHYs",
        "Physical pixel dimensions",
        x.to_string() + " × " + y.to_string() + " " + unit,
        Other,
        Low,
        Removable,
      )
    } else {
      png_diagnostic(
        diagnostics,
        "png.invalid-phys",
        "pHYs must contain nine bytes",
        chunk.offset,
      )
    }
  } else if chunk.name == "iCCP" {
    let profile = match png_find_zero(data, start, start + length) {
      Some(value) => bounded_text(data, start, value - start)
      None => "ICC profile"
    }
    png_push_metadata(
      metadata,
      "PNG/iCCP",
      "Color profile",
      profile,
      ColorProfile,
      NoRisk,
      DisplayRequired,
    )
  } else if chunk.role == ColorData {
    png_push_metadata(
      metadata,
      "PNG/" + chunk.name,
      "Color rendering data",
      "Present",
      ColorProfile,
      NoRisk,
      DisplayRequired,
    )
  } else if chunk.role == UnknownPngRole && !chunk.critical {
    png_push_metadata(
      metadata,
      "PNG/" + chunk.name,
      "Unknown ancillary chunk",
      length.to_string() + " bytes",
      Other,
      Medium,
      Removable,
    )
  }
  None
}

///|
fn valid_png_bit_depth(bit_depth : Int, color_type : Int) -> Bool {
  match color_type {
    0 =>
      bit_depth == 1 ||
      bit_depth == 2 ||
      bit_depth == 4 ||
      bit_depth == 8 ||
      bit_depth == 16
    2 => bit_depth == 8 || bit_depth == 16
    3 => bit_depth == 1 || bit_depth == 2 || bit_depth == 4 || bit_depth == 8
    4 | 6 => bit_depth == 8 || bit_depth == 16
    _ => false
  }
}

///|
/// Inspect PNG chunks, validate CRCs and normalize privacy-relevant metadata.
pub fn inspect_png(data : Bytes) -> Result[PngInspection, PngError] {
  if !bytes_at(data, 0, b"\x89PNG\x0D\x0A\x1A\x0A") {
    return Err(NotPng)
  }
  let chunks : Array[PngChunk] = []
  let metadata : Array[MetadataItem] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let mut position = 8
  let mut dimensions : ImageDimensions? = None
  let mut bit_depth = 0
  let mut color_type = 0
  let mut has_trns = false
  let mut animated = false
  let mut orientation : Int? = None
  let mut seen_ihdr = false
  let mut seen_plte = false
  let mut seen_idat = false
  let mut idat_ended = false
  let mut seen_actl = false
  let mut seen_fctl = false
  let mut chunk_count = 0
  while position < data.length() {
    if chunk_count >= 16384 {
      return Err(ChunkLimitExceeded(chunk_count))
    }
    if data.length() - position < 12 {
      return Err(UnexpectedEof(position, 12, data.length() - position))
    }
    guard png_u32(data, position) is Some(length_u) else {
      return Err(UnexpectedEof(position, 4, data.length() - position))
    }
    if (length_u & 0x80000000U) != 0U {
      return Err(InvalidChunkLength(position, -1))
    }
    let length = length_u.reinterpret_as_int()
    guard png_chunk_name(data, position + 4) is Some(name) else {
      return Err(InvalidChunkType(position + 4))
    }
    if length > data.length() - position - 12 {
      return Err(
        UnexpectedEof(position + 8, length + 4, data.length() - position - 8),
      )
    }
    let end_offset = position + 12 + length
    let stored_crc = png_u32(data, position + 8 + length).unwrap()
    let computed_crc = png_crc32_range(data, position + 4, length + 4)
    if stored_crc != computed_crc {
      return Err(CrcMismatch(position, stored_crc, computed_crc))
    }
    let critical = png_is_critical(data, position + 4)
    let role = png_chunk_role(name)
    let chunk = PngChunk::{
      name,
      offset: position,
      data_offset: position + 8,
      data_length: length,
      end_offset,
      crc: stored_crc,
      critical,
      known: png_chunk_known(name),
      role,
    }
    if !seen_ihdr {
      if name != "IHDR" {
        return Err(MissingIhdr)
      }
      if length != 13 {
        return Err(InvalidChunkLength(position, length))
      }
      let width_u = png_u32(data, position + 8).unwrap()
      let height_u = png_u32(data, position + 12).unwrap()
      if width_u == 0U ||
        height_u == 0U ||
        (width_u & 0x80000000U) != 0U ||
        (height_u & 0x80000000U) != 0U {
        return Err(InvalidChunkLength(position, length))
      }
      bit_depth = byte_int(data[position + 16])
      color_type = byte_int(data[position + 17])
      if !valid_png_bit_depth(bit_depth, color_type) ||
        data[position + 18] != b'\x00' ||
        data[position + 19] != b'\x00' ||
        byte_int(data[position + 20]) > 1 {
        return Err(InvalidChunkLength(position, length))
      }
      dimensions = Some({
        width: width_u.reinterpret_as_int(),
        height: height_u.reinterpret_as_int(),
      })
      seen_ihdr = true
    } else if name == "IHDR" {
      return Err(InvalidChunkOrder("duplicate IHDR", position))
    }
    if name == "PLTE" {
      if seen_plte ||
        seen_idat ||
        length == 0 ||
        length > 768 ||
        length % 3 != 0 {
        return Err(
          InvalidChunkOrder("PLTE must precede IDAT and occur once", position),
        )
      }
      seen_plte = true
    }
    if name == "IDAT" {
      if idat_ended {
        return Err(
          InvalidChunkOrder("IDAT chunks must be consecutive", position),
        )
      }
      seen_idat = true
    } else if seen_idat && name != "IEND" {
      idat_ended = true
    }
    if name == "tRNS" {
      if seen_idat {
        return Err(InvalidChunkOrder("tRNS must precede IDAT", position))
      }
      has_trns = true
    }
    if name == "acTL" {
      if seen_actl || seen_idat || length != 8 {
        return Err(
          InvalidChunkOrder(
            "acTL must precede IDAT and contain eight bytes", position,
          ),
        )
      }
      seen_actl = true
      animated = true
    }
    if name == "fcTL" {
      if !seen_actl || length != 26 {
        return Err(
          InvalidChunkOrder(
            "fcTL requires acTL and must contain 26 bytes", position,
          ),
        )
      }
      seen_fctl = true
    }
    if name == "fdAT" {
      if !seen_actl || !seen_fctl || !seen_idat || length < 4 {
        return Err(
          InvalidChunkOrder(
            "fdAT requires animation control, a frame, and image data", position,
          ),
        )
      }
    }
    if critical && !chunk.known {
      png_diagnostic(
        diagnostics,
        "png.unknown-critical",
        "Unknown critical chunk " + name + " prevents safe cleaning",
        position,
      )
    } else if !critical && !chunk.known {
      png_diagnostic(
        diagnostics,
        "png.unknown-ancillary",
        "Unknown ancillary chunk " + name + " will be removed during cleaning",
        position,
      )
    }
    match png_metadata_from_chunk(data, chunk, metadata, diagnostics) {
      Some(value) => if orientation is None { orientation = Some(value) }
      None => ()
    }
    chunks.push(chunk)
    chunk_count += 1
    position = end_offset
    if name == "IEND" {
      if length != 0 {
        return Err(InvalidChunkLength(chunk.offset, length))
      }
      if !seen_idat {
        return Err(MissingIdat)
      }
      if color_type == 3 && !seen_plte {
        return Err(
          InvalidChunkOrder("indexed-color PNG requires PLTE", position),
        )
      }
      if position < data.length() {
        png_diagnostic(
          diagnostics, "png.trailing-data", "Data after IEND will be removed during cleaning",
          position,
        )
      }
      return Ok({
        info: ImageInfo::new(
          Png,
          data.length(),
          dimensions,
          Some(color_type == 4 || color_type == 6 || has_trns),
          Some(animated),
          metadata,
          diagnostics,
        ),
        chunks: chunks.copy(),
        iend_end: position,
        bit_depth,
        color_type,
        orientation,
      })
    }
  }
  if !seen_ihdr {
    Err(MissingIhdr)
  } else if !seen_idat {
    Err(MissingIdat)
  } else {
    Err(MissingIend)
  }
}

///|
fn png_append_u32(output : Array[Byte], value : UInt) -> Unit {
  output.push(((value >> 24) & 0xFFU).to_byte())
  output.push(((value >> 16) & 0xFFU).to_byte())
  output.push(((value >> 8) & 0xFFU).to_byte())
  output.push((value & 0xFFU).to_byte())
}

///|
fn png_build_chunk(name : String, payload : Bytes) -> Bytes {
  let output : Array[Byte] = []
  png_append_u32(output, payload.length().reinterpret_as_uint())
  for character in name {
    output.push(character.to_int().to_byte())
  }
  append_byte_range(output, payload, 0, payload.length())
  let without_crc = Bytes::from_array(output.copy())
  png_append_u32(output, png_crc32_range(without_crc, 4, payload.length() + 4))
  Bytes::from_array(output)
}

///|
fn png_preserve_chunk(name : String) -> Bool {
  match name {
    "IHDR"
    | "PLTE"
    | "IDAT"
    | "IEND"
    | "tRNS"
    | "bKGD"
    | "gAMA"
    | "cHRM"
    | "sRGB"
    | "iCCP"
    | "sBIT"
    | "acTL"
    | "fcTL"
    | "fdAT" => true
    _ => false
  }
}

///|
fn png_removal_name(chunk : PngChunk) -> String {
  match chunk.name {
    "tEXt" => "PNG text (tEXt)"
    "zTXt" => "PNG compressed text (zTXt)"
    "iTXt" => "PNG international text (iTXt)"
    "eXIf" => "PNG Exif (eXIf)"
    "tIME" => "PNG modification time (tIME)"
    "pHYs" => "PNG physical dimensions (pHYs)"
    name => "PNG ancillary chunk (" + name + ")"
  }
}

///|
fn png_has_removable_metadata(info : ImageInfo) -> Bool {
  for item in info.metadata() {
    if item.disposition == Removable {
      return true
    }
  }
  false
}

///|
/// Remove privacy metadata while preserving compressed pixels, color and APNG data.
pub fn sanitize_png(data : Bytes) -> Result[PngSanitizeResult, PngError] {
  let inspection = match inspect_png(data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for chunk in inspection.chunks() {
    if chunk.critical && !chunk.known {
      return Err(UnknownCriticalChunk(chunk.name, chunk.offset))
    }
  }
  let output : Array[Byte] = []
  append_byte_range(output, data, 0, 8)
  let removed : Array[PngRemoval] = []
  let mut removed_bytes = data.length() - inspection.iend_end()
  for chunk in inspection.chunks() {
    if png_preserve_chunk(chunk.name) {
      append_byte_range(output, data, chunk.offset, chunk.end_offset)
    } else if chunk.name == "eXIf" {
      let replacement = match inspection.orientation() {
        Some(value) if value >= 1 && value <= 8 =>
          png_build_chunk("eXIf", minimal_orientation_tiff(value))
        _ => b""
      }
      append_byte_range(output, replacement, 0, replacement.length())
      removed.push(PngRemoval::{
        name: png_removal_name(chunk),
        offset: chunk.offset,
        original_length: chunk.end_offset - chunk.offset,
        replacement_length: replacement.length(),
      })
      removed_bytes += chunk.end_offset - chunk.offset - replacement.length()
    } else {
      removed.push(PngRemoval::{
        name: png_removal_name(chunk),
        offset: chunk.offset,
        original_length: chunk.end_offset - chunk.offset,
        replacement_length: 0,
      })
      removed_bytes += chunk.end_offset - chunk.offset
    }
  }
  let trailing_length = data.length() - inspection.iend_end()
  if trailing_length > 0 {
    removed.push(PngRemoval::{
      name: "Data after IEND",
      offset: inspection.iend_end(),
      original_length: trailing_length,
      replacement_length: 0,
    })
  }
  let cleaned = Bytes::from_array(output)
  let verified = match inspect_png(cleaned) {
    Ok(report) => !png_has_removable_metadata(report.info())
    Err(_) => false
  }
  Ok({ output: cleaned, removed, removed_bytes, verified, })
}
