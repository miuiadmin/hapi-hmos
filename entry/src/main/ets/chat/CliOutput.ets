// CliOutput —— CLI 命令输出块的检测 / 合并 / 格式化（纯层，无 @kit，可 LocalUnit 测）
// 对照 web/src/chat/reducerCliOutput.ts（isCliOutputText/mergeCliOutputBlocks）
//   + web/src/components/CliOutputBlock.tsx（buildCliOutput/extractCommandName）
//   + web/src/components/assistant-ui/markdown-utils.ts（stripAnsiAndControls）
//
// 用途：
//   - Reducer.ets：isCliOutputText(text, sentFrom) 严格 AND 门控 → 产出 cli-output ChatBlock；
//     全部块构建后 mergeCliOutputBlocks 把相邻 command-name 块 + 紧随 stdout 块合并。
//   - CliOutputCard：parseCliSegments/buildCliOutput 格式化为带标签单串喂 CodeBlock；
//     extractCommandName 取命令名作卡片标题。
//
// ArkTS 限制：String.replace(regexp, fn)/反向引用不稳 → 配对解析用手写扫描器；
//   检测/取命令名用正则字面量 + .test()/.exec()（GitParsers 先例，capture group 可用）。
//   控制字符（ESC/BEL 等）用 String.fromCharCode 在运行时构造，源码不出现 \u00XX 转义
//   也不内嵌裸控制字节（避工具传输吞字节）。

import { ChatBlock } from './ChatBlock';
import { t } from '../i18n/Translate';

// —— 标签检测（无反向引用；正则字面量 + .test()）——
const CLI_TAG_CHECK_REGEX: RegExp = /<(?:local-command-[a-z-]+|command-(?:name|message|args))>/i;
const COMMAND_NAME_OPEN_REGEX: RegExp = /<command-name>/i;
const LOCAL_STDOUT_OPEN_REGEX: RegExp = /<local-command-stdout>/i;

// 提取 <command-name>...</command-name> 内容（非贪婪，[\s\S] 跨行；.exec() 取 group[1]）
const COMMAND_NAME_CONTENT_REGEX: RegExp = /<command-name>([\s\S]*?)<\/command-name>/i;

// —— ANSI / 控制字符剥离（逐字移植 stripAnsiAndControls）——
//   控制字符运行时用 fromCharCode 构造（源码零 \u00XX、零裸控制字节）。
function cc(n: number): string { return String.fromCharCode(n); }
const ESC: string = cc(0x1b);   // ANSI 转义引导符
const CSI: string = cc(0x9b);   // 控制序列引导符（8-bit CSI）
const BEL: string = cc(0x07);   // 响铃（OSC 终止符之一）

// ANSI CSI 序列（颜色/光标等）：对照 ANSI_REGEX
const ANSI_REGEX: RegExp = new RegExp(
  '[' + ESC + CSI + '][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]', 'g');
// ANSI OSC 序列（标题等）：对照 ANSI_OSC_REGEX = /<ESC>][^<BEL>]*(?:<BEL>|<ESC>\)/g
const ANSI_OSC_REGEX: RegExp = new RegExp(
  ESC + '][^' + BEL + ']*(?:' + BEL + '|' + ESC + '\\\\)', 'g');
// 其它控制字符（对照 CONTROL_CHARS_REGEX = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g）
const CONTROL_CHARS_CLASS: string =
  '[' + cc(0) + '-' + cc(8) + cc(11) + cc(12) + cc(14) + '-' + cc(31) + cc(127) + ']';
const CONTROL_CHARS_REGEX: RegExp = new RegExp(CONTROL_CHARS_CLASS, 'g');
const CRLF_REGEX: RegExp = /\r\n?/g;
const BR_REGEX: RegExp = /<br\s*\/?>/gi;

function stripAnsiAndControls(text: string): string {
  const normalized: string = text.replace(CRLF_REGEX, '\n');
  const withoutOsc: string = normalized.replace(ANSI_OSC_REGEX, '');
  const withoutAnsi: string = withoutOsc.replace(ANSI_REGEX, '');
  return withoutAnsi.replace(CONTROL_CHARS_REGEX, '');
}

function normalizeCliText(text: string): string {
  return stripAnsiAndControls(text).replace(BR_REGEX, '\n');
}

