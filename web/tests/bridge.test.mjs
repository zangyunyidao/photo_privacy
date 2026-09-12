import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const artifact = new URL("../dist/photo_privacy.wasm", import.meta.url);

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

test("Wasm bridge rejects unsupported input", async () => {
  const bridge = await createBridge(Buffer.from("not an image"));
  assert.equal(bridge.exports.photo_privacy_inspect(), 2);
  const report = resultJson(bridge.state);
  assert.equal(report.ok, false);
  assert.equal(report.code, "unsupported-format");
});
