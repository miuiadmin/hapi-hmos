// TerminalToolDisplay —— 终端类工具卡片显示模式（纯层，无 @kit，LocalUnit 可加载）
//
// 对照上游：
//   - web/src/hooks/useTerminalToolDisplayMode.ts（类型 + 默认 + parse + options）
//   - web/src/components/ToolCard/ToolCard.tsx:28-45（TERMINAL_RELATED_TOOL_NAMES + 两个 should 判定）
//   - web/src/chat/subagentTool.ts（isSubagentToolName，已抽到本层 SubagentTool.ets 共用）
//
// 语义（协议/行为对齐 web 端）：
//   - 'compact'（默认）：Bash 等终端类工具仅渲染 header（命令在副标题单行截断）；卡片体不内联。
//   - 'detailed'：终端类工具额外内联卡片体（命令预览），点 header 仍可进详情 sheet 看完整输入/输出。
//   - 非终端类工具不受影响：仍由 presentation.minimal 决定（minimal=true→仅 header；false→内联体）。
//   - 子代理工具（Task/Agent）恒不内联（其嵌套 children 单独渲染，上游 shouldShowInlineToolCardBody 首判）。

import { isSubagentToolName } from './SubagentTool';
// re-export 供既有 import 自 TerminalToolDisplay 的调用方（ToolGroups.ets / 测试）继续可用。
export { isSubagentToolName };

export type TerminalToolDisplayMode = 'compact' | 'detailed';

// 默认 compact：终端密集时降噪（仅 header），对齐上游 DEFAULT_TERMINAL_TOOL_DISPLAY_MODE
export const DEFAULT_TERMINAL_TOOL_DISPLAY_MODE: TerminalToolDisplayMode = 'compact';

// 终端类工具名集合（对照上游 TERMINAL_RELATED_TOOL_NAMES）：
//   Bash=claude, CodexBash=codex, shell_command/run_shell_command=gemini 等蛇形命名变体。
const TERMINAL_RELATED_TOOL_NAMES: Set<string> = new Set<string>([
  'Bash',
  'CodexBash',
  'shell_command',
  'run_shell_command',
]);

// 是否终端类工具
export function isTerminalRelatedToolName(toolName: string): boolean {
  return TERMINAL_RELATED_TOOL_NAMES.has(toolName);
}

// compact 模式下终端类卡片是否走紧凑样式（对照上游 shouldUseCompactTerminalToolCard）：
//   用于副标题单行截断（whitespace-nowrap）等紧凑呈现；detailed 或非终端类恒 false。
export function shouldUseCompactTerminalToolCard(
  toolName: string,
  terminalToolDisplayMode: TerminalToolDisplayMode
): boolean {
  return isTerminalRelatedToolName(toolName) && terminalToolDisplayMode === 'compact';
}

// 是否内联渲染卡片体（对照上游 shouldShowInlineToolCardBody）：
//   - 子代理工具 → 恒 false（嵌套 children 另渲染）
//   - 终端类工具 → detailed 时 true（绕过 minimal，让命令预览内联）；compact 时 false
//   - 其他 → !presentationMinimal（minimal=false 的工具：TodoWrite/update_plan/ExitPlanMode 内联体）
export function shouldShowInlineToolCardBody(
  toolName: string,
  presentationMinimal: boolean,
  terminalToolDisplayMode: TerminalToolDisplayMode
): boolean {
  if (isSubagentToolName(toolName)) {
    return false;
  }
  if (isTerminalRelatedToolName(toolName)) {
    return terminalToolDisplayMode === 'detailed';
  }
  return !presentationMinimal;
}

// 持久化值 → 合法模式（非法/空 → DEFAULT；对照上游 parseTerminalToolDisplayMode）
export function parseTerminalToolDisplayMode(raw: string): TerminalToolDisplayMode {
  if (raw === 'compact' || raw === 'detailed') {
    return raw;
  }
  return DEFAULT_TERMINAL_TOOL_DISPLAY_MODE;
}

// 设置页选项（value + i18n labelKey；对照上游 getTerminalToolDisplayModeOptions）
export class TerminalToolDisplayOption {
  value: TerminalToolDisplayMode = 'compact';
  labelKey: string = '';

  constructor(value: TerminalToolDisplayMode, labelKey: string) {
    this.value = value;
    this.labelKey = labelKey;
  }
}

export function getTerminalToolDisplayModeOptions(): TerminalToolDisplayOption[] {
  return [
    new TerminalToolDisplayOption('compact', 'settings.chat.terminalToolDisplay.compact'),
    new TerminalToolDisplayOption('detailed', 'settings.chat.terminalToolDisplay.detailed'),
  ];
}
