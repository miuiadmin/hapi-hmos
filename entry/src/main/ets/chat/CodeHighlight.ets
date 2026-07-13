// 代码语法高亮纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/lib/shiki.ts（Shiki 细粒度逐 token 染色）；本项目无 Shiki，且
//   markdown_hybrid 是否自带 prism 高亮未经真机证实（chatcube 仅依赖 markdown_hybrid，
//   其代码只 setCodeBlockTextColor 单色）—— 故走自包含轻量扫描器，行为确定、可单测、
//   不依赖外部库高亮能力。
//
// 设计取舍（S 规模）：
//   - 单行无状态：不跨行追踪 /* 块注释 */ / 模板字符串续行。多数目标语言以行注释为主，
//     多行块注释仅 C 系（ts/js 也常用 //），单行扫描覆盖 ~90% 可见高亮价值。
//   - 关键字集合覆盖高频语言（js/ts/py/go/rs/java·kt/sql/sh/json/yaml）；
//     未注册语言 → 全 plain（与现状一致，无回归）。
//   - 四类 token：comment / string / number / keyword + plain 兜底。
//   - 颜色由渲染层（CodeBlock.ets）按 token 类型映射既有 palette（不新增调色板项）：
//       keyword=primary / string=success / number=warning / comment=codeMuted / plain=codeText。
//
// 算法：逐行索引扫描，每个位置依次试「行注释 → 字符串 → 数字 → 标识符(关键字) → 单字符 plain」，
//   命中即消费对应片段继续；相邻 plain 合并以减少 Span 数量。纯函数无副作用、无 replace-fn。

// token 类型（渲染层映射颜色）
export type HighlightTokenType = 'comment' | 'string' | 'number' | 'keyword' | 'plain';

export class HighlightToken {
  type: HighlightTokenType = 'plain';
  text: string = '';
}

// 语言画像：行注释前缀 + 关键字集合
export class LanguageProfile {
  lineComments: string[] = [];
  keywords: Set<string> = new Set<string>();
}

function profile(lineComments: string[], keywords: string[]): LanguageProfile {
  const p: LanguageProfile = new LanguageProfile();
  p.lineComments = lineComments;
  const s: Set<string> = new Set<string>();
  for (let i = 0; i < keywords.length; i++) { s.add(keywords[i]); }
  p.keywords = s;
  return p;
}

// —— 关键字表（高频子集，够用即可，非穷举）——
const JS_KEYWORDS: string[] = [
  'abstract', 'as', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'debugger', 'declare', 'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'false',
  'finally', 'for', 'from', 'function', 'get', 'if', 'implements', 'import', 'in', 'instanceof',
  'interface', 'is', 'let', 'new', 'null', 'of', 'private', 'protected', 'public', 'readonly',
  'return', 'set', 'static', 'super', 'switch', 'this', 'throw', 'true', 'try', 'type', 'typeof',
  'undefined', 'var', 'void', 'while', 'with', 'yield'
];
const PY_KEYWORDS: string[] = [
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
  'def', 'del', 'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in',
  'is', 'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield'
];
const GO_KEYWORDS: string[] = [
  'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough', 'for',
  'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range', 'return', 'select',
  'struct', 'switch', 'type', 'var', 'true', 'false', 'nil'
];
const RS_KEYWORDS: string[] = [
  'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else', 'enum', 'extern',
  'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub',
  'ref', 'return', 'self', 'Self', 'static', 'struct', 'super', 'trait', 'true', 'type', 'unsafe',
  'use', 'where', 'while'
];
const JAVA_KEYWORDS: string[] = [   // java + kotlin 高频共用
  'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
  'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float',
  'for', 'fun', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
  'new', 'null', 'object', 'override', 'package', 'private', 'protected', 'public', 'return', 'short',
  'static', 'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'true',
  'false', 'try', 'val', 'var', 'void', 'volatile', 'when', 'while'
];
const SQL_KEYWORDS: string[] = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE', 'CREATE',
  'TABLE', 'DROP', 'ALTER', 'ADD', 'PRIMARY', 'KEY', 'NOT', 'NULL', 'DEFAULT', 'AND', 'OR', 'IN',
  'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'AS', 'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT',
  'OFFSET', 'DISTINCT', 'UNION', 'ALL', 'INDEX', 'UNIQUE', 'FOREIGN', 'REFERENCES', 'CASCADE',
  'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create',
  'table', 'drop', 'alter', 'and', 'or', 'null', 'not', 'default', 'join', 'inner', 'outer', 'on'
];
const SH_KEYWORDS: string[] = [
  'if', 'then', 'else', 'elif', 'fi', 'for', 'do', 'done', 'while', 'case', 'esac', 'in',
  'function', 'return', 'export', 'local', 'echo', 'exit', 'set', 'unset', 'source', 'cd', 'pwd',
  'echo', 'printf', 'read', 'true', 'false'
];

