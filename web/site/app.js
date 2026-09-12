const MAX_FILE_SIZE = 50 * 1024 * 1024;

const elements = {
  dropZone: document.querySelector("#drop-zone"),
  fileInput: document.querySelector("#file-input"),
  chooseButton: document.querySelector("#choose-button"),
  replaceButton: document.querySelector("#replace-button"),
  loading: document.querySelector("#loading"),
  errorPanel: document.querySelector("#error-panel"),
  resultPanel: document.querySelector("#result-panel"),
  originalPreview: document.querySelector("#original-preview"),
  fileName: document.querySelector("#file-name"),
  fileSize: document.querySelector("#file-size"),
  formatChip: document.querySelector("#format-chip"),
  factFormat: document.querySelector("#fact-format"),
  factDimensions: document.querySelector("#fact-dimensions"),
  factSegments: document.querySelector("#fact-segments"),
  factUnitLabel: document.querySelector("#fact-unit-label"),
  factOrientation: document.querySelector("#fact-orientation"),
  factBitDepth: document.querySelector("#fact-bit-depth"),
  factColorType: document.querySelector("#fact-color-type"),
  factAlpha: document.querySelector("#fact-alpha"),
  factAnimation: document.querySelector("#fact-animation"),
  factEncoding: document.querySelector("#fact-encoding"),
  factFrameCount: document.querySelector("#fact-frame-count"),
  factLoopCount: document.querySelector("#fact-loop-count"),
  factBitDepthRow: document.querySelector("#fact-bit-depth-row"),
  factColorRow: document.querySelector("#fact-color-row"),
  factAlphaRow: document.querySelector("#fact-alpha-row"),
  factAnimationRow: document.querySelector("#fact-animation-row"),
  factEncodingRow: document.querySelector("#fact-encoding-row"),
  factFrameRow: document.querySelector("#fact-frame-row"),
  factLoopRow: document.querySelector("#fact-loop-row"),
  metadataCount: document.querySelector("#metadata-count"),
  metadataBody: document.querySelector("#metadata-body"),
  metadataEmpty: document.querySelector("#metadata-empty"),
  metadataTableWrap: document.querySelector("#metadata-table-wrap"),
  diagnostics: document.querySelector("#diagnostics"),
  sanitizeButton: document.querySelector("#sanitize-button"),
  cleanResult: document.querySelector("#clean-result"),
  cleanedPreview: document.querySelector("#cleaned-preview"),
  cleanSummary: document.querySelector("#clean-summary"),
  removedList: document.querySelector("#removed-list"),
  downloadButton: document.querySelector("#download-button"),
};

const state = {
  wasm: null,
  input: new Uint8Array(),
  output: new Uint8Array(),
  json: [],
  file: null,
  format: null,
  previewUrl: null,
  downloadUrl: null,
};

const host = {
  input_length() {
    return state.input.length;
  },
  input_word(offset) {
    let word = 0;
    const available = Math.min(4, state.input.length - offset);
    for (let lane = 0; lane < available; lane += 1) {
      word |= state.input[offset + lane] << (lane * 8);
    }
    return word >>> 0;
  },
  json_reset() {
    state.json = [];
  },
  json_code_point(value) {
    state.json.push(String.fromCodePoint(value));
  },
  output_begin(length) {
    state.output = new Uint8Array(length);
  },
  output_word(offset, value, validBytes) {
    const word = value >>> 0;
    for (let lane = 0; lane < validBytes; lane += 1) {
      state.output[offset + lane] = (word >>> (lane * 8)) & 0xff;
    }
  },
};

async function loadWasm() {
  const imports = { photo_privacy_host: host };
  try {
    const response = await fetch("./photo_privacy.wasm");
    if (!response.ok) {
      throw new Error(`无法加载 Wasm（HTTP ${response.status}）`);
    }
    try {
      const result = await WebAssembly.instantiateStreaming(response.clone(), imports);
      state.wasm = result.instance.exports;
    } catch {
      const result = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
      state.wasm = result.instance.exports;
    }
  } catch (error) {
    showError(`MoonBit/Wasm 初始化失败：${error.message}`);
    throw error;
  }
}

