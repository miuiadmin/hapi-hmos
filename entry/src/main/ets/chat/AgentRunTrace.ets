// AgentRunTrace —— 对照 web/src/chat/reducerTimeline.ts（agent-run 段 + normalizeTraceMessage）
// 纯层（零 @kit）：Codex agent-run（spawn_agent/wait_agent 等）事件的状态机/字段读取/trace 展开 helper。
//   仅做无状态变换（读 event 字段、映射状态、展开 trace 伪消息、孤儿/噪声判定）；**不**触碰 block/Map 副作用——
//   建卡/合并/清理/递归 reduce 在 Reducer.handleAgentRunMessage（C2-C）内，本文件供其与单测共用。
// '' 哨兵表 null；camelCase+snake_case 双读（getEventString/getEventNumber 语义）；手写扫描器（禁 regex）。
//   时间戳 0 = 缺省（epoch-ms 恒 > 0）；工具状态缺省 'running'（对照 mapAgentRunStatusToToolState）。

import { ChatMessage } from '../models/Message';
import { ChatBlock, ToolState } from './ChatBlock';
import { NormalizedAgentContent } from './NormalizedContent';

// ===== event 字段读取（camelCase + snake_case 双写）=====

// 读字符串字段：camel 优先，否则 snake；皆缺/非串 → ''（替 getEventString 的 null）。导出供 Reducer 复用。
export function evStr(event: Record<string, Object>, camel: string, snake: string): string {
  const a: Object = event[camel];
  if (typeof a === 'string') { return a; }
  const b: Object = event[snake];
  if (typeof b === 'string') { return b; }
  return '';
}

// 读数字字段：camel 优先，否则 snake；皆缺/非数 → 0（0 = 缺省哨兵）。
function evNum(event: Record<string, Object>, camel: string, snake: string): number {
  const a: Object = event[camel];
  if (typeof a === 'number') { return a; }
  const b: Object = event[snake];
  if (typeof b === 'number') { return b; }
  return 0;
}

// event 是否含某 key（替 'xxx' in event）。JSON 无 undefined 值，故 typeof 判定等价。
function evHas(event: Record<string, Object>, key: string): boolean {
  const v: Object = event[key];
  return typeof v !== 'undefined';
}

// 折叠连续空白为单空格 + trim（替 /\s+/g → ' ' + trim；fingerprint 归一用）。逐 char 扫描。
function compactText(text: string): string {
  const out: string[] = [];
  let pendingSpace: boolean = false;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    const ws: boolean = code === 32 /* space */ || code === 9 /* \t */ || code === 10 /* \n */
      || code === 13 /* \r */ || code === 12 /* \f */ || code === 11 /* \v */;
    if (ws) {
      pendingSpace = true;
    } else {
      if (pendingSpace) {
        out.push(' ');
        pendingSpace = false;
      }
      out.push(text.charAt(i));
    }
  }
  return out.join('');
}

// ===== id 前缀（对照 reducerTimeline.ts:161-164 prefixAgentTraceId）=====

// trace 消息/工具 call id 加 `codex-agent:${agentId}:` 前缀（kind='trace'|'call'），保证全局唯一 +
//   tool-call/tool-call-result 同 callId 配对（reduceTimelineCore 按 id 合并）。已带前缀则原样返回（indexOf===0 替 startsWith）。
export function prefixAgentTraceId(agentId: string, kind: string, id: string): string {
  const prefix: string = 'codex-agent:' + agentId + ':';
  if (id.indexOf(prefix) === 0) { return id; }
  return prefix + kind + ':' + id;
}

// ===== 状态机（对照 reducerTimeline.ts:44-64）=====

// agent-run status → 工具状态。completed→completed；failed/error/canceled/cancelled/notFound/not_found→error；
//   pending→pending；缺省（含 null/''）→running。
export function mapAgentRunStatusToToolState(status: string): ToolState {
  if (status === 'completed') { return 'completed'; }
  if (status === 'failed' || status === 'error' || status === 'canceled' || status === 'cancelled'
    || status === 'notFound' || status === 'not_found') { return 'error'; }
  if (status === 'pending') { return 'pending'; }
  return 'running';
}

