// ToolGroups 单测 —— 对照 web/src/chat/toolGroups.ts
//   覆盖：getToolGroupActionKind（名→kind 映射）、isEligibleForToolGrouping（普通工具 eligible；
//   子代理/计划/里程碑/待批/ask/request/CodexPermission 否）、buildVisibleChatBlocks（连续 ≥2 成组；
//   <2 原样；非 eligible 打断 run；needsOlderHistory 边界 + id 锚点策略）、summarizeToolGroup（counts +
//   状态计数 + target 桶去重）。纯逻辑无 i18n 依赖（ToolGroups.ets 不调 t）。
//   input 用 JSON.parse(json) as Record<string,Object> 构造（避嵌套字面量类型坑，同 AgentState 范式）。

import { describe, it, expect } from '@ohos/hypium';
import { ChatBlock, ChatToolCall, ToolPermission, ToolState } from '../main/ets/chat/ChatBlock';
import {
  getToolGroupActionKind,
  isEligibleForToolGrouping,
  summarizeToolGroup,
  buildVisibleChatBlocks
} from '../main/ets/chat/ToolGroups';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

// 构造 tool-call 块（id/name/state/input；permission 可选）
function mkBlock(id: string, name: string, state: ToolState, input: Record<string, Object> | null,
  permission: ToolPermission | null = null): ChatBlock {
  const tool: ChatToolCall = new ChatToolCall();
  tool.id = id;
  tool.name = name;
  tool.state = state;
  tool.input = input;
  tool.permission = permission;
  const b: ChatBlock = new ChatBlock();
  b.kind = 'tool-call';
  b.id = id;
  b.tool = tool;
  return b;
}

function pendingPermission(): ToolPermission {
  const p: ToolPermission = new ToolPermission();
  p.status = 'pending';
  return p;
}

