// 斜杠命令补全（对照 shared/src/slashCommands.ts + web useSlashCommands.getSuggestions）
//   纯逻辑：静态内置命令表（claude/codex/gemini/grok/opencode/cursor/copilot；kimi/pi 空）+ 服务端命令合并
//   （mergeSlashCommands，server 覆盖同名 builtin）+ getSuggestions 评分（精确/前缀/包含/Levenshtein）。
//
// 服务端命令：Hub GET /api/sessions/:id/slash-commands 返回用户/项目/插件命令（source != 'builtin'），
//   合并进内置表（同名 server 覆盖 builtin），使设备端无 CLI 也能拿到活命令。失败静默回落内置（不阻塞输入）。
//   codex 自定义命令的 content 展开（findCodexCustomPromptExpansion）留 TODO——MVP 仍发字面 /name 由 CLI 解析。
//   $ 技能（$name 菜单）见 Skills.ets：来源 GET /api/sessions/:id/skills。

import { ServerSlashCommand } from '../models/Types';

// 斜杠命令（对齐 shared/src/apiTypes.ts SlashCommand，取渲染所需字段）
export class SlashCommand {
  name: string = '';
  description: string = '';        // 可空 → ''（内置皆有；用户/插件命令上游可空）
  source: string = 'builtin';      // 'builtin' | 'user' | 'plugin' | 'project'
  content: string = '';            // 用户/插件自定义命令的展开内容（builtin 空；上游 findCodexCustomPromptExpansion 用）
}

