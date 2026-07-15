// Reducer —— 对齐 web/src/chat/reducer.ts + reducerTimeline.ts + reducerTools.ts
// 纯函数：喂 ChatMessage[] + AgentState → 产出全新 ChatBlock[]（每次调用新数组新对象，ChatPage 赋值即刷新）。
//
// 状态机要点（已读上游确认）：
//   block.state（执行生命周期 pending/running/completed/error）与 block.permission.status（权限生命周期）解耦。
//   「等用户批准」由 permission.status==='pending' 表达（footer 据此挂载），不由 state==='pending' 表达。
//   - tool-call 块：ensureToolBlock 后若 state==='pending' 翻为 running（pending 态仅孤儿卡保留）。
//   - tool-result 块：合并后强制 state=is_error?'error':'completed' + result。
//   - 孤儿权限卡（有权限无对应消息）：approved→completed(result='Approved')；denied/canceled→error(result={error:reason})；pending→pending。

import { ChatMessage, parseClaudeUsageLimit } from '../models/Message';
import { AgentEvent } from '../models/Types';
import { AgentState } from './AgentState';
import {
  ChatBlock,
  ChatBlockKind,
  ChatToolCall,
  ToolPermission,
  PermissionEntry,
  ToolState,
  PermissionStatus
} from './ChatBlock';
import { isCliOutputText, mergeCliOutputBlocks } from './CliOutput';
import { isSubagentToolName } from './SubagentTool';
import { traceAndGroup, TracedResult } from './Tracer';

// ===== getPermissions：agentState → Map<id, PermissionEntry>（completed 先、pending 后，completed 优先）=====
function getPermissions(agentState: AgentState | null): Map<string, PermissionEntry> {
  const map = new Map<string, PermissionEntry>();
  if (agentState === null) {
    return map;
  }
  // 已决请求优先写入
  const doneKeys: string[] = Object.keys(agentState.completedRequests);
  for (let i = 0; i < doneKeys.length; i++) {
    const id: string = doneKeys[i];
    const c = agentState.completedRequests[id];
    const p: ToolPermission = new ToolPermission();
    p.id = id;
    p.status = normalizeCompletedStatus(c.status);
    p.reason = c.reason;
    p.mode = c.mode;
    p.decision = c.decision;
    p.allowedTools = c.allowTools;
    p.answers = c.answers;
    p.createdAt = c.createdAt;
    p.completedAt = c.completedAt;
    const e: PermissionEntry = new PermissionEntry();
    e.toolName = c.tool;
    e.input = c.arguments;
    e.permission = p;
    map.set(id, e);
  }
  // 待决请求补齐（completed 已有则跳过）
  const reqKeys: string[] = Object.keys(agentState.requests);
  for (let i = 0; i < reqKeys.length; i++) {
    const id: string = reqKeys[i];
    if (map.has(id)) {
      continue;
    }
    const r = agentState.requests[id];
    const p: ToolPermission = new ToolPermission();
    p.id = id;
    p.status = 'pending';
    p.createdAt = r.createdAt;
    const e: PermissionEntry = new PermissionEntry();
    e.toolName = r.tool;
    e.input = r.arguments;
    e.permission = p;
    map.set(id, e);
  }
  return map;
}

// completed.status 枚举 canceled|denied|approved；未知 → canceled（已决、非批准）
function normalizeCompletedStatus(s: string): PermissionStatus {
  if (s === 'approved' || s === 'denied' || s === 'canceled') {
    return s;
  }
  return 'canceled';
}

function isPlaceholderToolName(name: string): boolean {
  const n: string = name.trim().toLowerCase();
  return n === '' || n === 'tool' || n === 'unknown';
}

// Object → Record<string,Object>（仅非数组对象；其余 → null）
function toInputRecord(obj: Object | null): Record<string, Object> | null {
  if (obj === null || obj === undefined) {
    return null;
  }
  if (typeof obj === 'object' && !Array.isArray(obj)) {
    return obj as Record<string, Object>;
  }
  return null;
}

