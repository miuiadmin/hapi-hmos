import { pickStr, pickNum, pickObj, AttachmentMetadata } from './Types';
import { NormalizedAgentContent } from '../chat/NormalizedContent';
import { CodexReview, parseCodexReviewMessage } from '../chat/CodexReview';
import { parseAttachmentsFromContent } from '../chat/AttachmentFormat';
import { t } from '../i18n/Translate';

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
  invokedAt: number = 0;         // 0 = 未被 CLI 消费（排队中）；现代 hub null→0 语义一致
  scheduledAt: number = 0;       // 0 = 无定时（即时排队或已发出）；>0 = 定时发送 epoch-ms（对照 SendMessageRequest.scheduledAt）
  status: MessageStatus = 'sent';
  isOptimistic: boolean = false;
  // agent 消息的归一化内容块（text/reasoning/tool-call/tool-result）；user/event 为空。
  // reducer 据此把 tool-call + tool-result（按 id=tool_use_id）合并成有状态的工具卡。
  blocks: NormalizedAgentContent[] = [];

  // agent 消息的 Token 用量（对齐 web NormalizedMessage.usage；user/event 为 null）。
  //   由 parseUsage 从 data.message.usage 提取；ContextStatusBar 据最新可见 usage 显上下文占比/告警。
  usage: UsageData | null = null;

  // agent 消息的模型名（对齐 web NormalizedMessage.model；从 data.model 提取，user/event 为 ''）。
  //   消息脚注 Model 用之；REST 历史 data 无 model 时为 ''，UI 回退会话 model（parseMessage 尽力解析）。
  model: string = '';

  // 消息来源标记（对齐 web msg.meta.sentFrom；''=未标记）。'cli' = CLI 注入的命令输出消息，
  //   reducerCliOutput 据此（AND 标签）门控产出 cli-output ChatBlock。由 content 信封 meta.sentFrom 解析。
  sentFrom: string = '';

  // user 消息的附件（对齐 web content.content.attachments；agent/event 为空）。
  //   仅 user 侧（agent 产图走 generated-image 块、改文件走 tool-call）。parseMessage 从 inner.attachments 解析；
  //   乐观消息在发送端填 previewUrl（data: URI），使「刚发的图」立即在历史里显缩略图。Reducer 透传到 user-text 块。
  attachments: AttachmentMetadata[] = [];

  // 是否排队中（user 消息 invokedAt 为空且未失败，对照 isQueuedForInvocation）
  get isQueued(): boolean {
    return this.role === 'user' && this.invokedAt === 0 && this.status !== 'failed';
  }
}

// 发送消息请求体（对齐 shared SendMessageRequestSchema）
//   scheduledAt：>0 = 定时发送（epoch-ms，须 >0、≤7 天、须带 localId、禁附件）；0 = 省略（即时）。
//   注：实际请求体由 HubClient 构建 Record，scheduledAt===0 时**不序列化**（上游 refine：scheduledAt==null 放行，
//   若发 0 会撞 positive 校验 → 400）。本类仅作类型文档。
export class SendMessageRequest {
  text: string = '';
  localId: string = '';
  scheduledAt: number = 0;
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
  c.scheduledAt = m.scheduledAt;
  c.status = m.status;
  c.isOptimistic = m.isOptimistic;
  c.blocks = m.blocks;            // 浅拷贝引用：blocks 解析后不可变，无需深拷
  c.usage = m.usage;              // 浅拷贝引用：UsageData 解析后不可变，无需深拷
  c.model = m.model;
  c.sentFrom = m.sentFrom;
  c.attachments = m.attachments;    // 浅拷贝引用：AttachmentMetadata 解析后不可变，无需深拷
  return c;
}

// —— Token / 上下文用量（对齐 web/src/chat/types.ts UsageData + reducer.ts calculateContextSize）——
// ArkTS 无 optional number：可选数值字段用 -1 哨兵表示缺省（< 0）。input/output 上游必填——
//   解析时缺任一则整条 usage 视为无（parseUsage 返 null，对照 web normalizeAssistant「inputTokens !== null」门）。
export class UsageData {
  inputTokens: number = 0;
  outputTokens: number = 0;
  cacheCreation: number = 0;
  cacheRead: number = 0;
  contextTokens: number = -1;     // < 0 = 缺省（context_tokens）
  contextWindow: number = -1;     // < 0 = 缺省（context_window；缺则按 model/flavor 静态回退）
  scopeRole: string = '';         // 'child' = 子链不并入父上下文（对照 isUsageVisibleInParentContext）
  serviceTier: string = '';       // 计费档（usage.service_tier；'standard' 不显示，对照上游 MessageMetadata）

