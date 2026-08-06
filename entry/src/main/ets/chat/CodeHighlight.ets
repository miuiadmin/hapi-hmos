// 代码语法高亮纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/lib/shiki.ts（Shiki 细粒度逐 token 染色）；本项目无 Shiki，且
//   markdown_hybrid 无 token 高亮 API —— 故走自包含轻量扫描器，行为确定、可单测、不依赖外部库。
//
// 设计取舍：
//   - 跨行状态：tokenizeCode 整块单遍扫描，携带「块注释 / 三引号串」跨行态
//     （修多行 /* … */、Python """…""" 中间行被当代码高亮的显眼 bug）。模板串 `${…}`
//     跨行嵌套不做（复杂度极高、ROI 低）。tokenizeLine 保留为「单行无 carry」入口（测试用）。
//   - token 分类：comment / string / number / keyword / literal / function / type / punctuation + plain。
//     function=标识符后紧跟 `(` 且非关键字（heuristic）；type=PascalCase 标识符（heuristic）；
//     literal=true/false/null/undefined 等常量（从关键字表分出）；punctuation=()[]{};,.: 暗化。
//     operator(=+-*/<>) 保持 plain（不单独着色，避免满屏花花）。
//   - 关键字集合覆盖高频语言（js/ts/py/go/rs/java·kt/sql/sh/json/yaml）；未注册语言 → 全 plain（零回归）。
//   - 颜色由渲染层（CodeBlock.ets）按 token 类型映射 palette。
//
// 算法：tokenizeCode 逐行 scanLine，scanLine 内索引扫描 + 跨行态；相邻同类型 token 合并以减少 Span。
//   纯函数无副作用、无 replace-fn、无 regex。

// token 类型（渲染层映射颜色）
export type HighlightTokenType = 'comment' | 'string' | 'number' | 'keyword' |
  'literal' | 'function' | 'type' | 'punctuation' | 'plain';

export class HighlightToken {
  type: HighlightTokenType = 'plain';
  text: string = '';
}

// 语言画像：行注释 / 关键字 / 常量 / 块注释对 / 三引号串
export class LanguageProfile {
  lineComments: string[] = [];
  keywords: Set<string> = new Set<string>();
  literals: Set<string> = new Set<string>();
  blockComments: string[][] = [];      // 如 [['/*','*/']]
  tripleQuotes: string[] = [];         // 如 ['"""',"'''"]（Python）
}

// 跨行扫描态（tokenizeCode 逐行传递）
class ScanState {
  inBlock: boolean = false;     // 处于块注释中（等 */
  inTriple: string = '';        // 处于三引号串中（值为定界符 """ / '''，空=不在）
}

function profile(lineComments: string[], keywords: string[], literals: string[],
                 blockComments: string[][], tripleQuotes: string[]): LanguageProfile {
  const p: LanguageProfile = new LanguageProfile();
  p.lineComments = lineComments;
  const ks: Set<string> = new Set<string>();
  for (let i = 0; i < keywords.length; i++) { ks.add(keywords[i]); }
  p.keywords = ks;
  const ls: Set<string> = new Set<string>();
  for (let i = 0; i < literals.length; i++) { ls.add(literals[i]); }
  p.literals = ls;
  p.blockComments = blockComments;
  p.tripleQuotes = tripleQuotes;
  return p;
}

