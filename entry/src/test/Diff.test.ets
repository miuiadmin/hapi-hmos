// Diff 纯逻辑单测 —— 对照 web/src/components/DiffView.test.tsx
// 上游用 React Testing Library 渲染断言；此处把同样的语义落到纯函数 computeDiff / computeDiffStats / splitDiffLines。
// 移植的上游用例：
//   1) 「counts blank-line additions and removals in diff stats」→ computeDiff + computeDiffStats 得 +1 -1
//   2) 「reports zero lines for an empty side of the diff」       → 空旧侧 → oldLines=0、newLines=N（上游 "0 → 1 lines"）
//   3) 「comfortable rows / 末尾追加一行」                        → 仅 1 个 added
// 并补 LCS 边界：全等 / 全增 / 全删 / 单行替换 / 行号连续。

import { describe, it, expect } from '@ohos/hypium';
import {
  splitDiffLines,
  computeDiff,
  computeDiffStats,
  DiffLine
} from '../main/ets/chat/Diff';

// 将 DiffLine[] 压成可读签名，便于整体断言：'=line 1|+line 3|-line 3'（= 不变 / + 新增 / - 删除）
function diffSig(lines: DiffLine[]): string {
  const parts: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const dl: DiffLine = lines[i];
    const tag: string = dl.type === 'added' ? '+' : (dl.type === 'removed' ? '-' : '=');
    parts.push(`${tag}${dl.text}`);
  }
  return parts.join('|');
}

export default function diffTest(): void {
  describe('splitDiffLines', () => {
    it('returns an empty array for the empty string', 0, () => {
      expect(splitDiffLines('').length).assertEqual(0);
    });

    it('drops the trailing empty line produced by a trailing newline', 0, () => {
      // 'a\n' split → ['a','']，末尾空串丢弃 → ['a']
      const lines: string[] = splitDiffLines('a\n');
      expect(lines.length).assertEqual(1);
      expect(lines[0]).assertEqual('a');
    });

    it('keeps an explicit blank line in the middle', 0, () => {
      // 'a\n\nb' → ['a','','b']（中间空行保留，是真实的第 2 行）
      const lines: string[] = splitDiffLines('a\n\nb');
      expect(lines.length).assertEqual(3);
      expect(lines[1]).assertEqual('');
    });

    it('keeps the last line when there is no trailing newline', 0, () => {
      const lines: string[] = splitDiffLines('x\ny');
      expect(lines.length).assertEqual(2);
      expect(lines[1]).assertEqual('y');
    });
  });

  describe('computeDiff', () => {
    it('returns an empty array when both sides are empty', 0, () => {
      expect(computeDiff('', '').length).assertEqual(0);
    });

    it('produces only added lines when the old side is empty', 0, () => {
      // 上游 DiffView：「reports zero lines for an empty side of the diff」（"0 → 1 lines"）
      const lines: DiffLine[] = computeDiff('', 'created\n');
      expect(lines.length).assertEqual(1);
      expect(lines[0].type).assertEqual('added');
      expect(lines[0].text).assertEqual('created');
      expect(lines[0].oldLine).assertEqual(0);
      expect(lines[0].newLine).assertEqual(1);
    });

    it('produces only removed lines when the new side is empty', 0, () => {
      const lines: DiffLine[] = computeDiff('gone\n', '');
      expect(lines.length).assertEqual(1);
      expect(lines[0].type).assertEqual('removed');
      expect(lines[0].text).assertEqual('gone');
      expect(lines[0].oldLine).assertEqual(1);
      expect(lines[0].newLine).assertEqual(0);
    });

    it('marks everything unchanged and keeps line numbers contiguous when old equals new', 0, () => {
      const lines: DiffLine[] = computeDiff('a\nb\nc', 'a\nb\nc');
      expect(diffSig(lines)).assertEqual('=a|=b|=c');
      expect(lines[0].oldLine).assertEqual(1);
      expect(lines[0].newLine).assertEqual(1);
      expect(lines[2].oldLine).assertEqual(3);
      expect(lines[2].newLine).assertEqual(3);
    });

    it('detects a single-line replacement as one add plus one remove', 0, () => {
      const lines: DiffLine[] = computeDiff('before', 'after');
      expect(diffSig(lines)).assertEqual('+after|-before');
    });

    it('counts blank-line additions and removals as +1 -1 (upstream DiffView case)', 0, () => {
      // 上游：oldStr 'line 1\n\nline 3\n'  newStr 'line 1\nline 3\n\n' → +1 -1
      const lines: DiffLine[] = computeDiff('line 1\n\nline 3\n', 'line 1\nline 3\n\n');
      const stats = computeDiffStats(lines);
      expect(stats.additions).assertEqual(1);
      expect(stats.deletions).assertEqual(1);
    });

    it('appends a single new line at the end (upstream comfortable-rows case)', 0, () => {
      // 上游：123 行 + 末尾 1 行新增 → 仅 1 个 added、0 个 removed。此处缩小规模验证「末尾追加」语义。
      let built: string = 'old 1';
      for (let i = 2; i <= 5; i++) {
        built += '\nold ' + i;
      }
      const newStr: string = built + '\nnew line';
      const lines: DiffLine[] = computeDiff(built, newStr);
      const stats = computeDiffStats(lines);
      expect(stats.additions).assertEqual(1);
      expect(stats.deletions).assertEqual(0);
      expect(lines[lines.length - 1].type).assertEqual('added');
      expect(lines[lines.length - 1].text).assertEqual('new line');
    });
  });

  describe('computeDiffStats', () => {
    it('reports 0 old lines and N new lines for an all-added diff', 0, () => {
      // 上游 "0 → 1 lines"：空旧侧 → oldLines=0、newLines=1
      const stats = computeDiffStats(computeDiff('', 'created\n'));
      expect(stats.oldLines).assertEqual(0);
      expect(stats.newLines).assertEqual(1);
      expect(stats.additions).assertEqual(1);
      expect(stats.deletions).assertEqual(0);
    });

    it('counts additions and deletions across a mixed diff', 0, () => {
      // 'a\nb' → 'a\nc'：'a' 不变，'b' 删，'c' 增；oldLines=2、newLines=2
      const stats = computeDiffStats(computeDiff('a\nb', 'a\nc'));
      expect(stats.additions).assertEqual(1);
      expect(stats.deletions).assertEqual(1);
      expect(stats.oldLines).assertEqual(2);
      expect(stats.newLines).assertEqual(2);
    });

    it('reports zero changes for an identical pair', 0, () => {
      const stats = computeDiffStats(computeDiff('x\ny', 'x\ny'));
      expect(stats.additions).assertEqual(0);
      expect(stats.deletions).assertEqual(0);
      expect(stats.oldLines).assertEqual(2);
      expect(stats.newLines).assertEqual(2);
    });
  });
}