// ===== ensureToolBlock：取/建工具卡，合并 permission/名/入参（对照 reducerTools.ensureToolBlock）=====
function ensureToolBlock(
  blocks: ChatBlock[],
  toolBlocksById: Map<string, ChatBlock>,
  id: string,
  createdAt: number,
  name: string,
  input: Object | null,
  description: string,
  permission: ToolPermission | null
): ChatBlock {
  const existing: ChatBlock | undefined = toolBlocksById.get(id);
  if (existing !== undefined && existing.tool !== null) {
    const tool: ChatToolCall = existing.tool;
    // 保最早 createdAt（稳定排序）
    if (createdAt < existing.createdAt) {
      existing.createdAt = createdAt;
      tool.createdAt = createdAt;
    }
    // 合并 permission（同 id 在单次 reduce 内 permission 恒定，主要为状态迁移：running+pending→pending）
    if (permission !== null) {
      tool.permission = permission;
      if (tool.state === 'running' && permission.status === 'pending') {
        tool.state = 'pending';
      }
    }
    // 占位名升级
    if (name !== '' && (!isPlaceholderToolName(name) || isPlaceholderToolName(tool.name))) {
      tool.name = name;
    }
    // 入参（非空才覆盖）
    if (input !== null) {
      tool.input = toInputRecord(input);
    }
    // 描述（非空才覆盖）
    if (description !== '') {
      tool.description = description;
    }
    return existing;
  }

  // 新建：初态据 permission.status（pending→pending；denied/canceled→error；其余→running）
  let initialState: ToolState = 'running';
  if (permission !== null) {
    if (permission.status === 'pending') {
      initialState = 'pending';
    } else if (permission.status === 'denied' || permission.status === 'canceled') {
      initialState = 'error';
    }
  }
  const tool: ChatToolCall = new ChatToolCall();
  tool.id = id;
  tool.name = name !== '' ? name : 'Tool';
  tool.state = initialState;
  tool.input = toInputRecord(input);
  tool.createdAt = createdAt;
  tool.startedAt = initialState === 'running' ? createdAt : 0;
  tool.completedAt = 0;
  tool.description = description;
  tool.permission = permission;

  const block: ChatBlock = new ChatBlock();
  block.kind = 'tool-call';
  block.id = id;
  block.createdAt = createdAt;
  block.tool = tool;

  toolBlocksById.set(id, block);
  blocks.push(block);
  return block;
}

// 最旧消息 createdAt（0 = 无消息或全空，作 null 哨兵）
function oldestCreatedAt(messages: ChatMessage[]): number {
  let min: number = 0;
  for (let i = 0; i < messages.length; i++) {
    const t: number = messages[i].createdAt;
    if (t > 0 && (min === 0 || t < min)) {
      min = t;
    }
  }
  return min;
}

// ===== reduceTimelineCore（可递归时间线核心）=====
// 递归 reduce 的共享上下文（对照上游 reduceTimeline 的 reducerContext）：
//   permissionsById 跨 root/children 共享（子代理权限也在此）；groups/consumedGroupIds 为 Flow A sidechain
//   归组服务（children 内的子代理消息 id 不在 root groups → children 内无二次分组，但共享 consumedGroupIds 防重复）。
class ReduceContext {
  permissionsById: Map<string, PermissionEntry> = new Map<string, PermissionEntry>();
  groups: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();
  consumedGroupIds: Set<string> = new Set<string>();
}

// reduceTimelineCore 返回：blocks（本层产出，push 进 result.blocks）+ toolIdsInMessages（本层见过 tool id）。
class ReduceTimelineResult {
  blocks: ChatBlock[] = [];
  toolIdsInMessages: Set<string> = new Set<string>();
}

