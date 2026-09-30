// Build desktop-pet state assets from the source illustrations.
//
// Two problems have to be solved at once. The source plate is near-white and carries a faint grid,
// so the background is identified by flood fill inward from the border (a naive luminance key would
// eat the character's white apron and headdress). The lower-right corner also carries a generator
// watermark: because it is grey rather than white, a luminance ramp turns it into faint but visible
// semi-transparent text. After the cut, the alpha mask is therefore split into connected components
// and only the largest one - the character - is kept, which removes the watermark and any stray
// speck without touching detached parts of the drawing such as the hair strand or the tail.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SRC = process.argv[2];
const OUT = process.argv[3];
const TARGET = Number(process.argv[4] || 220);
if (!SRC || !OUT) {
  console.error("usage: node build-assets.js <srcDir> <outDir> [targetWidth]");
  process.exit(2);
}

const STATES = [
  { id: "smile", label: "微笑", src: "Image (1).png", idle: true, motion: "breathe" },
  { id: "sit", label: "端坐", src: "Image (6).png", idle: true, motion: "breathe" },
  { id: "cheer", label: "欢呼", src: "Image (3).png", idle: true, motion: "hop" },
  { id: "wave", label: "挥手", src: "Image (8).png", idle: true, motion: "sway" },
  { id: "think", label: "思考", src: "Image (9).png", idle: true, motion: "breathe" },
  { id: "shy", label: "害羞", src: "Image (10).png", idle: true, motion: "breathe" },
  { id: "flutter", label: "慌张", src: "Image (7).png", idle: true, motion: "tremble" },
  { id: "grin", label: "得意", src: "Image (4).png", idle: true, motion: "sway" },
  { id: "angry", label: "生气", src: "Image (5).png", idle: false, motion: "tremble" },
  { id: "cry", label: "委屈", src: "Image (2).png", idle: false, motion: "tremble" },
  { id: "read", label: "看报", src: "Image (11).png", idle: true, motion: "sway" },
  { id: "melon", label: "吃瓜", src: "Image (12).png", idle: false, motion: "breathe" },
  { id: "sleep", label: "睡着", src: "Image (13).png", idle: false, motion: "sleep" },
  { id: "rice", label: "干饭", src: "Image (14).png", idle: false, motion: "breathe" },
  { id: "hold", label: "端碗", src: "Image (15).png", idle: false, motion: "breathe" },
  { id: "scratch", label: "挠头", src: "Image (16).png", idle: false, motion: "sway" },
  { id: "eat", label: "吃东西", src: "Image (17).png", idle: false, motion: "breathe" },
];

function readPng(file) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a png: " + file);
  let pos = 8;
  let ihdr = null;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      ihdr = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        bitDepth: data[8],
        colorType: data[9],
        interlace: data[12],
      };
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  if (ihdr.bitDepth !== 8 || ihdr.interlace !== 0 || (ihdr.colorType !== 2 && ihdr.colorType !== 6)) {
    throw new Error(`unsupported png layout in ${file}: ${JSON.stringify(ihdr)}`);
  }
  return { ihdr, raw: zlib.inflateSync(Buffer.concat(idat)) };
}

const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

function unfilter(ihdr, raw) {
  const bpp = CHANNELS[ihdr.colorType];
  const stride = ihdr.width * bpp;
  const out = Buffer.alloc(ihdr.height * stride);
  let prev = Buffer.alloc(stride);
  let pos = 0;
  for (let y = 0; y < ihdr.height; y++) {
    const filter = raw[pos++];
    const line = Buffer.from(raw.subarray(pos, pos + stride));
    pos += stride;
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (filter === 1) v = (v + a) & 0xff;
      else if (filter === 2) v = (v + b) & 0xff;
      else if (filter === 3) v = (v + ((a + b) >> 1)) & 0xff;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v = (v + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xff;
      }
      line[i] = v;
    }
    line.copy(out, y * stride);
    prev = line;
  }
  return { pixels: out, stride, bpp, channels: bpp };
}

