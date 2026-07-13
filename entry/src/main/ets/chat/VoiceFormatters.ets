// VoiceFormatters —— 语音上下文回灌文案格式化（纯层，无 @kit，可 LocalUnit 测）
// 对照 web/src/realtime/hooks/contextFormatters.ts（文案逐字移植）+
//      web/src/realtime/voiceConfig.ts（VOICE_CONFIG 静态配置）+ hooks/voiceHooks.ts（调用语义）。
//
// 运行于 ChatMessage（已解析形态），非上游的原始 content 信封：
//   - 覆盖 Claude agent 的主要形态（text 块 → 文案；tool_use 块 → 工具调用提示）与 user 文本。
//   - 已知限制：codex {type:'codex',data:{type:'message',message:string}} 等纯字符串 message 未被
//     parseMessage 提取为文本（models/Message extractTextFromObj 仅读 obj.text / content[] / obj.message(对象)），
//     此类 agent 消息 text 为空 → formatMessage 返 null（跳过）。根因修复应改 extractTextFromObj 读
//     obj.message 字符串分支（惠及聊天渲染+语音）；超出语音 Phase 3 范围，暂不扩。
//
// 调用语义（对照 voiceHooks.ts）：
//   - boot 初始上下文 = formatVoiceStartedContext（dynamicVariables.initialConversationContext）
//   - message-received → pushContext(formatNewMessages)        [sendContextualUpdate]
//   - 权限请求         → pushText(formatPermissionRequest)      [sendTextMessage，agent 须据此询问]
//   - ready(thinking→false) → pushText(formatReadyEvent)        [sendTextMessage]

import { ChatMessage } from '../models/Message';
import { NormalizedAgentContent } from './NormalizedContent';

// VOICE_CONFIG（对照上游 voiceConfig.ts，全为常量，无运行时可配）
const DISABLE_TOOL_CALLS: boolean = false;   // 工具调用信息是否完全不进上下文
const LIMITED_TOOL_CALLS: boolean = true;     // true=仅工具名；false=含入参 JSON
const MAX_HISTORY_MESSAGES: number = 50;       // 历史回灌最多条数（0=不限）

type VoiceRole = 'assistant' | 'user';

// role → 前缀文案（对照 formatPlainText，逐字）
function formatPlainText(role: VoiceRole, text: string): string {
  if (role === 'assistant') {
    return 'Claude Code: \n<text>' + text + '</text>';
  }
  return 'User sent message: \n<text>' + text + '</text>';
}

// JSON.stringify 工具入参（input 可能为 null）——对照上游 JSON.stringify(item.input)
function stringifyToolInput(input: Record<string, Object> | null): string {
  if (input === null) { return 'null'; }
  try {
    return JSON.stringify(input);
  } catch (e) {
    return 'null';
  }
}

// 单条消息 → 可朗读文案行（可能多行），无可朗读内容返 null（对照 formatMessage）
//   user：text → "User sent message: ..."；agent：遍历 blocks，text 块 + tool-call 块；event：null。
export function formatMessage(m: ChatMessage): string | null {
  if (m.role === 'user') {
    const text: string = m.text.trim();
    return text !== '' ? formatPlainText('user', text) : null;
  }
  if (m.role === 'agent') {
    const lines: string[] = [];
    const blocks: NormalizedAgentContent[] = m.blocks;
    for (let i = 0; i < blocks.length; i++) {
      const b: NormalizedAgentContent = blocks[i];
      if (b.type === 'text') {
        const t: string = b.text.trim();
        if (t !== '') { lines.push(formatPlainText('assistant', t)); }
      } else if (b.type === 'tool-call' && !DISABLE_TOOL_CALLS) {
        const name: string = b.name !== '' ? b.name : 'unknown';
        if (LIMITED_TOOL_CALLS) {
          lines.push('Claude Code is using ' + name);
        } else {
          lines.push('Claude Code is using ' + name + ' with arguments: <arguments>'
            + stringifyToolInput(b.input) + '</arguments>');
        }
      }
    }
    if (lines.length === 0) {
      // 兜底：blocks 为空但 m.text 有值（非标准形态）→ 整条作 assistant 文本
      const t: string = m.text.trim();
      return t !== '' ? formatPlainText('assistant', t) : null;
    }
    return lines.join('\n\n');
  }
  return null;   // event 无文案
}

// 反向取最新可朗读 agent 文本（对照 extractLastAssistantSpeakable）：text 块用 \n\n 拼
export function extractLastAssistantSpeakable(messages: ChatMessage[]): string | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const m: ChatMessage = messages[i];
    if (m.role !== 'agent') { continue; }
    const parts: string[] = [];
    const blocks: NormalizedAgentContent[] = m.blocks;
    for (let j = 0; j < blocks.length; j++) {
      const b: NormalizedAgentContent = blocks[j];
      if (b.type === 'text') {
        const t: string = b.text.trim();
        if (t !== '') { parts.push(t); }
      }
    }
    if (parts.length > 0) { return parts.join('\n\n'); }
    const t2: string = m.text.trim();
    if (t2 !== '') { return t2; }
  }
  return null;
}