// —— 关键字表（高频子集，够用即可，非穷举；常量 true/false/null 等移至 *_LITERALS）——
const JS_KEYWORDS: string[] = [
  'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'debugger', 'declare', 'default', 'delete', 'do', 'else', 'enum', 'export', 'extends',
  'finally', 'for', 'from', 'function', 'get', 'if', 'implements', 'import', 'in', 'instanceof',
  'interface', 'is', 'let', 'new', 'of', 'private', 'protected', 'public', 'readonly',
  'return', 'set', 'static', 'super', 'switch', 'this', 'throw', 'try', 'type', 'typeof',
  'var', 'void', 'while', 'with', 'yield'
];
const JS_LITERALS: string[] = ['false', 'null', 'true', 'undefined'];
const PY_KEYWORDS: string[] = [
  'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
  'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in',
  'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield'
];
const PY_LITERALS: string[] = ['False', 'None', 'True'];
const GO_KEYWORDS: string[] = [
  'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough', 'for',
  'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range', 'return', 'select',
  'struct', 'switch', 'type', 'var'
];
const GO_LITERALS: string[] = ['true', 'false', 'nil'];
const RS_KEYWORDS: string[] = [
  'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else', 'enum', 'extern',
  'fn', 'for', 'if', 'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub',
  'ref', 'return', 'self', 'Self', 'static', 'struct', 'super', 'trait', 'type', 'unsafe',
  'use', 'where', 'while'
];
const RS_LITERALS: string[] = ['true', 'false'];
const JAVA_KEYWORDS: string[] = [   // java + kotlin 高频共用
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
  'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float',
  'for', 'fun', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
  'new', 'object', 'override', 'package', 'private', 'protected', 'public', 'return', 'short',
  'static', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient',
  'try', 'val', 'var', 'void', 'volatile', 'when', 'while'
];
const JAVA_LITERALS: string[] = ['null', 'true', 'false'];
const SQL_KEYWORDS: string[] = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE',
  'TABLE', 'DROP', 'ALTER', 'ADD', 'PRIMARY', 'KEY', 'NOT', 'DEFAULT', 'AND', 'OR', 'IN',
  'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'AS', 'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT',
  'OFFSET', 'DISTINCT', 'UNION', 'ALL', 'INDEX', 'UNIQUE', 'FOREIGN', 'REFERENCES', 'CASCADE',
  'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create',
  'table', 'drop', 'alter', 'and', 'or', 'not', 'default', 'join', 'inner', 'outer', 'on'
];
const SQL_LITERALS: string[] = ['NULL', 'null'];
const SH_KEYWORDS: string[] = [
  'if', 'then', 'else', 'elif', 'fi', 'for', 'do', 'done', 'while', 'case', 'esac', 'in',
  'function', 'return', 'export', 'local', 'echo', 'exit', 'set', 'unset', 'source', 'cd', 'pwd',
  'printf', 'read'
];
const SH_LITERALS: string[] = ['true', 'false'];
const JSON_KEYWORDS: string[] = [];
const JSON_LITERALS: string[] = ['true', 'false', 'null'];
const YAML_KEYWORDS: string[] = [];
const YAML_LITERALS: string[] = ['true', 'false', 'null', 'yes', 'no'];

// 标点暗化集合（结构符）
const PUNCTUATION: Set<string> = new Set<string>(['(', ')', '[', ']', '{', '}', ';', ',', '.', ':']);

// 语言画像注册表（key = normalizeLanguage 归一结果）
const PROFILES: Map<string, LanguageProfile> = (() => {
  const m: Map<string, LanguageProfile> = new Map<string, LanguageProfile>();
  m.set('js', profile(['//'], JS_KEYWORDS, JS_LITERALS, [['/*', '*/']], []));
  m.set('py', profile(['#'], PY_KEYWORDS, PY_LITERALS, [], ['"""', "'''"]));
  m.set('go', profile(['//'], GO_KEYWORDS, GO_LITERALS, [['/*', '*/']], []));
  m.set('rs', profile(['//'], RS_KEYWORDS, RS_LITERALS, [['/*', '*/']], []));
  m.set('java', profile(['//'], JAVA_KEYWORDS, JAVA_LITERALS, [['/*', '*/']], []));
  m.set('sql', profile(['--'], SQL_KEYWORDS, SQL_LITERALS, [['/*', '*/']], []));
  m.set('sh', profile(['#'], SH_KEYWORDS, SH_LITERALS, [], []));
  m.set('json', profile([], JSON_KEYWORDS, JSON_LITERALS, [], []));
  m.set('yaml', profile(['#'], YAML_KEYWORDS, YAML_LITERALS, [], []));
  return m;
})();

