// Tracer —— sidechain 子代理消息的追踪与归组（纯层，无 @kit，LocalUnit 可加载）
//
// 原样移植上游 chat/tracer.ts：把 isSidechain 消息按「发起它的 Task/Agent 工具卡所在消息 id」(sidechainId)
//   归组，供 Reducer 递归 reduce 成该工具卡的 children（Flow A：Claude Task/Agent sidechain 嵌套渲染）。
//
// 算法（对照 tracer.ts）：
//   1. promptToTaskId：扫所有 agent 消息的 tool-call 块，isSubagentToolName + input.prompt(字符串)
//      → prompt 映射到「发起消息 id」。
//   2. 遍历消息：非 sidechain → root；sidechain →
//      - 根匹配（m.sidechainPrompt 命中 promptToTaskId）→ 记 uuid→sidechainId、入组、回捞孤儿；
//      - 否则 parentUuid 链式（uuidToSidechainId 命中）→ 入组、回捞；父未解析 → 缓存为孤儿；
//      - 无根匹配且无 parentUuid → 进 root（对照 tracer.ts:120）。
//   3. 永不解析的孤儿 sidechain 丢弃（对照上游：留在 orphanMessages 不入 results）。
//
//   端口差异：上游 uuid/parentUUID 从 content[0] 读、prompt 从 'sidechain' content block 读；端口把它们
//   存在 ChatMessage.uuid/parentUuid/sidechainPrompt（parseMessage 已填），语义等价。

import { ChatMessage } from '../models/Message';
import { isSubagentToolName } from './SubagentTool';

// 追踪结果：root = 进主时间线的消息（原序）；groups = sidechainId(发起消息 id) → sidechain 消息（原序）。
export class TracedResult {
  root: ChatMessage[] = [];
  groups: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();
}

// 从 Task/Agent 工具入参 input.prompt 建索引：prompt → 发起消息 id（对照 tracer.ts:63-71）。
function buildPromptToTaskId(messages: ChatMessage[]): Map<string, string> {
  const map = new Map<string, string>();
  for (let i = 0; i < messages.length; i++) {
    const msg: ChatMessage = messages[i];
    if (msg.role !== 'agent') {
      continue;
    }
    for (let bi = 0; bi < msg.blocks.length; bi++) {
      const c = msg.blocks[bi];
      if (c.type !== 'tool-call') {
        continue;
      }
      if (!isSubagentToolName(c.name)) {
        continue;
      }
      const input: Record<string, Object> | null = c.input;
      if (input === null) {
        continue;
      }
      const promptVal: Object = input['prompt'];
      if (typeof promptVal === 'string' && (promptVal as string) !== '') {
        map.set(promptVal as string, msg.id);
      }
    }
  }
  return map;
}

// 把消息加入 sidechain 组（组不存在则新建）。
function addToGroup(groups: Map<string, ChatMessage[]>, sidechainId: string, msg: ChatMessage): void {
  const existing: ChatMessage[] | undefined = groups.get(sidechainId);
  if (existing !== undefined) {
    existing.push(msg);
  } else {
    const arr: ChatMessage[] = [];
    arr.push(msg);
    groups.set(sidechainId, arr);
  }
}

// 递归回捞先到的孤儿 sidechain（parentUuid 当时已知但父尚未解析）。对照 tracer.ts:31-51 processOrphans。
function processOrphans(
  groups: Map<string, ChatMessage[]>,
  uuidToSidechainId: Map<string, string>,
  orphanMessages: Map<string, ChatMessage[]>,
  parentUuid: string,
  sidechainId: string
): void {
  const orphans: ChatMessage[] | undefined = orphanMessages.get(parentUuid);
  if (orphans === undefined) {
    return;
  }
  orphanMessages.delete(parentUuid);
  for (let i = 0; i < orphans.length; i++) {
    const orphan: ChatMessage = orphans[i];
    if (orphan.uuid !== '') {
      uuidToSidechainId.set(orphan.uuid, sidechainId);
    }
    addToGroup(groups, sidechainId, orphan);
    if (orphan.uuid !== '') {
      processOrphans(groups, uuidToSidechainId, orphanMessages, orphan.uuid, sidechainId);
    }
  }
}

// 追踪 + 归组主入口（对照 tracer.ts:traceMessages，端口产出 {root, groups} 而非带 sidechainId 的数组）。
export function traceAndGroup(messages: ChatMessage[]): TracedResult {
  const result: TracedResult = new TracedResult();
  const promptToTaskId: Map<string, string> = buildPromptToTaskId(messages);
  const uuidToSidechainId: Map<string, string> = new Map<string, string>();
  const orphanMessages: Map<string, ChatMessage[]> = new Map<string, ChatMessage[]>();

  for (let i = 0; i < messages.length; i++) {
    const msg: ChatMessage = messages[i];
    if (!msg.isSidechain) {
      result.root.push(msg);
      continue;
    }

    // 根匹配：sidechain 根 prompt → Task/Agent 入参 prompt 精确匹配（发起消息 id）。
    let sidechainId: string = '';
    if (msg.sidechainPrompt !== '') {
      const tid: string | undefined = promptToTaskId.get(msg.sidechainPrompt);
      if (tid !== undefined) {
        sidechainId = tid;
      }
    }

    if (sidechainId !== '') {
      if (msg.uuid !== '') {
        uuidToSidechainId.set(msg.uuid, sidechainId);
      }
      addToGroup(result.groups, sidechainId, msg);
      if (msg.uuid !== '') {
        processOrphans(result.groups, uuidToSidechainId, orphanMessages, msg.uuid, sidechainId);
      }
      continue;
    }

    if (msg.parentUuid !== '') {
      const parentSid: string | undefined = uuidToSidechainId.get(msg.parentUuid);
      if (parentSid !== undefined) {
        if (msg.uuid !== '') {
          uuidToSidechainId.set(msg.uuid, parentSid);
        }
        addToGroup(result.groups, parentSid, msg);
        if (msg.uuid !== '') {
          processOrphans(result.groups, uuidToSidechainId, orphanMessages, msg.uuid, parentSid);
        }
      } else {
        // 父尚未解析 → 缓存为孤儿，待父解析时回捞（父永不解析则丢弃，对照上游）。
        const arr: ChatMessage[] | undefined = orphanMessages.get(msg.parentUuid);
        if (arr !== undefined) {
          arr.push(msg);
        } else {
          const na: ChatMessage[] = [];
          na.push(msg);
          orphanMessages.set(msg.parentUuid, na);
        }
      }
      continue;
    }

    // sidechain 但无根匹配且无 parentUuid → 进 root（对照 tracer.ts:120）。
    result.root.push(msg);
  }

  return result;
}
