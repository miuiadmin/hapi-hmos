// CodexDiff 单测 —— unified diff 解析纯逻辑层（零 @kit，LocalUnit 可加载）。
//   对照 CodexDiffView.tsx:5-55 parseUnifiedDiff 语义：手写行扫描器把 input.unified_diff
//   拆成 {oldText,newText,fileName}。覆盖纯增/纯删/混合/多文件/+++ 无 b/ 前缀/元信息行跳过/
//   \ No newline 跳过/空串/fileName 末次 +++ 覆盖（faithful 上游）。

import { describe, it, expect } from '@ohos/hypium';
import { parseUnifiedDiff } from '../main/ets/chat/CodexDiff';

export default function codexDiffTest(): void {
  // —— 纯增 ——
  describe('CodexDiff — 纯增（+ 行只入 new）', () => {
    it('单条新增 → old 仅 ctx，new 含 added', 0, () => {
      const diff = 'diff --git a/foo.ts b/foo.ts\n' +
        'index 123..456 100644\n' +
        '--- a/foo.ts\n' +
        '+++ b/foo.ts\n' +
        '@@ -1,2 +1,3 @@\n' +
        ' line1\n' +
        '+added\n' +
        ' line2';
      const p = parseUnifiedDiff(diff);
      expect(p.fileName).assertEqual('foo.ts');
      expect(p.oldText).assertEqual('line1\nline2');
      expect(p.newText).assertEqual('line1\nadded\nline2');
    });
  });

  // —— 纯删 ——
  describe('CodexDiff — 纯删（- 行只入 old）', () => {
    it('单条删除 → old 含 removed，new 仅 ctx', 0, () => {
      const diff = '--- a/bar.ts\n' +
        '+++ b/bar.ts\n' +
        '@@ -1,2 +1,1 @@\n' +
        ' line1\n' +
        '-removed';
      const p = parseUnifiedDiff(diff);
      expect(p.fileName).assertEqual('bar.ts');
      expect(p.oldText).assertEqual('line1\nremoved');
      expect(p.newText).assertEqual('line1');
    });
  });

  // —— 混合 ——
  describe('CodexDiff — 混合（+/-/空 共存）', () => {
    it('ctx + old + new + ctx → 双侧各自拼', 0, () => {
      const diff = '+++ b/baz.ts\n' +
        '@@ -1,3 +1,3 @@\n' +
        ' ctx\n' +
        '-old\n' +
        '+new\n' +
        ' ctx2';
      const p = parseUnifiedDiff(diff);
      expect(p.oldText).assertEqual('ctx\nold\nctx2');
      expect(p.newText).assertEqual('ctx\nnew\nctx2');
    });
  });

  // —— +++ 无 b/ 前缀 ——
  describe('CodexDiff — +++ 无 b/ 前缀', () => {
    it('+++ path/to/file.ts → fileName 取 substring(4)', 0, () => {
      const diff = '+++ path/to/file.ts\n' +
        '@@ -0,0 +1,1 @@\n' +
        '+a';
      const p = parseUnifiedDiff(diff);
      expect(p.fileName).assertEqual('path/to/file.ts');
      expect(p.newText).assertEqual('a');
      expect(p.oldText).assertEqual('');
    });
  });

  // —— 元信息行跳过（diff --git / index / --- / new file mode / deleted file mode）——
  describe('CodexDiff — 元信息行跳过', () => {
    it('new file：--- /dev/null 不入 old，仅 +hello 入 new', 0, () => {
      const diff = 'diff --git a/x b/x\n' +
        'new file mode 100644\n' +
        'index 000..111\n' +
        '--- /dev/null\n' +
        '+++ b/x\n' +
        '@@ -0,0 +1,1 @@\n' +
        '+hello';
      const p = parseUnifiedDiff(diff);
      expect(p.fileName).assertEqual('x');
      expect(p.oldText).assertEqual('');
      expect(p.newText).assertEqual('hello');
    });
    it('deleted file：仅 -bye 入 old，new 空', 0, () => {
      const diff = 'diff --git a/y b/y\n' +
        'deleted file mode 100644\n' +
        '--- a/y\n' +
        '+++ /dev/null\n' +
        '@@ -1,1 +0,0 @@\n' +
        '-bye';
      const p = parseUnifiedDiff(diff);
      // +++ /dev/null → fileName='/dev/null'（faithful：上游也取 +++ 行原文）
      expect(p.fileName).assertEqual('/dev/null');
      expect(p.oldText).assertEqual('bye');
      expect(p.newText).assertEqual('');
    });
  });

  // —— \ No newline at end of file 跳过 ——
  describe('CodexDiff — \\ No newline 行跳过', () => {
    it('\\ No newline at end of file 不入任一侧', 0, () => {
      const diff = '+++ b/y\n' +
        '@@ -1,1 +1,1 @@\n' +
        '-old\n' +
        '\\ No newline at end of file\n' +
        '+new';
      const p = parseUnifiedDiff(diff);
      expect(p.oldText).assertEqual('old');
      expect(p.newText).assertEqual('new');
    });
  });

  // —— 空串 ——
  describe('CodexDiff — 空串 / 无 hunk', () => {
    it('空串 → 三字段空', 0, () => {
      const p = parseUnifiedDiff('');
      expect(p.oldText).assertEqual('');
      expect(p.newText).assertEqual('');
      expect(p.fileName).assertEqual('');
    });
    it('仅文件头无 @@ hunk → 体空', 0, () => {
      const diff = 'diff --git a/z b/z\n+++ b/z\n';
      const p = parseUnifiedDiff(diff);
      expect(p.fileName).assertEqual('z');
      expect(p.oldText).assertEqual('');
      expect(p.newText).assertEqual('');
    });
  });

  // —— 多文件：fileName 取末次 +++（faithful 上游 fileName 覆盖）——
  describe('CodexDiff — 多文件 fileName 取末次 +++', () => {
    it('两文件 → fileName = 末次 +++', 0, () => {
      const diff = 'diff --git a/a.ts b/a.ts\n' +
        '+++ b/a.ts\n' +
        '@@ -1,1 +1,1 @@\n' +
        '-x\n' +
        '+x2\n' +
        'diff --git a/b.ts b/b.ts\n' +
        '+++ b/b.ts\n' +
        '@@ -1,1 +1,1 @@\n' +
        '-y\n' +
        '+y2';
      const p = parseUnifiedDiff(diff);
      // 末次 +++ b/b.ts → fileName='b.ts'；体行两侧都拼上（两 hunk 累加）
      expect(p.fileName).assertEqual('b.ts');
      expect(p.oldText).assertEqual('x\ny');
      expect(p.newText).assertEqual('x2\ny2');
    });
  });

  // —— 拼回不变量：hunk 内 '-' 行 + ' ' 行数 == oldText 行数 ——
  describe('CodexDiff — 行数不变量', () => {
    it('oldText 行数 = (- 行 + 空格行) 数', 0, () => {
      const diff = '+++ b/w.ts\n' +
        '@@ -1,4 +1,4 @@\n' +
        ' k1\n' +
        '-d1\n' +
        ' k2\n' +
        '-d2';
      const p = parseUnifiedDiff(diff);
      // old = k1, d1, k2, d2 → 4 行
      expect(p.oldText.split('\n').length).assertEqual(4);
    });
  });
}
