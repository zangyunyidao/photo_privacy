///|
/// Failures that make a WebP RIFF container unsafe to process.
pub(all) suberror WebpError {
  NotWebp
  UnexpectedEof(Int, Int, Int)
  InvalidRiffSize(UInt, Int)
  InvalidChunkType(Int)
  InvalidChunkLength(String, Int, Int)
  InvalidPadding(Int, Int)
  InvalidChunkOrder(String, Int)
  MissingImageData
  ChunkLimitExceeded(Int)
} derive(Eq, Debug)

///|
/// Encoding family used by a WebP image.
pub(all) enum WebpEncoding {
  Lossy
  Lossless
  Extended
} derive(Eq, Debug)

///|
pub fn WebpEncoding::display_name(self : WebpEncoding) -> String {
  match self {
    Lossy => "有损 VP8"
    Lossless => "无损 VP8L"
    Extended => "扩展 VP8X"
  }
}

///|
/// The role of a top-level WebP RIFF chunk.
pub(all) enum WebpChunkRole {
  WebpStructure
  WebpImageData
  WebpMetadata
  WebpColorData
  WebpAnimationData
  UnknownWebpRole
} derive(Eq, Debug)

///|
/// A bounded top-level WebP chunk, including its RIFF padding byte.
pub(all) struct WebpChunk {
  name : String
  offset : Int
  data_offset : Int
  data_length : Int
  padded_length : Int
  end_offset : Int
  known : Bool
  role : WebpChunkRole
} derive(Eq, Debug)

///|
/// Complete structural and normalized information for a WebP image.
pub struct WebpInspection {
  priv info : ImageInfo
  priv chunks : Array[WebpChunk]
  priv riff_end : Int
  priv encoding : WebpEncoding
  priv orientation : Int?
  priv frame_count : Int
  priv loop_count : Int?
}

///|
pub fn WebpInspection::info(self : WebpInspection) -> ImageInfo {
  self.info
}

///|
pub fn WebpInspection::chunks(self : WebpInspection) -> Array[WebpChunk] {
  self.chunks.copy()
}

///|
pub fn WebpInspection::riff_end(self : WebpInspection) -> Int {
  self.riff_end
}

///|
pub fn WebpInspection::encoding(self : WebpInspection) -> WebpEncoding {
  self.encoding
}

///|
pub fn WebpInspection::orientation(self : WebpInspection) -> Int? {
  self.orientation
}

///|
pub fn WebpInspection::frame_count(self : WebpInspection) -> Int {
  self.frame_count
}

///|
pub fn WebpInspection::loop_count(self : WebpInspection) -> Int? {
  self.loop_count
}

///|
/// One removed or replaced WebP chunk or trailing byte range.
pub(all) struct WebpRemoval {
  name : String
  offset : Int
  original_length : Int
  replacement_length : Int
} derive(Eq, Debug)

///|
/// Result of losslessly rewriting a WebP RIFF container.
pub struct WebpSanitizeResult {
  priv output : Bytes
  priv removed : Array[WebpRemoval]
  priv removed_bytes : Int
  priv verified : Bool
}

///|
pub fn WebpSanitizeResult::output(self : WebpSanitizeResult) -> Bytes {
  self.output
}

///|
pub fn WebpSanitizeResult::removed(
  self : WebpSanitizeResult,
) -> Array[WebpRemoval] {
  self.removed.copy()
}

///|
pub fn WebpSanitizeResult::removed_bytes(self : WebpSanitizeResult) -> Int {
  self.removed_bytes
}

///|
pub fn WebpSanitizeResult::verified(self : WebpSanitizeResult) -> Bool {
  self.verified
}

///|
fn webp_u16_le(data : Bytes, offset : Int) -> Int? {
  if !span_is_valid(data, offset, 2) {
    return None
  }
  Some(byte_int(data[offset]) | (byte_int(data[offset + 1]) << 8))
}

///|
fn webp_u24_le(data : Bytes, offset : Int) -> Int? {
  if !span_is_valid(data, offset, 3) {
    return None
  }
  Some(
    byte_int(data[offset]) |
    (byte_int(data[offset + 1]) << 8) |
    (byte_int(data[offset + 2]) << 16),
  )
}