// —— 静态内置命令表（faithful 移植 shared/src/slashCommands.ts BUILTIN_SLASH_COMMANDS）——
export const BUILTIN_CLAUDE_COMMANDS: SlashCommand[] = [
  cmd('clear', 'Clear conversation history and free up context'),
  cmd('compact', 'Clear conversation history but keep a summary in context'),
  cmd('context', 'Visualize current context usage as a colored grid'),
  cmd('cost', 'Show the total cost and duration of the current session'),
  cmd('doctor', 'Diagnose and verify your Claude Code installation and settings'),
  cmd('plan', 'View or open the current session plan'),
  cmd('stats', 'Show your Claude Code usage statistics and activity'),
  cmd('status', 'Show Claude Code status including version, model, account, and API connectivity')
];
export const BUILTIN_CODEX_COMMANDS: SlashCommand[] = [
  cmd('agent', 'Toggle proactive Codex multi-agent delegation'),
  cmd('clear', 'Clear current Codex thread context'),
  cmd('compact', 'Compact current Codex thread context'),
  cmd('goal', 'Set, view, pause, resume, or clear a persistent Codex goal'),
  cmd('help', 'Show supported HAPI Codex slash commands'),
  cmd('plan', 'Enable plan mode; use /plan off to return to default'),
  cmd('default', 'Return Codex collaboration mode to default'),
  cmd('execute', 'Return Codex collaboration mode to default'),
  cmd('status', 'Show current Codex session config'),
  cmd('model', 'Show or set Codex model, e.g. /model gpt-5.5'),
  cmd('reasoning', 'Show or set reasoning effort'),
  cmd('effort', 'Alias for /reasoning'),
  cmd('personality', 'Show or set response style: friendly, pragmatic, or none'),
  cmd('permissions', 'Show or set permission mode'),
  cmd('permission', 'Alias for /permissions')
];
export const BUILTIN_GEMINI_COMMANDS: SlashCommand[] = [
  cmd('about', 'Show version info'),
  cmd('clear', 'Clear the screen and conversation history'),
  cmd('compress', 'Compress the context by replacing it with a summary'),
  cmd('stats', 'Check session stats')
];
// grok（对照上游 BUILTIN_SLASH_COMMANDS.grok）
export const BUILTIN_GROK_COMMANDS: SlashCommand[] = [
  cmd('compact', 'Compress conversation history to save context'),
  cmd('context', 'Show context window usage and session stats'),
  cmd('session-info', 'Show Grok session model, turns, and context usage'),
  cmd('goal', 'Set, manage, or inspect an autonomous goal'),
  cmd('always-approve', 'Toggle automatic tool approval'),
  cmd('auto', 'Let Grok classify safe tool calls for automatic approval')
];
// opencode（对照上游 BUILTIN_SLASH_COMMANDS.opencode）
export const BUILTIN_OPENCODE_COMMANDS: SlashCommand[] = [
  cmd('help', 'Show supported HAPI OpenCode slash commands'),
  cmd('status', 'Show current OpenCode session config'),
  cmd('plan', 'Enable plan mode; use /plan off to return to default'),
  cmd('default', 'Return OpenCode permission mode to default'),
  cmd('init', 'Generate or refresh AGENTS.md for this project')
];
// cursor（对照上游 BUILTIN_SLASH_COMMANDS.cursor；仅 1 条 pass-through）
export const BUILTIN_CURSOR_COMMANDS: SlashCommand[] = [
  cmd('compress', 'Compress conversation context to free window space (pass-through to Cursor agent)')
];
// copilot（对照上游 BUILTIN_SLASH_COMMANDS.copilot）
export const BUILTIN_COPILOT_COMMANDS: SlashCommand[] = [
  cmd('help', 'Show supported Copilot slash commands'),
  cmd('status', 'Show current Copilot session config'),
  cmd('plan', 'Start plan mode for structured implementation planning'),
  cmd('autopilot', 'Start autopilot mode for autonomous multi-step work'),
  cmd('fleet', 'Run parallel subagents for a task (combine with Interactive/Plan/Autopilot)'),
  cmd('tasks', 'List or manage fleet tasks'),
  cmd('subagents', 'Manage Copilot subagents'),
  cmd('agents', 'Alias for /subagents'),
  cmd('delegate', 'Delegate work to a subagent'),
  cmd('agent', 'Select or configure a custom agent'),
  cmd('rubber-duck', 'Consult the rubber-duck agent for a second opinion on plans, code, and tests'),
  cmd('security-review', 'Run a focused security review of active local code changes'),
  cmd('research', 'Run a deep research investigation across the codebase and web'),
  cmd('review', 'Run the code-review agent on current changes'),
  cmd('skills', 'List, inspect, add, or remove Copilot skills'),
  cmd('context', 'Show current context usage'),
  cmd('model', 'Show or switch the active model'),
  cmd('permissions', 'Show or set permission mode'),
  cmd('permission', 'Alias for /permissions'),
  cmd('usage', 'Show session usage metrics')
];

function cmd(name: string, description: string): SlashCommand {
  const c: SlashCommand = new SlashCommand();
  c.name = name;
  c.description = description;
  c.source = 'builtin';
  return c;
}

// 某 agent 的内置命令（对照 getBuiltinSlashCommands；返回拷贝）。kimi/pi 上游空数组；未知 agent 回退 claude
//   （对照上游 `?? claude`）。opencode/cursor/copilot/grok 各有专属表（v0.26.0 不再靠 RPC）。
export function getBuiltinSlashCommands(agent: string): SlashCommand[] {
  if (agent === 'claude') { return BUILTIN_CLAUDE_COMMANDS.slice(); }
  if (agent === 'codex') { return BUILTIN_CODEX_COMMANDS.slice(); }
  if (agent === 'gemini') { return BUILTIN_GEMINI_COMMANDS.slice(); }
  if (agent === 'grok') { return BUILTIN_GROK_COMMANDS.slice(); }
  if (agent === 'opencode') { return BUILTIN_OPENCODE_COMMANDS.slice(); }
  if (agent === 'cursor') { return BUILTIN_CURSOR_COMMANDS.slice(); }
  if (agent === 'copilot') { return BUILTIN_COPILOT_COMMANDS.slice(); }
  if (agent === 'kimi' || agent === 'pi') { return []; }
  return BUILTIN_CLAUDE_COMMANDS.slice();
}