function readJsonResult() {
  const raw = state.json.join("");
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("Wasm 返回了无法解析的结果");
  }
}

function formatBytes(value) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  return `${(value / (1024 * 1024)).toFixed(2)} MiB`;
}

function orientationLabel(value) {
  const labels = {
    1: "正常（1）",
    2: "水平镜像（2）",
    3: "旋转 180°（3）",
    4: "垂直镜像（4）",
    5: "镜像并旋转 270°（5）",
    6: "旋转 90°（6）",
    7: "镜像并旋转 90°（7）",
    8: "旋转 270°（8）",
  };
  return labels[value] ?? "未记录";
}

function pngColorTypeLabel(value) {
  const labels = {
    0: "灰度（0）",
    2: "真彩色（2）",
    3: "索引色（3）",
    4: "灰度 + Alpha（4）",
    6: "真彩色 + Alpha（6）",
  };
  return labels[value] ?? `未知（${value}）`;
}

function riskClass(risk) {
  if (risk === "高") return "risk-high";
  if (risk === "中") return "risk-medium";
  if (risk === "低") return "risk-low";
  return "risk-none";
}

function clearObjectUrls() {
  if (state.previewUrl) URL.revokeObjectURL(state.previewUrl);
  if (state.downloadUrl) URL.revokeObjectURL(state.downloadUrl);
  state.previewUrl = null;
  state.downloadUrl = null;
}

function showError(message) {
  elements.errorPanel.textContent = message;
  elements.errorPanel.hidden = false;
}

function hideError() {
  elements.errorPanel.hidden = true;
  elements.errorPanel.textContent = "";
}

function setLoading(value) {
  elements.loading.hidden = !value;
}

function resetResult() {
  elements.resultPanel.hidden = true;
  elements.cleanResult.hidden = true;
  elements.cleanedPreview.removeAttribute("src");
  elements.metadataBody.replaceChildren();
  elements.removedList.replaceChildren();
  elements.diagnostics.hidden = true;
  elements.diagnostics.textContent = "";
  elements.sanitizeButton.disabled = false;
}

function renderMetadata(items) {
  elements.metadataBody.replaceChildren();
  elements.metadataCount.textContent = `${items.length} 项`;
  elements.metadataEmpty.hidden = items.length !== 0;
  elements.metadataTableWrap.hidden = items.length === 0;
  for (const item of items) {
    const row = document.createElement("tr");
    const category = document.createElement("td");
    const name = document.createElement("td");
    const value = document.createElement("td");
    const risk = document.createElement("td");
    const disposition = document.createElement("td");
    category.textContent = item.category;
    name.textContent = item.name;
    value.textContent = item.value || "（空值）";
    const riskBadge = document.createElement("span");
    riskBadge.className = `risk-chip ${riskClass(item.risk)}`;
    riskBadge.textContent = item.risk;
    risk.append(riskBadge);
    disposition.textContent = item.disposition;
    row.append(category, name, value, risk, disposition);
    elements.metadataBody.append(row);
  }
}

