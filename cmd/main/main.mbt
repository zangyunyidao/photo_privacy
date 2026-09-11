///|
fn main {
  println("PhotoPrivacy format detector")
  println(
    "JPEG sample: " + @lib.detect_format(b"\xFF\xD8\xFF\xE0").display_name(),
  )
  println(
    "PNG sample: " +
    @lib.detect_format(b"\x89PNG\x0D\x0A\x1A\x0A").display_name(),
  )
  println("Pre-registration prototype: no files are uploaded.")
}
