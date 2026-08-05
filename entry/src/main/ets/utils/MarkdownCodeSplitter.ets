// Markdown 代码块拆分器（纯逻辑层，无 @kit，LocalUnit 可测）。
//   把 markdown 文本拆成「正文段 markdown / 代码段 code」交替序列，供 MarkdownText 分别渲染：
//     正文段 → CJMarkdown（标题 / 列表 / 表格 / 行内码 … 排版能力强）；代码段 → CodeBlock（语法高亮）。
//
//   动机：markdown_hybrid 无 token 级语法着色 API（CJMarkDown.d.ets 仅有颜色 / 行号 / 圆角等样式
//     setter，无 keyword/string/comment 着色、无自定义代码节点渲染钩子；MarkdownPlugin 只是语法开关）。
//     故 fenced 代码块必须脱离 CJMarkdown 自渲；正文段仍走 CJMarkdown。
//
//   范围：仅拆 fenced code block（``` / ~~~，CommonMark）；缩进代码块 / 行内码（`…`）留在 markdown
//     段交 CJMarkdown（agent 文本几乎都用 fenced；缩进代码罕见）。
//
//   ★ 流式前缀稳定（关键）：逐行 append-only 扫描 → content 增长只影响末段或追加新段，已产出段不变 →
//     ForEach 用 `${configSignature}:${index}` 键可复用前缀段（避免每 token 整列重建）。
//     未闭合 fence（流式中）→ 末尾视作 code 段（部分代码实时高亮）；fence 闭合后后续行进新 markdown 段。
//
//   不用正则（ArkTS 严格模式禁）—— fence 识别 / language 提取全部手写字符扫描。

export type MarkdownSegmentKind = 'markdown' | 'code';

export class MarkdownSegment {
  kind: MarkdownSegmentKind = 'markdown';
  text: string = '';
  language: string = '';   // 仅 code 段：fence info 串首 token（如 'ts' / 'python'）
}

// fence 开行解析结果（marker = '`' 或 '~'；lang = info 串首 token）
class FenceOpenInfo {
  marker: string = '`';
  lang: string = '';
}

// 行首连续空白（空格 / Tab）的结束索引
function leadingWhitespaceEnd(line: string): number {
  let i: number = 0;
  while (i < line.length) {
    const ch: string = line.charAt(i);
    if (ch !== ' ' && ch !== '\t') {
      break;
    }
    i++;
  }
  return i;
}

// 判定某行是否为 fence 开行；是 → 返回 {marker, lang}，否 → null。
//   规则（CommonMark 简化）：去行首空白后，≥3 个连续 ` 或 ~；其后 info 串首 token = 语言（其余忽略）。
function matchFenceOpen(line: string): FenceOpenInfo | null {
  const rest: string = line.substring(leadingWhitespaceEnd(line));
  if (rest.length < 3) {
    return null;
  }
  const ch: string = rest.charAt(0);
  if (ch !== '`' && ch !== '~') {
    return null;
  }
  let count: number = 0;
  while (count < rest.length && rest.charAt(count) === ch) {
    count++;
  }
  if (count < 3) {
    return null;
  }
  // info 串 = fence 标记之后文本；首 token（到首个空白止）= 语言
  const info: string = rest.substring(count).trim();
  let langEnd: number = 0;
  while (langEnd < info.length && info.charAt(langEnd) !== ' ' && info.charAt(langEnd) !== '\t') {
    langEnd++;
  }
  const result: FenceOpenInfo = new FenceOpenInfo();
  result.marker = ch;
  result.lang = info.substring(0, langEnd);
  return result;
}

// 判定某行是否为 fence 闭行（与 marker 同字符 ≥3 个，其后仅空白）。对照 CommonMark closing fence。
function matchFenceClose(line: string, marker: string): boolean {
  const rest: string = line.substring(leadingWhitespaceEnd(line));
  if (rest.length < 3) {
    return false;
  }
  const ch: string = marker.charAt(0);
  let count: number = 0;
  while (count < rest.length && rest.charAt(count) === ch) {
    count++;
  }
  if (count < 3) {
    return false;
  }
  let j: number = count;
  while (j < rest.length && (rest.charAt(j) === ' ' || rest.charAt(j) === '\t')) {
    j++;
  }
  return j === rest.length;
}

function makeMarkdown(text: string): MarkdownSegment {
  const seg: MarkdownSegment = new MarkdownSegment();
  seg.kind = 'markdown';
  seg.text = text;
  return seg;
}

function makeCode(text: string, language: string): MarkdownSegment {
  const seg: MarkdownSegment = new MarkdownSegment();
  seg.kind = 'code';
  seg.text = text;
  seg.language = language;
  return seg;
}

// 主入口：markdown 文本 → 段序列（正文 / 代码交替）。前缀稳定（见上）。
export function splitMarkdown(content: string): MarkdownSegment[] {
  const segments: MarkdownSegment[] = [];
  const lines: string[] = content.length === 0 ? [''] : content.split('\n');
  const n: number = lines.length;
  let i: number = 0;
  let mdStart: number = 0;   // 待 flush 的 markdown 段在 lines 的起始索引（含）

  while (i < n) {
    const open: FenceOpenInfo | null = matchFenceOpen(lines[i]);
    if (open !== null) {
      // flush 待 flush 的正文段 [mdStart, i)
      if (i > mdStart) {
        segments.push(makeMarkdown(lines.slice(mdStart, i).join('\n')));
      }
      // 收集代码体 [i+1, close)
      const codeStart: number = i + 1;
      i = codeStart;
      let closed: boolean = false;
      while (i < n) {
        if (matchFenceClose(lines[i], open.marker)) {
          closed = true;
          break;
        }
        i++;
      }
      const codeEnd: number = i;   // 闭行索引（未闭合则 = n）
      segments.push(makeCode(lines.slice(codeStart, codeEnd).join('\n'), open.lang));
      if (!closed) {
        // 未闭合（流式中）→ 末段 code，后续无正文；跳出（trailing flush 的 mdStart 已越界）
        mdStart = n;
        break;
      }
      i++;          // 跳过闭行
      mdStart = i;  // 闭行之后起新 markdown 段
    } else {
      i++;
    }
  }

  // flush 末尾正文段 [mdStart, n)
  if (n > mdStart) {
    segments.push(makeMarkdown(lines.slice(mdStart, n).join('\n')));
  }

  // 兜底：全程无内容 / 无段 → 单个空正文段（等价旧行为：CJMarkdown 渲染空）
  if (segments.length === 0) {
    segments.push(makeMarkdown(''));
  }
  return segments;
}