function renderInspection(report) {
  state.format = report.format;
  elements.resultPanel.hidden = false;
  elements.fileName.textContent = state.file.name;
  elements.fileSize.textContent = formatBytes(state.file.size);
  elements.formatChip.textContent = report.format;
  elements.factFormat.textContent = report.format;
  elements.factDimensions.textContent =
    report.width == null || report.height == null
      ? "未找到"
      : `${report.width} × ${report.height} px`;
  elements.factUnitLabel.textContent = report.unitLabel ?? "结构单元";
  const unit = report.format === "JPEG" ? "段" : "块";
  elements.factSegments.textContent = `${report.unitCount ?? report.segmentCount} ${unit}`;
  elements.factOrientation.textContent = orientationLabel(report.orientation);
  const isPng = report.format === "PNG";
  const isWebp = report.format === "WebP";
  elements.factBitDepthRow.hidden = !isPng;
  elements.factColorRow.hidden = !isPng;
  elements.factAlphaRow.hidden = !(isPng || isWebp);
  elements.factAnimationRow.hidden = !(isPng || isWebp);
  elements.factEncodingRow.hidden = !isWebp;
  elements.factFrameRow.hidden = !(isWebp && report.isAnimated);
  elements.factLoopRow.hidden = !(isWebp && report.isAnimated);
  elements.factBitDepth.textContent = isPng ? `${report.bitDepth} bit` : "—";
  elements.factColorType.textContent = isPng ? pngColorTypeLabel(report.colorType) : "—";
  elements.factAlpha.textContent = isPng || isWebp ? (report.hasAlpha ? "有" : "无") : "—";
  elements.factAnimation.textContent = isPng || isWebp
    ? (report.isAnimated ? (isPng ? "APNG" : "动画 WebP") : "静态")
    : "—";
  elements.factEncoding.textContent = isWebp ? report.encoding : "—";
  elements.factFrameCount.textContent = isWebp ? `${report.frameCount} 帧` : "—";
  elements.factLoopCount.textContent = isWebp
    ? (report.loopCount === 0 ? "无限循环" : `${report.loopCount} 次`)
    : "—";
  renderMetadata(report.metadata ?? []);
  const diagnostics = report.diagnostics ?? [];
  if (diagnostics.length > 0) {
    elements.diagnostics.hidden = false;
    elements.diagnostics.textContent = diagnostics
      .map((item) => `${item.severity}：${item.message}`)
      .join("；");
  }
}

