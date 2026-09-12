import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { deflateSync } from "node:zlib";

const artifact = new URL("../dist/photo_privacy.wasm", import.meta.url);
const realWebpSamples = {
  lossy: "UklGRjwAAABXRUJQVlA4IDAAAACwAQCdASoCAAEAAUAmJaACdAEO/gLsAM4/Whd1iCP/9NI//ppH/9NI+YsrSaSSAAA=",
  losslessAlpha: "UklGRiAAAABXRUJQVlA4TBMAAAAvAQAAEA8w//sfD/oPBxWI6H8AAA==",
  animated: "UklGRoQAAABXRUJQVlA4WAoAAAASAAAAAQAAAQAAQU5JTQYAAAAAAAAAAABBTk1GKAAAAAAAAAAAAAEAAAEAAGQAAAJWUDhMDwAAAC8BQAAABxD9j/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAEAAGQAAAJWUDhMDwAAAC8BQAAQBxDR/wIGIqL/AQA=",
};

function sampleJpeg() {
  return Buffer.concat([
    Buffer.from([0xff, 0xd8]),
    Buffer.from([0xff, 0xe1, 0x00, 0x34]),
    Buffer.from("Exif\0\0", "binary"),
    Buffer.from([0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00]),
    Buffer.from([0x02, 0x00]),
    Buffer.from([0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00]),
    Buffer.from([0x0f, 0x01, 0x02, 0x00, 0x06, 0x00, 0x00, 0x00, 0x26, 0x00, 0x00, 0x00]),
    Buffer.from([0x00, 0x00, 0x00, 0x00]),
    Buffer.from("Canon\0", "binary"),
    Buffer.from([0xff, 0xfe, 0x00, 0x07]),
    Buffer.from("hello", "binary"),
    Buffer.from([0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x08, 0x00, 0x10, 0x01, 0x01, 0x11, 0x00]),
    Buffer.from([0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00]),
    Buffer.from([0x11, 0x22, 0xff, 0x00, 0x33]),
    Buffer.from([0xff, 0xd9]),
    Buffer.from("trailing", "binary"),
  ]);
}

function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(name, payload) {
  const type = Buffer.from(name, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(payload.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([type, payload])));
  return Buffer.concat([length, type, payload, checksum]);
}