export function isTerminalAgentRunState(state: string): boolean {
  return state === 'completed' || state === 'error';
}

export function isNonTerminalAgentRunState(state: string): boolean {
  return state === 'running' || state === 'pending';
}

// ===== cardId 解析 + fallback↔named（对照 reducerTimeline.ts:36-42 + 476-528）=====

// fallback cardId 格式：有 agentId → `codex-agent:${agentId}`；无 → 消息自身 id（调用方传）。
export function getAgentRunCardId(event: Record<string, Object>, fallback: string): string {
  const c: string = evStr(event, 'cardId', 'card_id');
  return c !== '' ? c : fallback;
}

// 该 cardId 是否为「fallback」（= `codex-agent:${agentId}`，非 named）。无 agentId 恒非 fallback。
export function isFallbackAgentRunCardId(cardId: string, agentId: string): boolean {
  return agentId !== '' && cardId === 'codex-agent:' + agentId;
}

export function getAgentRunStartedAt(event: Record<string, Object>): number {
  return evNum(event, 'startedAt', 'started_at');   // 0 = 缺省
}

export function getAgentRunCompletedAt(event: Record<string, Object>): number {
  return evNum(event, 'completedAt', 'completed_at');   // 0 = 缺省
}

// 透传 summary/activity/activityKind（仅非空字段，对照 reducerTimeline.ts:100-111 getAgentRunDisplayPatch）。
//   Reducer 浅合并进 tool.input（agentId/agentStatus/statusText 在调用方拼），供 CodexAgent 卡副标题/活动显示。
export function getAgentRunDisplayPatch(event: Record<string, Object>): Record<string, Object> {
  const patch: Record<string, Object> = {};
  const summary: string = evStr(event, 'summary', 'summary');
  if (summary !== '') { patch['summary'] = summary; }
  const activity: string = evStr(event, 'activity', 'activity');
  if (activity !== '') { patch['activity'] = activity; }
  const activityKind: string = evStr(event, 'activityKind', 'activity_kind');
  if (activityKind !== '') { patch['activityKind'] = activityKind; }
  return patch;
}

// 无 agentId 的 start 事件去重指纹（对照 reducerTimeline.ts:113-132 getAgentRunFingerprint）：
//   优先 summary（原样）→ input.message（压缩空白）→ input.prompt（压缩）→ input.items[].text join \n\n（压缩）。皆缺 → ''。
export function getAgentRunFingerprint(event: Record<string, Object>): string {
  const summary: string = evStr(event, 'summary', 'summary');
  if (summary !== '') { return summary; }
  const inputObj: Object = event['input'];
  if (typeof inputObj === 'object' && inputObj !== null) {
    const input: Record<string, Object> = inputObj as Record<string, Object>;
    const msg: string = evStr(input, 'message', 'message');
    if (msg !== '') { return compactText(msg); }
    const prompt: string = evStr(input, 'prompt', 'prompt');
    if (prompt !== '') { return compactText(prompt); }
    const itemsObj: Object = input['items'];
    if (Array.isArray(itemsObj)) {
      const items: Object[] = itemsObj as Object[];
      let joined: string = '';
      for (let i = 0; i < items.length; i++) {
        const it: Object = items[i];
        if (typeof it === 'object' && it !== null) {
          const rec: Record<string, Object> = it as Record<string, Object>;
          const txt: Object = rec['text'];
          if (typeof txt === 'string') {
            joined += (joined !== '' ? '\n\n' : '') + txt;
          }
        }
      }
      if (joined !== '') { return compactText(joined); }
    }
  }
  return '';
}

// ===== update 噪声过滤 / 孤儿判定（对照 reducerTimeline.ts:66-159）=====

export function isAgentNotFoundUpdate(event: Record<string, Object>): boolean {
  const status: string = evStr(event, 'status', 'status');
  const activityKind: string = evStr(event, 'activityKind', 'activity_kind');
  return status === 'notFound' || status === 'not_found' || activityKind === 'not_found';
}