// 现 reduceChatBlocks 的消息循环抽出为可递归函数：参数化 toolBlocksById/reasoningByStreamId（递归各传新 Map，
//   child 工具卡/reasoning 不与父层合并）；permissionsById/groups/consumedGroupIds 经 ctx 跨层共享。
//   blocks/toolIdsInMessages 写入并返回 result（孤儿权限卡判定用 toolIdsInMessages；toolBlocksById 由调用方持有）。
function reduceTimelineCore(
  messages: ChatMessage[],
  ctx: ReduceContext,
  toolBlocksById: Map<string, ChatBlock>,
  reasoningByStreamId: Map<string, ChatBlock>
): ReduceTimelineResult {
  const result: ReduceTimelineResult = new ReduceTimelineResult();
  const blocks: ChatBlock[] = result.blocks;
  const toolIdsInMessages: Set<string> = result.toolIdsInMessages;

  // 按消息顺序、每条 blocks 顺序遍历（插入序，不排序）
  for (let mi = 0; mi < messages.length; mi++) {
    const msg: ChatMessage = messages[mi];

    // user 消息：CLI 命令输出（sentFrom==='cli' 且含 CLI 标签）→ cli-output 块（source='user'）；否则一行文本气泡
    if (msg.role === 'user') {
      if (isCliOutputText(msg.text, msg.sentFrom)) {
        blocks.push(ChatBlock.cliOutput(msg.id, msg.createdAt, msg.text, 'user'));
      } else if (msg.text !== '' || msg.attachments.length > 0) {
        // 纯图消息（text 空、有附件）也产出 user-text 块以渲染附件（对照 web：text 可空，附件照常渲染）
        const ub: ChatBlock = ChatBlock.userText(msg.id, msg.createdAt, msg.text);
        ub.userOptimistic = msg.isOptimistic;
        ub.userStatus = msg.status;
        ub.attachments = msg.attachments;
        blocks.push(ub);
      }
      continue;
    }
    // event 消息：turn-duration event 回填目标块耗时（对照 reducerTimeline.ts:443-468）；
    //   携带 agent 事件（api-error/microcompact/compact）→ 居中灰条系统消息块（#1）。
    if (msg.role === 'event') {
      if (msg.turnDurationMs >= 0) {
        applyTurnDuration(blocks, msg.turnDurationTargetId, msg.turnDurationMs);
      }
      if (msg.event !== null) {
        blocks.push(ChatBlock.agentEvent(msg.id, msg.createdAt, msg.event));
      }
      continue;
    }
    if (msg.role !== 'agent') {
      continue;
    }

    for (let bi = 0; bi < msg.blocks.length; bi++) {
      const c = msg.blocks[bi];

      if (c.type === 'text') {
        if (c.text !== '') {
          // 用量限额文本嗅探（对照 reducerEvents.ts parseMessageAsEvent）：命中「Claude AI usage limit ...」
          //   → limit agent-event 块（#4 限额提示），不再产 agent-text。命中文本极特定，误伤可忽略。
          const limitEv: AgentEvent | null = parseClaudeUsageLimit(c.text);
          if (limitEv !== null) {
            blocks.push(ChatBlock.agentEvent(`${msg.id}:${bi}`, msg.createdAt, limitEv));
          } else if (isCliOutputText(c.text, msg.sentFrom)) {
            // CLI 命令输出（sentFrom==='cli' 且含 CLI 标签）→ cli-output 块（source='assistant'）；否则 agent-text
            blocks.push(ChatBlock.cliOutput(`${msg.id}:${bi}`, msg.createdAt, c.text, 'assistant'));
          } else {
            blocks.push(ChatBlock.agentText(`${msg.id}:${bi}`, msg.createdAt, c.text, msg.invokedAt, msg.model, msg.usage));
          }
        }
      } else if (c.type === 'reasoning') {
        // 思考过程块（对照上游 reasoning.tsx）：非空才产出（空 thinking 不渲染，同 text 块处理）。
        //   streamId 流式合并（对照 reducerTimeline.ts:756-785）：同 streamId 的后续快照替换既有块的
        //   text（snapshot-replace，非 append）→ 单个会刷新的气泡；无 streamId（Claude thinking）每块独立。
        if (c.text !== '') {
          if (c.streamId !== '' && reasoningByStreamId.has(c.streamId)) {
            const existing: ChatBlock | undefined = reasoningByStreamId.get(c.streamId);
            if (existing !== undefined) {
              existing.text = c.text;   // 快照替换
            }
          } else {
            const rb: ChatBlock = ChatBlock.reasoning(`${msg.id}:${bi}`, msg.createdAt, c.text);
            blocks.push(rb);
            if (c.streamId !== '') {
              reasoningByStreamId.set(c.streamId, rb);
            }
          }
        }
      } else if (c.type === 'summary') {
        // Codex summary 压缩摘要 → 居中灰条系统消息（对照 reducerTimeline.ts:803-814：映射为
        //   agent-event {type:'message', message}）。复用 #1 灰条基础设施 + 既有 dedupe 通用键去重。
        if (c.summary !== '') {
          const ev: AgentEvent = new AgentEvent();
          ev.type = 'message';
          ev.message = c.summary;
          blocks.push(ChatBlock.agentEvent(`${msg.id}:${bi}`, msg.createdAt, ev));
        }
      } else if (c.type === 'generated-image') {
        // 生成图片块（对照上游 reducerTimeline.ts:741-753）：id 同 agent-text 方案 `${msg.id}:${idx}`；
        //   imageId 非空才产出（缺 id 无法拉二进制）。二进制按 imageId 渲染时按需 GET。
        if (c.imageId !== '') {
          blocks.push(ChatBlock.generatedImage(`${msg.id}:${bi}`, msg.createdAt, c.imageId, c.fileName, c.mimeType));
        }
      } else if (c.type === 'codex-review') {
        // Codex review 块（对照上游 reducerTimeline.ts:788-793）：parse 时已嗅探命中并解析；
        //   review 非空才产出（全空 marker 的已被 parseCodexReviewJson 过滤为 null，不产 block）。
        if (c.review !== null) {
          blocks.push(ChatBlock.codexReview(`${msg.id}:${bi}`, msg.createdAt, c.review));
        }
      } else if (c.type === 'tool-call') {
        toolIdsInMessages.add(c.id);
        const entry: PermissionEntry | undefined = ctx.permissionsById.get(c.id);
        const permission: ToolPermission | null = entry !== undefined ? entry.permission : null;
        const block: ChatBlock = ensureToolBlock(blocks, toolBlocksById, c.id,
          msg.createdAt, c.name, c.input, c.description, permission);
        // tool-call 到达 → 工具已发起；pending 态翻为 running（等用户批准由 permission.status 表达）
        if (block.tool !== null && block.tool.state === 'pending') {
          block.tool.state = 'running';
          block.tool.startedAt = msg.createdAt;
        }
        // Flow A 子代理 children（对照 reducerTimeline.ts:853-861）：Task/Agent 工具卡 + 本消息 id 有 sidechain
        //   归组 → 递归 reduce 该组为 block.children。consumedGroupIds 防同组多次 reduce；递归传新 toolBlocksById/
        //   reasoningByStreamId（child 卡不与父层合并），共享 ctx（子代理权限 + 防重复归组）。
        if (isSubagentToolName(c.name) && !ctx.consumedGroupIds.has(msg.id)) {
          const group: ChatMessage[] | undefined = ctx.groups.get(msg.id);
          if (group !== undefined && group.length > 0) {
            ctx.consumedGroupIds.add(msg.id);
            const childTB: Map<string, ChatBlock> = new Map<string, ChatBlock>();
            const childRS: Map<string, ChatBlock> = new Map<string, ChatBlock>();
            block.children = reduceTimelineCore(group, ctx, childTB, childRS).blocks;
          }
        }
      } else if (c.type === 'tool-result') {
        toolIdsInMessages.add(c.id);
        const entry: PermissionEntry | undefined = ctx.permissionsById.get(c.id);
        const toolName: string = entry !== undefined && entry.toolName !== '' ? entry.toolName : 'Tool';
        const inputObj: Object | null = entry !== undefined ? entry.input : null;
        const permission: ToolPermission | null = entry !== undefined ? entry.permission : null;
        const block: ChatBlock = ensureToolBlock(blocks, toolBlocksById, c.id,
          msg.createdAt, toolName, inputObj, '', permission);
        // 结果到达 → 终态（error / completed）+ 结果内容
        if (block.tool !== null) {
          block.tool.result = c.content;
          block.tool.completedAt = msg.createdAt;
          block.tool.state = c.isError ? 'error' : 'completed';
        }
      }
    }
  }

  return result;
}

