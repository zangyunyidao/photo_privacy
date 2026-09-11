///|
/// Image container formats recognized by PhotoPrivacy's initial detector.
/// Detection uses file signatures rather than filenames or MIME labels.
pub(all) enum ImageFormat {
  Jpeg
  Png
  Webp
  Gif
  Bmp
  Tiff
  Heif
  Avif
  Unknown
} derive(Eq, Debug)

///|
/// Return a stable human-readable format name.
pub fn ImageFormat::display_name(self : ImageFormat) -> String {
  match self {
    Jpeg => "JPEG"
    Png => "PNG"
    Webp => "WebP"
    Gif => "GIF"
    Bmp => "BMP"
    Tiff => "TIFF"
    Heif => "HEIF/HEIC"
    Avif => "AVIF"
    Unknown => "Unknown"
  }
}

///|
/// Return the conventional MIME type for a detected format.
pub fn ImageFormat::mime_type(self : ImageFormat) -> String {
  match self {
    Jpeg => "image/jpeg"
    Png => "image/png"
    Webp => "image/webp"
    Gif => "image/gif"
    Bmp => "image/bmp"
    Tiff => "image/tiff"
    Heif => "image/heif"
    Avif => "image/avif"
    Unknown => "application/octet-stream"
  }
}

///|
fn has_prefix(data : Bytes, prefix : Bytes) -> Bool {
  if data.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if data[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn has_fourcc(data : Bytes, offset : Int, code : Bytes) -> Bool {
  if code.length() != 4 || offset < 0 || offset + 4 > data.length() {
    return false
  }
  for i in 0..<4 {
    if data[offset + i] != code[i] {
      return false
    }
  }
  true
}

///|
fn detect_iso_bmff(data : Bytes) -> ImageFormat {
  if data.length() < 12 || !has_fourcc(data, 4, b"ftyp") {
    return Unknown
  }
  let scan_end = if data.length() < 64 { data.length() } else { 64 }
  for offset = 8; offset + 4 <= scan_end; offset = offset + 4 {
    if has_fourcc(data, offset, b"avif") || has_fourcc(data, offset, b"avis") {
      return Avif
    }
    if has_fourcc(data, offset, b"heic") ||
      has_fourcc(data, offset, b"heix") ||
      has_fourcc(data, offset, b"hevc") ||
      has_fourcc(data, offset, b"hevx") ||
      has_fourcc(data, offset, b"mif1") ||
      has_fourcc(data, offset, b"msf1") {
      return Heif
    }
  }
  Unknown
}

///|
/// Detect an image container from its magic bytes.
///
/// This function deliberately does not accept a filename: changing an
/// extension does not change the actual file format.
pub fn detect_format(data : Bytes) -> ImageFormat {
  if has_prefix(data, b"\xFF\xD8\xFF") {
    return Jpeg
  }
  if has_prefix(data, b"\x89PNG\x0D\x0A\x1A\x0A") {
    return Png
  }
  if data.length() >= 12 &&
    has_prefix(data, b"RIFF") &&
    has_fourcc(data, 8, b"WEBP") {
    return Webp
  }
  if has_prefix(data, b"GIF87a") || has_prefix(data, b"GIF89a") {
    return Gif
  }
  if has_prefix(data, b"BM") {
    return Bmp
  }
  if has_prefix(data, b"II\x2A\x00") || has_prefix(data, b"MM\x00\x2A") {
    return Tiff
  }
  detect_iso_bmff(data)
}
