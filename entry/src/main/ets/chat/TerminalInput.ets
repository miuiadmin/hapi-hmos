// 终端快捷键 + 修饰键合成 + terminalId 生成（对照 web routes/sessions/terminal.tsx）
//   纯逻辑层（无 @kit，可 LocalUnit 测）。TerminalPage 渲染 QUICK_INPUT_ROWS 为触屏快捷键栏：
//     - kind='seq'：tap → applyModifierState(seq, 修饰态) → sendInput（数据面在 terminal.html）
//     - kind='ctrl'/'alt'：tap → 切换该修饰键（与后续 seq 合成）
//   applyModifierState / shouldResetModifiers 逐行移植上游同名函数（terminal.tsx:75-94）。
//
//   QUICK_INPUT_ROWS 前两行逐键对照上游（Esc///-/Home/↑/End/PgUp + Tab/Ctrl/Alt/←/↓/→/PgDn）；
//   上游的 popup（长按变体 ?/|）移动端长按不实用 → v1 仅主序列。
//   第三行为移动端增补的常用控制字符（C-c/d/z/l/r/a/w），单键直发，无需修饰键组合（触屏友好）。

export type QuickKeyKind = 'seq' | 'ctrl' | 'alt';

// 快捷键定义（纯数据 → interface，ArkTS 对象字面量可直填）
export interface QuickKey {
  label: string;        // 按钮文案
  seq: string;          // 固定序列（kind='seq' 时发；ctrl/alt 切换键为 ''）
  kind: QuickKeyKind;   // seq=发序列；ctrl/alt=切换修饰键
}

// 修饰键状态（Ctrl/Alt 切换；与序列经 applyModifierState 合成）
export interface ModifierState {
  ctrl: boolean;
  alt: boolean;
}

// 触屏快捷键栏（对照上游 QUICK_INPUT_ROWS + 移动端增补行）
export const QUICK_INPUT_ROWS: QuickKey[][] = [
  [
    { label: 'Esc',  seq: '\x1b',    kind: 'seq' },
    { label: '/',     seq: '/',       kind: 'seq' },
    { label: '-',     seq: '-',       kind: 'seq' },
    { label: 'Home', seq: '\x1b[H',  kind: 'seq' },
    { label: '↑',    seq: '\x1b[A',  kind: 'seq' },
    { label: 'End',  seq: '\x1b[F',  kind: 'seq' },
    { label: 'PgUp', seq: '\x1b[5~', kind: 'seq' }
  ],
  [
    { label: 'Tab',  seq: '\t',       kind: 'seq' },
    { label: 'Ctrl', seq: '',         kind: 'ctrl' },
    { label: 'Alt',  seq: '',         kind: 'alt' },
    { label: '←',    seq: '\x1b[D',  kind: 'seq' },
    { label: '↓',    seq: '\x1b[B',  kind: 'seq' },
    { label: '→',    seq: '\x1b[C',  kind: 'seq' },
    { label: 'PgDn', seq: '\x1b[6~', kind: 'seq' }
  ],
  // 移动端增补：常用控制字符单键直发（值 = applyModifierState(ch,{ctrl:true}) 的结果）
  [
    { label: 'C-c', seq: '\x03', kind: 'seq' },
    { label: 'C-d', seq: '\x04', kind: 'seq' },
    { label: 'C-z', seq: '\x1a', kind: 'seq' },
    { label: 'C-l', seq: '\x0c', kind: 'seq' },
    { label: 'C-r', seq: '\x12', kind: 'seq' },
    { label: 'C-a', seq: '\x01', kind: 'seq' },
    { label: 'C-w', seq: '\x17', kind: 'seq' }
  ]
];

// 应用修饰键到序列（对照 applyModifierState，terminal.tsx:75-87）：
//   alt → 前缀 ESC(\x1b)；ctrl 且单字符且大写码落在 64..95(@.._) → 码 - 64 = 控制字符。
//   注意：alt 前缀会使长度变 2 → 之后 ctrl 分支（length===1）自动跳过，与上游一致。
export function applyModifierState(seq: string, state: ModifierState): string {
  let modified: string = seq;
  if (state.alt) {
    modified = '\x1b' + modified;
  }
  if (state.ctrl && modified.length === 1) {
    const code: number = modified.toUpperCase().charCodeAt(0);
    if (code >= 64 && code <= 95) {
      modified = String.fromCharCode(code - 64);
    }
  }
  return modified;
}

// 发送后是否复位修饰键（对照 shouldResetModifiers，terminal.tsx:89-94）：
//   序列非空且任一修饰键激活 → 复位（避免粘滞）。
export function shouldResetModifiers(seq: string, state: ModifierState): boolean {
  if (seq === '') { return false; }
  return state.ctrl || state.alt;
}

// UUID v4（终端实例标识；每实例一个，重连复用 → Hub 识别为 reconnect 不计配额）。
//   terminalId 非密钥，Math.random 熵足够；用 Math.random 保持纯逻辑层（不引 @kit.CryptoKit）。
//   格式 8-4-4-4-12，版本位 4，变体位 8/9/a/b。
export function uuid(): string {
  const hex: string = '0123456789abcdef';
  const chars: string[] = [];
  for (let i: number = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      chars.push('-');
      continue;
    }
    let n: number = Math.floor(Math.random() * 16);
    if (i === 14) {
      n = 4;                     // 版本 4
    } else if (i === 19) {
      n = (n & 0x3) | 0x8;       // 变体：8/9/a/b
    }
    chars.push(hex.charAt(n));
  }
  return chars.join('');
}

// —— terminal:error 文案分类（对照 hub/src/socket/handlers/terminal.ts 的错误文案常量）——
//   Hub 无 terminal:quota 事件：配额（maxTerminalsPerSocket/Session，默认 4）超限走
//   terminal:error 文案。本函数把文案归为四类，供 TerminalPage 显示专用友好态（协议不变）。
//     quota    → "Too many terminals open (max N)." / "...for this session (max N)."
//     inactive → "Session is inactive or unavailable."
//     cli      → "CLI is not connected for this session." / "CLI disconnected."
//     generic  → 其余（含 "Terminal ID is already in use." 等）
export type TerminalErrorKind = 'quota' | 'inactive' | 'cli' | 'generic';

export interface TerminalErrorInfo {
  kind: TerminalErrorKind;
  max: number;   // 仅 kind='quota' 有意义（提取的 max）；其余为 -1
}

export function classifyTerminalError(message: string): TerminalErrorInfo {
  const m: string = message;
  if (/too many terminals/i.test(m)) {
    let max: number = -1;
    const match: RegExpMatchArray | null = m.match(/\(max (\d+)\)/);
    if (match !== null && match.length > 1) {
      const captured: string = match[1];
      const parsed: number = parseInt(captured, 10);
      if (!isNaN(parsed)) { max = parsed; }
    }
    return { kind: 'quota', max: max };
  }
  if (/inactive|unavailable/i.test(m)) {
    return { kind: 'inactive', max: -1 };
  }
  if (/cli is not connected|cli disconnected/i.test(m)) {
    return { kind: 'cli', max: -1 };
  }
  return { kind: 'generic', max: -1 };
}
