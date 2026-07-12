// 斜杠命令补全（对照 shared/src/slashCommands.ts + web useSlashCommands.getSuggestions）
//   纯逻辑：静态内置命令表（claude/codex/gemini）+ getSuggestions 评分（精确/前缀/包含/Levenshtein）。
//
// Phase 1（HMOS）：仅静态内置。上游活命令来自 CLI RPC（扫 ~/.claude/commands 等用户/项目/插件命令），
//   设备上无 CLI，故不接 GET /api/sessions/:id/slash-commands；以内置为离线回退（上游 useSlashCommands:62-63 同款）。
//   $ 技能（$name 菜单）暂缓：来源是 CLI 文件系统（~/.claude/skills），无 CLI 则无来源，静态会成「编造内容」。

// 斜杠命令（对齐 shared/src/apiTypes.ts SlashCommand，取渲染所需字段）
export class SlashCommand {
  name: string = '';
  description: string = '';        // 可空 → ''（内置皆有；用户/插件命令上游可空）
  source: string = 'builtin';      // 'builtin' | 'user' | 'plugin' | 'project'
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
  cmd('permissions', 'Show or set permission mode'),
  cmd('permission', 'Alias for /permissions')
];
export const BUILTIN_GEMINI_COMMANDS: SlashCommand[] = [
  cmd('about', 'Show version info'),
  cmd('clear', 'Clear the screen and conversation history'),
  cmd('compress', 'Compress the context by replacing it with a summary'),
  cmd('stats', 'Check session stats')
];

function cmd(name: string, description: string): SlashCommand {
  const c: SlashCommand = new SlashCommand();
  c.name = name;
  c.description = description;
  c.source = 'builtin';
  return c;
}

// 某 agent 的内置命令（对照 getBuiltinSlashCommands；返回拷贝）。opencode/cursor 上游空数组（靠 RPC），
//   未知 agent 回退 claude（对照上游 `?? claude`）。
export function getBuiltinSlashCommands(agent: string): SlashCommand[] {
  if (agent === 'claude') { return BUILTIN_CLAUDE_COMMANDS.slice(); }
  if (agent === 'codex') { return BUILTIN_CODEX_COMMANDS.slice(); }
  if (agent === 'gemini') { return BUILTIN_GEMINI_COMMANDS.slice(); }
  if (agent === 'opencode' || agent === 'cursor') { return []; }
  return BUILTIN_CLAUDE_COMMANDS.slice();
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
