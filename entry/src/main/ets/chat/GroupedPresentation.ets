// GroupedPresentation —— 对照 web/src/components/ToolCard/groupedPresentation.ts
// 工具分组头标题 / 副标题 / 行 label 的展示计算。纯逻辑，零 ArkUI 依赖（import Translate.t）。
//
//   主标题：组内 plurality intent（首现优先 tiebreak）→ 对应友好标签；全是 generic-tool → 「命令」兜底标题。
//   副标题：按 command · search · read · mutation · web 顺序拼各 kind 计数（other 仅当已有他部才追加）。
//
//   bash 命令意图判定：替上游两条 \b...\b 正则 → token-set 成员判定（ArkTS 禁正则 s-flag/反向引用；
//   此处只是按词边界匹配，token-set 更直白）。命令文本按 [a-z0-9-] 词边界切词后小写查表（\b 等价）。

import { ChatBlock, ChatToolCall, ToolGroupCounts, ToolGroupSummary } from './ChatBlock';
import { commandStr } from './ToolInputUtils';
import { t } from '../i18n/Translate';

export type GroupedSummaryIntent =
  | 'inspect-files'
  | 'search-content'
  | 'run-project-command'
  | 'modify-files'
  | 'open-web'
  | 'generic-command'
  | 'generic-tool';

// 文件列举/查看命令 token（对照上游 FILE_INSPECTION_COMMAND_RE）
const FILE_INSPECTION_TOKENS: string[] = [
  'get-childitem', 'ls', 'dir', 'get-content', 'cat', 'type', 'tree'
];
// 内容搜索命令 token（对照上游 CONTENT_SEARCH_COMMAND_RE）
const CONTENT_SEARCH_TOKENS: string[] = [
  'rg', 'grep', 'select-string', 'findstr'
];

function tokenInSet(token: string, set: string[]): boolean {
  for (let i = 0; i < set.length; i++) {
    if (set[i] === token) {
      return true;
    }
  }
  return false;
}

// 命令文本（对照上游 getCommandText；复用端口 commandStr，语义一致：command 字符串/数组 → cmd 兜底）。
function getCommandText(tool: ChatToolCall): string {
  return commandStr(tool.input);
}

// 命令文本是否含某 token-set 的词（替上游正则 \b...\b：按 [a-z0-9-] 词边界切词后查表，等价 word-boundary 匹配）。
function commandHasToken(command: string, set: string[]): boolean {
  if (command === '') {
    return false;
  }
  const lower: string = command.toLowerCase();
  const len: number = lower.length;
  let start: number = -1;
  for (let i = 0; i <= len; i++) {
    let isWord: boolean = false;
    if (i < len) {
      const ch: number = lower.charCodeAt(i);
      isWord = (ch >= 97 && ch <= 122) /* a-z */
        || (ch >= 48 && ch <= 57) /* 0-9 */
        || ch === 45; /* - */
    }
    if (isWord) {
      if (start < 0) {
        start = i;
      }
    } else if (start >= 0) {
      const token: string = lower.substring(start, i);
      if (tokenInSet(token, set)) {
        return true;
      }
      start = -1;
    }
  }
  return false;
}

// 单工具意图（对照上游 inferGroupedSummaryIntent）。bash 命令词命中文件列举/搜索 → 归 inspect/search。
export function inferGroupedSummaryIntent(tool: ChatToolCall): GroupedSummaryIntent {
  const name: string = tool.name;
  const command: string = getCommandText(tool);

  if (name === 'Read' || name === 'LS' || name === 'NotebookRead') {
    return 'inspect-files';
  }
  if (name === 'Grep' || name === 'Glob') {
    return 'search-content';
  }
  if (name === 'Edit' || name === 'MultiEdit' || name === 'Write' || name === 'NotebookEdit'
    || name === 'CodexPatch' || name === 'CodexDiff') {
    return 'modify-files';
  }
  if (name === 'WebFetch' || name === 'WebSearch') {
    return 'open-web';
  }
  if (name === 'Bash' || name === 'CodexBash' || name === 'shell_command') {
    if (commandHasToken(command, FILE_INSPECTION_TOKENS)) {
      return 'inspect-files';
    }
    if (commandHasToken(command, CONTENT_SEARCH_TOKENS)) {
      return 'search-content';
    }
    return 'run-project-command';
  }
  return 'generic-tool';
}