///|
fn webp_u32_le(data : Bytes, offset : Int) -> UInt? {
  if !span_is_valid(data, offset, 4) {
    return None
  }
  Some(
    data[offset].to_uint() |
    (data[offset + 1].to_uint() << 8) |
    (data[offset + 2].to_uint() << 16) |
    (data[offset + 3].to_uint() << 24),
  )
}

///|
fn webp_fourcc(data : Bytes, offset : Int) -> String? {
  if !span_is_valid(data, offset, 4) {
    return None
  }
  for index in offset..<(offset + 4) {
    let value = byte_int(data[index])
    if value < 0x20 || value > 0x7E {
      return None
    }
  }
  Some(@utf8.decode_lossy(data[offset:offset + 4]))
}

///|
fn webp_chunk_role(name : String) -> WebpChunkRole {
  match name {
    "VP8X" => WebpStructure
    "VP8 " | "VP8L" | "ALPH" => WebpImageData
    "EXIF" | "XMP " => WebpMetadata
    "ICCP" => WebpColorData
    "ANIM" | "ANMF" => WebpAnimationData
    _ => UnknownWebpRole
  }
}

///|
fn webp_diagnostic(
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
fn webp_dimensions_from_vp8(
  data : Bytes,
  chunk : WebpChunk,
) -> Result[ImageDimensions, WebpError] {
  if chunk.data_length < 10 {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let start = chunk.data_offset
  if data[start + 3] != b'\x9D' ||
    data[start + 4] != b'\x01' ||
    data[start + 5] != b'\x2A' {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let width = webp_u16_le(data, start + 6).unwrap() & 0x3FFF
  let height = webp_u16_le(data, start + 8).unwrap() & 0x3FFF
  if width == 0 || height == 0 {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  Ok({ width, height, })
}

///|
fn webp_vp8l_properties(
  data : Bytes,
  chunk : WebpChunk,
) -> Result[(ImageDimensions, Bool), WebpError] {
  if chunk.data_length < 5 || data[chunk.data_offset] != b'\x2F' {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let bits = webp_u32_le(data, chunk.data_offset + 1).unwrap()
  if bits >> 29 != 0U {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let width = ((bits & 0x3FFFU) + 1U).reinterpret_as_int()
  let height = (((bits >> 14) & 0x3FFFU) + 1U).reinterpret_as_int()
  let alpha = ((bits >> 28) & 1U) == 1U
  Ok(({ width, height, }, alpha))
}

///|
fn webp_vp8x_properties(
  data : Bytes,
  chunk : WebpChunk,
) -> Result[(ImageDimensions, Int), WebpError] {
  if chunk.data_length != 10 {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let start = chunk.data_offset
  let flags = byte_int(data[start])
  if (flags & 0xC1) != 0 ||
    data[start + 1] != b'\x00' ||
    data[start + 2] != b'\x00' ||
    data[start + 3] != b'\x00' {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let width = webp_u24_le(data, start + 4).unwrap() + 1
  let height = webp_u24_le(data, start + 7).unwrap() + 1
  if width <= 0 || height <= 0 || width > 16384 || height > 16384 {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  Ok(({ width, height, }, flags))
}

///|
fn webp_parse_nested_chunks(
  data : Bytes,
  start : Int,
  end : Int,
  diagnostics : Array[ParseDiagnostic],
) -> Result[Unit, WebpError] {
  let mut position = start
  let mut count = 0
  let mut seen_image = false
  while position < end {
    if count >= 1024 {
      return Err(ChunkLimitExceeded(count))
    }
    if end - position < 8 {
      return Err(UnexpectedEof(position, 8, end - position))
    }
    guard webp_fourcc(data, position) is Some(name) else {
      return Err(InvalidChunkType(position))
    }
    let length_u = webp_u32_le(data, position + 4).unwrap()
    if (length_u & 0x80000000U) != 0U {
      return Err(InvalidChunkLength(name, position, -1))
    }
    let length = length_u.reinterpret_as_int()
    let padded = length + (length & 1)
    if padded > end - position - 8 {
      return Err(UnexpectedEof(position + 8, padded, end - position - 8))
    }
    if length % 2 == 1 && data[position + 8 + length] != b'\x00' {
      return Err(
        InvalidPadding(
          position + 8 + length,
          byte_int(data[position + 8 + length]),
        ),
      )
    }
    if name == "VP8 " || name == "VP8L" {
      if seen_image {
        return Err(
          InvalidChunkOrder("ANMF contains multiple image bitstreams", position),
        )
      }
      seen_image = true
    } else if name != "ALPH" {
      webp_diagnostic(
        diagnostics,
        "webp.unknown-frame-chunk",
        "Unknown ANMF chunk " + name + " will be removed during cleaning",
        position,
      )
    }
    position += 8 + padded
    count += 1
  }
  if !seen_image {
    Err(InvalidChunkOrder("ANMF is missing a VP8/VP8L bitstream", start))
  } else {
    Ok(())
  }
}

///|
fn webp_validate_anmf(
  data : Bytes,
  chunk : WebpChunk,
  canvas : ImageDimensions?,
  diagnostics : Array[ParseDiagnostic],
) -> Result[Unit, WebpError] {
  if chunk.data_length < 24 {
    return Err(InvalidChunkLength(chunk.name, chunk.offset, chunk.data_length))
  }
  let start = chunk.data_offset
  let x = webp_u24_le(data, start).unwrap() * 2
  let y = webp_u24_le(data, start + 3).unwrap() * 2
  let width = webp_u24_le(data, start + 6).unwrap() + 1
  let height = webp_u24_le(data, start + 9).unwrap() + 1
  match canvas {
    Some(dimensions) =>
      if x > dimensions.width ||
        y > dimensions.height ||
        width > dimensions.width - x ||
        height > dimensions.height - y {
        return Err(
          InvalidChunkOrder("ANMF frame exceeds the canvas", chunk.offset),
        )
      }
    None => ()
  }
  webp_parse_nested_chunks(
    data,
    start + 16,
    start + chunk.data_length,
    diagnostics,
  )
}

///|
fn webp_add_metadata(
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
fn webp_exif_base(data : Bytes, chunk : WebpChunk) -> Int {
  if bytes_at(data, chunk.data_offset, b"Exif\x00\x00") {
    chunk.data_offset + 6
  } else {
    chunk.data_offset
  }
}

///|
/// Inspect a WebP RIFF container without decoding its compressed pixels.
pub fn inspect_webp(data : Bytes) -> Result[WebpInspection, WebpError] {
  if data.length() < 12 ||
    !bytes_at(data, 0, b"RIFF") ||
    !bytes_at(data, 8, b"WEBP") {
    return Err(NotWebp)
  }
  let declared_u = webp_u32_le(data, 4).unwrap()
  if (declared_u & 0x80000000U) != 0U {
    return Err(InvalidRiffSize(declared_u, data.length()))
  }
  let declared = declared_u.reinterpret_as_int()
  if declared < 4 {
    return Err(InvalidRiffSize(declared_u, data.length()))
  }
  let riff_end = declared + 8
  if riff_end > data.length() {
    return Err(UnexpectedEof(8, declared, data.length() - 8))
  }
  let chunks : Array[WebpChunk] = []
  let metadata : Array[MetadataItem] = []
  let diagnostics : Array[ParseDiagnostic] = []
  let mut position = 12
  let mut dimensions : ImageDimensions? = None
  let mut encoding : WebpEncoding? = None
  let mut orientation : Int? = None
  let mut flags = 0
  let mut seen_vp8x = false
  let mut seen_image = false
  let mut seen_alpha = false
  let mut seen_iccp = false
  let mut seen_exif = false
  let mut seen_xmp = false
  let mut seen_anim = false
  let mut frame_count = 0
  let mut loop_count : Int? = None
  let mut chunk_count = 0
  while position < riff_end {
    if chunk_count >= 16384 {
      return Err(ChunkLimitExceeded(chunk_count))
    }
    if riff_end - position < 8 {
      return Err(UnexpectedEof(position, 8, riff_end - position))
    }
    guard webp_fourcc(data, position) is Some(name) else {
      return Err(InvalidChunkType(position))
    }
    let length_u = webp_u32_le(data, position + 4).unwrap()
    if (length_u & 0x80000000U) != 0U {
      return Err(InvalidChunkLength(name, position, -1))
    }
    let length = length_u.reinterpret_as_int()
    let padded = length + (length & 1)
    if padded > riff_end - position - 8 {
      return Err(UnexpectedEof(position + 8, padded, riff_end - position - 8))
    }
    if length % 2 == 1 && data[position + 8 + length] != b'\x00' {
      return Err(
        InvalidPadding(
          position + 8 + length,
          byte_int(data[position + 8 + length]),
        ),
      )
    }
    let role = webp_chunk_role(name)
    let chunk = WebpChunk::{
      name,
      offset: position,
      data_offset: position + 8,
      data_length: length,
      padded_length: padded,
      end_offset: position + 8 + padded,
      known: role != UnknownWebpRole,
      role,
    }
    if chunk_count == 0 && name != "VP8X" && name != "VP8 " && name != "VP8L" {
      return Err(
        InvalidChunkOrder(
          "first WebP chunk must be VP8X, VP8, or VP8L", position,
        ),
      )
    }
    if name == "VP8X" {
      if chunk_count != 0 || seen_vp8x {
        return Err(
          InvalidChunkOrder("VP8X must be first and occur once", position),
        )
      }
      let (canvas, feature_flags) = match webp_vp8x_properties(data, chunk) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      dimensions = Some(canvas)
      flags = feature_flags
      encoding = Some(Extended)
      seen_vp8x = true
    } else if !seen_vp8x && chunk_count > 0 {
      return Err(
        InvalidChunkOrder(
          "simple WebP may contain only one image chunk", position,
        ),
      )
    } else if name == "VP8 " {
      if seen_image {
        return Err(
          InvalidChunkOrder("multiple top-level image bitstreams", position),
        )
      }
      let value = match webp_dimensions_from_vp8(data, chunk) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if dimensions is None {
        dimensions = Some(value)
        encoding = Some(Lossy)
      }
      seen_image = true
    } else if name == "VP8L" {
      if seen_image || seen_alpha {
        return Err(InvalidChunkOrder("invalid VP8L image layout", position))
      }
      let (value, alpha) = match webp_vp8l_properties(data, chunk) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if dimensions is None {
        dimensions = Some(value)
        encoding = Some(Lossless)
      }
      if alpha {
        seen_alpha = true
      }
      seen_image = true
    } else if name == "ALPH" {
      if seen_image || seen_alpha || length < 1 {
        return Err(
          InvalidChunkOrder("ALPH must occur once before VP8", position),
        )
      }
      seen_alpha = true
    } else if name == "ICCP" {
      if seen_image || seen_iccp {
        return Err(
          InvalidChunkOrder("ICCP must occur once before image data", position),
        )
      }
      seen_iccp = true
      webp_add_metadata(
        metadata,
        "WebP/ICCP",
        "Color profile",
        "ICC profile (" + length.to_string() + " bytes)",
        ColorProfile,
        NoRisk,
        DisplayRequired,
      )
    } else if name == "EXIF" {
      if seen_exif {
        webp_diagnostic(
          diagnostics, "webp.duplicate-exif", "Duplicate EXIF chunk will be removed",
          position,
        )
      }
      seen_exif = true
      let base = webp_exif_base(data, chunk)
      let parsed = parse_exif_metadata(
        data,
        base,
        chunk.data_offset + length,
        metadata,
        diagnostics,
      )
      match parsed {
        Some(value) => if orientation is None { orientation = Some(value) }
        None => ()
      }
    } else if name == "XMP " {
      if seen_xmp {
        webp_diagnostic(
          diagnostics, "webp.duplicate-xmp", "Duplicate XMP chunk will be removed",
          position,
        )
      }
      seen_xmp = true
      webp_add_metadata(
        metadata,
        "WebP/XMP",
        "XMP",
        "Adobe XMP packet (" + length.to_string() + " bytes)",
        Other,
        High,
        Removable,
      )
    } else if name == "ANIM" {
      if seen_anim || length != 6 {
        return Err(
          InvalidChunkOrder(
            "ANIM must occur once and contain six bytes", position,
          ),
        )
      }
      seen_anim = true
      loop_count = Some(webp_u16_le(data, chunk.data_offset + 4).unwrap())
    } else if name == "ANMF" {
      if !seen_anim {
        return Err(
          InvalidChunkOrder("ANMF requires a preceding ANIM chunk", position),
        )
      }
      match webp_validate_anmf(data, chunk, dimensions, diagnostics) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      frame_count += 1
    } else if role == UnknownWebpRole {
      webp_diagnostic(
        diagnostics,
        "webp.unknown-chunk",
        "Unknown WebP chunk " + name + " will be removed during cleaning",
        position,
      )
      webp_add_metadata(
        metadata,
        "WebP/" + name,
        "Unknown RIFF chunk",
        length.to_string() + " bytes",
        Other,
        Medium,
        Removable,
      )
    }
    chunks.push(chunk)
    chunk_count += 1
    position = chunk.end_offset
  }
  guard encoding is Some(actual_encoding) else { return Err(MissingImageData) }
  let animated = (flags & 0x02) != 0
  if animated {
    if !seen_anim || frame_count == 0 || seen_image {
      return Err(
        InvalidChunkOrder(
          "animated WebP requires ANIM/ANMF and no top-level image", 12,
        ),
      )
    }
  } else if !seen_image {
    return Err(MissingImageData)
  }
  if seen_alpha != ((flags & 0x10) != 0) && seen_vp8x {
    webp_diagnostic(
      diagnostics, "webp.alpha-flag-mismatch", "VP8X alpha flag does not match image chunks",
      12,
    )
  }
  if seen_iccp != ((flags & 0x20) != 0) && seen_vp8x {
    webp_diagnostic(
      diagnostics, "webp.iccp-flag-mismatch", "VP8X ICC flag does not match ICCP chunks",
      12,
    )
  }
  if seen_exif != ((flags & 0x08) != 0) && seen_vp8x {
    webp_diagnostic(
      diagnostics, "webp.exif-flag-mismatch", "VP8X Exif flag does not match EXIF chunks",
      12,
    )
  }
  if seen_xmp != ((flags & 0x04) != 0) && seen_vp8x {
    webp_diagnostic(
      diagnostics, "webp.xmp-flag-mismatch", "VP8X XMP flag does not match XMP chunks",
      12,
    )
  }
  if riff_end < data.length() {
    webp_diagnostic(
      diagnostics, "webp.trailing-data", "Data after the RIFF range will be removed during cleaning",
      riff_end,
    )
  }
  Ok({
    info: ImageInfo::new(
      Webp,
      data.length(),
      dimensions,
      Some(seen_alpha || (flags & 0x10) != 0),
      Some(animated),
      metadata,
      diagnostics,
    ),
    chunks: chunks.copy(),
    riff_end,
    encoding: actual_encoding,
    orientation,
    frame_count,
    loop_count,
  })
}

///|
fn webp_append_u32_le(output : Array[Byte], value : UInt) -> Unit {
  output.push((value & 0xFFU).to_byte())
  output.push(((value >> 8) & 0xFFU).to_byte())
  output.push(((value >> 16) & 0xFFU).to_byte())
  output.push(((value >> 24) & 0xFFU).to_byte())
}

///|
fn webp_build_chunk(name : String, payload : Bytes) -> Bytes {
  let output : Array[Byte] = []
  for character in name {
    output.push(character.to_int().to_byte())
  }
  webp_append_u32_le(output, payload.length().reinterpret_as_uint())
  append_byte_range(output, payload, 0, payload.length())
  if payload.length() % 2 == 1 {
    output.push(b'\x00')
  }
  Bytes::from_array(output)
}

///|
fn webp_rewrite_anmf(
  data : Bytes,
  chunk : WebpChunk,
  removed : Array[WebpRemoval],
) -> Bytes {
  let payload : Array[Byte] = []
  append_byte_range(payload, data, chunk.data_offset, chunk.data_offset + 16)
  let mut position = chunk.data_offset + 16
  let end = chunk.data_offset + chunk.data_length
  while position < end {
    let name = webp_fourcc(data, position).unwrap()
    let length = webp_u32_le(data, position + 4).unwrap().reinterpret_as_int()
    let padded = length + (length & 1)
    let nested_end = position + 8 + padded
    if name == "ALPH" || name == "VP8 " || name == "VP8L" {
      append_byte_range(payload, data, position, nested_end)
    } else {
      removed.push(WebpRemoval::{
        name: "ANMF unknown chunk (" + name + ")",
        offset: position,
        original_length: nested_end - position,
        replacement_length: 0,
      })
    }
    position = nested_end
  }
  webp_build_chunk("ANMF", Bytes::from_array(payload))
}

///|
/// Remove WebP privacy metadata without decoding or recompressing image data.
pub fn sanitize_webp(data : Bytes) -> Result[WebpSanitizeResult, WebpError] {
  let inspection = match inspect_webp(data) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let output : Array[Byte] = []
  append_byte_range(output, b"RIFF\x00\x00\x00\x00WEBP", 0, 12)
  let removed : Array[WebpRemoval] = []
  let mut removed_bytes = data.length() - inspection.riff_end()
  let retain_orientation = match inspection.orientation() {
    Some(value) if value >= 1 && value <= 8 => Some(value)
    _ => None
  }
  let mut wrote_orientation = false
  for chunk in inspection.chunks() {
    if chunk.name == "VP8X" {
      let payload : Array[Byte] = []
      append_byte_range(
        payload,
        data,
        chunk.data_offset,
        chunk.data_offset + chunk.data_length,
      )
      payload[0] = (byte_int(payload[0]) & 0xF3).to_byte()
      if retain_orientation is Some(_) {
        payload[0] = (byte_int(payload[0]) | 0x08).to_byte()
      }
      append_byte_range(
        output,
        webp_build_chunk("VP8X", Bytes::from_array(payload)),
        0,
        18,
      )
    } else if chunk.name == "EXIF" {
      let replacement = match (retain_orientation, wrote_orientation) {
        (Some(value), false) =>
          webp_build_chunk("EXIF", minimal_orientation_tiff(value))
        _ => b""
      }
      if replacement.length() > 0 {
        append_byte_range(output, replacement, 0, replacement.length())
        wrote_orientation = true
      }
      removed.push(WebpRemoval::{
        name: "WebP Exif (EXIF)",
        offset: chunk.offset,
        original_length: chunk.end_offset - chunk.offset,
        replacement_length: replacement.length(),
      })
      removed_bytes += chunk.end_offset - chunk.offset - replacement.length()
    } else if chunk.name == "XMP " {
      removed.push(WebpRemoval::{
        name: "WebP XMP (XMP )",
        offset: chunk.offset,
        original_length: chunk.end_offset - chunk.offset,
        replacement_length: 0,
      })
      removed_bytes += chunk.end_offset - chunk.offset
    } else if !chunk.known {
      removed.push(WebpRemoval::{
        name: "WebP unknown chunk (" + chunk.name + ")",
        offset: chunk.offset,
        original_length: chunk.end_offset - chunk.offset,
        replacement_length: 0,
      })
      removed_bytes += chunk.end_offset - chunk.offset
    } else if chunk.name == "ANMF" {
      let before = removed.length()
      let replacement = webp_rewrite_anmf(data, chunk, removed)
      append_byte_range(output, replacement, 0, replacement.length())
      if removed.length() > before {
        removed_bytes += chunk.end_offset - chunk.offset - replacement.length()
      }
    } else {
      append_byte_range(output, data, chunk.offset, chunk.end_offset)
    }
  }
  let trailing_length = data.length() - inspection.riff_end()
  if trailing_length > 0 {
    removed.push(WebpRemoval::{
      name: "Data after RIFF",
      offset: inspection.riff_end(),
      original_length: trailing_length,
      replacement_length: 0,
    })
  }
  let riff_size = output.length() - 8
  let size_u = riff_size.reinterpret_as_uint()
  output[4] = (size_u & 0xFFU).to_byte()
  output[5] = ((size_u >> 8) & 0xFFU).to_byte()
  output[6] = ((size_u >> 16) & 0xFFU).to_byte()
  output[7] = ((size_u >> 24) & 0xFFU).to_byte()
  let cleaned = Bytes::from_array(output)
  let verified = match inspect_webp(cleaned) {
    Ok(report) => !report_has_removable_metadata(report.info())
    Err(_) => false
  }
  Ok({ output: cleaned, removed, removed_bytes, verified, })
}
