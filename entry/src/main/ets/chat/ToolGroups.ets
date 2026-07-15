// ToolGroups —— 对照 web/src/chat/toolGroups.ts
// 工具卡分组：把连续的同质（eligible）工具调用折叠成一张 tool-group 块，压缩视觉噪音
//   （「检查文件」/「3 条命令 · 2 处编辑」+ 状态徽标）。纯客户端派生，在 ChatPage.recomputeBlocks 调，
//   不入 reducer（保 reducer 纯净 / 不影响其单测）。零 ArkUI 依赖（仅 import 端口纯 helper）。
//
//   buildVisibleChatBlocks：单遍贪心收集连续 eligible tool-call，≥2 成组；<2 / 被非 eligible 打断 → 原样透出。
//   eligibility（isEligibleForToolGrouping）：普通 file/search/command/edit/web 工具，且非子代理/计划/里程碑/
//   交互（待批/ask/request）——这些保留独立卡。
//
// ArkTS 取舍：上游 Record<ToolGroupActionKind, number> → ToolGroupCounts 六字段类（见 ChatBlock.ets）；
//   上游 Set → 平行 string[] + 线性扫描；上游 ?. → 显式 === null（端口惯例）；无正则（无需求）。

import { ChatBlock, ChatToolCall, ToolGroupSummary } from './ChatBlock';
import { getInputStrAny, commandStr } from './ToolInputUtils';
import { isSubagentToolName } from './TerminalToolDisplay';
import { isAskUserQuestionToolName } from './AskUserQuestion';
import { isRequestUserInputToolName } from './RequestUserInput';

export type ToolGroupActionKind = 'read' | 'search' | 'command' | 'mutation' | 'web' | 'other';

// 计划类工具名（对照上游 PLAN_TOOL_NAMES）：里程碑性行为，保留独立卡，不进组。
const PLAN_TOOL_NAMES: string[] = [
  'TodoWrite', 'update_plan', 'ExitPlanMode', 'exit_plan_mode', 'CodexReasoning'
];

// 里程碑类工具名（对照上游 MILESTONE_TOOL_NAMES）：子代理/技能/团队行为，保留独立卡，不进组。
//   （与 isSubagentToolName 部分重叠——上游 MILESTONE 更广，含 Task/Agent/Skill/Team*，照搬不裁。）
const MILESTONE_TOOL_NAMES: string[] = [
  'Task', 'Agent', 'CodexAgent', 'TeamCreate', 'TeamDelete', 'SendMessage', 'Skill',
  'spawn_agent', 'send_input', 'resume_agent', 'wait_agent', 'close_agent'
];

function nameInList(name: string, list: string[]): boolean {
  for (let i = 0; i < list.length; i++) {
    if (list[i] === name) {
      return true;
    }
  }
  return false;
}

function isPlanToolName(name: string): boolean {
  return nameInList(name, PLAN_TOOL_NAMES);
}

function isMilestoneToolName(name: string): boolean {
  return nameInList(name, MILESTONE_TOOL_NAMES);
}

// 交互类块（对照上游 isInteractiveToolBlock）：CodexPermission 待批页 / 任意待批权限 / 答题类工具 —— 保留独立卡。
function isInteractiveToolBlock(block: ChatBlock): boolean {
  const tool: ChatToolCall | null = block.tool;
  if (tool === null) {
    return false;
  }
  if (tool.name === 'CodexPermission') {
    return true;
  }
  if (tool.permission !== null && tool.permission.status === 'pending') {
    return true;
  }
  if (isAskUserQuestionToolName(tool.name)) {
    return true;
  }
  if (isRequestUserInputToolName(tool.name)) {
    return true;
  }
  return false;
}

// 块是否可进组（对照上游 isEligibleForToolGrouping）。
export function isEligibleForToolGrouping(block: ChatBlock): boolean {
  if (block.kind !== 'tool-call') {
    return false;
  }
  const tool: ChatToolCall | null = block.tool;
  if (tool === null) {
    return false;
  }
  if (isSubagentToolName(tool.name)) {
    return false;
  }
  if (isPlanToolName(tool.name)) {
    return false;
  }
  if (isMilestoneToolName(tool.name)) {
    return false;
  }
  if (isInteractiveToolBlock(block)) {
    return false;
  }
  return true;
}

// 工具名 → 动作 kind（对照上游 getToolGroupActionKind）。
export function getToolGroupActionKind(name: string): ToolGroupActionKind {
  if (name === 'Read' || name === 'NotebookRead') {
    return 'read';
  }
  if (name === 'Grep' || name === 'Glob' || name === 'LS') {
    return 'search';
  }
  if (name === 'Bash' || name === 'CodexBash' || name === 'shell_command') {
    return 'command';
  }
  if (name === 'Edit' || name === 'MultiEdit' || name === 'Write' || name === 'NotebookEdit'
    || name === 'CodexPatch' || name === 'CodexDiff') {
    return 'mutation';
  }
  if (name === 'WebFetch' || name === 'WebSearch') {
    return 'web';
  }
  return 'other';
}