// 语言归一：扩展名 / alias / 'language-xxx' → profile key；未注册 → 'text'（全 plain）。
export function normalizeLanguage(raw: string): string {
  if (raw === undefined || raw === null) { return 'text'; }
  let s: string = raw;
  if (s.startsWith('language-')) { s = s.substring('language-'.length); }
  s = s.toLowerCase().trim();
  if (s === '' || s === 'text' || s === 'plaintext' || s === 'txt' || s === 'unknown') { return 'text'; }
  // 直接命中 profile key
  if (s === 'js' || s === 'py' || s === 'go' || s === 'rs' || s === 'java' ||
      s === 'sql' || s === 'sh' || s === 'json' || s === 'yaml') {
    return s;
  }
  // alias / 扩展名映射
  if (s === 'ts' || s === 'tsx' || s === 'mts' || s === 'cts' ||
      s === 'javascript' || s === 'mjs' || s === 'cjs' || s === 'jsx') { return 'js'; }
  if (s === 'python' || s === 'py3') { return 'py'; }
  if (s === 'golang') { return 'go'; }
  if (s === 'rust') { return 'rs'; }
  if (s === 'kt' || s === 'kotlin' || s === 'scala' || s === 'csharp' || s === 'cs' ||
      s === 'c' || s === 'cpp' || s === 'cc' || s === 'cxx' || s === 'h' || s === 'hpp') { return 'java'; }
  if (s === 'pgsql' || s === 'mysql' || s === 'postgres') { return 'sql'; }
  if (s === 'bash' || s === 'zsh' || s === 'shell' || s === 'shellscript') { return 'sh'; }
  if (s === 'yml') { return 'yaml'; }
  return 'text';
}

function getProfile(language: string): LanguageProfile | null {
  const key: string = normalizeLanguage(language);
  const p: LanguageProfile | undefined = PROFILES.get(key);
  return p === undefined ? null : p;
}

// 标识符首字符 [A-Za-z_$]
function isIdentStart(ch: string): boolean {
  const c: number = ch.charCodeAt(0);
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95 || c === 36;   // A-Z a-z _ $
}
// 标识符续字符 [A-Za-z0-9_$]
function isIdentPart(ch: string): boolean {
  const c: number = ch.charCodeAt(0);
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 95 || c === 36;
}
// 数字字符 [0-9a-fA-FxXoObB._]（含十六进制 / 小数 / 下划线分隔；上限 S 简化）
function isNumberPart(ch: string): boolean {
  const c: number = ch.charCodeAt(0);
  // 0-9 a-f A-F
  if ((c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)) { return true; }
  if (ch === '.' || ch === '_') { return true; }
  // x X o O b B 进制前缀
  if (ch === 'x' || ch === 'X' || ch === 'o' || ch === 'O' || ch === 'b' || ch === 'B') { return true; }
  return false;
}
// PascalCase 判定（首字符 A-Z）—— type heuristic
function isPascalCase(ident: string): boolean {
  if (ident.length === 0) { return false; }
  const c: number = ident.charCodeAt(0);
  return c >= 65 && c <= 90;
}
function isPunctuation(ch: string): boolean {
  return PUNCTUATION.has(ch);
}
// 标识符后（跳过空白）是否紧跟 '(' —— function-call heuristic
function isFunctionCall(line: string, afterIdent: number): boolean {
  const n: number = line.length;
  let j: number = afterIdent;
  while (j < n && (line.charAt(j) === ' ' || line.charAt(j) === '\t')) { j++; }
  return j < n && line.charAt(j) === '(';
}

// 行注释匹配：position 处是否以某 lineComment 前缀开头
function matchLineComment(line: string, i: number, markers: string[]): boolean {
  for (let k = 0; k < markers.length; k++) {
    if (line.startsWith(markers[k], i)) { return true; }
  }
  return false;
}
// 块注释开匹配：position 处命中某 blockComment 对的开串 → 返回该对 [open, close]，否则 null
function matchBlockOpenPair(line: string, i: number, p: LanguageProfile): string[] | null {
  for (let k = 0; k < p.blockComments.length; k++) {
    const pair: string[] = p.blockComments[k];
    if (line.startsWith(pair[0], i)) { return pair; }
  }
  return null;
}
// 三引号匹配：position 处命中某 tripleQuote 定界符 → 返回该定界符，否则 ''
function matchTripleQuote(line: string, i: number, p: LanguageProfile): string {
  for (let k = 0; k < p.tripleQuotes.length; k++) {
    const tq: string = p.tripleQuotes[k];
    if (line.startsWith(tq, i)) { return tq; }
  }
  return '';
}

