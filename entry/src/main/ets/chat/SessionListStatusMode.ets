// 会话列表状态模式纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/hooks/useSessionListStatusMode.ts：standard（默认，极简）/detailed（显 attention 指示器）。
//   本层仅类型 + 常量 + 归一化；响应式状态 + 持久化在 services/SessionListStatusModeService.ets。

export type SessionListStatusMode = 'standard' | 'detailed';

export const DEFAULT_SESSION_LIST_STATUS_MODE: SessionListStatusMode = 'standard';

// 归一化：两合法值透传，非法 → DEFAULT。
export function normalizeSessionListStatusMode(raw: string): SessionListStatusMode {
  if (raw === 'standard') { return 'standard'; }
  if (raw === 'detailed') { return 'detailed'; }
  return DEFAULT_SESSION_LIST_STATUS_MODE;
}
