import { pickStr, pickNum, pickObj } from './Types';
import { NormalizedAgentContent } from '../chat/NormalizedContent';

// Hapi 对话消息（对齐 shared/src/schemas.ts DecryptedMessage + web/src/chat 归一化）
// ArkTS 无 Zod：手写信封解包（替代 unwrapRoleWrappedRecordEnvelope）+ 各 role 文本提取
// 刷新策略：始终重新赋值 messages 数组（@Local 引用变化触发 ForEach 重渲染），不依赖字段级 @Trace

export type MessageRole = 'user' | 'agent' | 'event';
export type MessageStatus = 'queued' | 'sending' | 'sent' | 'failed';

// 对话消息（content 已解包扁平化为 role + text，便于 UI 渲染）
export class ChatMessage {
  id: string = '';               // 服务端 UUID；乐观消息暂用 localId
  localId: string = '';          // 客户端幂等 id（'local-' 前缀），无则 ''
  seq: number = 0;               // 会话内序号；乐观/null → 0
  role: MessageRole = 'user';
  text: string = '';             // 可显示文本（user.text；agent 各 text 块拼接）
  createdAt: number = 0;
  invokedAt: number = 0;         // 0 = 未被 CLI 消费（排队中）
  status: MessageStatus = 'sent';
  isOptimistic: boolean = false;
  // agent 消息的归一化内容块（text/reasoning/tool-call/tool-result）；user/event 为空。
  // reducer 据此把 tool-call + tool-result（按 id=tool_use_id）合并成有状态的工具卡。
  blocks: NormalizedAgentContent[] = [];

  // 是否排队中（user 消息 invokedAt 为空且未失败，对照 isQueuedForInvocation）
  get isQueued(): boolean {
    return this.role === 'user' && this.invokedAt === 0 && this.status !== 'failed';
  }
}

// 发送消息请求体（对齐 shared SendMessageRequestSchema）
export class SendMessageRequest {
  text: string = '';
  localId: string = '';
}

// 拷贝（用于不可变更新：改状态时复制再替换，避免就地改 @Trace）
export function cloneMessage(m: ChatMessage): ChatMessage {
  const c = new ChatMessage();
  c.id = m.id;
  c.localId = m.localId;
  c.seq = m.seq;
  c.role = m.role;
  c.text = m.text;
  c.createdAt = m.createdAt;
  c.invokedAt = m.invokedAt;
  c.status = m.status;
  c.isOptimistic = m.isOptimistic;
  c.blocks = m.blocks;            // 浅拷贝引用：blocks 解析后不可变，无需深拷
  return c;
}

// 从对象尽力提取文本（Anthropic 风格 content 数组的 text 块 / 直接 text 字段 / 嵌套 message）
function extractTextFromObj(obj: Record<string, Object>): string {
  const directText = obj['text'];
  if (typeof directText === 'string' && directText !== '') {
    return directText;
  }
  const contentArr = obj['content'];
  if (contentArr !== null && contentArr !== undefined && Array.isArray(contentArr)) {
    let result = '';
    const blocks = contentArr as Object[];
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i];
      if (b !== null && b !== undefined && typeof b === 'object') {
        const block = b as Record<string, Object>;
        if (pickStr(block, 'type') === 'text') {
          const t = pickStr(block, 'text');
          if (t !== '') {
            result += t;
          }
        }
      }
    }
    if (result !== '') {
      return result;
    }
  }
  const nested = pickObj(obj, 'message');
  if (nested !== null) {
    return extractTextFromObj(nested);
  }
  return '';
}

// agent content 形如 { type, data }；从 data 提取文本
function extractAgentText(inner: Record<string, Object> | null): string {
  if (inner === null) {
    return '';
  }
  const data = pickObj(inner, 'data');
  const source = data !== null ? data : inner;
  const text = extractTextFromObj(source);
  if (text !== '') {
    return text;
  }
  return extractTextFromObj(inner);
}

