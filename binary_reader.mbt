///|
/// Structured failures returned while reading untrusted binary input.
pub(all) suberror BinaryReadError {
  InvalidPosition(Int, Int)
  InvalidLength(Int)
  UnexpectedEnd(Int, Int, Int)
} derive(Eq, Debug)

///|
/// A forward-only reader over immutable bytes.
///
/// Every consuming operation checks its complete span before reading. A failed
/// operation leaves the cursor unchanged, so parsers can safely report or
/// recover from malformed input.
pub struct BinaryReader {
  priv data : Bytes
  priv mut position : Int
}

///|
/// Create a reader positioned at the beginning of `data`.
pub fn BinaryReader::new(data : Bytes) -> BinaryReader {
  { data, position: 0, }
}

///|
/// Return the current byte offset.
pub fn BinaryReader::position(self : BinaryReader) -> Int {
  self.position
}

///|
/// Return the total input length in bytes.
pub fn BinaryReader::length(self : BinaryReader) -> Int {
  self.data.length()
}

///|
/// Return the number of unread bytes.
pub fn BinaryReader::remaining(self : BinaryReader) -> Int {
  self.data.length() - self.position
}

///|
fn BinaryReader::span_error(
  self : BinaryReader,
  length : Int,
) -> BinaryReadError? {
  if length < 0 {
    Some(InvalidLength(length))
  } else {
    let remaining = self.remaining()
    if length > remaining {
      Some(UnexpectedEnd(self.position, length, remaining))
    } else {
      None
    }
  }
}

///|
/// Move to an absolute byte position from `0` through `length()`.
pub fn BinaryReader::seek(
  self : BinaryReader,
  position : Int,
) -> Result[Unit, BinaryReadError] {
  if position < 0 || position > self.data.length() {
    Err(InvalidPosition(position, self.data.length()))
  } else {
    self.position = position
    Ok(())
  }
}

///|
/// Advance by `length` bytes without reading them.
pub fn BinaryReader::skip(
  self : BinaryReader,
  length : Int,
) -> Result[Unit, BinaryReadError] {
  match self.span_error(length) {
    Some(error) => Err(error)
    None => {
      self.position += length
      Ok(())
    }
  }
}

///|
/// Read one byte and advance the cursor.
pub fn BinaryReader::read_u8(
  self : BinaryReader,
) -> Result[Byte, BinaryReadError] {
  match self.span_error(1) {
    Some(error) => Err(error)
    None => {
      let value = self.data[self.position]
      self.position += 1
      Ok(value)
    }
  }
}

///|
/// Read a big-endian 16-bit unsigned integer.
pub fn BinaryReader::read_u16_be(
  self : BinaryReader,
) -> Result[UInt, BinaryReadError] {
  match self.span_error(2) {
    Some(error) => Err(error)
    None => {
      let offset = self.position
      let value = (self.data[offset].to_uint() << 8) |
        self.data[offset + 1].to_uint()
      self.position += 2
      Ok(value)
    }
  }
}

///|
/// Read a little-endian 16-bit unsigned integer.
pub fn BinaryReader::read_u16_le(
  self : BinaryReader,
) -> Result[UInt, BinaryReadError] {
  match self.span_error(2) {
    Some(error) => Err(error)
    None => {
      let offset = self.position
      let value = self.data[offset].to_uint() |
        (self.data[offset + 1].to_uint() << 8)
      self.position += 2
      Ok(value)
    }
  }
}

///|
/// Read a big-endian 32-bit unsigned integer.
pub fn BinaryReader::read_u32_be(
  self : BinaryReader,
) -> Result[UInt, BinaryReadError] {
  match self.span_error(4) {
    Some(error) => Err(error)
    None => {
      let offset = self.position
      let value = (self.data[offset].to_uint() << 24) |
        (self.data[offset + 1].to_uint() << 16) |
        (self.data[offset + 2].to_uint() << 8) |
        self.data[offset + 3].to_uint()
      self.position += 4
      Ok(value)
    }
  }
}

///|
/// Read a little-endian 32-bit unsigned integer.
pub fn BinaryReader::read_u32_le(
  self : BinaryReader,
) -> Result[UInt, BinaryReadError] {
  match self.span_error(4) {
    Some(error) => Err(error)
    None => {
      let offset = self.position
      let value = self.data[offset].to_uint() |
        (self.data[offset + 1].to_uint() << 8) |
        (self.data[offset + 2].to_uint() << 16) |
        (self.data[offset + 3].to_uint() << 24)
      self.position += 4
      Ok(value)
    }
  }
}

///|
/// Return a zero-copy view of the next `length` bytes and advance the cursor.
pub fn BinaryReader::read_view(
  self : BinaryReader,
  length : Int,
) -> Result[BytesView, BinaryReadError] {
  match self.span_error(length) {
    Some(error) => Err(error)
    None => {
      let start = self.position
      self.position += length
      Ok(self.data[start:self.position])
    }
  }
}