function samplePng() {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(2, 0);
  ihdr.writeUInt32BE(1, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const pixels = Buffer.from([0, 255, 0, 0, 255, 0, 255, 0, 128]);
  return Buffer.concat([
    Buffer.from("89504e470d0a1a0a", "hex"),
    pngChunk("IHDR", ihdr),
    pngChunk("tEXt", Buffer.from("Author\0Alice", "latin1")),
    pngChunk("iTXt", Buffer.from("Description\0\0\0\0\0private note", "utf8")),
    pngChunk("IDAT", deflateSync(pixels)),
    pngChunk("IEND", Buffer.alloc(0)),
    Buffer.from("trailing", "ascii"),
  ]);
}

function riffChunk(name, payload) {
  const header = Buffer.alloc(8);
  header.write(name, 0, 4, "ascii");
  header.writeUInt32LE(payload.length, 4);
  return Buffer.concat([
    header,
    payload,
    payload.length % 2 === 1 ? Buffer.from([0]) : Buffer.alloc(0),
  ]);
}

function sampleWebp() {
  const simpleLossy = Buffer.from(realWebpSamples.lossy, "base64");
  const vp8Length = simpleLossy.readUInt32LE(16);
  const vp8x = Buffer.from([
    0x0c, 0, 0, 0,
    1, 0, 0,
    0, 0, 0,
  ]);
  const vp8 = simpleLossy.subarray(20, 20 + vp8Length);
  const exif = Buffer.concat([
    Buffer.from([0x49, 0x49, 0x2a, 0, 8, 0, 0, 0]),
    Buffer.from([2, 0]),
    Buffer.from([0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0]),
    Buffer.from([0x0f, 0x01, 2, 0, 6, 0, 0, 0, 0x26, 0, 0, 0]),
    Buffer.from([0, 0, 0, 0]),
    Buffer.from("Canon\0", "latin1"),
  ]);
  const chunks = Buffer.concat([
    riffChunk("VP8X", vp8x),
    riffChunk("VP8 ", vp8),
    riffChunk("EXIF", exif),
    riffChunk("XMP ", Buffer.from("<xmp>private</xmp>")),
    riffChunk("META", Buffer.from("private application data")),
  ]);
  const header = Buffer.alloc(12);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(chunks.length + 4, 4);
  header.write("WEBP", 8, "ascii");
  return Buffer.concat([header, chunks, Buffer.from("trailing")]);
}

function sampleRiffInfoWebp() {
  const simple = Buffer.from(realWebpSamples.lossy, "base64");
  const chunks = Buffer.concat([
    simple.subarray(12),
    riffChunk("IART", Buffer.from("test\0\0", "latin1")),
    riffChunk("ICOP", Buffer.from("2010\0\0", "latin1")),
    riffChunk("INAM", Buffer.from("webp-03.webp\0\0", "latin1")),
    riffChunk("ICMT", Buffer.from("test vector\0", "latin1")),
  ]);
  const header = Buffer.alloc(12);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(chunks.length + 4, 4);
  header.write("WEBP", 8, "ascii");
  return Buffer.concat([header, chunks]);
}

async function createBridge(input) {
  const wasm = await readFile(artifact);
  const state = { input: new Uint8Array(input), output: null, json: [] };
  const imports = {
    photo_privacy_host: {
      input_length: () => state.input.length,
      input_word(offset) {
        let word = 0;
        for (let lane = 0; lane < Math.min(4, state.input.length - offset); lane += 1) {
          word |= state.input[offset + lane] << (lane * 8);
        }
        return word >>> 0;
      },
      json_reset: () => { state.json = []; },
      json_code_point: (value) => { state.json.push(String.fromCodePoint(value)); },
      output_begin: (length) => { state.output = new Uint8Array(length); },
      output_word(offset, value, validBytes) {
        const word = value >>> 0;
        for (let lane = 0; lane < validBytes; lane += 1) {
          state.output[offset + lane] = (word >>> (lane * 8)) & 0xff;
        }
      },
    },
  };
  const { instance } = await WebAssembly.instantiate(wasm, imports);
  return { exports: instance.exports, state };
}

function resultJson(state) {
  return JSON.parse(state.json.join(""));
}

test("Wasm bridge inspects JPEG metadata", async () => {
  const bridge = await createBridge(sampleJpeg());
  assert.equal(bridge.exports.photo_privacy_inspect(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.format, "JPEG");
  assert.equal(report.width, 16);
  assert.equal(report.height, 8);
  assert.equal(report.orientation, 6);
  assert.equal(report.metadata.some((item) => item.name === "Camera maker"), true);
  assert.equal(report.metadata.some((item) => item.name === "Comment"), true);
});

test("Wasm bridge sanitizes and verifies JPEG", async () => {
  const bridge = await createBridge(sampleJpeg());
  assert.equal(bridge.exports.photo_privacy_sanitize(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.verified, true);
  assert.ok(report.removedBytes > 0);
  assert.equal(report.removed.some((item) => item.name === "Data after EOI"), true);
  assert.ok(bridge.state.output instanceof Uint8Array);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("Canon")), false);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("hello")), false);
  const rescan = await createBridge(bridge.state.output);
  assert.equal(rescan.exports.photo_privacy_inspect(), 0);
  assert.equal(resultJson(rescan.state).orientation, 6);
});

test("Wasm bridge inspects PNG metadata and image properties", async () => {
  const bridge = await createBridge(samplePng());
  assert.equal(bridge.exports.photo_privacy_inspect(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.format, "PNG");
  assert.equal(report.width, 2);
  assert.equal(report.height, 1);
  assert.equal(report.bitDepth, 8);
  assert.equal(report.colorType, 6);
  assert.equal(report.hasAlpha, true);
  assert.equal(report.isAnimated, false);
  assert.equal(report.metadata.some((item) => item.name === "Author"), true);
});

test("Wasm bridge sanitizes and verifies PNG", async () => {
  const bridge = await createBridge(samplePng());
  assert.equal(bridge.exports.photo_privacy_sanitize(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.format, "PNG");
  assert.equal(report.verified, true);
  assert.equal(report.removed.some((item) => item.name === "PNG text (tEXt)"), true);
  assert.equal(report.removed.some((item) => item.name === "Data after IEND"), true);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("Alice")), false);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("private note")), false);
  const rescan = await createBridge(bridge.state.output);
  assert.equal(rescan.exports.photo_privacy_inspect(), 0);
  assert.equal(resultJson(rescan.state).metadata.length, 0);
});

