import { SessionSummary } from '../models/Types';

// 会话注意力分级（对照 web lib/sessionAttention.ts classifySessionAttention）
//   列表项左侧色点依据；与右侧 pending/bg 角标不冲突（不同位置、不同语义）。
//   优先级（逐字移植）：
//     selected || thinking        → null（正在看 / 正在流式，不打扰）
//     pendingRequestKinds 含 'permission' → 'permission'（琥珀，需授权）
//     pendingRequestKinds 含 'input'      → 'input'（蓝，需输入）
//     active && backgroundTaskCount > 0    → 'background'（蓝，后台跑）
//     updatedAt > lastSeenAt              → 'unread'（主色，有新活动）
//     否则                                 → null
export type AttentionKind = 'permission' | 'input' | 'background' | 'unread';

function includesKind(kinds: string[], kind: string): boolean {
  for (let i = 0; i < kinds.length; i++) {
    if (kinds[i] === kind) {
      return true;
    }
  }
  return false;
}

export function classifySessionAttention(
  summary: SessionSummary,
  selected: boolean,
  lastSeenAt: number
): AttentionKind | null {
  if (selected || summary.thinking) {
    return null;
  }
  if (includesKind(summary.pendingRequestKinds, 'permission')) {
    return 'permission';
  }
  if (includesKind(summary.pendingRequestKinds, 'input')) {
    return 'input';
  }
  if (summary.active && summary.backgroundTaskCount > 0) {
    return 'background';
  }
  if (summary.updatedAt > lastSeenAt) {
    return 'unread';
  }
  return null;
}

// 会话「已看」时间戳服务（内存 Map；重启清零——对照上游 selected 态亦内存，非持久化）。
//   markSeen(sid) 设 Date.now()；lastSeen(sid) 取（默认 0）。ChatPage aboutToAppear/Disappear 调 markSeen 清未读。
//   @ObservedV2 + @Trace revision：markSeen 自增；Index 渲染期读 revision 建立 V2 刷新依赖
//   （lastSeen 读 Map 内部值不自带观察，靠 revision 变化触发列表重渲染 → 重读 lastSeen 拿最新时间戳）。
//   装饰器 @ObservedV2/@Trace 为 ArkUI 全局装饰器（与 @ComponentV2 同级，无需 import）。
@ObservedV2
export class SessionSeenService {
  private seen: Map<string, number> = new Map();
  @Trace revision: number = 0;

  markSeen(sessionId: string): void {
    this.seen.set(sessionId, Date.now());
    this.revision = this.revision + 1;
  }

  lastSeen(sessionId: string): number {
    const v = this.seen.get(sessionId);
    return v !== undefined ? v : 0;
  }
}

let sessionSeenInstance: SessionSeenService | null = null;
export function getSessionSeenService(): SessionSeenService {
  if (sessionSeenInstance === null) {
    sessionSeenInstance = new SessionSeenService();
  }
  return sessionSeenInstance;
}
