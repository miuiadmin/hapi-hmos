// SessionStatus —— 会话列表四态状态判定（纯层，无 @kit，LocalUnit 可测）。
//
// 对照 paseo sidebar deriveAgentStateBucket（running/needs_input/attention/done）+ 上游 web
//   RUNNING_BUCKETS（working/pending/idle），映射到 hapi SessionSummary 现有字段。四态（优先级
//   从高到低，短路）：
//     pending  : pendingRequestsCount > 0          （待审批/待输入 → 待回复，琥珀）
//     running  : thinking || backgroundTaskCount>0 （进行中，蓝 + 脉冲）
//     unread   : updatedAt > lastSeenAt            （有新回复未读 → 完成请看，绿）
//     idle     : 其它                                （空闲，灰）
// 与 services/SessionAttention.ets classifySessionAttention 的区别：本层不做 detailed 门控、
//   thinking 不返 null（→ running）、idle 兜底显灰点（那套 thinking→null + null 兜底，仅 detailed 用）。
// 实时刷新靠 Index SSE → loadSessions（本层纯函数，每次列表渲染重算，无自身状态）。

import { SessionSummary } from '../models/Types';

export type SessionStatusKind = 'pending' | 'running' | 'unread' | 'idle';

// 四态判定（优先级从高到低短路）。lastSeenAt = SessionSeenService.lastSeen(session.id)，默认 0。
export function classifySessionStatus(s: SessionSummary, lastSeenAt: number): SessionStatusKind {
  if (s.pendingRequestsCount > 0) {
    return 'pending';
  }
  if (s.thinking || s.backgroundTaskCount > 0) {
    return 'running';
  }
  if (s.updatedAt > lastSeenAt) {
    return 'unread';
  }
  return 'idle';
}