// 「工具型」update（wait_agent/send_input/resume_agent/close_agent/notFound）——无 agentId + fallback 时早丢弃。
export function isAgentToolOnlyUpdate(event: Record<string, Object>): boolean {
  const activityKind: string = evStr(event, 'activityKind', 'activity_kind');
  return activityKind === 'wait_agent' || activityKind === 'send_input'
    || activityKind === 'resume_agent' || activityKind === 'close_agent'
    || isAgentNotFoundUpdate(event);
}

// 块已终态 + 本次非终态 + activityKind 是 wait_agent/close_agent → 丢弃（终态后工具型噪声）。
export function shouldIgnoreAgentRunNonTerminalUpdateAfterTerminal(
  block: ChatBlock, nextState: ToolState, event: Record<string, Object>): boolean {
  if (block.tool === null) { return false; }
  if (!isTerminalAgentRunState(block.tool.state)) { return false; }
  if (isTerminalAgentRunState(nextState)) { return false; }
  const activityKind: string = evStr(event, 'activityKind', 'activity_kind');
  return activityKind === 'wait_agent' || activityKind === 'close_agent';
}

// close_agent 清扫事件（关闭 agent 后服务端下发的清扫）：activityKind close_agent/closed；
//   或 activityKind=canceled 且 (activity/statusText='Closed') 且 result 带 previous_status(previousStatus)。
export function isCloseAgentCleanupUpdate(event: Record<string, Object>): boolean {
  const activityKind: string = evStr(event, 'activityKind', 'activity_kind');
  if (activityKind === 'close_agent' || activityKind === 'closed') { return true; }
  if (activityKind === 'canceled') {
    const activity: string = evStr(event, 'activity', 'activity');
    const statusText: string = evStr(event, 'statusText', 'status_text');
    if (activity === 'Closed' || statusText === 'Closed') {
      const resultObj: Object = event['result'];
      if (typeof resultObj === 'object' && resultObj !== null) {
        const result: Record<string, Object> = resultObj as Record<string, Object>;
        if (evHas(result, 'previous_status') || evHas(result, 'previousStatus')) { return true; }
      }
    }
  }
  return false;
}

// 块已终态 + close 清扫事件 + 非 failed/error status → 丢弃。
export function shouldIgnoreAgentRunCloseCleanupAfterTerminal(
  block: ChatBlock, status: string, event: Record<string, Object>): boolean {
  if (block.tool === null) { return false; }
  if (!isTerminalAgentRunState(block.tool.state)) { return false; }
  if (!isCloseAgentCleanupUpdate(event)) { return false; }
  return status !== 'failed' && status !== 'error';
}

// 孤儿判定（对照 reducerTimeline.ts:149-159 isOrphanAgentRunBlock）：有 children / 有 result / 终态 /
//   input 已带 agentId → 非孤儿；否则孤儿（将被 removeAgentRunBlock 清理）。
export function isOrphanAgentRunBlock(block: ChatBlock): boolean {
  if (block.children.length > 0) { return false; }
  if (block.tool === null) { return true; }
  if (block.tool.result !== null) { return false; }
  if (block.tool.state === 'completed' || block.tool.state === 'error') { return false; }
  if (block.tool.input !== null) {
    const aid: string = evStr(block.tool.input, 'agentId', 'agent_id');
    if (aid !== '') { return false; }
  }
  return true;
}

// ===== normalizeTraceMessage（对照 reducerTimeline.ts:166-258）=====