// ===== 主入口：reduceChatBlocks =====
// trace+group（Flow A sidechain 归组）→ reduceTimelineCore(root) → 孤儿权限卡 → 后处理。
//   oldestCreatedAt 仍用原 messages（含 sidechain，保现有语义）。reducer 仍纯层零 @kit。
export function reduceChatBlocks(messages: ChatMessage[], agentState: AgentState | null): ChatBlock[] {
  const permissionsById: Map<string, PermissionEntry> = getPermissions(agentState);
  const traced: TracedResult = traceAndGroup(messages);
  const ctx: ReduceContext = new ReduceContext();
  ctx.permissionsById = permissionsById;
  ctx.groups = traced.groups;
  ctx.consumedGroupIds = new Set<string>();
  const toolBlocksById: Map<string, ChatBlock> = new Map<string, ChatBlock>();
  const reasoningByStreamId: Map<string, ChatBlock> = new Map<string, ChatBlock>();
  const core: ReduceTimelineResult = reduceTimelineCore(traced.root, ctx, toolBlocksById, reasoningByStreamId);
  const blocks: ChatBlock[] = core.blocks;
  const toolIdsInMessages: Set<string> = core.toolIdsInMessages;

  // 孤儿权限卡：permissionsById 中未出现在任何消息 tool id 的（且不早于最旧消息），末尾补卡
  const oldest: number = oldestCreatedAt(messages);
  permissionsById.forEach((entry: PermissionEntry, id: string) => {
    if (toolIdsInMessages.has(id)) {
      return;
    }
    if (toolBlocksById.has(id)) {
      return;
    }
    const permCreatedAt: number = entry.permission.createdAt; // 0 = 未知
    // 早于当前视图最旧消息的权限跳过（分页加载旧消息时再显示）
    if (oldest > 0 && permCreatedAt > 0 && permCreatedAt < oldest) {
      return;
    }
    const createdAt: number = permCreatedAt > 0 ? permCreatedAt : (oldest > 0 ? oldest : 0);
    const block: ChatBlock = ensureToolBlock(blocks, toolBlocksById, id,
      createdAt, entry.toolName, entry.input, '', entry.permission);
    if (block.tool === null) {
      return;
    }
    const st: PermissionStatus = entry.permission.status;
    if (st === 'approved') {
      block.tool.state = 'completed';
      block.tool.completedAt = entry.permission.completedAt > 0 ? entry.permission.completedAt : createdAt;
      if (block.tool.result === null) {
        block.tool.result = 'Approved';
      }
    } else if (st === 'denied' || st === 'canceled') {
      block.tool.state = 'error';
      block.tool.completedAt = entry.permission.completedAt > 0 ? entry.permission.completedAt : createdAt;
      if (block.tool.result === null && entry.permission.reason !== '') {
        const errObj: Record<string, string> = { 'error': entry.permission.reason };
        block.tool.result = errObj;
      }
    }
    // pending 孤儿卡：state 保持 ensureToolBlock 设的 pending，permission.status=pending（footer 据此挂载）
  });

  // 后处理（对照 reducer.ts:183 dedupeAgentEvents(foldApiErrorEvents(...))）：
  //   合并相邻 cli-output → 折叠连续 api-error 事件（留最新）→ 去重相邻同键 agent-event。
  //   mergeCliOutput 鸿蒙独有，与 agent-event 块不相交，先后无碍。
  return dedupeAgentEvents(foldApiErrorEvents(mergeCliOutputBlocks(blocks)));
}