test("Wasm bridge inspects WebP metadata and image properties", async () => {
  const bridge = await createBridge(sampleWebp());
  assert.equal(bridge.exports.photo_privacy_inspect(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.format, "WebP");
  assert.equal(report.width, 2);
  assert.equal(report.height, 1);
  assert.equal(report.encoding, "扩展 VP8X");
  assert.equal(report.orientation, 6);
  assert.equal(report.metadata.some((item) => item.name === "Camera maker"), true);
  assert.equal(report.metadata.some((item) => item.name === "XMP"), true);
});

test("Wasm bridge sanitizes and verifies WebP", async () => {
  const bridge = await createBridge(sampleWebp());
  assert.equal(bridge.exports.photo_privacy_sanitize(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, true);
  assert.equal(report.format, "WebP");
  assert.equal(report.verified, true);
  assert.equal(report.removed.some((item) => item.name === "WebP XMP (XMP )"), true);
  assert.equal(report.removed.some((item) => item.name === "Data after RIFF"), true);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("Canon")), false);
  assert.equal(Buffer.from(bridge.state.output).includes(Buffer.from("private")), false);
  const rescan = await createBridge(bridge.state.output);
  assert.equal(rescan.exports.photo_privacy_inspect(), 0);
  const cleanReport = resultJson(rescan.state);
  assert.equal(cleanReport.orientation, 6);
  assert.equal(cleanReport.metadata.some((item) => item.name === "XMP"), false);
});

test("Wasm bridge accepts real lossy, transparent lossless, and animated WebP", async () => {
  const cases = [
    ["lossy", realWebpSamples.lossy, false, false],
    ["lossless alpha", realWebpSamples.losslessAlpha, true, false],
    ["animated", realWebpSamples.animated, true, true],
  ];
  for (const [name, encoded, hasAlpha, isAnimated] of cases) {
    const input = Buffer.from(encoded, "base64");
    const bridge = await createBridge(input);
    assert.equal(bridge.exports.photo_privacy_inspect(), 0, name);
    const report = resultJson(bridge.state);
    assert.equal(report.format, "WebP", name);
    assert.equal(report.width, 2, name);
    assert.equal(report.hasAlpha, hasAlpha, name);
    assert.equal(report.isAnimated, isAnimated, name);
    assert.equal(
      report.diagnostics.some((item) => item.code === "webp.alpha-flag-mismatch"),
      false,
      name,
    );
    assert.equal(bridge.exports.photo_privacy_sanitize(), 0, name);
    assert.equal(resultJson(bridge.state).verified, true, name);
    assert.deepEqual(Buffer.from(bridge.state.output), input, name);
  }
});

test("Wasm bridge cleans RIFF INFO metadata appended to a simple WebP", async () => {
  const bridge = await createBridge(sampleRiffInfoWebp());
  assert.equal(bridge.exports.photo_privacy_inspect(), 0);
  const report = resultJson(bridge.state);
  assert.equal(report.metadata.some((item) => item.name === "Artist"), true);
  assert.equal(report.metadata.some((item) => item.name === "Copyright"), true);
  assert.equal(report.metadata.some((item) => item.name === "Title"), true);
  assert.equal(report.metadata.some((item) => item.name === "Comment"), true);
  assert.equal(bridge.exports.photo_privacy_sanitize(), 0);
  const cleaned = resultJson(bridge.state);
  assert.equal(cleaned.verified, true);
  assert.equal(cleaned.removed.length, 4);
  assert.deepEqual(
    Buffer.from(bridge.state.output),
    Buffer.from(realWebpSamples.lossy, "base64"),
  );
});

test("Wasm bridge rejects unsupported input", async () => {
  const bridge = await createBridge(Buffer.from("not an image"));
  assert.equal(bridge.exports.photo_privacy_inspect(), 2);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, false);
  assert.equal(report.code, "unsupported-format");
});
