import { SessionSummary } from '../models/Types';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';

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

// 会话「已看」时间戳服务（持久化；对照上游 web lib/sessionLastSeen.ts：localStorage 存 {sid→seenAt} 单 blob）。
//   启动 hydrate() 从 Preferences 读 JSON {sid→seenAt} 灌内存 Map（lastSeen 保持同步读，渲染期调用不阻塞）。
//   markSeen(sid, seenAt) 写穿：更新内存 + 序列化落盘 + bump revision；单调 Math.max（防乱序事件回退）。
//   seenAt 存【服务端 session.updatedAt】（非 Date.now()）：对齐上游 router.tsx markSessionSeen(id, updatedAt)，
//   规避时钟偏移（客户端时钟超前 → Date.now()>服务端未来 updatedAt → 漏检新消息；与列表比较的 updatedAt 同源才稳）。
//   @ObservedV2 + @Trace revision：markSeen 自增；Index 渲染期读 revision 建立 V2 刷新依赖
//   （lastSeen 读 Map 内部值不自带观察，靠 revision 变化触发列表重渲染 → 重读 lastSeen 拿最新时间戳）。
//   装饰器 @ObservedV2/@Trace 为 ArkUI 全局装饰器（与 @ComponentV2 同级，无需 import）。
@ObservedV2
export class SessionSeenService {
  private seen: Map<string, number> = new Map();
  private hydrated: boolean = false;
  @Trace revision: number = 0;

  // 启动期调一次（EntryAbility.bootstrap，loadContent 前）：读盘灌内存 Map。空/损坏 JSON → 空 Map（容错不阻塞首屏）。
  async hydrate(): Promise<void> {
    if (this.hydrated) {
      return;
    }
    this.hydrated = true;
    try {
      const raw: string = await getPreferencesService().getString(PreferenceKeys.SESSION_LAST_SEEN, '');
      if (raw !== '') {
        const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
        const keys: string[] = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          const k: string = keys[i];
          if (k.length === 0) {
            continue;
          }
          const v: Object = parsed[k];
          if (typeof v === 'number') {
            this.seen.set(k, v as number);
          }
        }
      }
    } catch (_e) {
      // 损坏 JSON 或 Preferences 异常：留空 Map，不阻塞启动
    }
  }

  // 标记已看（seenAt = 服务端 updatedAt）。单调：仅当 seenAt > 旧值才更新 + 落盘 + bump revision。
  markSeen(sessionId: string, seenAt: number): void {
    if (sessionId === '') {
      return;
    }
    const prev: number = this.lastSeen(sessionId);
    if (seenAt > prev) {
      this.seen.set(sessionId, seenAt);
      this.revision = this.revision + 1;
      this.persist();
    }
  }

  lastSeen(sessionId: string): number {
    const v = this.seen.get(sessionId);
    return v !== undefined ? v : 0;
  }

  // 写穿：序列化整张 Map → Preferences（fire-and-forget；失败吞掉，下次 markSeen 重试）。
  private persist(): void {
    try {
      const obj: Record<string, number> = {};
      this.seen.forEach((v: number, k: string) => {
        obj[k] = v;
      });
      const raw: string = JSON.stringify(obj);
      getPreferencesService().putString(PreferenceKeys.SESSION_LAST_SEEN, raw).catch((): void => {});
    } catch (_e) {
      // Preferences 未就绪等异常：跳过落盘，内存态仍正确（下次 markSeen 重试）
    }
  }
}

let sessionSeenInstance: SessionSeenService | null = null;
export function getSessionSeenService(): SessionSeenService {
  if (sessionSeenInstance === null) {
    sessionSeenInstance = new SessionSeenService();
  }
  return sessionSeenInstance;
}
