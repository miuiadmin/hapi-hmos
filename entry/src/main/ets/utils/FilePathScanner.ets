// FilePathScanner —— 把 Markdown 正文里的裸文件路径包成 hapi-file: 链接（纯层，零 @kit，可 LocalUnit 测）。
//
// 对照上游 web/src/lib/remark-file-path-links.ts（remark MDAST 插件 remarkFilePathLinks）。上游在 MDAST
// 文本节点上跑 PATH_PATTERN 正则 + shouldLinkPath 白名单，把 web/src/router.tsx:42 之类裸路径转
// [displayPath](hapi-file:encodeURIComponent(filePath))，点开 FileViewer。
//
// 鸿蒙 CJMarkdown 无 MDAST hook（chat/LinkSchemes.ets 已断言），setIsLinkifyPlugin 只认 scheme://
// → 唯一出路是【喂 CJMarkdown 前文本预处理】：把裸路径包成标准 [text](hapi-file:enc) 语法，
//   再在 setLinkCallback 拦截 hapi-file: 前缀（见 MarkdownText.ets）。
//
// ArkTS 禁 regex/matchAll/replace-fn/反向引用/s-flag → 全程手写字符扫描 + 状态机，逐位复刻上游语义。
//   关键复刻点：
//     1. PATH_PATTERN 两择：含 `/` 的 dir/.../name.ext[:line[:col]]（懒 middle→首个 .ext）；
//        裸 name.ext[:line[:col]]（贪心 nameRun→最右 dot）。
//     2. previousChar 上下文守卫：token 前一字符 ∈ `:`/`/`/`\`/`.` → 弃（上游 line 91-94）。
//     3. splitTrailingPunctuation：剥尾标点 . , ; : ! ? + 未配对 ) + ]/}。
//     4. stripLineSuffix：剥尾 :line[:col]（target 不含行号，display 含）。
//     5. shouldLinkPath：:// 弃；abs/~/../.../Win 盘符弃；否则 41 扩展名白名单。
//   豁免区（上游靠 MDAST 节点类型天然豁免 code/link，这里手写状态机复刻）：
//     - 围栏代码块（``` / ~~~ 行首 toggle，含 ≤3 空格缩进）→ 整行 verbatim；
//     - 行内代码（`` ` `` 配对 run）→ verbatim；
//     - 链接/图片 span（[...] + 可选 (...)）→ 整段 verbatim（安全方向：宁可少链）。
//   幂等：无命中返回原串引用（免 CJMarkdown 无谓重渲染）。

// hapi-file: 链接前缀（与上游 FILE_PATH_HREF_PREFIX 一致）
const FILE_PATH_HREF_PREFIX: string = 'hapi-file:';

// 上游 COMMON_FILE_EXTENSIONS 白名单（41 项）—— string[] + indexOf（ArkTS 无 Set 字面便捷性偏好数组）
const COMMON_FILE_EXTENSIONS: string[] = [
  'avif', 'bmp', 'c', 'cjs', 'cpp', 'css', 'gif', 'go', 'h', 'hpp', 'html', 'ico', 'java',
  'jpeg', 'jpg', 'js', 'json', 'jsx', 'kt', 'lock', 'md', 'mdx', 'mjs', 'png', 'py', 'rs',
  'scss', 'sh', 'sql', 'svg', 'swift', 'toml', 'ts', 'tsx', 'txt', 'vue', 'webp', 'xml',
  'yaml', 'yml', 'zsh'
];

// 尾标点集合（上游 TRAILING_PUNCTUATION）
const TRAILING_PUNCT_CHARS: string = '.,;:!?';

// ===== 字符判定（手写，无 regex）=====

function isAlnum(ch: string): boolean {
  return isAlpha(ch) || isDigit(ch);
}