// 字符串匹配：position 处若为引号（" ' `），消费到「未转义同引号」为止；返回含引号整串，非串返 ''
function matchString(line: string, i: number): string {
  const quote: string = line.charAt(i);
  if (quote !== '"' && quote !== '\'' && quote !== '`') { return ''; }
  let j: number = i + 1;
  const n: number = line.length;
  while (j < n) {
    const ch: string = line.charAt(j);
    if (ch === '\\') { j += 2; continue; }   // 转义跳过下一字符
    if (ch === quote) { return line.substring(i, j + 1); }
    j++;
  }
  return line.substring(i);   // 未闭合（行尾）→ 当串消费到行末（行内扫描，无跨行态）
}

// 数字匹配：position 处若为数字，消费连续 number 片段
function matchNumber(line: string, i: number): string {
  const c: number = line.charAt(i).charCodeAt(0);
  if (c < 48 || c > 57) { return ''; }   // 必须以 0-9 起头
  let j: number = i + 1;
  const n: number = line.length;
  while (j < n && isNumberPart(line.charAt(j))) { j++; }
  return line.substring(i, j);
}

// 标识符匹配：position 处若为 ident 起始，消费连续标识符
function matchIdentifier(line: string, i: number): string {
  if (!isIdentStart(line.charAt(i))) { return ''; }
  let j: number = i + 1;
  const n: number = line.length;
  while (j < n && isIdentPart(line.charAt(j))) { j++; }
  return line.substring(i, j);
}

// 合并相邻同类型 token（减少渲染 Span 数量；plain 与 plain、punct 与 punct 等皆合并）
function mergeAdjacent(tokens: HighlightToken[]): HighlightToken[] {
  const out: HighlightToken[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const tk: HighlightToken = tokens[i];
    if (out.length > 0) {
      const last: HighlightToken = out[out.length - 1];
      if (last.type === tk.type) {
        last.text += tk.text;
        continue;
      }
    }
    const cp: HighlightToken = new HighlightToken();
    cp.type = tk.type;
    cp.text = tk.text;
    out.push(cp);
  }
  return out;
}

function makePlain(text: string): HighlightToken {
  const t: HighlightToken = new HighlightToken();
  t.type = 'plain';
  t.text = text;
  return t;
}
function makeToken(type: HighlightTokenType, text: string): HighlightToken {
  const t: HighlightToken = new HighlightToken();
  t.type = type;
  t.text = text;
  return t;
}