async function inspectFile(file) {
  hideError();
  resetResult();
  setLoading(true);
  clearObjectUrls();
  try {
    if (!state.wasm) await loadWasm();
    if (file.size > MAX_FILE_SIZE) {
      throw new Error("文件超过 50 MiB 安全限制");
    }
    state.file = file;
    state.input = new Uint8Array(await file.arrayBuffer());
    state.previewUrl = URL.createObjectURL(file);
    elements.originalPreview.src = state.previewUrl;
    const status = state.wasm.photo_privacy_inspect();
    const report = readJsonResult();
    if (status !== 0 || !report.ok) {
      throw new Error(report.message ?? "无法检查这个文件");
    }
    renderInspection(report);
    elements.resultPanel.scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (error) {
    showError(error.message);
  } finally {
    setLoading(false);
  }
}

function cleanedFileName(name) {
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const extension = { JPEG: "jpg", PNG: "png", WebP: "webp" }[state.format] ?? "bin";
  return `${stem}.clean.${extension}`;
}

function removalLabel(name) {
  if (name === "Data after EOI") return "JPEG 尾随数据（EOI 之后）";
  if (name === "Data after IEND") return "PNG 尾随数据（IEND 之后）";
  if (name === "PNG text (tEXt)") return "PNG 文本（tEXt）";
  if (name === "PNG compressed text (zTXt)") return "PNG 压缩文本（zTXt）";
  if (name === "PNG international text (iTXt)") return "PNG 国际文本（iTXt）";
  if (name === "PNG Exif (eXIf)") return "PNG Exif（eXIf）";
  if (name === "PNG modification time (tIME)") return "PNG 修改时间（tIME）";
  if (name === "PNG physical dimensions (pHYs)") return "PNG 物理尺寸（pHYs）";
  if (name === "WebP Exif (EXIF)") return "WebP Exif（EXIF）";
  if (name === "WebP XMP (XMP )") return "WebP XMP（XMP）";
  if (name === "Data after RIFF") return "WebP RIFF 范围后的尾随数据";
  if (name.startsWith("WebP unknown chunk")) return name.replace("WebP unknown chunk", "WebP 未知块");
  if (name.startsWith("ANMF unknown chunk")) return name.replace("ANMF unknown chunk", "动画帧内未知块");
  return name;
}

function renderSanitizeResult(report) {
  elements.cleanResult.hidden = false;
  elements.cleanedPreview.src = state.downloadUrl;
  elements.cleanSummary.textContent = `文件由 ${formatBytes(state.file.size)} 减至 ${formatBytes(
    report.outputSize,
  )}，共移除 ${formatBytes(report.removedBytes)}。`;
  elements.removedList.replaceChildren();
  if ((report.removed ?? []).length === 0 && report.removedBytes === 0) {
    const item = document.createElement("li");
    item.textContent = "没有发现需要移除的信息，输出仍已通过结构复检。";
    elements.removedList.append(item);
  } else {
    for (const removal of report.removed ?? []) {
      const item = document.createElement("li");
      const retained = removal.replacementLength > 0 ? "（保留显示方向）" : "";
      item.textContent = `${removalLabel(removal.name)}${retained}`;
      elements.removedList.append(item);
    }
    if (report.removedBytes > 0 && (report.removed ?? []).length === 0) {
      const item = document.createElement("li");
      item.textContent = "发现并移除了容器结束位置后的尾随数据";
      elements.removedList.append(item);
    }
  }
  elements.cleanResult.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

async function sanitizeCurrentFile() {
  hideError();
  elements.sanitizeButton.disabled = true;
  elements.sanitizeButton.textContent = "正在清理……";
  try {
    await new Promise((resolve) => requestAnimationFrame(resolve));
    const status = state.wasm.photo_privacy_sanitize();
    const report = readJsonResult();
    if (status !== 0 || !report.ok || !report.verified) {
      throw new Error(report.message ?? "清理后的文件未通过复检，已停止下载");
    }
    if (state.downloadUrl) URL.revokeObjectURL(state.downloadUrl);
    const mimeType = {
      JPEG: "image/jpeg",
      PNG: "image/png",
      WebP: "image/webp",
    }[state.format] ?? "application/octet-stream";
    state.downloadUrl = URL.createObjectURL(new Blob([state.output], { type: mimeType }));
    renderSanitizeResult(report);
  } catch (error) {
    showError(error.message);
    elements.sanitizeButton.disabled = false;
  } finally {
    elements.sanitizeButton.textContent = "洗去信息";
  }
}

function downloadCleanedFile() {
  if (!state.downloadUrl || !state.file) return;
  const anchor = document.createElement("a");
  anchor.href = state.downloadUrl;
  anchor.download = cleanedFileName(state.file.name);
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
}

function openPicker() {
  elements.fileInput.value = "";
  elements.fileInput.click();
}

elements.chooseButton.addEventListener("click", (event) => {
  event.stopPropagation();
  openPicker();
});
elements.replaceButton.addEventListener("click", openPicker);
elements.dropZone.addEventListener("click", openPicker);
elements.dropZone.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    openPicker();
  }
});
elements.fileInput.addEventListener("change", () => {
  const [file] = elements.fileInput.files;
  if (file) inspectFile(file);
});

for (const eventName of ["dragenter", "dragover"]) {
  elements.dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    elements.dropZone.classList.add("is-dragging");
  });
}
for (const eventName of ["dragleave", "drop"]) {
  elements.dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    elements.dropZone.classList.remove("is-dragging");
  });
}
elements.dropZone.addEventListener("drop", (event) => {
  const [file] = event.dataTransfer.files;
  if (file) inspectFile(file);
});
elements.sanitizeButton.addEventListener("click", sanitizeCurrentFile);
elements.downloadButton.addEventListener("click", downloadCleanedFile);
window.addEventListener("beforeunload", clearObjectUrls);

loadWasm().catch(() => {});