function isAlpha(ch: string): boolean {
  return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

// PATH_PATTERN 的 name 字符类 [A-Za-z0-9_.-]
function isNameChar(ch: string): boolean {
  return isAlnum(ch) || ch === '_' || ch === '.' || ch === '-';
}

// middle 类 [^\s`"'<>] 的反例：空白或 `` ` " ' < >  任一即停（上游 `[^\s\`"\'<>]`）
function isMiddleStop(ch: string): boolean {
  return isWhitespace(ch) || ch === '`' || ch === '"' || ch === '\'' || ch === '<' || ch === '>';
}

function isWhitespace(ch: string): boolean {
  return ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' || ch === '\f' || ch === '\v';
}

// ===== 移植上游 helper（均手写）=====

// splitTrailingPunctuation：从尾剥 . , ; : ! ? + 未配对 ) + ]/}（上游 line 34-59）
class SplitResult {
  path: string = '';
  trailing: string = '';
}

function splitTrailingPunctuation(value: string): SplitResult {
  const res: SplitResult = new SplitResult();
  let path: string = value;
  let trailing: string = '';
  while (path.length > 0) {
    const last: string = path.charAt(path.length - 1);
    if (TRAILING_PUNCT_CHARS.indexOf(last) >= 0) {
      trailing = last + trailing;
      path = path.substring(0, path.length - 1);
      continue;
    }
    if (last === ')' && countChar(path, '(') <= countChar(path, ')')) {
      trailing = last + trailing;
      path = path.substring(0, path.length - 1);
      continue;
    }
    if (last === ']' || last === '}') {
      trailing = last + trailing;
      path = path.substring(0, path.length - 1);
      continue;
    }
    break;
  }
  res.path = path;
  res.trailing = trailing;
  return res;
}

function countChar(s: string, ch: string): number {
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    if (s.charAt(i) === ch) { n++; }
  }
  return n;
}

// stripLineSuffix：剥尾 :digits 或 :digits:digits（上游 line 61-63，正则 /:\d+(?::\d+)?$/）
function stripLineSuffix(value: string): string {
  const n: number = value.length;
  let g2: number = n;                       // 尾数字组起点
  while (g2 > 0 && isDigit(value.charAt(g2 - 1))) { g2--; }
  if (g2 === n) { return value; }            // 无尾数字
  if (g2 === 0 || value.charAt(g2 - 1) !== ':') { return value; }   // 尾数字前非 ':' → 非行后缀
  const colonIdx: number = g2 - 1;           // 第二组前的 ':'
  // 可选的前一组 :digits
  let g1: number = colonIdx;
  while (g1 > 0 && isDigit(value.charAt(g1 - 1))) { g1--; }
  if (g1 < colonIdx && g1 > 0 && value.charAt(g1 - 1) === ':') {
    return value.substring(0, g1 - 1);       // 两组都在 → 从第一组 ':' 起剥
  }
  return value.substring(0, colonIdx);       // 单组 → 从该 ':' 起
}

// hasKnownFileExtension：白名单判定（上游 line 65-69）
function hasKnownFileExtension(value: string): boolean {
  const path: string = stripLineSuffix(value).toLowerCase();
  const dot: number = path.lastIndexOf('.');
  if (dot < 0) { return false; }
  const ext: string = path.substring(dot + 1);
  return COMMON_FILE_EXTENSIONS.indexOf(ext) >= 0;
}

// shouldLinkPath：综合判定（上游 line 71-80）
function shouldLinkPath(value: string): boolean {
  if (indexOfStr(value, '://') >= 0) { return false; }
  const path: string = stripLineSuffix(value);
  if (path.length < 3) { return false; }
  if (startsWithChar(path, '/')) { return false; }
  if (startsWithStr(path, '~/')) { return false; }
  if (startsWithStr(path, '../')) { return false; }
  if (indexOfStr(path, '/../') >= 0) { return false; }
  if (isWinDrivePath(path)) { return false; }
  return hasKnownFileExtension(path);
}

function indexOfStr(s: string, needle: string): number {
  return s.indexOf(needle);                  // indexOf 取子串（非 regex），ArkTS 允许
}

function startsWithChar(s: string, ch: string): boolean {
  return s.length > 0 && s.charAt(0) === ch;
}

function startsWithStr(s: string, prefix: string): boolean {
  if (s.length < prefix.length) { return false; }
  for (let i: number = 0; i < prefix.length; i++) {
    if (s.charAt(i) !== prefix.charAt(i)) { return false; }
  }
  return true;
}