// 单行扫描（携带跨行态，由 tokenizeCode 逐行调用 / tokenizeLine 以全新态调用）。
//   续态优先：上一行未闭合的块注释 / 三引号串 → 本行先消费到闭合符（可能整行）。
//   正常扫描：块注释开（跨行）→ 三引号开（跨行）→ 行注释 → 单行串 → 数字 → 标识符(关键字/常量/function/type) → 标点 → 单字符 plain。
function scanLine(line: string, p: LanguageProfile | null, state: ScanState): HighlightToken[] {
  if (line.length === 0) { return [makePlain(' ')]; }   // 空行占位空格，维持行高
  if (p === null) { return [makePlain(line)]; }          // text / 未注册 → 整行 plain（零回归：不伪染串/数字/标点）
  const raw: HighlightToken[] = [];
  const n: number = line.length;
  let i: number = 0;

  // —— 续态：块注释 ——
  if (state.inBlock) {
    const closeIdx: number = line.indexOf('*/', 0);
    if (closeIdx < 0) {
      raw.push(makeToken('comment', line));   // 整行仍处块注释
      return mergeAdjacent(raw);
    }
    raw.push(makeToken('comment', line.substring(0, closeIdx + 2)));
    state.inBlock = false;
    i = closeIdx + 2;
  } else if (state.inTriple !== '') {
    // —— 续态：三引号串 ——
    const tq: string = state.inTriple;
    const closeIdx: number = line.indexOf(tq, 0);
    if (closeIdx < 0) {
      raw.push(makeToken('string', line));
      return mergeAdjacent(raw);
    }
    raw.push(makeToken('string', line.substring(0, closeIdx + 3)));
    state.inTriple = '';
    i = closeIdx + 3;
  }

  // —— 正常扫描本行剩余 [i, n) ——
  while (i < n) {
    // 1. 块注释开（profile 有 blockComments）
    if (p !== null) {
      const pair: string[] | null = matchBlockOpenPair(line, i, p);
      if (pair !== null) {
        const close: string = pair[1];
        const closeIdx: number = line.indexOf(close, i + pair[0].length);
        if (closeIdx < 0) {
          raw.push(makeToken('comment', line.substring(i)));   // 跨行：本行剩余全 comment
          state.inBlock = true;
          return mergeAdjacent(raw);
        }
        raw.push(makeToken('comment', line.substring(i, closeIdx + close.length)));
        i = closeIdx + close.length;
        continue;
      }
    }
    // 2. 三引号串开（profile 有 tripleQuotes；须在单行串前判，避免被 matchString 吃掉首引号）
    if (p !== null) {
      const tq: string = matchTripleQuote(line, i, p);
      if (tq !== '') {
        const closeIdx: number = line.indexOf(tq, i + 3);
        if (closeIdx < 0) {
          raw.push(makeToken('string', line.substring(i)));   // 跨行
          state.inTriple = tq;
          return mergeAdjacent(raw);
        }
        raw.push(makeToken('string', line.substring(i, closeIdx + 3)));
        i = closeIdx + 3;
        continue;
      }
    }
    // 3. 行注释（命中即行尾全 comment）
    if (p !== null && matchLineComment(line, i, p.lineComments)) {
      raw.push(makeToken('comment', line.substring(i)));
      break;
    }
    // 4. 单行字符串（" ' `）
    const str: string = matchString(line, i);
    if (str !== '') { raw.push(makeToken('string', str)); i += str.length; continue; }
    // 5. 数字
    const num: string = matchNumber(line, i);
    if (num !== '') { raw.push(makeToken('number', num)); i += num.length; continue; }
    // 6. 标识符 → 关键字 / 常量 / function / type / plain
    const ident: string = matchIdentifier(line, i);
    if (ident !== '') {
      let tt: HighlightTokenType = 'plain';
      if (p !== null) {
        if (p.keywords.has(ident)) { tt = 'keyword'; }
        else if (p.literals.has(ident)) { tt = 'literal'; }
        else if (isFunctionCall(line, i + ident.length)) { tt = 'function'; }
        else if (isPascalCase(ident)) { tt = 'type'; }
      }
      raw.push(makeToken(tt, ident));
      i += ident.length;
      continue;
    }
    // 7. 标点（暗化）
    if (p !== null && isPunctuation(line.charAt(i))) {
      raw.push(makeToken('punctuation', line.charAt(i)));
      i++;
      continue;
    }
    // 8. 单字符 plain（运算符 / 空白等）
    raw.push(makeToken('plain', line.charAt(i)));
    i++;
  }
  return mergeAdjacent(raw);
}

// 单行入口（无跨行 carry；测试 / 兼容旧调用）。
export function tokenizeLine(line: string, language: string): HighlightToken[] {
  const p: LanguageProfile | null = getProfile(language);
  const state: ScanState = new ScanState();
  return scanLine(line, p, state);
}

// 整块入口（携带跨行态：块注释 / 三引号串）。返回「每行 token 数组」，供 CodeBlock 整块一次性高亮。
export function tokenizeCode(code: string, language: string): HighlightToken[][] {
  const p: LanguageProfile | null = getProfile(language);
  let lines: string[];
  if (code.length === 0) {
    lines = [''];
  } else {
    lines = code.split('\n');
    if (lines.length > 1 && lines[lines.length - 1] === '') {
      lines.splice(lines.length - 1, 1);
    }
  }
  const state: ScanState = new ScanState();
  const out: HighlightToken[][] = [];
  for (let li = 0; li < lines.length; li++) {
    out.push(scanLine(lines[li], p, state));
  }
  return out;
}