  // 父上下文是否可见（对照 reducer.ts:18 isUsageVisibleInParentContext：scope_role !== 'child'）
  get isVisibleInParent(): boolean {
    return this.scopeRole !== 'child';
  }

  // 上下文用量（对照 reducer.ts:11 calculateContextSize：有 context_tokens 用之，否则 cache_creation+cache_read+input）
  get contextSize(): number {
    if (this.contextTokens >= 0) { return this.contextTokens; }
    return this.cacheCreation + this.cacheRead + this.inputTokens;
  }
}

// 从 data.message.usage 提取用量（input/output 必填，缺任一返 null；对照 normalizeAgent.ts:258-279）
export function parseUsage(message: Record<string, Object>): UsageData | null {
  const usageRaw: Record<string, Object> | null = pickObj(message, 'usage');
  if (usageRaw === null) { return null; }
  const inVal: Object = usageRaw['input_tokens'];
  if (typeof inVal !== 'number') { return null; }   // input_tokens 必填（Object→number 单变量收窄，同 parseTodoList idVal 模式）
  const outVal: Object = usageRaw['output_tokens'];
  if (typeof outVal !== 'number') { return null; }  // output_tokens 必填
  const u: UsageData = new UsageData();
  u.inputTokens = inVal;
  u.outputTokens = outVal;
  const cc: Object = usageRaw['cache_creation_input_tokens'];
  if (typeof cc === 'number') { u.cacheCreation = cc; }
  const cr: Object = usageRaw['cache_read_input_tokens'];
  if (typeof cr === 'number') { u.cacheRead = cr; }
  const ct: Object = usageRaw['context_tokens'];
  if (typeof ct === 'number') { u.contextTokens = ct; }
  const cw: Object = usageRaw['context_window'];
  if (typeof cw === 'number') { u.contextWindow = cw; }
  const sr: string = pickStr(usageRaw, 'scope_role');
  if (sr !== '') { u.scopeRole = sr; }
  const tier: string = pickStr(usageRaw, 'service_tier');
  if (tier !== '') { u.serviceTier = tier; }
  return u;
}

// 从 Record 按候选 key 顺序取首个数值；无命中返 -1（哨兵=缺省）。
function pickFirstNum(r: Record<string, Object>, keys: string[]): number {
  for (let i = 0; i < keys.length; i++) {
    const v: Object = r[keys[i]];
    if (typeof v === 'number') { return v; }
  }
  return -1;
}

// Codex token_count 事件用量（对照 normalizeAgent.ts:54 normalizeCodexTokenUsage）。
//   info.last = 本回合用量（优先，匹配实时上下文条），info.total = 会话累计（百万级，旧负载回退）；
//   input/output 必填（缺则 null）；cache_read 可选；context_tokens 缺则回退 inputTokens；
//   context_window / scope_role 可选。cache_creation 恒 0（codex inputTokens 已含 cached，不重复计）。
export function normalizeCodexTokenUsage(info: Record<string, Object> | null,
  data: Record<string, Object> | null): UsageData | null {
  if (info === null) { return null; }
  // usageSource：last → lastTokenUsage → last_token_usage → total → totalTokenUsage → total_token_usage → info
  let usageSource: Record<string, Object> = info;
  const candidates: string[] = ['last', 'lastTokenUsage', 'last_token_usage',
    'total', 'totalTokenUsage', 'total_token_usage'];
  for (let i = 0; i < candidates.length; i++) {
    const o: Record<string, Object> | null = pickObj(info, candidates[i]);
    if (o !== null) { usageSource = o; break; }
  }
  const inputTokens: number = pickFirstNum(usageSource, ['inputTokens', 'input_tokens']);
  const outputTokens: number = pickFirstNum(usageSource, ['outputTokens', 'output_tokens']);
  if (inputTokens < 0 || outputTokens < 0) { return null; }   // 必填缺失 → 整条 usage 视为无
  const u: UsageData = new UsageData();
  u.inputTokens = inputTokens;
  u.outputTokens = outputTokens;
  u.cacheCreation = 0;
  const cacheRead: number = pickFirstNum(usageSource,
    ['cachedInputTokens', 'cached_input_tokens', 'cacheReadInputTokens', 'cache_read_input_tokens']);
  if (cacheRead >= 0) { u.cacheRead = cacheRead; }
  let contextTokens: number = pickFirstNum(info, ['contextTokens', 'context_tokens']);
  if (contextTokens < 0) { contextTokens = pickFirstNum(usageSource, ['contextTokens', 'context_tokens']); }
  u.contextTokens = contextTokens < 0 ? inputTokens : contextTokens;   // 缺则回退 inputTokens
  const contextWindow: number = pickFirstNum(info, ['modelContextWindow', 'model_context_window']);
  if (contextWindow >= 0) { u.contextWindow = contextWindow; }
  let scopeRole: string = '';
  if (data !== null) {
    scopeRole = pickStr(data, 'scope_role');
    if (scopeRole === '') { scopeRole = pickStr(data, 'scopeRole'); }
    if (scopeRole === '') {
      const scope: Record<string, Object> | null = pickObj(data, 'scope');
      if (scope !== null) { scopeRole = pickStr(scope, 'role'); }
    }
  }
  if (scopeRole !== '') { u.scopeRole = scopeRole; }
  return u;
}

