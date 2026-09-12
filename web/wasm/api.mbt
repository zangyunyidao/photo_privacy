///|
extern "wasm" fn host_input_length() -> Int = "photo_privacy_host" "input_length"

///|
extern "wasm" fn host_input_word(offset : Int) -> UInt = "photo_privacy_host" "input_word"

///|
extern "wasm" fn host_json_reset() -> Unit = "photo_privacy_host" "json_reset"

///|
extern "wasm" fn host_json_code_point(value : Int) -> Unit = "photo_privacy_host" "json_code_point"

///|
extern "wasm" fn host_output_begin(length : Int) -> Unit = "photo_privacy_host" "output_begin"

///|
extern "wasm" fn host_output_word(
  offset : Int,
  value : UInt,
  valid_bytes : Int,
) -> Unit = "photo_privacy_host" "output_word"

///|
fn load_input() -> Bytes? {
  let length = host_input_length()
  if length < 0 || length > 50 * 1024 * 1024 {
    return None
  }
  let data = FixedArray::make(length, b'\x00')
  let mut offset = 0
  while offset < length {
    let word = host_input_word(offset)
    let available = if length - offset < 4 { length - offset } else { 4 }
    for lane in 0..<available {
      data[offset + lane] = ((word >> (lane * 8)) & 0xFFU).to_byte()
    }
    offset += 4
  }
  Some(Bytes::from_array(data))
}

///|
fn send_output(data : Bytes) -> Unit {
  host_output_begin(data.length())
  let mut offset = 0
  while offset < data.length() {
    let available = if data.length() - offset < 4 {
      data.length() - offset
    } else {
      4
    }
    let mut word = 0U
    for lane in 0..<available {
      word = word | (data[offset + lane].to_uint() << (lane * 8))
    }
    host_output_word(offset, word, available)
    offset += 4
  }
}

///|
fn send_json(value : String) -> Unit {
  host_json_reset()
  for character in value {
    host_json_code_point(character.to_int())
  }
}

///|
fn json_string(builder : StringBuilder, value : String) -> Unit {
  builder.write_char('"')
  for character in value {
    match character {
      '"' => builder.write_string("\\\"")
      '\\' => builder.write_string("\\\\")
      '\n' => builder.write_string("\\n")
      '\r' => builder.write_string("\\r")
      '\t' => builder.write_string("\\t")
      '\b' => builder.write_string("\\b")
      '\u{000C}' => builder.write_string("\\f")
      value =>
        if value.to_int() < 0x20 {
          builder.write_char(' ')
        } else {
          builder.write_char(value)
        }
    }
  }
  builder.write_char('"')
}

///|
fn category_name(value : @lib.MetadataCategory) -> String {
  match value {
    @lib.Location => "位置"
    @lib.CaptureTime => "拍摄时间"
    @lib.Device => "设备"
    @lib.Software => "软件"
    @lib.Author => "作者"
    @lib.Description => "描述"
    @lib.Orientation => "方向"
    @lib.ColorProfile => "色彩配置"
    @lib.Other => "其他"
  }
}

///|
fn risk_name(value : @lib.PrivacyRisk) -> String {
  match value {
    @lib.NoRisk => "无风险"
    @lib.Low => "低"
    @lib.Medium => "中"
    @lib.High => "高"
  }
}

///|
fn disposition_name(value : @lib.MetadataDisposition) -> String {
  match value {
    @lib.DisplayRequired => "显示必需"
    @lib.Removable => "可移除"
    @lib.UnknownUse => "用途未知"
  }
}

///|
fn severity_name(value : @lib.DiagnosticSeverity) -> String {
  match value {
    @lib.Info => "信息"
    @lib.Warning => "警告"
    @lib.Error => "错误"
  }
}

///|
fn append_metadata_json(
  builder : StringBuilder,
  items : Array[@lib.MetadataItem],
) -> Unit {
  builder.write_char('[')
  for index, item in items {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string("{\"source\":")
    json_string(builder, item.source)
    builder.write_string(",\"name\":")
    json_string(builder, item.name)
    builder.write_string(",\"value\":")
    json_string(builder, item.value)
    builder.write_string(",\"category\":")
    json_string(builder, category_name(item.category))
    builder.write_string(",\"risk\":")
    json_string(builder, risk_name(item.risk))
    builder.write_string(",\"disposition\":")
    json_string(builder, disposition_name(item.disposition))
    builder.write_char('}')
  }
  builder.write_char(']')
}

