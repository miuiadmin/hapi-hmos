// 会话列表每组预览行数限流纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/hooks/useSessionPreviewLimit.ts：
//     DEFAULT_SESSION_PREVIEW_LIMIT=8 / MIN=1 / MAX=99；normalizeSessionPreviewLimit 非整数→DEFAULT，否则 clamp。
//   限流是「每目录组的行数上限」（非预览文本长度），见 chat/SessionGrouping.ets flattenGroups 扩展。
//   本层仅常量 + 归一化；响应式状态 + 持久化在 services/SessionPreviewLimitService.ets。

export const DEFAULT_SESSION_PREVIEW_LIMIT: number = 8;
export const MIN_SESSION_PREVIEW_LIMIT: number = 1;
export const MAX_SESSION_PREVIEW_LIMIT: number = 99;

// 归一化：非整数（含 NaN）→ DEFAULT；否则 clamp 到 [MIN, MAX]（对照上游 normalizeSessionPreviewLimit）。
export function normalizeSessionPreviewLimit(value: number): number {
  if (!Number.isInteger(value)) { return DEFAULT_SESSION_PREVIEW_LIMIT; }
  let v: number = value;
  if (v < MIN_SESSION_PREVIEW_LIMIT) { v = MIN_SESSION_PREVIEW_LIMIT; }
  if (v > MAX_SESSION_PREVIEW_LIMIT) { v = MAX_SESSION_PREVIEW_LIMIT; }
  return v;
}