// 反向遍历消息，取最新「父上下文可见」的 usage（对照 reducer.ts:164-180 latestUsage 循环）。
//   messages 每次整体重赋值（刷新策略）→ 由 ChatPage getter 读 this.messages 派生，无需手动维护。
export function latestVisibleUsage(messages: ChatMessage[]): UsageData | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const u: UsageData | null = messages[i].usage;
    if (u !== null && u.isVisibleInParent) {
      return u;
    }
  }
  return null;
}

// 上下文预算上限（对照 web/src/chat/modelConfig.ts getContextBudgetTokens）。
//   仅 claude/codex 有静态回退（其余返 null → UI 只显 ctx {size}，不算百分比/告警）。
//   headroom 10000 留余量，避免临近上限虚高自信（系统提示/工具开销等隐藏 token）。
const CONTEXT_HEADROOM_TOKENS: number = 10000;
const DEFAULT_CLAUDE_CONTEXT_WINDOW_TOKENS: number = 200000;
const LARGE_CLAUDE_CONTEXT_WINDOW_TOKENS: number = 1000000;
const DEFAULT_CODEX_CONTEXT_WINDOW_TOKENS: number = 258400;
export function getContextBudgetTokens(model: string, flavor: string): number | null {
  if (flavor === 'codex') {
    return Math.max(1, DEFAULT_CODEX_CONTEXT_WINDOW_TOKENS - CONTEXT_HEADROOM_TOKENS);
  }
  if (flavor !== 'claude') {
    return null;
  }
  const trimmed: string = model.trim();
  let windowTokens: number = -1;
  if (trimmed === '') {
    windowTokens = DEFAULT_CLAUDE_CONTEXT_WINDOW_TOKENS;
  } else if (trimmed.endsWith('[1m]')) {
    windowTokens = LARGE_CLAUDE_CONTEXT_WINDOW_TOKENS;   // sonnet[1m] / opus[1m] 预设
  } else if (trimmed === 'sonnet' || trimmed === 'opus') {
    windowTokens = DEFAULT_CLAUDE_CONTEXT_WINDOW_TOKENS; // claude 预设（无前缀）
  } else if (trimmed.startsWith('claude-')) {
    windowTokens = DEFAULT_CLAUDE_CONTEXT_WINDOW_TOKENS; // 完整 model id（claude-sonnet-4-…）
  } else {
    return null;
  }
  return Math.max(1, windowTokens - CONTEXT_HEADROOM_TOKENS);
}

// token 数紧凑显示（对照 StatusBar.tsx:120 formatTokenCount：≥1M→1.2M / ≥1k→12k / 原值）
export function formatTokenCount(value: number): string {
  if (value >= 1000000) { return `${(value / 1000000).toFixed(1)}M`; }
  if (value >= 1000) { return `${Math.round(value / 1000)}k`; }
  return String(value);
}