// ===== turn-duration 回填（对照 web reducerTimeline.ts:443-468）=====
// event/turn_duration 消息带 targetMessageId + durationMs，需回填到本次 agent turn 产出的块。
// 回填后 MessageMetadata 脚注据此显 Duration。单趟遍历可行：event 在其 agent turn 之后到达，
// 目标块已在 blocks 中。

// 可挂耗时的块类型（对照 reducerTimeline isDurationTarget）：agent 正文 / 推理 / review / cli 输出 / 工具调用。
export function isDurationTargetKind(kind: ChatBlockKind): boolean {
  return kind === 'agent-text' || kind === 'reasoning' || kind === 'codex-review' ||
    kind === 'cli-output' || kind === 'tool-call';
}

// 回填目标块耗时。匹配优先级（与上游一致）：
//   1. targetId 非空 → block.id 精确或 id.startsWith(targetId+':')（agent-text 的 `${msgId}:${idx}` 前缀命中）；
//   2. targetId 非空且上未命中 → tool-call 块 tool.id === targetId；
//   3. targetId 空 / 上都未命中 → 最后一个 duration-target 块。
// 反向手写查找（ArkTS 无 findLastIndex）。
export function applyTurnDuration(blocks: ChatBlock[], targetId: string, durationMs: number): void {
  if (blocks.length === 0) {
    return;
  }
  if (targetId !== '') {
    const prefix = targetId + ':';
    for (let i = blocks.length - 1; i >= 0; i--) {
      const b: ChatBlock = blocks[i];
      if (isDurationTargetKind(b.kind) && (b.id === targetId || b.id.startsWith(prefix))) {
        b.durationMs = durationMs;
        return;
      }
    }
    for (let i = blocks.length - 1; i >= 0; i--) {
      const b: ChatBlock = blocks[i];
      if (b.kind === 'tool-call' && b.tool !== null && b.tool.id === targetId) {
        b.durationMs = durationMs;
        return;
      }
    }
  }
  for (let i = blocks.length - 1; i >= 0; i--) {
    const b: ChatBlock = blocks[i];
    if (isDurationTargetKind(b.kind)) {
      b.durationMs = durationMs;
      return;
    }
  }
}