// Win 盘符 ^[A-Za-z]:[\\/]（上游 line 77）
function isWinDrivePath(path: string): boolean {
  return path.length >= 3 && isAlpha(path.charAt(0)) && path.charAt(1) === ':'
    && (path.charAt(2) === '/' || path.charAt(2) === '\\');
}

// ===== token 匹配（手写复刻 PATH_PATTERN，无 regex）=====

// 扩展名匹配 [A-Za-z0-9]{1,12}（上游 |lock 冗余——lock 已被 alnum 覆盖，故省略）。
//   返回从 k 起的 alnum 长度（贪心，上限 12）；0 表示无。
function matchExt(s: string, k: number): number {
  const n: number = s.length;
  let len: number = 0;
  while (len < 12 && k + len < n && isAlnum(s.charAt(k + len))) { len++; }
  return len;
}

// 行后缀 :\d+(?::\d+)? —— 返回从 k 起的消费长度（含冒号）；0 表示无。
function matchLineSuffix(s: string, k: number): number {
  const n: number = s.length;
  if (k >= n || s.charAt(k) !== ':') { return 0; }
  let d: number = k + 1;
  while (d < n && isDigit(s.charAt(d))) { d++; }
  if (d === k + 1) { return 0; }              // ':' 后须至少 1 数字
  // 可选第二组 :digits
  if (d < n && s.charAt(d) === ':') {
    let d2: number = d + 1;
    while (d2 < n && isDigit(s.charAt(d2))) { d2++; }
    if (d2 > d + 1) { d = d2; }               // 仅当第二组 ≥1 数字才消费
  }
  return d - k;
}

// matchTokenAt：在 s 恰好 p 处匹配一个路径 token，返回长度（≥1）；0 表示 p 处无 token。
//   先试 alt A（含 /），失败再试 alt B（裸名），逐字复刻上游两择正则。
function matchTokenAt(s: string, p: number): number {
  const n: number = s.length;
  if (p >= n) { return 0; }

  // --- alt A：前缀 ./ 或 [A-Za-z0-9_.-]+/ ---
  let prefixEnd: number = -1;
  if (p + 1 < n && s.charAt(p) === '.' && s.charAt(p + 1) === '/') {
    prefixEnd = p + 2;
  } else {
    let j: number = p;
    while (j < n && isNameChar(s.charAt(j))) { j++; }
    if (j > p && j < n && s.charAt(j) === '/') {
      prefixEnd = j + 1;
    }
  }
  if (prefixEnd > 0) {
    // middle 懒：从 prefixEnd 起找首个 .ext（遇 isMiddleStop 即 alt A 失败）
    let d: number = prefixEnd;
    while (d < n) {
      const ch: string = s.charAt(d);
      if (isMiddleStop(ch)) { break; }
      if (ch === '.') {
        const extLen: number = matchExt(s, d + 1);
        if (extLen > 0) {
          const lineLen: number = matchLineSuffix(s, d + 1 + extLen);
          return (d + 1 + extLen + lineLen) - p;
        }
      }
      d++;
    }
    // alt A 结构性失败 → 落到 alt B（与上游同位置两择一致）
  }

  // --- alt B：裸名 [A-Za-z0-9_.-]+\.ext（贪心 nameRun → 最右 dot）---
  let r: number = p;
  while (r < n && isNameChar(s.charAt(r))) { r++; }
  const runLen: number = r - p;
  if (runLen === 0) { return 0; }
  // 找最右 dot（贪心 nameRun 留最短 ext）：从尾往前扫，首个带合法 ext 的 dot 即用
  for (let k: number = runLen - 1; k >= 1; k--) {
    if (s.charAt(p + k) === '.') {
      const extLen: number = matchExt(s, p + k + 1);
      if (extLen > 0) {
        const lineLen: number = matchLineSuffix(s, p + k + 1 + extLen);
        return (p + k + 1 + extLen + lineLen) - p;
      }
      // 该 dot 后无合法 ext：继续往左找（贪心回退）
    }
  }
  return 0;
}

// linkifyProse：对一段 prose 文本跑路径链接（复刻上游 linkTextNode）。
//   linked=false 时原样返回（text 指向 seg 本身）。
class ProseResult {
  text: string = '';
  linked: boolean = false;
}