// 合并命令：照上游 mergeSlashCommands——按 name.toLowerCase() 去重，**后出现者覆盖先者**（删除再 set 重排到末尾）。
//   调用方保证 builtin 在前、server 在后（mergeSlashCommands(builtin.concat(server))），故 server 同名覆盖 builtin。
//   ArkTS Map 保插入序，delete + set 行为与上游 Array.from(commandMap.values()) 一致。
export function mergeSlashCommands(commands: SlashCommand[]): SlashCommand[] {
  const map: Map<string, SlashCommand> = new Map();
  for (let i = 0; i < commands.length; i++) {
    const key: string = commands[i].name.toLowerCase();
    if (map.has(key)) {
      map.delete(key);
    }
    map.set(key, commands[i]);
  }
  const out: SlashCommand[] = [];
  map.forEach((v: SlashCommand) => { out.push(v); });
  return out;
}

// 服务端命令（models/ServerSlashCommand）→ 渲染命令（chat/SlashCommand）映射。
//   models 不依赖 chat，故 parse 落 ServerSlashCommand；此处在合并前转成 SlashCommand。
export function serverCommandsToSlash(server: ServerSlashCommand[]): SlashCommand[] {
  const out: SlashCommand[] = [];
  for (let i = 0; i < server.length; i++) {
    const c: SlashCommand = new SlashCommand();
    c.name = server[i].name;
    c.description = server[i].description;
    c.source = server[i].source;
    c.content = server[i].content;
    out.push(c);
  }
  return out;
}

// Levenshtein 编辑距离（对照 useSlashCommands:9；滚动两行实现，避免二维数组，ArkTS 友好）
export function levenshteinDistance(a: string, b: string): number {
  if (a.length === 0) { return b.length; }
  if (b.length === 0) { return a.length; }
  let prev: number[] = [];
  for (let j = 0; j <= b.length; j++) { prev[j] = j; }
  for (let i = 1; i <= a.length; i++) {
    const curr: number[] = [];
    curr[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost: number = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(Math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = curr;
  }
  return prev[b.length];
}

// 命令建议（对照 useSlashCommands.getSuggestions 评分）：query 含 / 前缀剥之；
//   空 → 全部；否则 精确=0 / 前缀=1 / 包含=2 / Levenshtein≤max(2,len/2)=3+dist，按分数升序。
export function slashCommandSuggestions(commands: SlashCommand[], query: string): SlashCommand[] {
  const searchTerm: string = query.startsWith('/')
    ? query.substring(1).toLowerCase()
    : query.toLowerCase();
  if (searchTerm === '') {
    return commands.slice();
  }
  const maxDistance: number = Math.max(2, Math.floor(searchTerm.length / 2));
  const matched: SlashCommand[] = [];
  const scores: number[] = [];
  for (let i = 0; i < commands.length; i++) {
    const name: string = commands[i].name.toLowerCase();
    let score: number = -1;   // -1 = 不入选（替代上游 Infinity）
    if (name === searchTerm) {
      score = 0;
    } else if (name.startsWith(searchTerm)) {
      score = 1;
    } else if (name.indexOf(searchTerm) >= 0) {
      score = 2;
    } else {
      const dist: number = levenshteinDistance(searchTerm, name);
      score = dist <= maxDistance ? 3 + dist : -1;
    }
    if (score >= 0) {
      matched.push(commands[i]);
      scores.push(score);
    }
  }
  // 按 score 升序（下标排序，避免对对象数组直接比较器）
  const order: number[] = [];
  for (let i = 0; i < matched.length; i++) { order.push(i); }
  order.sort((a: number, b: number): number => scores[a] - scores[b]);
  const out: SlashCommand[] = [];
  for (let i = 0; i < order.length; i++) { out.push(matched[order[i]]); }
  return out;
}