function pushUnique(target: string[], value: string): void {
  if (value === '') {
    return;
  }
  for (let i = 0; i < target.length; i++) {
    if (target[i] === value) {
      return;
    }
  }
  target.push(value);
}

function primaryFileTarget(tool: ChatToolCall): string {
  return getInputStrAny(tool.input, ['file_path', 'path', 'file', 'filePath', 'notebook_path', 'name']);
}

function primarySearchTarget(tool: ChatToolCall): string {
  return getInputStrAny(tool.input, ['pattern', 'query']);
}

function primaryUrlTarget(tool: ChatToolCall): string {
  return getInputStrAny(tool.input, ['url']);
}

// other 类的目标（对照上游 getPrimaryOtherTarget）：file → search → command → url → 工具名 兜底。
function primaryOtherTarget(tool: ChatToolCall): string {
  const file: string = primaryFileTarget(tool);
  if (file !== '') {
    return file;
  }
  const search: string = primarySearchTarget(tool);
  if (search !== '') {
    return search;
  }
  const command: string = commandStr(tool.input);
  if (command !== '') {
    return command;
  }
  const url: string = primaryUrlTarget(tool);
  if (url !== '') {
    return url;
  }
  return tool.name;
}

// 汇总（对照上游 summarizeToolGroup）：逐块累 counts 字段 + 状态计数 + 各 target 桶（去重）。
export function summarizeToolGroup(tools: ChatBlock[]): ToolGroupSummary {
  const summary: ToolGroupSummary = new ToolGroupSummary();
  summary.totalTools = tools.length;
  for (let i = 0; i < tools.length; i++) {
    const tool: ChatToolCall | null = tools[i].tool;
    if (tool === null) {
      continue;
    }
    const kind: ToolGroupActionKind = getToolGroupActionKind(tool.name);
    if (kind === 'read') {
      summary.counts.read += 1;
    } else if (kind === 'search') {
      summary.counts.search += 1;
    } else if (kind === 'command') {
      summary.counts.command += 1;
    } else if (kind === 'mutation') {
      summary.counts.mutation += 1;
    } else if (kind === 'web') {
      summary.counts.web += 1;
    } else {
      summary.counts.other += 1;
    }

    if (tool.state === 'error') {
      summary.errorCount += 1;
    } else if (tool.state === 'running') {
      summary.runningCount += 1;
    } else if (tool.state === 'pending') {
      summary.pendingCount += 1;
    }

    if (kind === 'read' || kind === 'mutation') {
      pushUnique(summary.fileTargets, primaryFileTarget(tool));
    } else if (kind === 'search') {
      pushUnique(summary.searchTargets, primarySearchTarget(tool));
    } else if (kind === 'command') {
      pushUnique(summary.commandTargets, commandStr(tool.input));
    } else if (kind === 'web') {
      const u: string = primaryUrlTarget(tool);
      pushUnique(summary.urlTargets, u !== '' ? u : primarySearchTarget(tool));
    } else {
      pushUnique(summary.otherTargets, primaryOtherTarget(tool));
    }
  }
  return summary;
}

// 单遍贪心分组（对照上游 buildVisibleChatBlocks）。
//   needsOlderHistory = hasMoreMessages && 组起于最旧可见边界（out 为空时）—— v1 仅作 id 锚点策略标记，
//   不移植跨页懒加载回灌（组不跨已加载窗口回填；上游 hydration 需 loadOlderMessages 循环，留观察）。
export function buildVisibleChatBlocks(blocks: ChatBlock[], hasMoreMessages: boolean): ChatBlock[] {
  const out: ChatBlock[] = [];
  let i: number = 0;
  while (i < blocks.length) {
    const block: ChatBlock = blocks[i];
    if (!isEligibleForToolGrouping(block)) {
      out.push(block);
      i += 1;
      continue;
    }
    // 向前扫连续 eligible run
    const run: ChatBlock[] = [block];
    let cursor: number = i + 1;
    while (cursor < blocks.length && isEligibleForToolGrouping(blocks[cursor])) {
      run.push(blocks[cursor]);
      cursor += 1;
    }
    if (run.length < 2) {
      // 单个 eligible 块前后无同类 → 原样透出（不成组）
      out.push(block);
      i += 1;
      continue;
    }
    const startsAtOldestVisibleBoundary: boolean = out.length === 0;
    const needsOlderHistory: boolean = hasMoreMessages && startsAtOldestVisibleBoundary;
    const summary: ToolGroupSummary = summarizeToolGroup(run);
    out.push(ChatBlock.makeToolGroupBlock(run, summary, needsOlderHistory));
    i = cursor;
  }
  return out;
}