// 语言画像注册表（key = normalizeLanguage 归一结果）
const PROFILES: Map<string, LanguageProfile> = (() => {
  const m: Map<string, LanguageProfile> = new Map<string, LanguageProfile>();
  m.set('js', profile(['//'], JS_KEYWORDS));
  m.set('py', profile(['#'], PY_KEYWORDS));
  m.set('go', profile(['//'], GO_KEYWORDS));
  m.set('rs', profile(['//'], RS_KEYWORDS));
  m.set('java', profile(['//'], JAVA_KEYWORDS));
  m.set('sql', profile(['--'], SQL_KEYWORDS));
  m.set('sh', profile(['#'], SH_KEYWORDS));
  m.set('json', profile([], ['true', 'false', 'null']));
  m.set('yaml', profile(['#'], ['true', 'false', 'null', 'yes', 'no']));
  return m;
})();

// 语言归一：扩展名 / alias / 'language-xxx' → profile key；未注册 → 'text'（全 plain）。
//   对照上游 langAlias + resolveLanguage；差异：本项目 key 面向自有关键字表，非 Shiki 语言名。
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
      s === 'javascript' || s === 'js' || s === 'mjs' || s === 'cjs' || s === 'jsx') { return 'js'; }
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

// 行注释匹配：position 处是否以某 lineComment 前缀开头
function matchLineComment(line: string, i: number, markers: string[]): boolean {
  for (let k = 0; k < markers.length; k++) {
    if (line.startsWith(markers[k], i)) { return true; }
  }
  return false;
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

// 合并相邻 plain token（减少渲染 Span 数量）
function mergeAdjacentPlain(tokens: HighlightToken[]): HighlightToken[] {
  const out: HighlightToken[] = [];
  let buf: string = '';
  for (let i = 0; i < tokens.length; i++) {
    const tk: HighlightToken = tokens[i];
    if (tk.type === 'plain') {
      buf += tk.text;
    } else {
      if (buf !== '') { out.push(makePlain(buf)); buf = ''; }
      out.push(tk);
    }
  }
  if (buf !== '') { out.push(makePlain(buf)); }
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

// 主入口：单行 → token 序列。
//   comment 命中即消费至行尾（行注释）；string/number/identifier 按起始字符判定；
//   标识符查关键字表 → keyword / plain；其余字符逐字 plain（合并）。
export function tokenizeLine(line: string, language: string): HighlightToken[] {
  if (line === '') { return [makePlain(' ')]; }   // 空行保留一个空格占位，维持行高
  const p: LanguageProfile | null = getProfile(language);
  const raw: HighlightToken[] = [];
  let i: number = 0;
  const n: number = line.length;
  while (i < n) {
    // 1. 行注释（命中即行尾全 comment）
    if (p !== null && matchLineComment(line, i, p.lineComments)) {
      raw.push(makeToken('comment', line.substring(i)));
      break;
    }
    // 2. 字符串
    const str: string = matchString(line, i);
    if (str !== '') { raw.push(makeToken('string', str)); i += str.length; continue; }
    // 3. 数字
    const num: string = matchNumber(line, i);
    if (num !== '') { raw.push(makeToken('number', num)); i += num.length; continue; }
    // 4. 标识符 / 关键字
    const ident: string = matchIdentifier(line, i);
    if (ident !== '') {
      const isKw: boolean = p !== null && p.keywords.has(ident);
      raw.push(makeToken(isKw ? 'keyword' : 'plain', ident));
      i += ident.length;
      continue;
    }
    // 5. 单字符 plain
    raw.push(makeToken('plain', line.charAt(i)));
    i++;
  }
  return mergeAdjacentPlain(raw);
}
