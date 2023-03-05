"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkBounds = void 0;
function checkBounds(array, index) {
    if (index < 0 || index >= array.length) {
        throw new Error('Index out of bounds');
    }
}
exports.checkBounds = checkBounds;
//# sourceMappingURL=check-bounds.js.map