// 按 seq 升序拷贝（不改入参；seq 缺省 0）
function sortBySeq(messages: ChatMessage[]): ChatMessage[] {
  const copy: ChatMessage[] = messages.slice();
  copy.sort((a: ChatMessage, b: ChatMessage): number => { return a.seq - b.seq; });
  return copy;
}

// 新单条消息回灌（对照 formatNewSingleMessage）
export function formatNewSingleMessage(sessionId: string, m: ChatMessage): string | null {
  const f: string | null = formatMessage(m);
  if (f === null) { return null; }
  return 'New message in session: ' + sessionId + '\n\n' + f;
}

// 新消息批量回灌（对照 formatNewMessages）：按 seq 排序，过滤 null
export function formatNewMessages(sessionId: string, messages: ChatMessage[]): string | null {
  const sorted: ChatMessage[] = sortBySeq(messages);
  const lines: string[] = [];
  for (let i = 0; i < sorted.length; i++) {
    const f: string | null = formatMessage(sorted[i]);
    if (f !== null) { lines.push(f); }
  }
  if (lines.length === 0) { return null; }
  return 'New messages in session: ' + sessionId + '\n\n' + lines.join('\n\n');
}

// 历史回灌（对照 formatHistory）：取最近 MAX_HISTORY_MESSAGES 条
export function formatHistory(sessionId: string, messages: ChatMessage[]): string {
  const sorted: ChatMessage[] = sortBySeq(messages);
  const slice: ChatMessage[] = MAX_HISTORY_MESSAGES > 0 && sorted.length > MAX_HISTORY_MESSAGES
    ? sorted.slice(sorted.length - MAX_HISTORY_MESSAGES) : sorted;
  const lines: string[] = [];
  for (let i = 0; i < slice.length; i++) {
    const f: string | null = formatMessage(slice[i]);
    if (f !== null) { lines.push(f); }
  }
  return 'History of messages in session: ' + sessionId + '\n\n' + lines.join('\n\n');
}

// 整会话回灌（对照 formatSessionFull）—— session 字段（id/path/summary）由调用方传入，保持纯、不依赖 Session 类
export function formatSessionFull(sessionId: string, path: string, summary: string,
  messages: ChatMessage[]): string {
  const lines: string[] = [];
  lines.push('# Session ID: ' + sessionId);
  lines.push('# Project path: ' + path);
  lines.push('# Session summary:\n' + summary);
  if (summary !== '') {
    lines.push('## Session Summary');
    lines.push(summary);
    lines.push('');
  }
  lines.push('## Our interaction history so far');
  lines.push('');
  lines.push(formatHistory(sessionId, messages));
  return lines.join('\n\n');
}

// onVoiceStarted 初始上下文（对照 voiceHooks.onVoiceStarted 返回值）—— boot 时灌入 initialConversationContext
export function formatVoiceStartedContext(sessionId: string, path: string, summary: string,
  messages: ChatMessage[]): string {
  return 'THIS IS AN ACTIVE SESSION: \n\n' + formatSessionFull(sessionId, path, summary, messages);
}

// 权限请求回灌（对照 formatPermissionRequest，逐字）—— 走 pushText，agent 须据此询问 allow/deny
//   toolArgs 为调用方 JSON.stringify 后的串（上游用 JSON.stringify(toolArgs)）
export function formatPermissionRequest(sessionId: string, requestId: string, toolName: string,
  toolArgs: string): string {
  return 'Claude Code is requesting permission to use ' + toolName + ' (session ' + sessionId + '):\n'
    + '<request_id>' + requestId + '</request_id>\n'
    + '<tool_name>' + toolName + '</tool_name>\n'
    + '<tool_args>' + toolArgs + '</tool_args>';
}

// ready 事件回灌（对照 formatReadyEvent）—— thinking true→false 触发
export function formatReadyEvent(sessionId: string, lastAssistantText: string | null): string {
  const trimmed: string = lastAssistantText !== null ? lastAssistantText.trim() : '';
  if (trimmed !== '') {
    return 'The coding agent finished working in session: ' + sessionId
      + '. Summarize this for the human immediately:\n<text>' + trimmed + '</text>';
  }
  return 'The coding agent finished working in session: ' + sessionId
    + '. Use the latest agent message already present in context and summarize it for the human immediately.';
}

// 会话状态回灌（对照 formatSessionOnline/Offline/Focus）—— 上游 DISABLE_SESSION_STATUS=true 通常不触发 online/offline
export function formatSessionOffline(sessionId: string): string {
  return 'Session went offline: ' + sessionId;
}
export function formatSessionOnline(sessionId: string): string {
  return 'Session came online: ' + sessionId;
}
export function formatSessionFocus(sessionId: string): string {
  return 'Session became focused: ' + sessionId;
}
