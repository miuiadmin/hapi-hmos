// Hapi SSE 事件模型（对齐 hapi shared/src/schemas.ts 的 SyncEventSchema）
// ArkTS 无 Zod discriminatedUnion，用单一 class + type 字段区分；特有字段从 raw 按需读取。
// SSE 端点 GET /api/events 的每条 data: 是一个 SyncEvent 的 JSON。

// 事件类型常量（对齐 schema 的 z.literal）
export class SyncEventType {
  static readonly SESSION_ADDED: string = 'session-added';
  static readonly SESSION_UPDATED: string = 'session-updated';
  static readonly SESSION_REMOVED: string = 'session-removed';
  static readonly MESSAGE_RECEIVED: string = 'message-received';
  static readonly MESSAGES_INVALIDATED: string = 'messages-invalidated';
  static readonly SCHEDULED_MATURED: string = 'scheduled-matured';
  static readonly SESSION_ENDED: string = 'session-ended';
  static readonly MACHINE_UPDATED: string = 'machine-updated';
  static readonly TOAST: string = 'toast';
  static readonly MESSAGES_CONSUMED: string = 'messages-consumed';
  static readonly MESSAGE_CANCELLED: string = 'message-cancelled';
  static readonly HEARTBEAT: string = 'heartbeat';
  static readonly CONNECTION_CHANGED: string = 'connection-changed';
}

// SSE 同步事件。type 必填（判别字段），其余字段按事件类型不同，统一存 raw 供上层按需读取。
export class SyncEvent {
  type: string = '';
  raw: Record<string, Object> = {};     // 原始解析结果

  // 便捷取字符串（缺失返回 ''）
  getString(key: string): string {
    const v = this.raw[key];
    return typeof v === 'string' ? v : '';
  }

  // 便捷取数字（缺失返回 0）
  getNumber(key: string): number {
    const v = this.raw[key];
    return typeof v === 'number' ? v : 0;
  }

  // 取嵌套对象（message / data 等），缺失返回 null
  getObject(key: string): Record<string, Object> | null {
    const v = this.raw[key];
    if (v !== null && v !== undefined && typeof v === 'object') {
      return v as Record<string, Object>;
    }
    return null;
  }

  // 常用字段便捷访问
  get sessionId(): string { return this.getString('sessionId'); }
  get machineId(): string { return this.getString('machineId'); }
  get namespace(): string { return this.getString('namespace'); }
}

// 解析 SSE data 文本为 SyncEvent。非法 JSON 或无 type 返回 null。
export function parseSyncEvent(json: string): SyncEvent | null {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return null;
  }
  const typeVal = raw['type'];
  if (typeof typeVal !== 'string') {
    return null;
  }
  const ev = new SyncEvent();
  ev.type = typeVal;
  ev.raw = raw;
  return ev;
}
