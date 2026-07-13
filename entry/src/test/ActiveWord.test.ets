// ActiveWord 纯逻辑单测 —— 光标处前缀活动词定位 + 建议应用（对照 web findActiveWord + applySuggestion）
//
// 覆盖：findActiveWord（/ 前缀命中 / 无前缀→null / 有选区→null / 起点→null / 词中光标），
//       applySuggestion（替换活动词、词尾补空格、已有尾空格不重复、光标定位）。

import { describe, it, expect } from '@ohos/hypium';
import { findActiveWord, applySuggestion } from '../main/ets/chat/ActiveWord';

const SLASH: string[] = ['/'];
const AT: string[] = ['@'];

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

  // @ 文件提及依赖 ActiveWord 的 '@' 前缀分支（findEnd 对文件路径的 / . 不中断）。
  //   mention 文本联想（MentionMenu）以 findActiveWord(['@']) 定位、applySuggestion(['@']) 回填，
  //   以下用例锁该契约，防日后改 findStart/findEnd 边界时静默打破 @ 联想。
  describe('findActiveWord — @ 前缀（文件提及）', () => {
    it('光标在词尾命中（含路径分隔 / 不中断）', 0, () => {
      const aw = findActiveWord('see @src/fo', 10, 10, AT);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('@src/fo');
      expect(aw!.offset).assertEqual(4);
    });
    it('文件名点号 . 不中断（@foo.ts）', 0, () => {
      const aw = findActiveWord('@foo.ts', 7, 7, AT);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('@foo.ts');
    });
    it('@ 后仅前缀（空 query）→ activeWord 为 @', 0, () => {
      // 输入 "hi @" 光标在尾：命中 @（query 为空 → MentionMenu 触发，searchSessionFiles 空 query 返默认列表）
      const aw = findActiveWord('hi @', 4, 4, AT);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('@');
      expect(aw!.offset).assertEqual(3);
    });
    it('空格分隔的第二个 @ 词（命中后者）', 0, () => {
      const aw = findActiveWord('@a.txt @b', 9, 9, AT);
      expect(aw !== null).assertTrue();
      expect(aw!.activeWord).assertEqual('@b');
      expect(aw!.offset).assertEqual(7);
    });
  });

  describe('applySuggestion — @ 回填', () => {
    it('替换 @ 活动词为完整路径 + 补空格', 0, () => {
      const r = applySuggestion('see @src/fo', 10, 10, '@src/foo.ts', AT, true);
      expect(r.text).assertEqual('see @src/foo.ts ');
      expect(r.cursorPosition).assertEqual(16);
    });
    it('已有尾随文本（空格）不重复补空格', 0, () => {
      const r = applySuggestion('edit @foo end', 9, 9, '@foo.ts', AT, true);
      expect(r.text).assertEqual('edit @foo.ts end');
    });
  });
}
