// ActiveWord 纯逻辑单测 —— 光标处前缀活动词定位 + 建议应用（对照 web findActiveWord + applySuggestion）
//
// 覆盖：findActiveWord（/ 前缀命中 / 无前缀→null / 有选区→null / 起点→null / 词中光标），
//       applySuggestion（替换活动词、词尾补空格、已有尾空格不重复、光标定位）。

import { describe, it, expect } from '@ohos/hypium';
import { findActiveWord, applySuggestion } from '../main/ets/chat/ActiveWord';

const SLASH: string[] = ['/'];

export default function activeWordTest(): void {
  describe('findActiveWord — / 前缀定位', () => {
    it('光标在词尾命中', 0, () => {
      const aw = findActiveWord('hello /wor', 10, 10, SLASH);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('/wor');
      expect(aw!.offset).assertEqual(6);
    });
    it('整串即命令（/cl）', 0, () => {
      const aw = findActiveWord('/cl', 3, 3, SLASH);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('/cl');
      expect(aw!.offset).assertEqual(0);
    });
    it('光标在词中（/clear done，光标在 clear 后即空格前）', 0, () => {
      // '/clear done'：光标 index6 = 紧跟 'r' 之后（空格位）
      const aw = findActiveWord('/clear done', 6, 6, SLASH);
      expect(aw !== null).assertTrue();
      expect(aw!.word).assertEqual('/clear');
      expect(aw!.activeWord).assertEqual('/clear');
    });
    it('无前缀 → null', 0, () => {
      expect(findActiveWord('no command here', 15, 15, SLASH)).assertNull();
    });
    it('有选区 → null', 0, () => {
      expect(findActiveWord('/clear', 1, 3, SLASH)).assertNull();
    });
    it('光标在起点(0) → null', 0, () => {
      expect(findActiveWord('/clear', 0, 0, SLASH)).assertNull();
    });
    it('活动词尾随空格 → null', 0, () => {
      expect(findActiveWord('/clear ', 7, 7, SLASH)).assertNull();
    });
  });

  describe('applySuggestion — 替换 + 补空格 + 光标', () => {
    it('词尾替换 + 末尾补空格', 0, () => {
      const r = applySuggestion('/cl', 3, 3, '/clear', SLASH, true);
      expect(r.text).assertEqual('/clear ');
      expect(r.cursorPosition).assertEqual(7);
    });
    it('已有尾随文本且含空格 → 不重复补空格', 0, () => {
      const r = applySuggestion('/clear done', 6, 6, '/clear', SLASH, true);
      expect(r.text).assertEqual('/clear done');
      expect(r.cursorPosition).assertEqual(6);
    });
    it('addSpace=false → 不补空格', 0, () => {
      const r = applySuggestion('/cl', 3, 3, '/clear', SLASH, false);
      expect(r.text).assertEqual('/clear');
      expect(r.cursorPosition).assertEqual(6);
    });
    it('无活动词 → 在光标处直接插入', 0, () => {
      const r = applySuggestion('hello', 5, 5, '/clear', SLASH, true);
      expect(r.text).assertEqual('hello/clear ');
    });
  });
}