export default function toolGroupsTest(): void {
  describe('ToolGroups — getToolGroupActionKind', () => {
    it('Read/NotebookRead → read', 0, () => {
      expect(getToolGroupActionKind('Read')).assertEqual('read');
      expect(getToolGroupActionKind('NotebookRead')).assertEqual('read');
    });
    it('Grep/Glob/LS → search', 0, () => {
      expect(getToolGroupActionKind('Grep')).assertEqual('search');
      expect(getToolGroupActionKind('Glob')).assertEqual('search');
      expect(getToolGroupActionKind('LS')).assertEqual('search');
    });
    it('Bash/CodexBash/shell_command → command', 0, () => {
      expect(getToolGroupActionKind('Bash')).assertEqual('command');
      expect(getToolGroupActionKind('CodexBash')).assertEqual('command');
      expect(getToolGroupActionKind('shell_command')).assertEqual('command');
    });
    it('Edit/MultiEdit/Write/NotebookEdit/CodexPatch/CodexDiff → mutation', 0, () => {
      expect(getToolGroupActionKind('Edit')).assertEqual('mutation');
      expect(getToolGroupActionKind('MultiEdit')).assertEqual('mutation');
      expect(getToolGroupActionKind('Write')).assertEqual('mutation');
      expect(getToolGroupActionKind('NotebookEdit')).assertEqual('mutation');
      expect(getToolGroupActionKind('CodexPatch')).assertEqual('mutation');
      expect(getToolGroupActionKind('CodexDiff')).assertEqual('mutation');
    });
    it('WebFetch/WebSearch → web；余 → other', 0, () => {
      expect(getToolGroupActionKind('WebFetch')).assertEqual('web');
      expect(getToolGroupActionKind('WebSearch')).assertEqual('web');
      expect(getToolGroupActionKind('Task')).assertEqual('other');
      expect(getToolGroupActionKind('Something')).assertEqual('other');
    });
  });

  describe('ToolGroups — isEligibleForToolGrouping', () => {
    it('普通 Read/Bash → eligible', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'Read', 'completed', null))).assertTrue();
      expect(isEligibleForToolGrouping(mkBlock('2', 'Bash', 'completed', null))).assertTrue();
    });
    it('子代理 Task → 否', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'Task', 'completed', null))).assertFalse();
    });
    it('计划 TodoWrite/update_plan/CodexReasoning → 否', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'TodoWrite', 'completed', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('2', 'update_plan', 'completed', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('3', 'CodexReasoning', 'completed', null))).assertFalse();
    });
    it('里程碑 Agent/Skill/SendMessage → 否', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'Agent', 'completed', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('2', 'Skill', 'completed', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('3', 'SendMessage', 'completed', null))).assertFalse();
    });
    it('待批权限块 → 否', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'Bash', 'running', null, pendingPermission()))).assertFalse();
    });
    it('AskUserQuestion / request_user_input / CodexPermission → 否', 0, () => {
      expect(isEligibleForToolGrouping(mkBlock('1', 'AskUserQuestion', 'running', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('2', 'request_user_input', 'running', null))).assertFalse();
      expect(isEligibleForToolGrouping(mkBlock('3', 'CodexPermission', 'running', null))).assertFalse();
    });
  });

  describe('ToolGroups — buildVisibleChatBlocks', () => {
    it('连续 3 个 Read → 折成 1 组', 0, () => {
      const blocks: ChatBlock[] = [
        mkBlock('a', 'Read', 'completed', rec('{"file_path":"a.ts"}')),
        mkBlock('b', 'Read', 'completed', rec('{"file_path":"b.ts"}')),
        mkBlock('c', 'Read', 'completed', rec('{"file_path":"c.ts"}'))
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, false);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('tool-group');
      expect(out[0].groupTools.length).assertEqual(3);
    });
    it('单个 eligible 块 → 不成组（原样透出）', 0, () => {
      const blocks: ChatBlock[] = [mkBlock('a', 'Read', 'completed', null)];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, false);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('tool-call');
    });
    it('非 eligible 块打断 run → 前后各自独立', 0, () => {
      const blocks: ChatBlock[] = [
        mkBlock('a', 'Read', 'completed', null),
        mkBlock('b', 'Task', 'completed', null),   // 子代理打断
        mkBlock('c', 'Read', 'completed', null)
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, false);
      expect(out.length).assertEqual(3);
      expect(out[0].kind).assertEqual('tool-call');
      expect(out[1].kind).assertEqual('tool-call');
      expect(out[2].kind).assertEqual('tool-call');
    });
    it('两段连续 run → 两组（中间夹 agent-text）', 0, () => {
      const text: ChatBlock = ChatBlock.agentText('m1', 2, 'hi', 0);
      const blocks: ChatBlock[] = [
        mkBlock('a', 'Read', 'completed', null),
        mkBlock('b', 'Read', 'completed', null),
        text,
        mkBlock('d', 'Edit', 'completed', null),
        mkBlock('e', 'Edit', 'completed', null)
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, false);
      expect(out.length).assertEqual(3);
      expect(out[0].kind).assertEqual('tool-group');
      expect(out[0].groupTools.length).assertEqual(2);
      expect(out[1].kind).assertEqual('agent-text');
      expect(out[2].kind).assertEqual('tool-group');
      expect(out[2].groupTools.length).assertEqual(2);
    });
    it('id 锚点：needsOlderHistory=false → 锚 firstToolId', 0, () => {
      const blocks: ChatBlock[] = [
        mkBlock('first', 'Read', 'completed', null),
        mkBlock('last', 'Read', 'completed', null)
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, false);
      expect(out[0].id).assertEqual('tool-group:first');
      expect(out[0].groupNeedsOlderHistory).assertFalse();
    });
    it('id 锚点：hasMoreMessages=true 且组起于最旧边界 → needsOlderHistory=true，锚 lastToolId', 0, () => {
      const blocks: ChatBlock[] = [
        mkBlock('first', 'Read', 'completed', null),
        mkBlock('last', 'Read', 'completed', null)
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, true);
      expect(out[0].id).assertEqual('tool-group:last');
      expect(out[0].groupNeedsOlderHistory).assertTrue();
    });
    it('组起于非最旧边界（前面有 agent-text）→ needsOlderHistory=false', 0, () => {
      const text: ChatBlock = ChatBlock.agentText('m1', 1, 'hi', 0);
      const blocks: ChatBlock[] = [
        text,
        mkBlock('a', 'Read', 'completed', null),
        mkBlock('b', 'Read', 'completed', null)
      ];
      const out: ChatBlock[] = buildVisibleChatBlocks(blocks, true);
      expect(out[1].groupNeedsOlderHistory).assertFalse();
      expect(out[1].id).assertEqual('tool-group:a');
    });
  });

  describe('ToolGroups — summarizeToolGroup', () => {
    it('counts + 状态计数 + fileTargets 去重', 0, () => {
      const tools: ChatBlock[] = [
        mkBlock('a', 'Read', 'completed', rec('{"file_path":"a.ts"}')),
        mkBlock('b', 'Read', 'running', rec('{"file_path":"a.ts"}')),   // 同路径去重
        mkBlock('c', 'Edit', 'error', rec('{"file_path":"c.ts"}'))
      ];
      const s = summarizeToolGroup(tools);
      expect(s.totalTools).assertEqual(3);
      expect(s.counts.read).assertEqual(2);
      expect(s.counts.mutation).assertEqual(1);
      expect(s.runningCount).assertEqual(1);
      expect(s.errorCount).assertEqual(1);
      expect(s.pendingCount).assertEqual(0);
      expect(s.fileTargets.length).assertEqual(2);   // a.ts + c.ts（b 的 a.ts 去重）
    });
    it('command/web/search 各进对应 target 桶', 0, () => {
      const tools: ChatBlock[] = [
        mkBlock('a', 'Bash', 'completed', rec('{"command":"ls -la"}')),
        mkBlock('b', 'Grep', 'completed', rec('{"pattern":"foo"}')),
        mkBlock('c', 'WebFetch', 'completed', rec('{"url":"https://x"}'))
      ];
      const s = summarizeToolGroup(tools);
      expect(s.counts.command).assertEqual(1);
      expect(s.counts.search).assertEqual(1);
      expect(s.counts.web).assertEqual(1);
      expect(s.commandTargets.length).assertEqual(1);
      expect(s.searchTargets.length).assertEqual(1);
      expect(s.urlTargets.length).assertEqual(1);
    });
  });
}