// ===== agent-event 后处理（对照 reducerEvents.ts foldApiErrorEvents / dedupeAgentEvents）=====
//   上游管线序：dedupeAgentEvents(foldApiErrorEvents(blocks))。title-changed/message 专用去重分支随其
//   解析一并 deferred（当前不产这两类 agent-event），其余 type 走通用 JSON.stringify 键去重。

// 折叠连续 api-error 事件，仅留最新（重试序列 retry1/3 → retry2/3 → retry3/3 收敛为末态）。
export function foldApiErrorEvents(blocks: ChatBlock[]): ChatBlock[] {
  const result: ChatBlock[] = [];
  for (let i = 0; i < blocks.length; i++) {
    const block: ChatBlock = blocks[i];
    if (block.kind !== 'agent-event' || block.event === null) {
      result.push(block);
      continue;
    }
    if (block.event.type !== 'api-error') {
      result.push(block);
      continue;
    }
    const len: number = result.length;
    if (len > 0) {
      const prev: ChatBlock = result[len - 1];
      if (prev.kind === 'agent-event' && prev.event !== null && prev.event.type === 'api-error') {
        result[len - 1] = block;   // 连续 api-error → 替换为最新
        continue;
      }
    }
    result.push(block);
  }
  return result;
}

// 去重相邻同键 agent-event（通用键 event:${JSON.stringify(event)}；对照 dedupeAgentEvents 通用分支）。
//   非事件块重置键（仅相邻事件才比较）。JSON.stringify 不可逆时退 type 串（AgentEvent 无嵌套，恒可逆）。
export function dedupeAgentEvents(blocks: ChatBlock[]): ChatBlock[] {
  const result: ChatBlock[] = [];
  let prevKey: string = '';
  for (let i = 0; i < blocks.length; i++) {
    const block: ChatBlock = blocks[i];
    if (block.kind !== 'agent-event' || block.event === null) {
      result.push(block);
      prevKey = '';   // 非事件块打断相邻性
      continue;
    }
    let key: string;
    try {
      key = 'event:' + JSON.stringify(block.event);
    } catch (e) {
      key = 'event:' + block.event.type;
    }
    if (key === prevKey) {
      continue;   // 与前一相邻事件同键 → 跳过
    }
    result.push(block);
    prevKey = key;
  }
  return result;
}
