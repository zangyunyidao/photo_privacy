///|
/// Pixel dimensions read from an image container.
pub(all) struct ImageDimensions {
  width : Int
  height : Int
} derive(Eq, Debug)

///|
/// Normalized metadata categories shared by all supported formats.
pub(all) enum MetadataCategory {
  Location
  CaptureTime
  Device
  Software
  Author
  Description
  Orientation
  ColorProfile
  Other
} derive(Eq, Debug)

///|
/// User-facing privacy severity for one piece of metadata.
pub(all) enum PrivacyRisk {
  NoRisk
  Low
  Medium
  High
} derive(Eq, Debug)

///|
/// Whether data is required for rendering or eligible for removal.
pub(all) enum MetadataDisposition {
  DisplayRequired
  Removable
  UnknownUse
} derive(Eq, Debug)

///|
/// One normalized metadata value, including its original namespace.
pub(all) struct MetadataItem {
  source : String
  name : String
  value : String
  category : MetadataCategory
  risk : PrivacyRisk
  disposition : MetadataDisposition
} derive(Eq, Debug)

///|
/// Severity of a non-fatal or fatal parsing diagnostic.
pub(all) enum DiagnosticSeverity {
  Info
  Warning
  Error
} derive(Eq, Debug)

///|
/// A structured message tied to an optional byte offset.
pub(all) struct ParseDiagnostic {
  code : String
  message : String
  offset : Int?
  severity : DiagnosticSeverity
} derive(Eq, Debug)

///|
/// Format-independent inspection result used by the CLI and browser UI.
/// Internal arrays are copied at API boundaries to prevent callers from
/// mutating a completed report through shared references.
pub struct ImageInfo {
  priv format : ImageFormat
  priv file_size : Int
  priv dimensions : ImageDimensions?
  priv has_alpha : Bool?
  priv is_animated : Bool?
  priv metadata : Array[MetadataItem]
  priv diagnostics : Array[ParseDiagnostic]
}

///|
/// Construct an immutable-style image report from parser output.
pub fn ImageInfo::new(
  format : ImageFormat,
  file_size : Int,
  dimensions : ImageDimensions?,
  has_alpha : Bool?,
  is_animated : Bool?,
  metadata : Array[MetadataItem],
  diagnostics : Array[ParseDiagnostic],
) -> ImageInfo {
  {
    format,
    file_size,
    dimensions,
    has_alpha,
    is_animated,
    metadata: metadata.copy(),
    diagnostics: diagnostics.copy(),
  }
}

///|
pub fn ImageInfo::format(self : ImageInfo) -> ImageFormat {
  self.format
}

///|
pub fn ImageInfo::file_size(self : ImageInfo) -> Int {
  self.file_size
}

///|
pub fn ImageInfo::dimensions(self : ImageInfo) -> ImageDimensions? {
  self.dimensions
}

///|
pub fn ImageInfo::has_alpha(self : ImageInfo) -> Bool? {
  self.has_alpha
}

///|
pub fn ImageInfo::is_animated(self : ImageInfo) -> Bool? {
  self.is_animated
}

///|
pub fn ImageInfo::metadata(self : ImageInfo) -> Array[MetadataItem] {
  self.metadata.copy()
}

///|
pub fn ImageInfo::diagnostics(self : ImageInfo) -> Array[ParseDiagnostic] {
  self.diagnostics.copy()
}