// —— 字符串小工具（手写，避 trimEnd/endsWith 等 ArkTS 边缘 API）——
function rtrim(s: string): string {
  let end: number = s.length;
  while (end > 0) {
    const ch: number = s.charCodeAt(end - 1);
    if (ch === 32 || ch === 9 || ch === 10 || ch === 13) { end--; } else { break; }
  }
  return s.substring(0, end);
}

function startsWith(s: string, prefix: string): boolean {
  if (s.length < prefix.length) { return false; }
  for (let i = 0; i < prefix.length; i++) {
    if (s.charAt(i) !== prefix.charAt(i)) { return false; }
  }
  return true;
}

function endsWith(s: string, suffix: string): boolean {
  if (s.length < suffix.length) { return false; }
  const off: number = s.length - suffix.length;
  for (let i = 0; i < suffix.length; i++) {
    if (s.charAt(off + i) !== suffix.charAt(i)) { return false; }
  }
  return true;
}

function dashesToSpaces(s: string): string {
  let out: string = '';
  for (let i = 0; i < s.length; i++) {
    const ch: string = s.charAt(i);
    out += ch === '-' ? ' ' : ch;
  }
  return out;
}

// —— 检测门控 ——
export function hasCliOutputTags(text: string): boolean {
  return CLI_TAG_CHECK_REGEX.test(text);
}

export function hasCommandNameTag(text: string): boolean {
  return COMMAND_NAME_OPEN_REGEX.test(text);
}

export function hasLocalCommandStdoutTag(text: string): boolean {
  return LOCAL_STDOUT_OPEN_REGEX.test(text);
}

// 严格 AND：sentFrom==='cli' && hasCliTags（对照上游 isCliOutputText）
export function isCliOutputText(text: string, sentFrom: string): boolean {
  return sentFrom === 'cli' && hasCliOutputTags(text);
}

// —— 手写扫描器：在 ltPos('<') 处解析 <tagName> ——
function isTagNameChar(ch: string): boolean {
  const c: number = ch.charCodeAt(0);
  return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c === 45; // a-z A-Z -
}

function isKnownTagName(lower: string): boolean {
  if (lower === 'command-name' || lower === 'command-message' || lower === 'command-args' ||
    lower === 'local-command-stdout' || lower === 'local-command-stderr') {
    return true;
  }
  // 通用 local-command-*（如 local-command-duration/cwd）——前缀校验
  return lower.length > 'local-command-'.length && startsWith(lower, 'local-command-');
}

class TagOpen {
  tagStart: number = 0;       // '<' 位置
  tagName: string = '';       // 小写标签名
  contentStart: number = 0;   // '>' 后位置
}

// 在 ltPos('<') 处解析 <tagName>；命中已知标签返回 TagOpen，否则 null
function tryParseTagOpen(text: string, ltPos: number): TagOpen | null {
  let j: number = ltPos + 1;
  let name: string = '';
  while (j < text.length) {
    const ch: string = text.charAt(j);
    if (isTagNameChar(ch)) { name += ch; j++; } else { break; }
  }
  if (j >= text.length || text.charAt(j) !== '>') { return null; }
  const lower: string = name.toLowerCase();
  if (!isKnownTagName(lower)) { return null; }
  const r: TagOpen = new TagOpen();
  r.tagStart = ltPos;
  r.tagName = lower;
  r.contentStart = j + 1;
  return r;
}

// 从 from 起找下一个已知开标签
function findNextTagOpen(text: string, from: number): TagOpen | null {
  let i: number = from;
  while (i < text.length) {
    if (text.charCodeAt(i) === 60) { // '<'
      const parsed: TagOpen | null = tryParseTagOpen(text, i);
      if (parsed !== null) { return parsed; }
    }
    i++;
  }
  return null;
}

// —— 解析分段（结构化，无 i18n，便于单测）——
//   isTag=true 段为已知标签配对内容；isTag=false 段为标签间纯文本（已 rtrim、非空）。
export class CliSegment {
  isTag: boolean = false;
  tag: string = '';       // isTag 时小写标签名
  content: string = '';   // 归一化（stripAnsi+br）后内容
}

