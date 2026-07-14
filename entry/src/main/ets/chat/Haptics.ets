// 触感反馈纯逻辑层（无 @kit，LocalUnit 可测）。
//   纯移动端增强（Web 无对应）：把「交互意图」映射成震动效果描述（kind + 时长），
//   不碰 @ohos.vibrator；实际震动在 services/HapticService.ets（镜像 TerminalToolDisplay 范式）。
//   本层只产出意图描述（可测）；系统预设名/时长为纯常量。
//   设计：统一用 duration（ms）型效果（API 9+ 通用，preset 名随版本变动故不依赖）。

// 交互意图：发送 / 删除 / 长按 / 错误 / 成功
export type HapticEvent = 'send' | 'delete' | 'longPress' | 'error' | 'success';

// 震动效果描述（kind 固定 'time'；durationMs 毫秒数，短促）
export interface HapticEffect {
  kind: 'time';
  durationMs: number;
}

// 默认时长（轻点，用于未知事件回落）
export const DEFAULT_HAPTIC_DURATION_MS: number = 10;

// 意图 → 时长（ms）。手写 if-else 链，避 Record 索引类型坑（ArkTS strict）。
//   send 10（最轻，频繁触发）/ longPress 15 / success 12 / delete 20 / error 30（最重，警示）。
export function hapticEffectFor(event: HapticEvent): HapticEffect {
  let ms: number = DEFAULT_HAPTIC_DURATION_MS;
  if (event === 'send') { ms = 10; }
  else if (event === 'longPress') { ms = 15; }
  else if (event === 'success') { ms = 12; }
  else if (event === 'delete') { ms = 20; }
  else if (event === 'error') { ms = 30; }
  return { kind: 'time', durationMs: ms };
}

// —— 持久化偏好（'on'/'off'，移动端默认开）——
export type HapticsPref = 'off' | 'on';

export const DEFAULT_HAPTICS_PREF: HapticsPref = 'on';

// 归一化：合法值透传，非法（含空/未知）→ DEFAULT（移动端默认开）。
export function normalizeHapticsPref(raw: string): HapticsPref {
  if (raw === 'off') { return 'off'; }
  if (raw === 'on') { return 'on'; }
  return DEFAULT_HAPTICS_PREF;
}

export function hapticsPrefToEnabled(pref: HapticsPref): boolean {
  return pref === 'on';
}

export function hapticsEnabledToPref(enabled: boolean): HapticsPref {
  return enabled ? 'on' : 'off';
}
