// Reducer —— 对齐 web/src/chat/reducer.ts + reducerTimeline.ts + reducerTools.ts
// 纯函数：喂 ChatMessage[] + AgentState → 产出全新 ChatBlock[]（每次调用新数组新对象，ChatPage 赋值即刷新）。
//
// 状态机要点（已读上游确认）：
//   block.state（执行生命周期 pending/running/completed/error）与 block.permission.status（权限生命周期）解耦。
//   「等用户批准」由 permission.status==='pending' 表达（footer 据此挂载），不由 state==='pending' 表达。
//   - tool-call 块：ensureToolBlock 后若 state==='pending' 翻为 running（pending 态仅孤儿卡保留）。
//   - tool-result 块：合并后强制 state=is_error?'error':'completed' + result。
//   - 孤儿权限卡（有权限无对应消息）：approved→completed(result='Approved')；denied/canceled→error(result={error:reason})；pending→pending。

import { ChatMessage } from '../models/Message';
import { AgentState } from './AgentState';
import {
  ChatBlock,
  ChatToolCall,
  ToolPermission,
  PermissionEntry,
  ToolState,
  PermissionStatus
} from './ChatBlock';
import { isCliOutputText, mergeCliOutputBlocks } from './CliOutput';

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

// ===== 主入口：reduceChatBlocks =====
export function reduceChatBlocks(messages: ChatMessage[], agentState: AgentState | null): ChatBlock[] {
  const permissionsById: Map<string, PermissionEntry> = getPermissions(agentState);
  const blocks: ChatBlock[] = [];
  const toolBlocksById: Map<string, ChatBlock> = new Map<string, ChatBlock>();
  const toolIdsInMessages: Set<string> = new Set<string>();

  // 按消息顺序、每条 blocks 顺序遍历（插入序，不排序）
  for (let mi = 0; mi < messages.length; mi++) {
    const msg: ChatMessage = messages[mi];

    // user 消息：CLI 命令输出（sentFrom==='cli' 且含 CLI 标签）→ cli-output 块（source='user'）；否则一行文本气泡
    if (msg.role === 'user') {
      if (isCliOutputText(msg.text, msg.sentFrom)) {
        blocks.push(ChatBlock.cliOutput(msg.id, msg.createdAt, msg.text, 'user'));
      } else if (msg.text !== '') {
        const ub: ChatBlock = ChatBlock.userText(msg.id, msg.createdAt, msg.text);
        ub.userOptimistic = msg.isOptimistic;
        ub.userStatus = msg.status;
        blocks.push(ub);
      }
      continue;
    }
    // event 消息：MVP 不渲染
    if (msg.role !== 'agent') {
      continue;
    }

    for (let bi = 0; bi < msg.blocks.length; bi++) {
      const c = msg.blocks[bi];

      if (c.type === 'text') {
        if (c.text !== '') {
          // CLI 命令输出（sentFrom==='cli' 且含 CLI 标签）→ cli-output 块（source='assistant'）；否则 agent-text
          if (isCliOutputText(c.text, msg.sentFrom)) {
            blocks.push(ChatBlock.cliOutput(`${msg.id}:${bi}`, msg.createdAt, c.text, 'assistant'));
          } else {
            blocks.push(ChatBlock.agentText(`${msg.id}:${bi}`, msg.createdAt, c.text, msg.invokedAt, msg.model, msg.usage));
          }
        }
      } else if (c.type === 'reasoning') {
        // 思考过程块（对照上游 reasoning.tsx）：非空才产出（空 thinking 不渲染，同 text 块处理）
        if (c.text !== '') {
          blocks.push(ChatBlock.reasoning(`${msg.id}:${bi}`, msg.createdAt, c.text));
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
        const entry: PermissionEntry | undefined = permissionsById.get(c.id);
        const permission: ToolPermission | null = entry !== undefined ? entry.permission : null;
        const block: ChatBlock = ensureToolBlock(blocks, toolBlocksById, c.id,
          msg.createdAt, c.name, c.input, c.description, permission);
        // tool-call 到达 → 工具已发起；pending 态翻为 running（等用户批准由 permission.status 表达）
        if (block.tool !== null && block.tool.state === 'pending') {
          block.tool.state = 'running';
          block.tool.startedAt = msg.createdAt;
        }
      } else if (c.type === 'tool-result') {
        toolIdsInMessages.add(c.id);
        const entry: PermissionEntry | undefined = permissionsById.get(c.id);
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

  // 合并相邻 cli-output 块（command-name 块 + 紧随 stdout 块）——对照 web mergeCliOutputBlocks
  return mergeCliOutputBlocks(blocks);
}