// 把 trace 事件的 data.message 内层消息展开为 ChatMessage[]（预建 NormalizedAgentContent 块，端口简化免再 parse）。
//   内层 type：message/reasoning（字符串 message）→ agent text/reasoning 块；tool-call/tool-call-result（有 callId）
//   → tool-call/tool-result 块（callId 加前缀配对）；token_count/ready/task_complete/其它 → [] 丢弃（端口简化：
//   activity/statusText 已在父 CodexAgent 卡副标题显示，children 聚焦 text/reasoning/工具，避免重复）。
//   traceId = `codex-agent:${agentId}:trace:${data.id ?? sourceId:trace}`；reasoning 块 streamId = traceId。
export function normalizeTraceMessage(agentId: string, message: Object | null,
  sourceId: string, sourceCreatedAt: number): ChatMessage[] {
  if (typeof message !== 'object' || message === null) { return []; }
  const data: Record<string, Object> = message as Record<string, Object>;
  const dt: Object = data['type'];
  if (typeof dt !== 'string') { return []; }

  const dataIdObj: Object = data['id'];
  const dataId: string = typeof dataIdObj === 'string' ? dataIdObj : '';
  const traceId: string = prefixAgentTraceId(agentId, 'trace',
    dataId !== '' ? dataId : sourceId + ':trace');

  // message（字符串）→ agent text 块
  if (dt === 'message') {
    const msgTextObj: Object = data['message'];
    if (typeof msgTextObj !== 'string') { return []; }
    const m: ChatMessage = new ChatMessage();
    m.id = traceId; m.role = 'agent'; m.createdAt = sourceCreatedAt; m.status = 'sent';
    const b: NormalizedAgentContent = new NormalizedAgentContent();
    b.type = 'text'; b.text = msgTextObj;
    m.blocks = [b];
    return [m];
  }
  // reasoning（字符串）→ reasoning 块（streamId=traceId，供 reducer 快照合并）
  if (dt === 'reasoning') {
    const msgTextObj: Object = data['message'];
    if (typeof msgTextObj !== 'string') { return []; }
    const m: ChatMessage = new ChatMessage();
    m.id = traceId; m.role = 'agent'; m.createdAt = sourceCreatedAt; m.status = 'sent';
    const b: NormalizedAgentContent = new NormalizedAgentContent();
    b.type = 'reasoning'; b.text = msgTextObj; b.streamId = traceId;
    m.blocks = [b];
    return [m];
  }
  // tool-call（有 callId）→ tool-call 块（callId 加 call 前缀；name 缺省 'unknown'）
  if (dt === 'tool-call') {
    const callIdRawObj: Object = data['callId'];
    if (typeof callIdRawObj !== 'string') { return []; }
    const callId: string = prefixAgentTraceId(agentId, 'call', callIdRawObj);
    const nameObj: Object = data['name'];
    const name: string = typeof nameObj === 'string' ? nameObj : 'unknown';
    const inputObj: Object = data['input'];
    const input: Record<string, Object> | null = typeof inputObj === 'object' && inputObj !== null
      ? inputObj as Record<string, Object> : null;
    const m: ChatMessage = new ChatMessage();
    m.id = traceId; m.role = 'agent'; m.createdAt = sourceCreatedAt; m.status = 'sent';
    const b: NormalizedAgentContent = new NormalizedAgentContent();
    b.type = 'tool-call'; b.id = callId; b.name = name; b.input = input;
    m.blocks = [b];
    return [m];
  }
  // tool-call-result（有 callId）→ tool-result 块（tool_use_id = 同前缀 callId，与 tool-call 配对）
  if (dt === 'tool-call-result') {
    const callIdRawObj: Object = data['callId'];
    if (typeof callIdRawObj !== 'string') { return []; }
    const callId: string = prefixAgentTraceId(agentId, 'call', callIdRawObj);
    const outputObj: Object = data['output'];
    const output: Object | null = typeof outputObj !== 'undefined' ? outputObj : null;
    const isError: boolean = data['is_error'] === true;
    const m: ChatMessage = new ChatMessage();
    m.id = traceId; m.role = 'agent'; m.createdAt = sourceCreatedAt; m.status = 'sent';
    const b: NormalizedAgentContent = new NormalizedAgentContent();
    b.type = 'tool-result'; b.id = callId; b.content = output; b.isError = isError;
    m.blocks = [b];
    return [m];
  }
  // token_count / ready / task_complete / 其它 → []（端口简化丢弃）
  return [];
}