function linkifyProse(seg: string): ProseResult {
  const n: number = seg.length;
  let out: string = '';
  let lastIdx: number = 0;
  let p: number = 0;
  let linked: boolean = false;
  while (p < n) {
    const tokLen: number = matchTokenAt(seg, p);
    if (tokLen <= 0) { p++; continue; }

    // previousChar 上下文守卫（上游 line 91-94）
    const prevChar: string = p > 0 ? seg.charAt(p - 1) : '';
    if (prevChar === ':' || prevChar === '/' || prevChar === '\\' || prevChar === '.') {
      p += tokLen;                            // 跳过该 token（lastIndex 已过，上游 continue 同义）
      continue;
    }
    const rawMatch: string = seg.substring(p, p + tokLen);
    const sp: SplitResult = splitTrailingPunctuation(rawMatch);
    const filePath: string = stripLineSuffix(sp.path);
    if (!shouldLinkPath(filePath)) {
      p += tokLen;                            // 白名单/路径形态否决 → 跳过
      continue;
    }
    // 命中：输出 [lastIdx,p) 原文 + 链接（display 含行号、target 不含）+ 尾标点
    if (p > lastIdx) { out += seg.substring(lastIdx, p); }
    out += '[' + sp.path + '](' + FILE_PATH_HREF_PREFIX + encodeURIComponent(filePath) + ')';
    if (sp.trailing.length > 0) { out += sp.trailing; }
    lastIdx = p + tokLen;
    p += tokLen;
    linked = true;
  }
  const res: ProseResult = new ProseResult();
  if (!linked) { res.text = seg; res.linked = false; return res; }
  if (lastIdx < n) { out += seg.substring(lastIdx); }
  res.text = out;
  res.linked = true;
  return res;
}

// ===== 行级 / 内联 verbatim 豁免扫描 =====

class LineResult {
  text: string = '';
  linked: boolean = false;
  inFenceNext: boolean = false;
}

// 围栏分隔行判定：≤3 空格缩进 + ≥3 个 ` 或 ~（CommonMark）
function isFenceDelimLine(line: string): boolean {
  const n: number = line.length;
  let i: number = 0;
  while (i < 4 && i < n && line.charAt(i) === ' ') { i++; }
  if (i >= n) { return false; }
  const ch: string = line.charAt(i);
  if (ch !== '`' && ch !== '~') { return false; }
  let count: number = 0;
  while (i < n && line.charAt(i) === ch) { i++; count++; }
  return count >= 3;
}

function findChar(s: string, from: number, ch: string): number {
  for (let i: number = from; i < s.length; i++) {
    if (s.charAt(i) === ch) { return i; }
  }
  return -1;
}

// 从 from 起找长度恰为 len 的反引号 run 起点（行内代码配对）
function findBacktickRun(s: string, from: number, len: number): number {
  const n: number = s.length;
  for (let k: number = from; k + len <= n; k++) {
    if (s.charAt(k) !== '`') { continue; }
    let ok: boolean = true;
    for (let m: number = 0; m < len; m++) {
      if (s.charAt(k + m) !== '`') { ok = false; break; }
    }
    if (ok) { return k; }
  }
  return -1;
}

// 从 openIdx（指向 '('）起找配对 ')'，支持嵌套平衡
function findBalancedParen(s: string, openIdx: number): number {
  let depth: number = 0;
  for (let k: number = openIdx; k < s.length; k++) {
    const ch: string = s.charAt(k);
    if (ch === '(') { depth++; }
    else if (ch === ')') { depth--; if (depth === 0) { return k; } }
  }
  return -1;
}