function getIntentLabel(intent: GroupedSummaryIntent): string {
  switch (intent) {
    case 'inspect-files':
      return t('toolGroup.friendly.inspectFiles');
    case 'search-content':
      return t('toolGroup.friendly.searchContent');
    case 'run-project-command':
      return t('toolGroup.friendly.runCommands');
    case 'modify-files':
      return t('toolGroup.friendly.editFiles');
    case 'open-web':
      return t('toolGroup.friendly.openWeb');
    case 'generic-command':
      return t('toolGroup.friendly.genericCommand');
    default:
      return t('toolGroup.friendly.genericTool');
  }
}

// 主意图（对照上游 getPrimaryIntent）：plurality 取最大计数，首现优先 tiebreak。
export function getPrimaryIntent(tools: ChatBlock[]): GroupedSummaryIntent {
  const order: GroupedSummaryIntent[] = [];
  const counts: number[] = [];   // 平行于 order（替 Map<union,number>）
  for (let i = 0; i < tools.length; i++) {
    const tool: ChatToolCall | null = tools[i].tool;
    if (tool === null) {
      continue;
    }
    const intent: GroupedSummaryIntent = inferGroupedSummaryIntent(tool);
    const idx: number = order.indexOf(intent);
    if (idx < 0) {
      order.push(intent);
      counts.push(1);
    } else {
      counts[idx] = counts[idx] + 1;
    }
  }
  let primary: GroupedSummaryIntent = 'generic-tool';
  let maxCount: number = -1;
  for (let i = 0; i < order.length; i++) {
    if (counts[i] > maxCount) {
      primary = order[i];
      maxCount = counts[i];
    }
  }
  return primary;
}

// 头标题（对照上游 formatGroupedHeaderTitle）：plurality===generic-tool → 兜底标题，否则 intent label。
export function formatGroupedHeaderTitle(tools: ChatBlock[]): string {
  const primary: GroupedSummaryIntent = getPrimaryIntent(tools);
  if (primary === 'generic-tool') {
    return t('toolGroup.title');
  }
  return getIntentLabel(primary);
}

// 头副标题（对照上游 formatGroupedHeaderSubtitle）：command·search·read·mutation·web 顺序（other 仅当已有他部）。
export function formatGroupedHeaderSubtitle(summary: ToolGroupSummary): string {
  const parts: string[] = [];
  const c: ToolGroupCounts = summary.counts;
  if (c.command > 0) {
    parts.push(t('toolGroup.summary.command', { n: c.command }));
  }
  if (c.search > 0) {
    parts.push(t('toolGroup.summary.search', { n: c.search }));
  }
  if (c.read > 0) {
    parts.push(t('toolGroup.summary.read', { n: c.read }));
  }
  if (c.mutation > 0) {
    parts.push(t('toolGroup.summary.mutation', { n: c.mutation }));
  }
  if (c.web > 0) {
    parts.push(t('toolGroup.summary.web', { n: c.web }));
  }
  if (c.other > 0 && parts.length > 0) {
    parts.push(t('toolGroup.summary.other', { n: c.other }));
  }
  return parts.length > 0 ? parts.join(' · ') : '';
}

// 行 label（对照上游 formatGroupedRowLabel）：单块 intent label。
export function formatGroupedRowLabel(tool: ChatToolCall): string {
  return getIntentLabel(inferGroupedSummaryIntent(tool));
}
