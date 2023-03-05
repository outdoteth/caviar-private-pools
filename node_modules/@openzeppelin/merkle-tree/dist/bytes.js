"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hex = exports.compareBytes = void 0;
const utils_1 = require("ethereum-cryptography/utils");
function compareBytes(a, b) {
    const n = Math.min(a.length, b.length);
    for (let i = 0; i < n; i++) {
        if (a[i] !== b[i]) {
            return a[i] - b[i];
        }
    }
    return a.length - b.length;
}
exports.compareBytes = compareBytes;
function hex(b) {
    return '0x' + (0, utils_1.bytesToHex)(b);
}
exports.hex = hex;
//# sourceMappingURL=bytes.js.map