// —— 定时 / 排队消息（对照 web QueuedMessagesBar + sortQueuedMessages + lib/messages isQueuedForInvocation）——
//   isQueued 已在 ChatMessage getter：role==='user' && invokedAt===0 && status!=='failed'（即时排队 + 定时共用此态）。
//   排序：即时排队（无未来 scheduledAt）在前按 createdAt 升序；定时（scheduledAt>0）在后按 scheduledAt 升序。
export function sortQueuedMessages(list: ChatMessage[]): ChatMessage[] {
  const copy: ChatMessage[] = list.slice();
  copy.sort((a: ChatMessage, b: ChatMessage): number => {
    const aScheduled: boolean = a.scheduledAt > 0;
    const bScheduled: boolean = b.scheduledAt > 0;
    if (aScheduled !== bScheduled) { return aScheduled ? 1 : -1; }   // 即时在前、定时在后
    if (aScheduled) { return a.scheduledAt - b.scheduledAt; }
    return a.createdAt - b.createdAt;
  });
  return copy;
}

// 定时剩余时间紧凑显示（纯函数：传 now 便于测试）。对照 web「Scheduled for …」——移动端用相对时间更直观。
//   ≤0 = 已到时间（成熟/即将被发出）；<1h→N 分钟后；<1d→N 小时后；否则→N 天后。
export function formatScheduledIn(scheduledAt: number, now: number): string {
  if (scheduledAt <= 0) { return ''; }
  const diff: number = scheduledAt - now;
  if (diff <= 0) { return t('msg.scheduledDue'); }
  const mins: number = Math.round(diff / 60000);
  if (mins < 60) { return t('msg.scheduledInMins', { n: mins }); }
  const hours: number = Math.round(mins / 60);
  if (hours < 24) { return t('msg.scheduledInHours', { n: hours }); }
  const days: number = Math.round(hours / 24);
  return t('msg.scheduledInDays', { n: days });
}

// 取消排队消息响应（对照 shared CancelMessageResponse：cancelled | invoked 竞态分支）。
//   cancelled：已取消（含 localId，可能 null）；invoked：竞态失败——CLI 已消费，返回权威行（应恢复入 thread）。
export class CancelMessageResult {
  cancelled: boolean = false;
  localId: string = '';
  invokedMessage: ChatMessage | null = null;   // invoked 分支的权威消息（已 invokedAt，并入 thread）
}