// processProseLine：prose 行内联扫描——行内代码 / 链接 span verbatim，其余 prose 段跑 linkifyProse。
function processProseLine(line: string): LineResult {
  const n: number = line.length;
  let out: string = '';
  let i: number = 0;
  let proseStart: number = 0;
  let anyLinked: boolean = false;

  const flushProse = (end: number): void => {
    if (end > proseStart) {
      const seg: string = line.substring(proseStart, end);
      const r: ProseResult = linkifyProse(seg);
      if (r.linked) { anyLinked = true; }
      out += r.text;
    }
    proseStart = end;
  };

  while (i < n) {
    const ch: string = line.charAt(i);
    if (ch === '`') {
      let runLen: number = 0;
      while (i + runLen < n && line.charAt(i + runLen) === '`') { runLen++; }
      const closeStart: number = findBacktickRun(line, i + runLen, runLen);
      if (closeStart >= 0) {
        const closeEnd: number = closeStart + runLen;
        flushProse(i);                        // 行内代码前 prose 先落盘
        out += line.substring(i, closeEnd);   // 整段行内代码 verbatim（含两端 run）
        i = closeEnd;
        proseStart = i;
      } else {
        i++;                                   // 无配对 → 视普通字符
      }
    } else if (ch === '[') {
      const close: number = findChar(line, i + 1, ']');
      if (close >= 0) {
        flushProse(i);
        let spanEnd: number = close + 1;       // 含 ']'
        // 可选 ( ... )（链接/图片目标）
        if (spanEnd < n && line.charAt(spanEnd) === '(') {
          const parenClose: number = findBalancedParen(line, spanEnd);
          if (parenClose >= 0) { spanEnd = parenClose + 1; }
        } else if (spanEnd < n && line.charAt(spanEnd) === '[') {
          // 引用式 [text][ref]
          const refClose: number = findChar(line, spanEnd + 1, ']');
          if (refClose >= 0) { spanEnd = refClose + 1; }
        }
        out += line.substring(i, spanEnd);     // 整 link span verbatim
        i = spanEnd;
        proseStart = i;
      } else {
        i++;                                   // 未配对 '[' → 普通字符
      }
    } else {
      i++;
    }
  }
  flushProse(n);

  const res: LineResult = new LineResult();
  res.text = out;
  res.linked = anyLinked;
  res.inFenceNext = false;
  return res;
}

// processLine：单行调度（围栏 / prose）。
function processLine(line: string, inFence: boolean): LineResult {
  const fenceDelim: boolean = isFenceDelimLine(line);
  const res: LineResult = new LineResult();
  if (inFence) {
    res.text = line;
    res.linked = false;
    res.inFenceNext = !fenceDelim;             // 遇围栏分隔 → 出；否则仍在内
    return res;
  }
  if (fenceDelim) {
    res.text = line;
    res.linked = false;
    res.inFenceNext = true;                    // 进围栏
    return res;
  }
  return processProseLine(line);
}

// ===== 对外 API =====

// scanFilePaths：把 markdown 正文裸路径包成 [display](hapi-file:enc)。
//   无命中返回原串引用（幂等：免 CJMarkdown 无谓重渲染；对已链接输出再扫也安全——[...] span 豁免）。
export function scanFilePaths(markdown: string): string {
  const n: number = markdown.length;
  if (n === 0) { return markdown; }
  const pieces: string[] = [];
  let inFence: boolean = false;
  let anyLinked: boolean = false;
  let lineStart: number = 0;
  for (let i: number = 0; i <= n; i++) {
    if (i === n || markdown.charAt(i) === '\n') {
      const line: string = markdown.substring(lineStart, i);
      const newline: string = (i < n) ? '\n' : '';
      const r: LineResult = processLine(line, inFence);
      inFence = r.inFenceNext;
      if (r.linked) { anyLinked = true; }
      pieces.push(r.text);
      pieces.push(newline);
      lineStart = i + 1;
    }
  }
  if (!anyLinked) { return markdown; }          // 幂等：同引用
  let out: string = '';
  for (let i: number = 0; i < pieces.length; i++) { out += pieces[i]; }
  return out;
}

// decodeFilePathHref：剥 hapi-file: 前缀 + decodeURIComponent（上游同名，失败→null）。
//   供 MarkdownText.setLinkCallback 拦截复用。
export function decodeFilePathHref(href: string): string | null {
  if (!startsWithStr(href, FILE_PATH_HREF_PREFIX)) { return null; }
  const rest: string = href.substring(FILE_PATH_HREF_PREFIX.length);
  try {
    return decodeURIComponent(rest);
  } catch (e) {
    return null;
  }
}