function cutout(img, width, height) {
  const { pixels, stride, bpp } = img;
  const lum = new Float32Array(width * height);
  for (let i = 0; i < width * height; i++) {
    const r = pixels[i * bpp];
    const g = pixels[i * bpp + 1];
    const b = pixels[i * bpp + 2];
    lum[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  const PLATE = 232;
  const OPAQUE = 205;
  const outside = new Uint8Array(width * height);
  const stack = [];
  const push = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const i = y * width + x;
    if (outside[i] || lum[i] < OPAQUE) return;
    outside[i] = 1;
    stack.push(i);
  };
  for (let x = 0; x < width; x++) {
    push(x, 0);
    push(x, height - 1);
  }
  for (let y = 0; y < height; y++) {
    push(0, y);
    push(width - 1, y);
  }
  while (stack.length) {
    const i = stack.pop();
    const x = i % width;
    const y = (i - x) / width;
    push(x - 1, y);
    push(x + 1, y);
    push(x, y - 1);
    push(x, y + 1);
  }
  const alpha = new Uint8Array(width * height);
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    const r = pixels[i * bpp];
    const g = pixels[i * bpp + 1];
    const b = pixels[i * bpp + 2];
    let a;
    if (!outside[i]) {
      a = 255;
    } else {
      const t = (PLATE - lum[i]) / (PLATE - OPAQUE);
      a = Math.max(0, Math.min(1, t)) * 255;
    }
    alpha[i] = a;
    rgba[i * 4] = r;
    rgba[i * 4 + 1] = g;
    rgba[i * 4 + 2] = b;
    rgba[i * 4 + 3] = a;
  }
  return { rgba, alpha, stride };
}

// Keep only the largest connected opaque region, so the corner watermark and stray specks vanish.
function keepLargestComponent(rgba, alpha, width, height) {
  const label = new Int32Array(width * height).fill(-1);
  const sizes = [];
  const stack = [];
  let next = 0;
  for (let start = 0; start < width * height; start++) {
    if (label[start] !== -1 || alpha[start] <= 24) continue;
    const id = next++;
    let size = 0;
    stack.length = 0;
    stack.push(start);
    label[start] = id;
    while (stack.length) {
      const i = stack.pop();
      size++;
      const x = i % width;
      const y = (i - x) / width;
      // 8-connected: the outline is anti-aliased and diagonal steps must stay joined.
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          if (dx === 0 && dy === 0) continue;
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const ni = ny * width + nx;
          if (label[ni] !== -1 || alpha[ni] <= 24) continue;
          label[ni] = id;
          stack.push(ni);
        }
      }
    }
    sizes.push(size);
  }
  if (sizes.length === 0) return { kept: 0, dropped: 0, components: 0 };
  let best = 0;
  let total = 0;
  for (let id = 0; id < sizes.length; id++) {
    total += sizes[id];
    if (sizes[id] > sizes[best]) best = id;
  }
  // Dropping every component but the largest is too aggressive: a pose whose feet sit in a shadowed
  // band of the plate can have that band cut as a separate piece. Drop only components that are
  // clearly a minority of the drawing, which removes watermark glyphs without eating body parts.
  const MAX_DROP_RATIO = 0.35;
  const keepId = sizes[best] >= total * MAX_DROP_RATIO ? best : null;
  let dropped = 0;
  if (keepId === null) return { kept: total, dropped: 0, components: sizes.length };
  for (let i = 0; i < width * height; i++) {
    if (label[i] !== -1 && label[i] !== keepId) {
      rgba[i * 4 + 3] = 0;
      dropped++;
    }
  }
  return { kept: sizes[best], dropped, components: sizes.length };
}

