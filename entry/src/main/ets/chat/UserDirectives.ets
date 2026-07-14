// UserDirectives —— 用户气泡前导指令（/slash、$skill）抽取纯逻辑。
//   对照 web/src/components/AssistantChat/messages/user-bubble.tsx:13-41
//   （LEADING_DIRECTIVE_REGEX / extractLeadingDirectives / formatDirectiveLabel）。
//   零 @kit 纯层、零 i18n：把用户消息开头连续的 $xxx / /xxx 命令抽成 chip，剩余文本作 body。
//   鸿蒙 UI（StatusBar.ets UserBubble）据此把命令显成独立 pill，与正文分离。
//
//   手写扫描避 regex lookahead/s-flag（照 chat/ThreadGoal.ets isGoalSlashCommand 范式）。
//   语义逐字对齐上游正则 /^([$\/][a-z0-9][\w-]*)(?=\s|$)/i：
//     1) trimStart 跳前导空白；2) 首字符须 $ (36) 或 / (47)；3) 第二字符须字母/数字；
//     4) 贪心消费 [\w-]*（字母/数字/_/-）；5) 其后须空白或串尾（lookahead）；6) 切下该 token，重复。

// 指令抽取结果。directives = 前导命令（含前缀 $//，原样）；body = 抽完命令后的剩余（已 trimStart）。
export class DirectiveExtract {
  directives: string[] = [];
  body: string = '';
}

// \s 全集：tab9/nl10/vt11/ff12/cr13/space32（对齐 JS trimStart 的空白定义）
function isWs(code: number): boolean {
  return code === 9 || code === 10 || code === 11 || code === 12 || code === 13 || code === 32;
}

// [a-z0-9] 大小写不敏感（上游 i flag）：数字 48-57 / 大写 65-90 / 小写 97-122
function isAlnum(code: number): boolean {
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

// \w = [a-zA-Z0-9_]，外加 '-' (45)。即 isAlnum ∪ '_' (95) ∪ '-'
function isWordOrHyphen(code: number): boolean {
  return isAlnum(code) || code === 95 || code === 45;
}

// 抽取用户文本开头连续的前导指令（对照 user-bubble.tsx:19-34 extractLeadingDirectives）。
//   返回 { directives, body }：directives 含 $// 前缀原样；body 为剩余正文（已去前导空白）。
//   例：'/clear' → {['/clear'], ''}；'$skills foo' → {['$skills'], 'foo'}；
//       '/goal ship it' → {['/goal'], 'ship it'}；'$a /b' → {['$a','/b'], ''}；
//       'hello' → {[], 'hello'}；'$foo(bar)' → lookahead 失败 → {[], '$foo(bar)'}。
export function extractLeadingDirectives(text: string): DirectiveExtract {
  const result: DirectiveExtract = new DirectiveExtract();
  const n: number = text.length;
  let p: number = 0;
  // trimStart
  while (p < n && isWs(text.charCodeAt(p))) { p++; }

  const directives: string[] = [];
  while (p < n) {
    const c0: number = text.charCodeAt(p);
    if (c0 !== 36 && c0 !== 47) { break; }             // 须 $ 或 / 开头
    if (p + 1 >= n) { break; }                          // 须有第二字符
    if (!isAlnum(text.charCodeAt(p + 1))) { break; }    // 第二字符须字母/数字
    // 贪心消费 [\w-]*
    let end: number = p + 2;
    while (end < n && isWordOrHyphen(text.charCodeAt(end))) { end++; }
    // lookahead：end 处须空白或串尾
    if (end < n && !isWs(text.charCodeAt(end))) { break; }
    directives.push(text.substring(p, end));
    p = end;
    // trimStart
    while (p < n && isWs(text.charCodeAt(p))) { p++; }
  }

  result.directives = directives;
  result.body = text.substring(p);
  return result;
}

// 指令 → chip label（对照 user-bubble.tsx:36-40 formatDirectiveLabel）：
//   去前导 $ 或 / → [_-]+ 折叠成单空格 → trim。
//   例：'/clear'→'clear'；'$skills'→'skills'；'/ship-it'→'ship it'；'$a_b-c'→'a b c'。
export function formatDirectiveLabel(value: string): string {
  let s: string = value;
  // 去前导 $ (36) 或 / (47)
  if (s.length > 0 && (s.charCodeAt(0) === 36 || s.charCodeAt(0) === 47)) {
    s = s.substring(1);
  }
  // [_-]+ → 单空格
  let out: string = '';
  let i: number = 0;
  while (i < s.length) {
    const code: number = s.charCodeAt(i);
    if (code === 45 || code === 95) {
      out += ' ';
      while (i < s.length && (s.charCodeAt(i) === 45 || s.charCodeAt(i) === 95)) { i++; }
    } else {
      out += s.charAt(i);
      i++;
    }
  }
  return out.trim();
}