export function parseCliSegments(text: string): CliSegment[] {
  const segments: CliSegment[] = [];
  let pos: number = 0;
  let lastTail: number = 0;
  while (pos < text.length) {
    const open: TagOpen | null = findNextTagOpen(text, pos);
    if (open === null) { break; }
    const closeTag: string = '</' + open.tagName + '>';
    const closeIdx: number = text.indexOf(closeTag, open.contentStart);
    if (closeIdx === -1) {
      // 无闭合：'<' 当普通字符，跳过避死循环
      pos = open.tagStart + 1;
      continue;
    }
    if (open.tagStart > lastTail) {
      const before: string = rtrim(normalizeCliText(text.substring(lastTail, open.tagStart)));
      if (before.trim().length > 0) {
        const seg: CliSegment = new CliSegment();
        seg.isTag = false;
        seg.content = before;
        segments.push(seg);
      }
    }
    const content: string = normalizeCliText(text.substring(open.contentStart, closeIdx));
    const seg: CliSegment = new CliSegment();
    seg.isTag = true;
    seg.tag = open.tagName;
    seg.content = content;
    segments.push(seg);
    const closeEnd: number = closeIdx + closeTag.length;
    lastTail = closeEnd;
    pos = closeEnd;
  }
  if (lastTail < text.length) {
    const tail: string = rtrim(normalizeCliText(text.substring(lastTail)));
    if (tail.trim().length > 0) {
      const seg: CliSegment = new CliSegment();
      seg.isTag = false;
      seg.content = tail;
      segments.push(seg);
    }
  }
  return segments;
}

// 标签 → 显示标签（i18n key）；未知 local-command-* → 'xxx yyy'（'-'→' '）
function labelKeyForTag(tag: string): string {
  if (tag === 'command-name') { return 'terminal.commandName'; }
  if (tag === 'command-message') { return 'terminal.commandMessage'; }
  if (tag === 'command-args') { return 'terminal.commandArgs'; }
  if (tag === 'local-command-stdout') { return 'terminal.stdout'; }
  if (tag === 'local-command-stderr') { return 'terminal.stderr'; }
  return dashesToSpaces(tag);
}

// 格式化为带标签的单串（对照 buildCliOutput）：每段 "标签:\n内容" 或纯文本，段间空行。
//   无任何配对段时回落 normalizeCliText(text)。CliOutputCard 喂 CodeBlock（language=shellscript）。
export function buildCliOutput(text: string): string {
  const segments: CliSegment[] = parseCliSegments(text);
  if (segments.length === 0) { return normalizeCliText(text); }
  const parts: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const s: CliSegment = segments[i];
    if (s.isTag) {
      const label: string = t(labelKeyForTag(s.tag));
      parts.push(s.content.length > 0 ? label + ':\n' + s.content : label + ':');
    } else {
      parts.push(s.content);
    }
  }
  return parts.join('\n\n');
}

// 取命令名作卡片标题（对照 extractCommandName）：<command-name> 首个非空行；无则 ''。
export function extractCommandName(text: string): string {
  const m: RegExpExecArray | null = COMMAND_NAME_CONTENT_REGEX.exec(text);
  if (m === null || m.length < 2) { return ''; }
  const normalized: string = normalizeCliText(m[1]);
  // 首个非空行
  let start: number = 0;
  for (let i = 0; i <= normalized.length; i++) {
    if (i === normalized.length || normalized.charCodeAt(i) === 10) { // '\n'
      const line: string = normalized.substring(start, i);
      const trimmed: string = line.trim();
      if (trimmed.length > 0) { return trimmed; }
      start = i + 1;
    }
  }
  return '';
}

// —— 合并相邻 cli-output 块（对照 mergeCliOutputBlocks）——
//   prev 与 block 均 cli-output 且 source 相同，prev 有 command-name 无 stdout，block 有 stdout
//   → prev.text += 分隔符 + block.text（其余元数据取 prev，因 ChatBlock 仅载 text/source/createdAt）。
export function mergeCliOutputBlocks(blocks: ChatBlock[]): ChatBlock[] {
  const merged: ChatBlock[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const block: ChatBlock = blocks[i];
    if (block.kind !== 'cli-output') {
      merged.push(block);
      continue;
    }
    const prevIdx: number = merged.length - 1;
    if (prevIdx >= 0) {
      const prev: ChatBlock = merged[prevIdx];
      if (prev.kind === 'cli-output' && prev.source === block.source &&
        hasCommandNameTag(prev.text) && !hasLocalCommandStdoutTag(prev.text) &&
        hasLocalCommandStdoutTag(block.text)) {
        const sep: string = (endsWith(prev.text, '\n') || startsWith(block.text, '\n')) ? '' : '\n';
        prev.text = prev.text + sep + block.text;
        continue;
      }
    }
    merged.push(block);
  }
  return merged;
}