///|
fn append_diagnostics_json(
  builder : StringBuilder,
  items : Array[@lib.ParseDiagnostic],
) -> Unit {
  builder.write_char('[')
  for index, item in items {
    if index > 0 {
      builder.write_char(',')
    }
    builder.write_string("{\"code\":")
    json_string(builder, item.code)
    builder.write_string(",\"message\":")
    json_string(builder, item.message)
    builder.write_string(",\"severity\":")
    json_string(builder, severity_name(item.severity))
    builder.write_string(",\"offset\":")
    match item.offset {
      Some(offset) => builder.write_string(offset.to_string())
      None => builder.write_string("null")
    }
    builder.write_char('}')
  }
  builder.write_char(']')
}

///|
fn inspection_json(report : @lib.JpegInspection) -> String {
  let info = report.info()
  let builder = StringBuilder()
  builder.write_string("{\"ok\":true,\"format\":")
  json_string(builder, info.format().display_name())
  builder.write_string(",\"fileSize\":")
  builder.write_string(info.file_size().to_string())
  builder.write_string(",\"width\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.width.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"height\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.height.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"orientation\":")
  match report.orientation() {
    Some(value) => builder.write_string(value.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"segmentCount\":")
  builder.write_string(report.segments().length().to_string())
  builder.write_string(",\"unitCount\":")
  builder.write_string(report.segments().length().to_string())
  builder.write_string(",\"unitLabel\":\"JPEG 段数\"")
  builder.write_string(",\"hasAlpha\":false,\"isAnimated\":false")
  builder.write_string(",\"bitDepth\":null,\"colorType\":null")
  builder.write_string(",\"metadata\":")
  append_metadata_json(builder, info.metadata())
  builder.write_string(",\"diagnostics\":")
  append_diagnostics_json(builder, info.diagnostics())
  builder.write_char('}')
  builder.to_string()
}

///|
fn png_inspection_json(report : @lib.PngInspection) -> String {
  let info = report.info()
  let builder = StringBuilder()
  builder.write_string("{\"ok\":true,\"format\":")
  json_string(builder, info.format().display_name())
  builder.write_string(",\"fileSize\":")
  builder.write_string(info.file_size().to_string())
  builder.write_string(",\"width\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.width.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"height\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.height.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"orientation\":")
  match report.orientation() {
    Some(value) => builder.write_string(value.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"unitCount\":")
  builder.write_string(report.chunks().length().to_string())
  builder.write_string(",\"unitLabel\":\"PNG 块数\"")
  builder.write_string(",\"hasAlpha\":")
  builder.write_string(
    if info.has_alpha() == Some(true) {
      "true"
    } else {
      "false"
    },
  )
  builder.write_string(",\"isAnimated\":")
  builder.write_string(
    if info.is_animated() == Some(true) {
      "true"
    } else {
      "false"
    },
  )
  builder.write_string(",\"bitDepth\":")
  builder.write_string(report.bit_depth().to_string())
  builder.write_string(",\"colorType\":")
  builder.write_string(report.color_type().to_string())
  builder.write_string(",\"metadata\":")
  append_metadata_json(builder, info.metadata())
  builder.write_string(",\"diagnostics\":")
  append_diagnostics_json(builder, info.diagnostics())
  builder.write_char('}')
  builder.to_string()
}

///|
fn webp_inspection_json(report : @lib.WebpInspection) -> String {
  let info = report.info()
  let builder = StringBuilder()
  builder.write_string("{\"ok\":true,\"format\":")
  json_string(builder, info.format().display_name())
  builder.write_string(",\"fileSize\":")
  builder.write_string(info.file_size().to_string())
  builder.write_string(",\"width\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.width.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"height\":")
  match info.dimensions() {
    Some(dimensions) => builder.write_string(dimensions.height.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"orientation\":")
  match report.orientation() {
    Some(value) => builder.write_string(value.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"unitCount\":")
  builder.write_string(report.chunks().length().to_string())
  builder.write_string(",\"unitLabel\":\"WebP 块数\"")
  builder.write_string(",\"hasAlpha\":")
  builder.write_string(
    if info.has_alpha() == Some(true) {
      "true"
    } else {
      "false"
    },
  )
  builder.write_string(",\"isAnimated\":")
  builder.write_string(
    if info.is_animated() == Some(true) {
      "true"
    } else {
      "false"
    },
  )
  builder.write_string(",\"encoding\":")
  json_string(builder, report.encoding().display_name())
  builder.write_string(",\"frameCount\":")
  builder.write_string(report.frame_count().to_string())
  builder.write_string(",\"loopCount\":")
  match report.loop_count() {
    Some(value) => builder.write_string(value.to_string())
    None => builder.write_string("null")
  }
  builder.write_string(",\"bitDepth\":null,\"colorType\":null")
  builder.write_string(",\"metadata\":")
  append_metadata_json(builder, info.metadata())
  builder.write_string(",\"diagnostics\":")
  append_diagnostics_json(builder, info.diagnostics())
  builder.write_char('}')
  builder.to_string()
}

///|
fn error_json(code : String, message : String) -> String {
  let builder = StringBuilder()
  builder.write_string("{\"ok\":false,\"code\":")
  json_string(builder, code)
  builder.write_string(",\"message\":")
  json_string(builder, message)
  builder.write_char('}')
  builder.to_string()
}

///|
fn jpeg_error_message(error : @lib.JpegError) -> String {
  match error {
    @lib.NotJpeg => "文件不是有效的 JPEG"
    @lib.UnexpectedEof(_, _, _) => "JPEG 数据被截断"
    @lib.InvalidMarker(_, _) => "JPEG 标记结构无效"
    @lib.InvalidSegmentLength(_, _) => "JPEG 段长度无效"
    @lib.MissingEoi => "JPEG 缺少结束标记"
    @lib.SegmentLimitExceeded(_) => "JPEG 段数量超过安全限制"
  }
}

///|
fn png_error_message(error : @lib.PngError) -> String {
  match error {
    @lib.NotPng => "文件不是有效的 PNG"
    @lib.UnexpectedEof(_, _, _) => "PNG 数据被截断"
    @lib.InvalidChunkType(_) => "PNG 块类型无效"
    @lib.InvalidChunkLength(_, _) => "PNG 块长度或图像头字段无效"
    @lib.CrcMismatch(_, _, _) => "PNG 块 CRC 校验失败"
    @lib.InvalidChunkOrder(_, _) => "PNG 块顺序或结构无效"
    @lib.MissingIhdr => "PNG 缺少图像头 IHDR"
    @lib.MissingIdat => "PNG 缺少图像数据 IDAT"
    @lib.MissingIend => "PNG 缺少结束块 IEND"
    @lib.UnknownCriticalChunk(name, _) =>
      "无法安全清理未知关键块 " + name
    @lib.ChunkLimitExceeded(_) => "PNG 块数量超过安全限制"
  }
}

///|
fn webp_error_message(error : @lib.WebpError) -> String {
  match error {
    @lib.NotWebp => "文件不是有效的 WebP"
    @lib.UnexpectedEof(_, _, _) => "WebP 数据被截断"
    @lib.InvalidRiffSize(_, _) => "WebP RIFF 文件长度无效"
    @lib.InvalidChunkType(_) => "WebP 块类型无效"
    @lib.InvalidChunkLength(_, _, _) => "WebP 块长度或图像头字段无效"
    @lib.InvalidPadding(_, _) => "WebP 奇数长度块的填充字节无效"
    @lib.InvalidChunkOrder(_, _) => "WebP 块顺序或结构无效"
    @lib.MissingImageData => "WebP 缺少图像数据"
    @lib.ChunkLimitExceeded(_) => "WebP 块数量超过安全限制"
  }
}

///|
#export_name("photo_privacy_inspect")
pub fn inspect_loaded_file() -> Int {
  guard load_input() is Some(data) else {
    send_json(
      error_json("file-too-large", "文件大小无效或超过 50 MiB 限制"),
    )
    return 3
  }
  match @lib.detect_format(data) {
    @lib.Jpeg =>
      match @lib.inspect_jpeg(data) {
        Ok(report) => {
          send_json(inspection_json(report))
          0
        }
        Err(error) => {
          send_json(error_json("invalid-jpeg", jpeg_error_message(error)))
          1
        }
      }
    @lib.Png =>
      match @lib.inspect_png(data) {
        Ok(report) => {
          send_json(png_inspection_json(report))
          0
        }
        Err(error) => {
          send_json(error_json("invalid-png", png_error_message(error)))
          1
        }
      }
    @lib.Webp =>
      match @lib.inspect_webp(data) {
        Ok(report) => {
          send_json(webp_inspection_json(report))
          0
        }
        Err(error) => {
          send_json(error_json("invalid-webp", webp_error_message(error)))
          1
        }
      }
    _ => {
      send_json(
        error_json(
          "unsupported-format", "当前网页支持 JPEG、PNG 和 WebP 清理",
        ),
      )
      2
    }
  }
}

///|
#export_name("photo_privacy_sanitize")
pub fn sanitize_loaded_file() -> Int {
  guard load_input() is Some(data) else {
    send_json(
      error_json("file-too-large", "文件大小无效或超过 50 MiB 限制"),
    )
    return 3
  }
  match @lib.detect_format(data) {
    @lib.Jpeg => sanitize_loaded_jpeg(data)
    @lib.Png => sanitize_loaded_png(data)
    @lib.Webp => sanitize_loaded_webp(data)
    _ => {
      send_json(
        error_json(
          "unsupported-format", "当前网页支持 JPEG、PNG 和 WebP 清理",
        ),
      )
      2
    }
  }
}

///|
fn sanitize_loaded_jpeg(data : Bytes) -> Int {
  match @lib.sanitize_jpeg(data) {
    Err(error) => {
      send_json(error_json("invalid-jpeg", jpeg_error_message(error)))
      1
    }
    Ok(result) => {
      send_output(result.output())
      let builder = StringBuilder()
      builder.write_string("{\"ok\":true,\"verified\":")
      builder.write_string(if result.verified() { "true" } else { "false" })
      builder.write_string(",\"outputSize\":")
      builder.write_string(result.output().length().to_string())
      builder.write_string(",\"removedBytes\":")
      builder.write_string(result.removed_bytes().to_string())
      builder.write_string(",\"removed\":[")
      for index, item in result.removed() {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string("{\"name\":")
        json_string(builder, item.name)
        builder.write_string(",\"offset\":")
        builder.write_string(item.offset.to_string())
        builder.write_string(",\"originalLength\":")
        builder.write_string(item.original_length.to_string())
        builder.write_string(",\"replacementLength\":")
        builder.write_string(item.replacement_length.to_string())
        builder.write_char('}')
      }
      builder.write_string("]}")
      send_json(builder.to_string())
      if result.verified() {
        0
      } else {
        4
      }
    }
  }
}

///|
fn sanitize_loaded_png(data : Bytes) -> Int {
  match @lib.sanitize_png(data) {
    Err(error) => {
      send_json(error_json("invalid-png", png_error_message(error)))
      1
    }
    Ok(result) => {
      send_output(result.output())
      let builder = StringBuilder()
      builder.write_string("{\"ok\":true,\"format\":\"PNG\",\"verified\":")
      builder.write_string(if result.verified() { "true" } else { "false" })
      builder.write_string(",\"outputSize\":")
      builder.write_string(result.output().length().to_string())
      builder.write_string(",\"removedBytes\":")
      builder.write_string(result.removed_bytes().to_string())
      builder.write_string(",\"removed\":[")
      for index, item in result.removed() {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string("{\"name\":")
        json_string(builder, item.name)
        builder.write_string(",\"offset\":")
        builder.write_string(item.offset.to_string())
        builder.write_string(",\"originalLength\":")
        builder.write_string(item.original_length.to_string())
        builder.write_string(",\"replacementLength\":")
        builder.write_string(item.replacement_length.to_string())
        builder.write_char('}')
      }
      builder.write_string("]}")
      send_json(builder.to_string())
      if result.verified() {
        0
      } else {
        4
      }
    }
  }
}

///|
fn sanitize_loaded_webp(data : Bytes) -> Int {
  match @lib.sanitize_webp(data) {
    Err(error) => {
      send_json(error_json("invalid-webp", webp_error_message(error)))
      1
    }
    Ok(result) => {
      send_output(result.output())
      let builder = StringBuilder()
      builder.write_string("{\"ok\":true,\"format\":\"WebP\",\"verified\":")
      builder.write_string(if result.verified() { "true" } else { "false" })
      builder.write_string(",\"outputSize\":")
      builder.write_string(result.output().length().to_string())
      builder.write_string(",\"removedBytes\":")
      builder.write_string(result.removed_bytes().to_string())
      builder.write_string(",\"removed\":[")
      for index, item in result.removed() {
        if index > 0 {
          builder.write_char(',')
        }
        builder.write_string("{\"name\":")
        json_string(builder, item.name)
        builder.write_string(",\"offset\":")
        builder.write_string(item.offset.to_string())
        builder.write_string(",\"originalLength\":")
        builder.write_string(item.original_length.to_string())
        builder.write_string(",\"replacementLength\":")
        builder.write_string(item.replacement_length.to_string())
        builder.write_char('}')
      }
      builder.write_string("]}")
      send_json(builder.to_string())
      if result.verified() {
        0
      } else {
        4
      }
    }
  }
}
