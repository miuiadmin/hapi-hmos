// MarkdownCodeSplitter 单测 —— fenced code 拆分纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test 范式：同步断言。覆盖：无 fence / 单 fence / language 提取 / tilde fence /
//   多 fence 交替 / 流式未闭合 / 前缀稳定性（流式复用关键）/ 空内容 / 行内码不误拆 / 缩进 fence。

import { describe, it, expect } from '@ohos/hypium';
import { splitMarkdown, MarkdownSegment } from '../main/ets/utils/MarkdownCodeSplitter';

// 辅助：取段 kinds 数组（断言「正文/代码交替」结构用）
function kinds(segs: MarkdownSegment[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < segs.length; i++) {
    out.push(segs[i].kind);
  }
  return out;
}

// 辅助：取第 idx 段（越界返回一个空 markdown 段，避免 | undefined 类型坑）
function at(segs: MarkdownSegment[], idx: number): MarkdownSegment {
  if (idx < 0 || idx >= segs.length) {
    const fallback: MarkdownSegment = new MarkdownSegment();
    return fallback;
  }
  return segs[idx];
}

export default function markdownCodeSplitterTest(): void {
  // —— 基本：无 fence / 空内容 ——
  describe('MarkdownCodeSplitter — 基本（无 fence / 空）', () => {
    it('纯文本无 fence → 单 markdown 段（全文）', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('hello world\n# 标题');
      expect(segs.length).assertEqual(1);
      expect(segs[0].kind).assertEqual('markdown');
      expect(segs[0].text).assertEqual('hello world\n# 标题');
    });
    it('空内容 → 单空 markdown 段', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('');
      expect(segs.length).assertEqual(1);
      expect(segs[0].kind).assertEqual('markdown');
      expect(segs[0].text).assertEqual('');
    });
    it('行内码（`code`）不误拆 → 仍单 markdown 段', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('use `x` and `y` here');
      expect(segs.length).assertEqual(1);
      expect(segs[0].kind).assertEqual('markdown');
      expect(segs[0].text.includes('`x`')).assertTrue();
    });
  });

  // —— fenced code：单块 / language 提取 ——
  describe('MarkdownCodeSplitter — fenced code 基本拆分', () => {
    it('正文 + 代码 + 正文 → 三段（md/code/md）', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('before\n```ts\nconst x = 1\n```\nafter');
      expect(kinds(segs)).assertEqual(['markdown', 'code', 'markdown']);
      expect(at(segs, 0).text).assertEqual('before');
      expect(at(segs, 1).kind).assertEqual('code');
      expect(at(segs, 1).language).assertEqual('ts');
      expect(at(segs, 1).text).assertEqual('const x = 1');
      expect(at(segs, 2).text).assertEqual('after');
    });
    it('顶格 fence 无前导正文 → 仅一个 code 段', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('```ts\ncode\n```');
      expect(segs.length).assertEqual(1);
      expect(at(segs, 0).kind).assertEqual('code');
      expect(at(segs, 0).language).assertEqual('ts');
      expect(at(segs, 0).text).assertEqual('code');
    });
    it('language 提取：```typescript → typescript', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('```typescript\nx\n```');
      expect(at(segs, 0).language).assertEqual('typescript');
    });
    it('language 提取：fence 后带参数（```ts title=x）→ 仅取首 token ts', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('```ts title=x\nx\n```');
      expect(at(segs, 0).language).assertEqual('ts');
    });
    it('fence 无 info → language 空串', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('```\nx\n```');
      expect(at(segs, 0).language).assertEqual('');
    });
    it('tilde fence（~~~py）→ code 段 language=py', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('~~~py\nprint(1)\n~~~');
      expect(segs.length).assertEqual(1);
      expect(at(segs, 0).kind).assertEqual('code');
      expect(at(segs, 0).language).assertEqual('py');
      expect(at(segs, 0).text).assertEqual('print(1)');
    });
    it('代码体内含行内反引号串不误闭（非纯 fence 行）', 0, () => {
      // 代码体 "const s = `tmpl`" 不是闭行（首字符非 `）→ 不提前闭合
      const segs: MarkdownSegment[] = splitMarkdown('```js\nconst s = `tmpl`\n```');
      expect(at(segs, 0).kind).assertEqual('code');
      expect(at(segs, 0).text).assertEqual('const s = `tmpl`');
    });
  });

  // —— 多代码块交替 ——
  describe('MarkdownCodeSplitter — 多代码块交替', () => {
    it('pre/code/mid/code/post → 5 段，kinds 交替', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('pre\n```a\n1\n```\nmid\n```b\n2\n```\npost');
      expect(segs.length).assertEqual(5);
      expect(kinds(segs)).assertEqual(['markdown', 'code', 'markdown', 'code', 'markdown']);
      expect(at(segs, 0).text).assertEqual('pre');
      expect(at(segs, 1).language).assertEqual('a');
      expect(at(segs, 1).text).assertEqual('1');
      expect(at(segs, 2).text).assertEqual('mid');
      expect(at(segs, 3).language).assertEqual('b');
      expect(at(segs, 3).text).assertEqual('2');
      expect(at(segs, 4).text).assertEqual('post');
    });
  });

  // —— 流式：未闭合 fence + 前缀稳定性 ——
  describe('MarkdownCodeSplitter — 流式（未闭合 / 前缀稳定）', () => {
    it('未闭合 fence（流式中）→ 末段 code，含已到达的部分代码', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('hello\n```ts\nconst x =');
      expect(kinds(segs)).assertEqual(['markdown', 'code']);
      expect(at(segs, 0).text).assertEqual('hello');
      expect(at(segs, 1).kind).assertEqual('code');
      expect(at(segs, 1).language).assertEqual('ts');
      expect(at(segs, 1).text).assertEqual('const x =');
    });
    it('前缀稳定性：末尾正文增长 → 前缀段(kind/lang/text)不变', 0, () => {
      const a: MarkdownSegment[] = splitMarkdown('ab\n```ts\nx\n```\nend');
      const b: MarkdownSegment[] = splitMarkdown('ab\n```ts\nx\n```\nend more text');
      // 段数相同（都 3 段：md/code/md）
      expect(a.length).assertEqual(3);
      expect(b.length).assertEqual(3);
      // 前两段完全一致（前缀稳定 → ForEach 复用）
      expect(at(a, 0).kind).assertEqual(at(b, 0).kind);
      expect(at(a, 0).text).assertEqual(at(b, 0).text);
      expect(at(a, 1).kind).assertEqual(at(b, 1).kind);
      expect(at(a, 1).language).assertEqual(at(b, 1).language);
      expect(at(a, 1).text).assertEqual(at(b, 1).text);
      // 仅末段正文增长
      expect(at(a, 2).text).assertEqual('end');
      expect(at(b, 2).text).assertEqual('end more text');
    });
    it('前缀稳定性：流式代码体内增长 → 前缀正文段不变，末段 code 增长', 0, () => {
      const a: MarkdownSegment[] = splitMarkdown('pre\n```ts\nline1');
      const b: MarkdownSegment[] = splitMarkdown('pre\n```ts\nline1\nline2');
      expect(a.length).assertEqual(2);
      expect(b.length).assertEqual(2);
      expect(at(a, 0).text).assertEqual(at(b, 0).text);   // 'pre' 不变
      expect(at(a, 1).language).assertEqual('ts');
      expect(at(a, 1).text).assertEqual('line1');
      expect(at(b, 1).text).assertEqual('line1\nline2');
    });
  });

  // —— 缩进 fence ——
  describe('MarkdownCodeSplitter — 缩进 fence', () => {
    it('行首空白（≤缩进）的 fence 仍识别', 0, () => {
      const segs: MarkdownSegment[] = splitMarkdown('text\n  ```ts\nx\n  ```');
      // [md('text'), code(ts,'x')]
      expect(kinds(segs)).assertEqual(['markdown', 'code']);
      expect(at(segs, 1).language).assertEqual('ts');
      expect(at(segs, 1).text).assertEqual('x');
    });
  });
}