// 从 agent content（inner → data → message → content[]）提取归一化块（对照 web normalizeAssistant/normalizeUserOutput）
// 同时覆盖 assistant（text/thinking/tool_use）与 user（text/tool_result）两类 data.type：按每块的 type 产出。
function extractAgentBlocks(inner: Record<string, Object> | null): NormalizedAgentContent[] {
  const blocks: NormalizedAgentContent[] = [];
  if (inner === null) {
    return blocks;
  }
  const data: Record<string, Object> | null = pickObj(inner, 'data');
  if (data === null) {
    return blocks;
  }
  const message: Record<string, Object> | null = pickObj(data, 'message');
  if (message === null) {
    return blocks;
  }
  const contentArr: Object = message['content'];

  // content 为纯字符串（assistant 简单文本）
  if (typeof contentArr === 'string') {
    if (contentArr !== '') {
      const b: NormalizedAgentContent = new NormalizedAgentContent();
      b.type = 'text';
      b.text = contentArr;
      blocks.push(b);
    }
    return blocks;
  }
  if (contentArr === null || contentArr === undefined || !Array.isArray(contentArr)) {
    return blocks;
  }

  const list: Object[] = contentArr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item: Object = list[i];
    if (item === null || item === undefined || typeof item !== 'object') {
      continue;
    }
    const block: Record<string, Object> = item as Record<string, Object>;
    const bt: string = pickStr(block, 'type');

    if (bt === 'text') {
      const t: string = pickStr(block, 'text');
      if (t !== '') {
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'text';
        b.text = t;
        blocks.push(b);
      }
    } else if (bt === 'thinking') {
      // reasoning 块：v1 不渲染，保留数据供后续
      const t: string = pickStr(block, 'thinking');
      if (t !== '') {
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'reasoning';
        b.text = t;
        blocks.push(b);
      }
    } else if (bt === 'tool_use') {
      const id: string = pickStr(block, 'id');
      if (id !== '') {
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'tool-call';
        b.id = id;
        let name: string = pickStr(block, 'name');
        if (name === '') {
          name = 'Tool';
        }
        b.name = name;
        const inputVal: Object = block['input'];
        if (inputVal !== null && inputVal !== undefined && typeof inputVal === 'object') {
          b.input = inputVal as Record<string, Object>;
          const desc: Object = (inputVal as Record<string, Object>)['description'];
          if (typeof desc === 'string') {
            b.description = desc;
          }
        }
        blocks.push(b);
      }
    } else if (bt === 'tool_result') {
      const tuid: string = pickStr(block, 'tool_use_id');
      if (tuid !== '') {
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'tool-result';
        b.id = tuid;                // 合并键 = tool_use_id，与对应 tool-call.id 相等
        b.isError = block['is_error'] === true;
        // 结果内容：优先 data.toolUseResult（CLI 实际结果），否则 tool_result.content
        const tur: Object = data['toolUseResult'];
        if (tur !== undefined && tur !== null) {
          b.content = tur;
        } else {
          const c: Object = block['content'];
          if (c !== undefined) {
            b.content = c;
          }
        }
        blocks.push(b);
      }
    }
  }
  return blocks;
}

// 解析单条 DecryptedMessage（content 信封解包 + role 分流）
export function parseMessage(raw: Record<string, Object>): ChatMessage {
  const m = new ChatMessage();
  m.id = pickStr(raw, 'id');
  const seqVal = raw['seq'];
  m.seq = typeof seqVal === 'number' ? seqVal : 0;
  const localIdVal = raw['localId'];
  m.localId = typeof localIdVal === 'string' ? localIdVal : '';
  m.createdAt = pickNum(raw, 'createdAt');
  const invokedVal = raw['invokedAt'];
  m.invokedAt = typeof invokedVal === 'number' ? invokedVal : 0;

  // 解包角色信封 { role, content, meta? }（兼容 { message: { role, content } }）
  const contentRaw = raw['content'];
  let role = 'agent';
  let inner: Record<string, Object> | null = null;
  if (contentRaw !== null && contentRaw !== undefined && typeof contentRaw === 'object') {
    const env = contentRaw as Record<string, Object>;
    role = pickStr(env, 'role');
    if (role !== '') {
      inner = pickObj(env, 'content');
    } else {
      const msg = pickObj(env, 'message');
      if (msg !== null) {
        role = pickStr(msg, 'role');
        inner = pickObj(msg, 'content');
      }
    }
  }

  // 规范化 role（未知归 agent，对照 web normalize.ts）
  let normalizedRole: MessageRole = 'agent';
  if (role === 'user') {
    normalizedRole = 'user';
  } else if (role === 'event') {
    normalizedRole = 'event';
  }
  m.role = normalizedRole;

  if (normalizedRole === 'user') {
    m.text = inner !== null ? pickStr(inner, 'text') : '';
    m.status = m.invokedAt === 0 ? 'queued' : 'sent';
  } else if (normalizedRole === 'agent') {
    m.text = extractAgentText(inner);
    m.blocks = extractAgentBlocks(inner);
    m.status = 'sent';
  } else {
    // event 消息：MVP 不渲染（api-error/ready 等），文本留空被列表过滤
    m.text = '';
    m.status = 'sent';
  }
  return m;
}

