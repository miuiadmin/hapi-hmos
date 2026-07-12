// Hapi 核心数据类型（对齐 hapi shared/src）
// ArkTS 无 Zod，手写等价类型 + 安全解析（JSON → 强类型）

// —— 会话摘要（列表用，对齐 shared/src/sessionSummary.ts SessionSummary）——
export class SessionSummaryMetadata {
  name: string = '';           // 会话标题
  path: string = '';           // 工作目录
  machineId: string = '';
  summaryText: string = '';    // 摘要文本
  flavor: string = '';
  agentSessionId: string = '';
}

export class SessionSummary {
  id: string = '';
  active: boolean = false;
  thinking: boolean = false;
  activeAt: number = 0;
  updatedAt: number = 0;
  metadata: SessionSummaryMetadata | null = null;
  pendingRequestsCount: number = 0;
  backgroundTaskCount: number = 0;
  model: string = '';          // null → ''
  effort: string = '';
  todoCompleted: number = 0;
  todoTotal: number = 0;

  // 标题：name 优先，否则 path 末段，否则 id
  get title(): string {
    if (this.metadata !== null) {
      if (this.metadata.name !== '') {
        return this.metadata.name;
      }
      if (this.metadata.path !== '') {
        const i: number = this.metadata.path.lastIndexOf('/');
        return i >= 0 ? this.metadata.path.substring(i + 1) : this.metadata.path;
      }
    }
    return this.id;
  }

  get summaryText(): string {
    return this.metadata !== null ? this.metadata.summaryText : '';
  }
}

// —— 机器（运行 CLI/agent 的设备，对齐 shared/src/schemas.ts Machine，简化）——
export class Machine {
  id: string = '';
  namespace: string = '';
  active: boolean = false;
  activeAt: number = 0;
  updatedAt: number = 0;
  displayName: string = '';
}

// —— 会话详情（对齐 shared/src/schemas.ts Session）——
// 本类即上游 Session（完整会话记录）。当前只取渲染/工具卡所需字段，其余按需再补。
export class Session {
  id: string = '';
  namespace: string = '';
  seq: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  active: boolean = false;
  activeAt: number = 0;
  thinking: boolean = false;
  model: string = '';                       // nullable → ''
  effort: string = '';                       // nullable → ''
  agentStateVersion: number = 0;
  // 原始 agentState（{controlledByUser, requests, completedRequests}），由 chat/parseAgentState 解析。
  // 存原始 Record 而非已解析对象，避免 models/ 反向依赖 chat/。
  agentStateRaw: Record<string, Object> | null = null;
  // TODO: 详情页时补全 metadata / todos / teamState 等字段
}

// —— 重命名会话请求体（对齐 shared/src/apiTypes.ts RenameSessionRequest：name 1–255）——
export class RenameSessionRequest {
  name: string = '';
}

// 解析 GET /api/sessions/:id → { session: {...} }（对照 web getSession 的 SessionResponse）
export function parseSessionDetail(json: string): Session {
  const s: Session = new Session();
  let top: Record<string, Object>;
  try {
    top = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return s;
  }
  const raw: Record<string, Object> | null = pickObj(top, 'session');
  if (raw === null) {
    return s;
  }
  s.id = pickStr(raw, 'id');
  s.namespace = pickStr(raw, 'namespace');
  s.seq = pickNum(raw, 'seq');
  s.createdAt = pickNum(raw, 'createdAt');
  s.updatedAt = pickNum(raw, 'updatedAt');
  s.active = pickBool(raw, 'active');
  s.activeAt = pickNum(raw, 'activeAt');
  s.thinking = pickBool(raw, 'thinking');
  s.model = pickStr(raw, 'model');
  s.effort = pickStr(raw, 'effort');
  s.agentStateVersion = pickNum(raw, 'agentStateVersion');
  s.agentStateRaw = pickObj(raw, 'agentState');
  return s;
}

// —— 安全解析辅助（从 Record 取值，类型不符给默认）——
export function pickStr(r: Record<string, Object>, k: string): string {
  const v = r[k];
  return typeof v === 'string' ? v : '';
}
export function pickNum(r: Record<string, Object>, k: string): number {
  const v = r[k];
  return typeof v === 'number' ? v : 0;
}
export function pickBool(r: Record<string, Object>, k: string): boolean {
  const v = r[k];
  return typeof v === 'boolean' ? v : false;
}
export function pickObj(r: Record<string, Object>, k: string): Record<string, Object> | null {
  const v = r[k];
  if (v !== null && v !== undefined && typeof v === 'object') {
    return v as Record<string, Object>;
  }
  return null;
}

// 解析单个 SessionSummary
export function parseSessionSummary(raw: Record<string, Object>): SessionSummary {
  const s = new SessionSummary();
  s.id = pickStr(raw, 'id');
  s.active = pickBool(raw, 'active');
  s.thinking = pickBool(raw, 'thinking');
  s.activeAt = pickNum(raw, 'activeAt');
  s.updatedAt = pickNum(raw, 'updatedAt');
  s.pendingRequestsCount = pickNum(raw, 'pendingRequestsCount');
  s.backgroundTaskCount = pickNum(raw, 'backgroundTaskCount');
  s.model = pickStr(raw, 'model');
  s.effort = pickStr(raw, 'effort');

  const metaRaw = pickObj(raw, 'metadata');
  if (metaRaw !== null) {
    const m = new SessionSummaryMetadata();
    m.name = pickStr(metaRaw, 'name');
    m.path = pickStr(metaRaw, 'path');
    m.machineId = pickStr(metaRaw, 'machineId');
    const sumRaw = pickObj(metaRaw, 'summary');
    if (sumRaw !== null) {
      m.summaryText = pickStr(sumRaw, 'text');
    }
    m.flavor = pickStr(metaRaw, 'flavor');
    s.metadata = m;
  }

  const todoRaw = pickObj(raw, 'todoProgress');
  if (todoRaw !== null) {
    s.todoCompleted = pickNum(todoRaw, 'completed');
    s.todoTotal = pickNum(todoRaw, 'total');
  }
  return s;
}

// 解析 SessionsResponse { sessions: SessionSummary[] }
export function parseSessionsResponse(json: string): SessionSummary[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  const arr = raw['sessions'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: SessionSummary[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      result.push(parseSessionSummary(item as Record<string, Object>));
    }
  }
  return result;
}