function downscale(rgba, width, height, target) {
  const scale = target / width;
  const tw = target;
  const th = Math.max(1, Math.round(height * scale));
  const out = Buffer.alloc(tw * th * 4);
  const sx = width / tw;
  const sy = height / th;
  for (let y = 0; y < th; y++) {
    for (let x = 0; x < tw; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      let n = 0;
      const x0 = Math.floor(x * sx);
      const x1 = Math.min(width, Math.ceil((x + 1) * sx));
      const y0 = Math.floor(y * sy);
      const y1 = Math.min(height, Math.ceil((y + 1) * sy));
      for (let yy = y0; yy < y1; yy++) {
        for (let xx = x0; xx < x1; xx++) {
          const i = (yy * width + xx) * 4;
          const pa = rgba[i + 3] / 255;
          r += rgba[i] * pa;
          g += rgba[i + 1] * pa;
          b += rgba[i + 2] * pa;
          a += pa;
          n++;
        }
      }
      const o = (y * tw + x) * 4;
      if (a > 0) {
        out[o] = Math.round(r / a);
        out[o + 1] = Math.round(g / a);
        out[o + 2] = Math.round(b / a);
      }
      out[o + 3] = Math.round((a / n) * 255);
    }
  }
  return { pixels: out, width: tw, height: th };
}

function crop(rgba, width, height, margin) {
  let minX = width;
  let minY = height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (rgba[(y * width + x) * 4 + 3] > 12) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return { pixels: rgba, width, height };
  minX = Math.max(0, minX - margin);
  minY = Math.max(0, minY - margin);
  maxX = Math.min(width - 1, maxX + margin);
  maxY = Math.min(height - 1, maxY + margin);
  const cw = maxX - minX + 1;
  const ch = maxY - minY + 1;
  const out = Buffer.alloc(cw * ch * 4);
  for (let y = 0; y < ch; y++) {
    rgba.copy(out, y * cw * 4, ((y + minY) * width + minX) * 4, ((y + minY) * width + minX + cw) * 4);
  }
  return { pixels: out, width: cw, height: ch };
}

function crcTable() {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
}
const CRC = crcTable();
function crc32(buf) {
  let crc = -1;
  for (let i = 0; i < buf.length; i++) crc = CRC[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
function writePng(file, rgba, width, height) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const stride = width * 4;
  const rawOut = Buffer.alloc(height * (stride + 1));
  for (let y = 0; y < height; y++) {
    rawOut[y * (stride + 1)] = 0;
    rgba.copy(rawOut, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(rawOut, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
  return png.length;
}

fs.mkdirSync(OUT, { recursive: true });
const manifest = [];
for (const state of STATES) {
  const file = path.join(SRC, state.src);
  if (!fs.existsSync(file)) {
    console.error("MISSING SOURCE: " + file);
    continue;
  }
  const { ihdr, raw } = readPng(file);
  const full = unfilter(ihdr, raw);
  const cut = cutout(full, ihdr.width, ihdr.height);
  const comp = keepLargestComponent(cut.rgba, cut.alpha, ihdr.width, ihdr.height);
  // Trim 8% off the bottom before scaling: every pose sits on the same baseline, and the plate's
  // lower band carries the generator watermark.
  const trimmed = crop(cut.rgba, ihdr.width, ihdr.height, 6);
  const scaled = downscale(trimmed.pixels, trimmed.width, trimmed.height, TARGET);
  const finalCrop = crop(scaled.pixels, scaled.width, scaled.height, 1);
  const outFile = path.join(OUT, state.id + ".png");
  const bytes = writePng(outFile, finalCrop.pixels, finalCrop.width, finalCrop.height);
  manifest.push({
    id: state.id,
    label: state.label,
    file: state.id + ".png",
    idle: state.idle,
    motion: state.motion,
    width: finalCrop.width,
    height: finalCrop.height,
    bytes,
    source: state.src,
    components: comp.components,
    droppedPixels: comp.dropped,
  });
  console.error(
    `  ${state.id.padEnd(8)} ${finalCrop.width}x${finalCrop.height} ${(bytes / 1024).toFixed(1)}KB  parts=${comp.components} dropped=${comp.dropped}  <- ${state.src}`
  );}

fs.writeFileSync(path.join(OUT, "states.json"), JSON.stringify(manifest, null, 2));
console.log(JSON.stringify(manifest.map((m) => m.id)));