// 从已解析的响应对象取 messages 数组，逐条 parseMessage 后按 seq（无则 createdAt）升序。
// 共享给 parseMessagesResponse（仅 messages）与 parseMessagesPageResponse（含分页元数据），避免重复 JSON.parse。
function parseMessagesFromRaw(raw: Record<string, Object>): ChatMessage[] {
  const arr = raw['messages'];
  if (arr === null || arr === undefined || !Array.isArray(arr)) {
    return [];
  }
  const result: ChatMessage[] = [];
  const list = arr as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && item !== undefined && typeof item === 'object') {
      result.push(parseMessage(item as Record<string, Object>));
    }
  }
  // 按 seq（无则 createdAt）升序，保证历史顺序
  result.sort((a: ChatMessage, b: ChatMessage): number => {
    const sa = a.seq > 0 ? a.seq : a.createdAt;
    const sb = b.seq > 0 ? b.seq : b.createdAt;
    return sa - sb;
  });
  return result;
}

// 解析 MessagesResponse { messages: [...] }（首屏便捷，不含分页元数据）
export function parseMessagesResponse(json: string): ChatMessage[] {
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  return parseMessagesFromRaw(raw);
}

// 分页响应（对齐 shared/src/apiTypes.ts MessagesResponse）
//   游标 nextBeforeAt/nextBeforeSeq 由服务端在 page 里给出，客户端成对透传给下一页请求。
//   beforeAt 语义 = COALESCE(invoked_at, created_at)（消息生效位置时间），与 ChatMessage.invokedAt/createdAt 对齐。
//   禁止本地重算游标：服务端那行的 (at,seq) 与本地 min seq 不一定是同一条（上游 message-window-store 注释明示）。
export class MessagesPage {
  messages: ChatMessage[] = [];
  nextBeforeAt: number = 0;     // 0 = 无更旧（服务端 null）
  nextBeforeSeq: number = 0;    // 0 = 无更旧
  hasMore: boolean = false;
}

// 解析分页响应 { messages:[...], page:{ limit, nextBeforeSeq, nextBeforeAt, hasMore } }
//   page 缺省（老服务端 / 异常体）→ hasMore=false、游标 0，仅返回已解析的 messages。
export function parseMessagesPageResponse(json: string): MessagesPage {
  const page = new MessagesPage();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return page;
  }
  page.messages = parseMessagesFromRaw(raw);
  const pageObj = pickObj(raw, 'page');
  if (pageObj !== null) {
    const nba = pageObj['nextBeforeAt'];
    page.nextBeforeAt = typeof nba === 'number' ? nba : 0;
    const nbs = pageObj['nextBeforeSeq'];
    page.nextBeforeSeq = typeof nbs === 'number' ? nbs : 0;
    page.hasMore = pageObj['hasMore'] === true;
  }
  return page;
}

// 合并一条新消息：按 id 去重；匹配乐观消息 localId 则替换；否则追加（返回新数组，触发 @Local 刷新）
export function mergeMessage(list: ChatMessage[], incoming: ChatMessage): ChatMessage[] {
  if (incoming.id !== '') {
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === incoming.id) {
        const copy = list.slice();
        copy[i] = incoming;
        return copy;
      }
    }
  }
  if (incoming.localId !== '') {
    for (let i = 0; i < list.length; i++) {
      if (list[i].isOptimistic && list[i].localId === incoming.localId) {
        const copy = list.slice();
        copy[i] = incoming;
        return copy;
      }
    }
  }
  return list.concat([incoming]);
}
