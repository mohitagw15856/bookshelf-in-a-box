/*!
 * qr.js — tiny, dependency-free QR Code generator (byte mode).
 *
 * Used by bookshelf-in-a-box to draw scannable "point your phone here" codes
 * fully offline — no external requests, no libraries, no build step.
 *
 * Algorithm ported from Project Nayuki's QR Code generator (MIT License),
 * trimmed to byte-mode only. Reference:
 *   https://www.nayuki.io/page/qr-code-generator-library
 *
 * Exposes QR.generate(text, eclName) -> { version, ecl, mask, size, modules }
 * and QR.toSvg(text, opts) / QR.drawCanvas(canvas, text, opts).
 */
(function (root) {
  "use strict";

  // Error-correction levels: ordinal (table index) + 2-bit format value.
  var ECL = {
    L: { ord: 0, bits: 1 },
    M: { ord: 1, bits: 0 },
    Q: { ord: 2, bits: 3 },
    H: { ord: 3, bits: 2 }
  };

  // Canonical per-version tables (index by version 1..40; [0] is a placeholder).
  var ECC_CODEWORDS_PER_BLOCK = [
    [-1,7,10,15,20,26,18,20,24,30,18,20,24,26,30,22,24,28,30,28,28,28,28,30,30,26,28,30,30,30,30,30,30,30,30,30,30,30,30,30,30],
    [-1,10,16,26,18,24,16,18,22,22,26,30,22,22,24,24,28,28,26,26,26,26,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28,28],
    [-1,13,22,18,26,18,24,18,22,20,24,28,26,24,20,30,24,28,28,26,30,28,30,30,30,30,28,30,30,30,30,30,30,30,30,30,30,30,30,30,30],
    [-1,17,28,22,16,22,28,26,26,24,28,24,28,22,24,24,30,28,28,26,28,30,24,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30]
  ];
  var NUM_EC_BLOCKS = [
    [-1,1,1,1,1,1,2,2,2,2,4,4,4,4,4,6,6,6,6,7,8,8,9,9,10,12,12,12,13,14,15,16,17,18,19,19,20,21,22,24,25],
    [-1,1,1,1,2,2,4,4,4,5,5,5,8,9,9,10,10,11,13,14,16,17,17,18,20,21,23,25,26,28,29,31,33,35,37,38,40,43,45,47,49],
    [-1,1,1,2,2,4,4,6,6,8,8,8,10,12,16,12,17,16,18,21,20,23,23,25,27,29,34,34,35,38,40,43,45,48,51,53,56,59,62,65,68],
    [-1,1,1,2,4,4,4,5,6,8,8,11,11,16,16,18,16,19,21,25,25,25,34,30,32,35,37,40,42,45,48,51,54,57,60,63,66,70,74,77,81]
  ];

  var MIN_VER = 1, MAX_VER = 40;

  // ---- Galois field GF(256) arithmetic (primitive polynomial 0x11D) ----
  function gfMul(x, y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11D);
      z ^= ((y >>> i) & 1) * x;
    }
    return z & 0xFF;
  }

  function rsDivisor(degree) {
    var result = [];
    for (var i = 0; i < degree; i++) result.push(0);
    result[degree - 1] = 1;
    var root = 1;
    for (var d = 0; d < degree; d++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = gfMul(result[j], root);
        if (j + 1 < result.length) result[j] ^= result[j + 1];
      }
      root = gfMul(root, 0x02);
    }
    return result;
  }

  function rsRemainder(data, divisor) {
    var result = divisor.map(function () { return 0; });
    data.forEach(function (b) {
      var factor = b ^ result.shift();
      result.push(0);
      divisor.forEach(function (coef, i) { result[i] ^= gfMul(coef, factor); });
    });
    return result;
  }

  // ---- structural helpers ----
  function numRawDataModules(ver) {
    var result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
      var numAlign = Math.floor(ver / 7) + 2;
      result -= (25 * numAlign - 10) * numAlign - 55;
      if (ver >= 7) result -= 36;
    }
    return result;
  }
  function numDataCodewords(ver, ecl) {
    return Math.floor(numRawDataModules(ver) / 8) -
      ECC_CODEWORDS_PER_BLOCK[ecl.ord][ver] * NUM_EC_BLOCKS[ecl.ord][ver];
  }
  function alignPositions(ver) {
    if (ver === 1) return [];
    var numAlign = Math.floor(ver / 7) + 2;
    var step = (ver === 32) ? 26 : Math.ceil((ver * 4 + 4) / (numAlign * 2 - 2)) * 2;
    var result = [6];
    for (var pos = ver * 4 + 10; result.length < numAlign; pos -= step) result.splice(1, 0, pos);
    return result;
  }

  // ---- byte-mode segment ----
  function toUtf8(str) {
    var out = [];
    for (var i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (c < 0x80) out.push(c);
      else if (c < 0x800) { out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F)); }
      else if (c >= 0xD800 && c < 0xDC00 && i + 1 < str.length) {
        var c2 = str.charCodeAt(++i);
        var cp = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
        out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
      } else { out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)); }
    }
    return out;
  }

  function BitBuffer() { this.bits = []; }
  BitBuffer.prototype.append = function (val, len) {
    for (var i = len - 1; i >= 0; i--) this.bits.push((val >>> i) & 1);
  };

  function charCountBits(ver) { return ver <= 9 ? 8 : 16; }

  // ---- matrix builder ----
  function QrMatrix(version, eclUsed) {
    this.version = version;
    this.ecl = eclUsed;
    this.size = version * 4 + 17;
    var n = this.size;
    this.modules = [];
    this.isFn = [];
    for (var r = 0; r < n; r++) {
      this.modules.push(new Array(n).fill(false));
      this.isFn.push(new Array(n).fill(false));
    }
  }
  QrMatrix.prototype.set = function (x, y, dark) { this.modules[y][x] = dark; this.isFn[y][x] = true; };
  QrMatrix.prototype.finder = function (x, y) {
    for (var dy = -4; dy <= 4; dy++) for (var dx = -4; dx <= 4; dx++) {
      var xx = x + dx, yy = y + dy;
      if (xx < 0 || xx >= this.size || yy < 0 || yy >= this.size) continue;
      var dist = Math.max(Math.abs(dx), Math.abs(dy));
      this.set(xx, yy, dist !== 2 && dist !== 4);
    }
  };
  QrMatrix.prototype.align = function (x, y) {
    for (var dy = -2; dy <= 2; dy++) for (var dx = -2; dx <= 2; dx++)
      this.set(x + dx, y + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
  };

  QrMatrix.prototype.drawFunction = function () {
    var n = this.size, i;
    for (i = 0; i < n; i++) { this.set(6, i, i % 2 === 0); this.set(i, 6, i % 2 === 0); }
    this.finder(3, 3); this.finder(n - 4, 3); this.finder(3, n - 4);
    // separators are handled by finder drawing false ring; ensure surrounding light
    var pos = alignPositions(this.version);
    for (var a = 0; a < pos.length; a++) for (var b = 0; b < pos.length; b++) {
      if ((a === 0 && b === 0) || (a === 0 && b === pos.length - 1) || (a === pos.length - 1 && b === 0)) continue;
      this.align(pos[a], pos[b]);
    }
    this.drawFormat(0); // placeholder; real mask set later
    this.drawVersion();
  };

  QrMatrix.prototype.drawFormat = function (mask) {
    var data = (this.ecl.bits << 3) | mask;
    var rem = data;
    for (var i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
    var bits = ((data << 10) | rem) ^ 0x5412;
    var n = this.size, j;
    for (j = 0; j <= 5; j++) this.set(8, j, ((bits >>> j) & 1) !== 0);
    this.set(8, 7, ((bits >>> 6) & 1) !== 0);
    this.set(8, 8, ((bits >>> 7) & 1) !== 0);
    this.set(7, 8, ((bits >>> 8) & 1) !== 0);
    for (j = 9; j < 15; j++) this.set(14 - j, 8, ((bits >>> j) & 1) !== 0);
    for (j = 0; j < 8; j++) this.set(n - 1 - j, 8, ((bits >>> j) & 1) !== 0);
    for (j = 8; j < 15; j++) this.set(8, n - 15 + j, ((bits >>> j) & 1) !== 0);
    this.set(8, n - 8, true); // dark module
  };

  QrMatrix.prototype.drawVersion = function () {
    if (this.version < 7) return;
    var rem = this.version;
    for (var i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1F25);
    var bits = (this.version << 12) | rem;
    for (var j = 0; j < 18; j++) {
      var bit = ((bits >>> j) & 1) !== 0;
      var a = this.size - 11 + (j % 3), b = Math.floor(j / 3);
      this.set(a, b, bit); this.set(b, a, bit);
    }
  };

  QrMatrix.prototype.drawCodewords = function (data) {
    var n = this.size, i = 0;
    for (var right = n - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (var vert = 0; vert < n; vert++) {
        for (var k = 0; k < 2; k++) {
          var x = right - k;
          var upward = ((right + 1) & 2) === 0;
          var y = upward ? n - 1 - vert : vert;
          if (!this.isFn[y][x] && i < data.length * 8) {
            this.modules[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0;
            i++;
          }
        }
      }
    }
  };

  QrMatrix.prototype.applyMask = function (mask) {
    for (var y = 0; y < this.size; y++) for (var x = 0; x < this.size; x++) {
      if (this.isFn[y][x]) continue;
      var invert;
      switch (mask) {
        case 0: invert = (x + y) % 2 === 0; break;
        case 1: invert = y % 2 === 0; break;
        case 2: invert = x % 3 === 0; break;
        case 3: invert = (x + y) % 3 === 0; break;
        case 4: invert = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
        case 5: invert = (x * y) % 2 + (x * y) % 3 === 0; break;
        case 6: invert = ((x * y) % 2 + (x * y) % 3) % 2 === 0; break;
        default: invert = ((x + y) % 2 + (x * y) % 3) % 2 === 0; break;
      }
      if (invert) this.modules[y][x] = !this.modules[y][x];
    }
  };

  QrMatrix.prototype.penalty = function () {
    var n = this.size, score = 0, x, y;
    // rows & cols runs
    for (var t = 0; t < 2; t++) {
      for (y = 0; y < n; y++) {
        var run = 0, last = false;
        for (x = 0; x < n; x++) {
          var m = t === 0 ? this.modules[y][x] : this.modules[x][y];
          if (x === 0 || m !== last) { if (run >= 5) score += (run - 5) + 3; run = 1; last = m; }
          else { run++; }
        }
        if (run >= 5) score += (run - 5) + 3;
      }
    }
    // 2x2 blocks
    for (y = 0; y < n - 1; y++) for (x = 0; x < n - 1; x++) {
      var c = this.modules[y][x];
      if (c === this.modules[y][x + 1] && c === this.modules[y + 1][x] && c === this.modules[y + 1][x + 1]) score += 3;
    }
    // finder-like patterns
    var patA = [true, false, true, true, true, false, true];
    for (t = 0; t < 2; t++) for (y = 0; y < n; y++) {
      for (x = 0; x <= n - 7; x++) {
        var match = true;
        for (var i = 0; i < 7; i++) { var mm = t === 0 ? this.modules[y][x + i] : this.modules[x + i][y]; if (mm !== patA[i]) { match = false; break; } }
        if (match) {
          var before = true, after = true;
          for (i = 1; i <= 4; i++) { var bx = x - i; if (bx < 0 || (t === 0 ? this.modules[y][bx] : this.modules[bx][y])) { before = false; break; } }
          for (i = 7; i <= 10; i++) { var ax = x + i; if (ax >= n || (t === 0 ? this.modules[y][ax] : this.modules[ax][y])) { after = false; break; } }
          if (before || after) score += 40;
        }
      }
    }
    // dark proportion
    var dark = 0;
    for (y = 0; y < n; y++) for (x = 0; x < n; x++) if (this.modules[y][x]) dark++;
    var total = n * n;
    var k = 0;
    while (Math.abs(dark * 20 - total * 10) > (k + 1) * total) k++;
    score += k * 10;
    return score;
  };

  // ---- assemble codewords with ECC + interleaving ----
  function addEcc(dataCodewords, ver, ecl) {
    var numBlocks = NUM_EC_BLOCKS[ecl.ord][ver];
    var eccLen = ECC_CODEWORDS_PER_BLOCK[ecl.ord][ver];
    var rawCodewords = Math.floor(numRawDataModules(ver) / 8);
    var numShort = numBlocks - rawCodewords % numBlocks;
    var shortLen = Math.floor(rawCodewords / numBlocks);
    var blocks = [], divisor = rsDivisor(eccLen), k = 0;
    for (var i = 0; i < numBlocks; i++) {
      var datLen = shortLen - eccLen + (i < numShort ? 0 : 1);
      var dat = dataCodewords.slice(k, k + datLen); k += datLen;
      var ecc = rsRemainder(dat, divisor);
      blocks.push({ dat: dat, ecc: ecc });
    }
    var result = [];
    for (var j = 0; j < shortLen - eccLen + 1; j++) {
      for (i = 0; i < blocks.length; i++) {
        if (j < blocks[i].dat.length) result.push(blocks[i].dat[j]);
      }
    }
    for (j = 0; j < eccLen; j++) for (i = 0; i < blocks.length; i++) result.push(blocks[i].ecc[j]);
    return result;
  }

  function encode(text, eclName, forceVersion, forceMask) {
    var ecl = ECL[eclName || "M"];
    var bytes = toUtf8(text);

    // choose smallest version that fits
    var version = forceVersion || 0;
    if (!version) {
      for (var v = MIN_VER; v <= MAX_VER; v++) {
        var cap = numDataCodewords(v, ecl) * 8;
        var used = 4 + charCountBits(v) + bytes.length * 8;
        if (used <= cap) { version = v; break; }
      }
      if (!version) throw new Error("Data too long for QR code");
    }

    var bb = new BitBuffer();
    bb.append(0x4, 4);                        // byte mode
    bb.append(bytes.length, charCountBits(version));
    for (var i = 0; i < bytes.length; i++) bb.append(bytes[i], 8);

    var dataCapacityBits = numDataCodewords(version, ecl) * 8;
    bb.append(0, Math.min(4, dataCapacityBits - bb.bits.length)); // terminator
    while (bb.bits.length % 8 !== 0) bb.bits.push(0);             // byte align
    for (var pad = 0xEC; bb.bits.length < dataCapacityBits; pad ^= 0xEC ^ 0x11) bb.append(pad, 8);

    var dataCodewords = [];
    for (i = 0; i < bb.bits.length; i += 8) {
      var byte = 0; for (var b = 0; b < 8; b++) byte = (byte << 1) | bb.bits[i + b];
      dataCodewords.push(byte);
    }

    var allCodewords = addEcc(dataCodewords, version, ecl);

    var qr = new QrMatrix(version, ecl);
    qr.drawFunction();
    qr.drawCodewords(allCodewords);

    var mask = (forceMask === undefined || forceMask === null) ? -1 : forceMask;
    if (mask === -1) {
      var minScore = Infinity;
      for (var m = 0; m < 8; m++) {
        qr.applyMask(m); qr.drawFormat(m);
        var s = qr.penalty();
        if (s < minScore) { minScore = s; mask = m; }
        qr.applyMask(m); // undo
      }
    }
    qr.applyMask(mask);
    qr.drawFormat(mask);
    return { version: version, ecl: eclName || "M", mask: mask, size: qr.size, modules: qr.modules };
  }

  // ---- renderers ----
  function toSvg(text, opts) {
    opts = opts || {};
    var q = encode(text, opts.ecl);
    var border = opts.border == null ? 4 : opts.border;
    var dim = q.size + border * 2;
    var dark = opts.dark || "#12172a";
    var light = opts.light || "#ffffff";
    var parts = [];
    for (var y = 0; y < q.size; y++) for (var x = 0; x < q.size; x++)
      if (q.modules[y][x]) parts.push("M" + (x + border) + "," + (y + border) + "h1v1h-1z");
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + dim + ' ' + dim +
      '" width="' + (opts.px || dim * 4) + '" height="' + (opts.px || dim * 4) + '" shape-rendering="crispEdges">' +
      '<rect width="' + dim + '" height="' + dim + '" fill="' + light + '"/>' +
      '<path d="' + parts.join("") + '" fill="' + dark + '"/></svg>';
  }

  function drawCanvas(canvas, text, opts) {
    opts = opts || {};
    var q = encode(text, opts.ecl);
    var border = opts.border == null ? 4 : opts.border;
    var dim = q.size + border * 2;
    var scale = Math.max(1, Math.floor((opts.px || canvas.width || 260) / dim));
    canvas.width = canvas.height = dim * scale;
    var ctx = canvas.getContext("2d");
    ctx.fillStyle = opts.light || "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = opts.dark || "#12172a";
    for (var y = 0; y < q.size; y++) for (var x = 0; x < q.size; x++)
      if (q.modules[y][x]) ctx.fillRect((x + border) * scale, (y + border) * scale, scale, scale);
    return q;
  }

  var API = { generate: encode, toSvg: toSvg, drawCanvas: drawCanvas };
  if (typeof module !== "undefined" && module.exports) module.exports = API;
  if (root) root.QR = API;
})(typeof window !== "undefined" ? window : null);
