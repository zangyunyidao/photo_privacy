///|
test "detect common raster image signatures" {
  assert_eq(@photo_privacy.detect_format(b"\xFF\xD8\xFF\xE0"), Jpeg)
  assert_eq(@photo_privacy.detect_format(b"\x89PNG\x0D\x0A\x1A\x0A"), Png)
  assert_eq(@photo_privacy.detect_format(b"RIFF\x04\x00\x00\x00WEBP"), Webp)
  assert_eq(@photo_privacy.detect_format(b"GIF87a"), Gif)
  assert_eq(@photo_privacy.detect_format(b"GIF89a"), Gif)
  assert_eq(@photo_privacy.detect_format(b"BM"), Bmp)
}

///|
test "detect TIFF byte orders" {
  assert_eq(@photo_privacy.detect_format(b"II\x2A\x00"), Tiff)
  assert_eq(@photo_privacy.detect_format(b"MM\x00\x2A"), Tiff)
}

///|
test "detect AVIF and HEIF brands" {
  assert_eq(@photo_privacy.detect_format(b"\x00\x00\x00\x18ftypavif"), Avif)
  assert_eq(@photo_privacy.detect_format(b"\x00\x00\x00\x18ftypheic"), Heif)
  assert_eq(@photo_privacy.detect_format(b"\x00\x00\x00\x18ftypmif1"), Heif)
}

///|
test "reject empty, truncated, and misleading input" {
  assert_eq(@photo_privacy.detect_format(b""), Unknown)
  assert_eq(@photo_privacy.detect_format(b"\xFF\xD8"), Unknown)
  assert_eq(@photo_privacy.detect_format(b"RIFFnot-NOPE"), Unknown)
  assert_eq(@photo_privacy.detect_format(b"photo.jpg"), Unknown)
}

///|
test "provide stable labels" {
  assert_eq(ImageFormat::Png.display_name(), "PNG")
  assert_eq(ImageFormat::Png.mime_type(), "image/png")
  assert_eq(ImageFormat::Unknown.mime_type(), "application/octet-stream")
}
