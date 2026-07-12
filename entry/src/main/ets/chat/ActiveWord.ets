// 光标处「活动词」定位与建议应用（对照 web utils/findActiveWord.ts + applySuggestion.ts）
//   纯逻辑：根据光标选区在文本中回溯找到以某前缀（@ / $）起始的词；补全时把该词替换为建议文本。
//   Phase 1 仅接 '/'（斜杠命令）；'@' 文件提及 / '$' 技能 需各自数据源，后续接入复用本逻辑（接口已通用）。
//   仅无选区（光标点）时触发；移动端无 ↑↓，导航靠 tap，故上游 useActiveSuggestions 的键盘选中态不移植。

// 停止字符（对照 findActiveWord.ts STOP_CHARACTERS）
const STOP_CHARACTERS: string[] = ['\n', ',', '(', ')', '[', ']', '{', '}', '<', '>', ';', '!', '?', '.'];

function isStop(ch: string): boolean { return STOP_CHARACTERS.indexOf(ch) >= 0; }
function isPrefix(ch: string, prefixes: string[]): boolean { return prefixes.indexOf(ch) >= 0; }

// 活动词信息（对照 ActiveWord 接口）
export class ActiveWord {
  word: string = '';           // 前缀到词尾的完整词（如 "/clear"）
  activeWord: string = '';     // 前缀到光标的片段（如 "/cl"）
  offset: number = 0;          // 词起点
  length: number = 0;          // 完整词长
  activeLength: number = 0;    // 前缀到光标长
  endOffset: number = 0;       // 词尾位置（offset + length）
}

// 向左回溯找词起点（对照 findActiveWordStart）。上游对 '@' 有 foundPrefix 分支但两支均立即 return，等价。
function findStart(content: string, selStart: number, prefixes: string[]): number {
  let startIndex: number = selStart - 1;
  let spaceIndex: number = -1;
  let foundPrefix: boolean = false;
  let prefixIndex: number = -1;
  while (startIndex >= 0) {
    const ch: string = content.charAt(startIndex);
    if (ch === ' ') {
      if (foundPrefix) { return prefixIndex; }
      if (spaceIndex >= 0) { return spaceIndex + 1; }
      spaceIndex = startIndex;
      startIndex--;
    } else if (isPrefix(ch, prefixes) &&
      (startIndex === 0 || content.charAt(startIndex - 1) === ' ' || content.charAt(startIndex - 1) === '\n')) {
      return startIndex;
    } else if (isStop(ch)) {
      if (foundPrefix) { return prefixIndex; }
      return startIndex + 1;
    } else {
      startIndex--;
    }
  }
  if (foundPrefix) { return prefixIndex; }
  return (spaceIndex >= 0 ? spaceIndex : startIndex) + 1;
}

// 向右找词尾（对照 findActiveWordEnd；@ 文件路径含 / . 不中断）
function findEnd(content: string, cursorPos: number, wordStartPos: number): number {
  let endIndex: number = cursorPos;
  let isFilePath: boolean = false;
  if (wordStartPos >= 0 && wordStartPos < content.length && content.charAt(wordStartPos) === '@') {
    isFilePath = true;
  }
  while (endIndex < content.length) {
    const ch: string = content.charAt(endIndex);
    if (isFilePath && (ch === '/' || ch === '.')) { endIndex++; continue; }
    if (ch === ' ' || isStop(ch)) { break; }
    endIndex++;
  }
  return endIndex;
}

// 找光标处的前缀活动词（对照 findActiveWord）；仅在无选区（光标点）时检测。
export function findActiveWord(content: string, selStart: number, selEnd: number, prefixes: string[]): ActiveWord | null {
  if (selStart !== selEnd) { return null; }   // 有选区不触发
  if (selStart === 0) { return null; }        // 文本起点不触发（左侧无前缀）
  const startIndex: number = findStart(content, selStart, prefixes);
  const activeWordPart: string = content.substring(startIndex, selEnd);
  if (activeWordPart.endsWith(' ')) { return null; }
  if (activeWordPart.length > 0) {
    const firstChar: string = activeWordPart.charAt(0);
    if (isPrefix(firstChar, prefixes)) {
      const endIndex: number = findEnd(content, selEnd, startIndex);
      const fullWord: string = content.substring(startIndex, endIndex);
      const w: ActiveWord = new ActiveWord();
      w.word = fullWord;
      w.activeWord = activeWordPart;
      w.offset = startIndex;
      w.length = fullWord.length;
      w.activeLength = activeWordPart.length;
      w.endOffset = endIndex;
      return w;
    }
  }
  return null;
}

// 建议应用结果（对照 applySuggestion 返回 { text, cursorPosition }）
export class AppliedSuggestion {
  text: string = '';
  cursorPosition: number = 0;
}

// 把活动词替换为建议文本（对照 applySuggestion）；addSpace 默认词尾补空格。
export function applySuggestion(content: string, selStart: number, selEnd: number,
  suggestion: string, prefixes: string[], addSpace: boolean = true): AppliedSuggestion {
  const r: AppliedSuggestion = new AppliedSuggestion();
  const aw: ActiveWord | null = findActiveWord(content, selStart, selEnd, prefixes);
  if (aw === null) {
    // 无活动词：在光标处直接插入
    const before: string = content.substring(0, selStart);
    const after: string = content.substring(selEnd);
    const ins: string = addSpace ? `${suggestion} ` : suggestion;
    r.text = before + ins + after;
    r.cursorPosition = selStart + ins.length;
    return r;
  }
  // 替换完整词（offset→endOffset）
  const beforeWord: string = content.substring(0, aw.offset);
  const afterWord: string = content.substring(aw.endOffset);
  let ins: string = suggestion;
  if (addSpace) {
    if (afterWord.length === 0 || afterWord.charAt(0) !== ' ') { ins = `${ins} `; }
  }
  r.text = beforeWord + ins + afterWord;
  r.cursorPosition = aw.offset + ins.length;
  return r;
}
