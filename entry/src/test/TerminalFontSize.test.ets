// TerminalFontSize 单测 —— 终端字号纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言（assertEqual / ===）。
//   覆盖 VALID 列表 / DEFAULT / normalizeTerminalFontSize（合法透传 + 非法回落 DEFAULT）。

import { describe, it, expect } from '@ohos/hypium';
import {
  VALID_TERMINAL_FONT_SIZES,
  DEFAULT_TERMINAL_FONT_SIZE,
  normalizeTerminalFontSize
} from '../main/ets/chat/TerminalFontSize';

export default function terminalFontSizeTest(): void {
  describe('TerminalFontSize — 常量', () => {
    it('DEFAULT = 13', 0, () => {
      expect(DEFAULT_TERMINAL_FONT_SIZE).assertEqual(13);
    });
    it('VALID = [9,11,13,15,17] 恰 5 档', 0, () => {
      expect(VALID_TERMINAL_FONT_SIZES.length).assertEqual(5);
      expect(VALID_TERMINAL_FONT_SIZES[0]).assertEqual(9);
      expect(VALID_TERMINAL_FONT_SIZES[1]).assertEqual(11);
      expect(VALID_TERMINAL_FONT_SIZES[2]).assertEqual(13);
      expect(VALID_TERMINAL_FONT_SIZES[3]).assertEqual(15);
      expect(VALID_TERMINAL_FONT_SIZES[4]).assertEqual(17);
    });
  });

  describe('TerminalFontSize — normalizeTerminalFontSize 合法值透传', () => {
    it('9 → 9', 0, () => { expect(normalizeTerminalFontSize(9)).assertEqual(9); });
    it('11 → 11', 0, () => { expect(normalizeTerminalFontSize(11)).assertEqual(11); });
    it('13 → 13', 0, () => { expect(normalizeTerminalFontSize(13)).assertEqual(13); });
    it('15 → 15', 0, () => { expect(normalizeTerminalFontSize(15)).assertEqual(15); });
    it('17 → 17', 0, () => { expect(normalizeTerminalFontSize(17)).assertEqual(17); });
  });

  describe('TerminalFontSize — normalizeTerminalFontSize 非法值回落 DEFAULT(13)', () => {
    it('0 → 13（不在档位）', 0, () => { expect(normalizeTerminalFontSize(0)).assertEqual(13); });
    it('10 → 13（在范围内但非档位）', 0, () => { expect(normalizeTerminalFontSize(10)).assertEqual(13); });
    it('14 → 13（在范围内但非档位）', 0, () => { expect(normalizeTerminalFontSize(14)).assertEqual(13); });
    it('18 → 13（超出最大档）', 0, () => { expect(normalizeTerminalFontSize(18)).assertEqual(13); });
    it('8 → 13（低于最小档）', 0, () => { expect(normalizeTerminalFontSize(8)).assertEqual(13); });
    it('-1 → 13（负数）', 0, () => { expect(normalizeTerminalFontSize(-1)).assertEqual(13); });
    it('NaN → 13（NaN 与任何 === 均 false）', 0, () => {
      expect(normalizeTerminalFontSize(Number.NaN)).assertEqual(13);
    });
  });
}