export function parseCancelMessageResponse(json: string): CancelMessageResult {
  const r: CancelMessageResult = new CancelMessageResult();
  let raw: Record<string, Object>;
  try {
    raw = JSON.parse(json) as Record<string, Object>;
  } catch (e) {
    return r;
  }
  const status: string = pickStr(raw, 'status');
  if (status === 'cancelled') {
    r.cancelled = true;
    r.localId = pickStr(raw, 'localId');
  } else if (status === 'invoked') {
    r.cancelled = false;
    const msgRaw: Record<string, Object> | null = pickObj(raw, 'message');
    if (msgRaw !== null) {
      r.invokedMessage = parseMessage(msgRaw);
    }
  }
  return r;
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

// 从对象按 camelCase → snake_case 顺序取首个非空字符串；均无命中返 ''（generated-image 字段两种命名兼容）。
function pickStrFallback(r: Record<string, Object>, camel: string, snake: string): string {
  const a: string = pickStr(r, camel);
  if (a !== '') { return a; }
  return pickStr(r, snake);
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

  // 生成图片消息：data.type==='generated-image'，元数据在 data 顶层（imageId/fileName/mimeType），
  //   **不在 data.message.content[]** —— 须在 message 判空之前拦截（对照 web normalizeAgent.ts:558-578）。
  //   二进制不随报文传，渲染时按 imageId 单独 GET；此处只取元数据。字段兼容 snake_case。
  if (pickStr(data, 'type') === 'generated-image') {
    const imageId: string = pickStrFallback(data, 'imageId', 'image_id');
    if (imageId !== '') {
      const b: NormalizedAgentContent = new NormalizedAgentContent();
      b.type = 'generated-image';
      b.imageId = imageId;
      const fn: string = pickStrFallback(data, 'fileName', 'file_name');
      b.fileName = fn !== '' ? fn : 'generated-image';
      b.mimeType = pickStrFallback(data, 'mimeType', 'mime_type');
      blocks.push(b);
    }
    return blocks;
  }

  const message: Record<string, Object> | null = pickObj(data, 'message');
  if (message === null) {
    // 字符串 message（Codex 偶把 review JSON 当文本发：data.type==='message' && data.message 为字符串）。
    //   对照上游 normalizeAgent.ts:580-602：嗅探 parseCodexReviewMessage 命中 → codex-review 块；否则 → text 块。
    //   pickObj 对字符串返回 null，故在此拦截——否则字符串 message 会被整条丢弃（review 不可见）。
    const dataMessageStr: Object = data['message'];
    if (pickStr(data, 'type') === 'message' && typeof dataMessageStr === 'string') {
      const messageStr: string = dataMessageStr as string;
      const review: CodexReview | null = parseCodexReviewMessage(messageStr);
      if (review !== null) {
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'codex-review';
        b.review = review;
        blocks.push(b);
      } else if (messageStr !== '') {
        // 非 review 的字符串 message → 普通 agent-text（faithful：上游同分支返 text content 块）
        const b: NormalizedAgentContent = new NormalizedAgentContent();
        b.type = 'text';
        b.text = messageStr;
        blocks.push(b);
      }
    }
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

// 从 agent content（inner → data → message.usage）提取 Token 用量（导航同 extractAgentBlocks，
//   对照 normalizeAgent.ts:258 读 message.usage）。缺 usage 或必填字段 → null。
function extractAgentUsage(inner: Record<string, Object> | null): UsageData | null {
  if (inner === null) { return null; }
  const data: Record<string, Object> | null = pickObj(inner, 'data');
  if (data === null) { return null; }
  const message: Record<string, Object> | null = pickObj(data, 'message');
  if (message === null) { return null; }
  return parseUsage(message);
}

// 从 agent content（inner → data）提取模型名（对照 normalizeAgent.ts 读 data.model）。无 → ''。
function extractAgentModel(inner: Record<string, Object> | null): string {
  if (inner === null) { return ''; }
  const data: Record<string, Object> | null = pickObj(inner, 'data');
  if (data === null) { return ''; }
  return pickStr(data, 'model');
}
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
  const scheduledVal = raw['scheduledAt'];
  m.scheduledAt = typeof scheduledVal === 'number' ? scheduledVal : 0;

  // 解包角色信封 { role, content, meta? }（兼容 { message: { role, content } }）
  const contentRaw = raw['content'];
  let role = 'agent';
  let inner: Record<string, Object> | null = null;
  if (contentRaw !== null && contentRaw !== undefined && typeof contentRaw === 'object') {
    const env = contentRaw as Record<string, Object>;
    role = pickStr(env, 'role');
    if (role !== '') {
      inner = pickObj(env, 'content');
      // meta.sentFrom（CLI 来源标记，对照 web msg.meta.sentFrom；reducerCliOutput 据此门控 cli-output）
      const metaObj: Record<string, Object> | null = pickObj(env, 'meta');
      if (metaObj !== null) {
        m.sentFrom = pickStr(metaObj, 'sentFrom');
      }
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
    m.attachments = inner !== null ? parseAttachmentsFromContent(inner['attachments']) : [];
    m.status = m.invokedAt === 0 ? 'queued' : 'sent';
  } else if (normalizedRole === 'agent') {
    m.text = extractAgentText(inner);
    m.blocks = extractAgentBlocks(inner);
    m.usage = extractAgentUsage(inner);   // Token 用量（data.message.usage；缺必填字段则 null）
    m.model = extractAgentModel(inner);   // 模型名（data.model；REST 历史无则 ''，UI 回退会话 model）
    m.status = 'sent';
  } else {
    // event 消息：文本留空被列表过滤；token_count（codex 用量）提取 usage 供 ContextStatusBar。
    //   其余 event（api-error/ready/task_complete 等）无 usage。type 兼容下划线(token_count)/连字符(token-count)。
    m.text = '';
    m.status = 'sent';
    const innerType: string = inner !== null ? pickStr(inner, 'type') : '';
    if (innerType === 'token_count' || innerType === 'token-count') {
      const infoObj: Record<string, Object> | null = inner !== null ? pickObj(inner, 'info') : null;
      m.usage = normalizeCodexTokenUsage(infoObj, inner);
    }
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
