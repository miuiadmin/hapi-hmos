// StatusBarChips —— 顶部状态行右侧 chip 簇纯逻辑（对照 web StatusBar.tsx:126-273 + shared/src/modes.ts）。
//   零 @kit 纯层、零 i18n 调用：permissionModeTone（语义色调）/ isPermissionModeAllowedForFlavor
//   （flavor 域校验）/ normalizeReasoningEffort（推理努力归一）/ isCodexFastMode（fast 判定）/
//   toneColor（tone→调色板色）+ 4 个 chip 可见性谓词。i18n label（reasoning/fast/permission/
//   collaboration）由组件层 StatusBar.ets 解析；本层只出 tone + 谓词，保可单测。
//
//   tone 语义（对照上游 PermissionModeTone + fast）：
//     neutral=提示灰、info=蓝、warning=琥珀、danger=红、success=绿（fast）。

import { PaletteColors } from '../theme/Palette';

// flavor → 权限模式域（对照 modes.ts:100-117 getPermissionModesForFlavor；与 models/Types.ets
//   permissionModesForFlavor 同义，本层自含避免 import models/Types 传染 i18n t() 耦合面）。
function permissionModesForFlavor(flavor: string): string[] {
  if (flavor === 'codex' || flavor === 'gemini' || flavor === 'kimi') {
    return ['default', 'read-only', 'safe-yolo', 'yolo'];
  }
  if (flavor === 'opencode') { return ['default', 'plan', 'yolo']; }
  if (flavor === 'cursor') { return ['default', 'plan', 'ask', 'yolo']; }
  return ['default', 'acceptEdits', 'bypassPermissions', 'plan'];   // claude + 未知回退
}

// 权限模式 → 语义色调（对照 modes.ts:61-70 PERMISSION_MODE_TONES）。
//   plan/ask→info、acceptEdits/read-only/safe-yolo→warning、bypassPermissions/yolo→danger、default/未知→neutral。
export function permissionModeTone(mode: string): string {
  if (mode === 'plan' || mode === 'ask') { return 'info'; }
  if (mode === 'acceptEdits' || mode === 'read-only' || mode === 'safe-yolo') { return 'warning'; }
  if (mode === 'bypassPermissions' || mode === 'yolo') { return 'danger'; }
  return 'neutral';   // default + 未知
}

// flavor 是否允许该权限模式（对照 modes.ts:127-129 isPermissionModeAllowedForFlavor）。
export function isPermissionModeAllowedForFlavor(mode: string, flavor: string): boolean {
  const modes: string[] = permissionModesForFlavor(flavor);
  for (let i = 0; i < modes.length; i++) {
    if (modes[i] === mode) { return true; }
  }
  return false;
}

// 推理努力归一（对照 StatusBar.tsx:126-130 formatCodexReasoningLabel 的归一部分）：
//   trim+lower；'' 或 'default' → 'default'；否则小写原值。组件层据此拼 label（default 用专门 key）。
export function normalizeReasoningEffort(effort: string): string {
  const normalized: string = effort.trim().toLowerCase();
  if (normalized === '' || normalized === 'default') { return 'default'; }
  return normalized;
}

// fast 判定（对照 StatusBar.tsx:132-140 isCodexFastMode）：effort∈{none,minimal,low} 或 model 含 'mini'/'fast'。
export function isCodexFastMode(model: string, effort: string): boolean {
  const e: string = effort.trim().toLowerCase();
  if (e === 'none' || e === 'minimal' || e === 'low') { return true; }
  const m: string = model.trim().toLowerCase();
  return m.indexOf('mini') >= 0 || m.indexOf('fast') >= 0;
}

// tone → 调色板色（对照 StatusBar.tsx:34-39 PERMISSION_TONE_CLASSES + fast 绿 #34C759）：
//   info→primary（蓝）、warning→warning（琥珀）、danger→error（红）、success→success（绿）、neutral→textTertiary（灰）。
export function toneColor(tone: string, palette: PaletteColors): string {
  if (tone === 'info') { return palette.primary; }
  if (tone === 'warning') { return palette.warning; }
  if (tone === 'danger') { return palette.error; }
  if (tone === 'success') { return palette.success; }
  return palette.textTertiary;   // neutral + 未知
}

// —— chip 可见性谓词（对照 StatusBar.tsx:192-213 的 display 判定，goal 留 follow-up）——

// reasoning chip：codex / opencode 才显示（对照 StatusBar.tsx:208-210）。
export function shouldShowReasoningChip(flavor: string): boolean {
  return flavor === 'codex' || flavor === 'opencode';
}

// fast chip：仅 codex 且 isCodexFastMode（对照 StatusBar.tsx:211-213 + 254-258）。
export function shouldShowFastChip(flavor: string, model: string, effort: string): boolean {
  return flavor === 'codex' && isCodexFastMode(model, effort);
}

// collaboration chip：仅 codex 且 plan（对照 StatusBar.tsx:202-204 + 264-268）。
export function shouldShowCollaborationChip(flavor: string, collaborationMode: string): boolean {
  return flavor === 'codex' && collaborationMode === 'plan';
}

// permission chip：非 default 且 flavor 域允许（对照 StatusBar.tsx:192-197 + 269-273）。
export function shouldShowPermissionChip(mode: string, flavor: string): boolean {
  if (mode === '' || mode === 'default') { return false; }
  return isPermissionModeAllowedForFlavor(mode, flavor);
}
