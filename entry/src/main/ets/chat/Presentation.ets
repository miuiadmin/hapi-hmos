// Presentation —— 对齐 web/src/components/ToolCard/knownTools.tsx
// 纯数据注册表：按工具名返回 { icon(emoji), title, subtitle, minimal }。无 ArkUI 依赖、无组件。
// ArkUI 无动态组件引用，Presentation 只出数据；ToolCard 据此渲染 header，卡片体特化视图在 components/ToolCardViews（P6）按名 if-chain 派发。
// emoji 替代上游 SVG 图标（ArkUI 原生渲染，无需资源文件）。

import { ChatToolCall } from './ChatBlock';
import { getInputStrAny, truncateStr, basenameOfPath, commandStr, codexPatchFiles, extractStdoutStderr } from './ToolInputUtils';
import { extractUpdatePlanChecklist } from './Checklist';
import { parseUnifiedDiff, CodexDiffParsed } from './CodexDiff';
import { t } from '../i18n/Translate';

export class ToolPresentation {
  icon: string = '🔧';
  title: string = '';
  subtitle: string = '';        // '' = null
  minimal: boolean = true;
}

// snake_case → Title Case（MCP 标题用）
function snakeToTitle(value: string): string {
  const parts: string[] = value.split('_').filter((p: string): boolean => p.length > 0);
  let out: string = '';
  for (let i = 0; i < parts.length; i++) {
    const p: string = parts[i];
    const head: string = p.charAt(0).toUpperCase();
    const tail: string = p.length > 1 ? p.substring(1).toLowerCase() : '';
    out += (i > 0 ? ' ' : '') + head + tail;
  }
  return out;
}

// MCP 工具名 → 标题：mcp__server__tool → "MCP: Server Tool"
function formatMCPTitle(toolName: string): string {
  const withoutPrefix: string = toolName.replace(/^mcp__/, '');
  const parts: string[] = withoutPrefix.split('__');
  if (parts.length >= 2) {
    const server: string = snakeToTitle(parts[0]);
    const tool: string = snakeToTitle(parts.slice(1).join('_'));
    return `MCP: ${server} ${tool}`;
  }
  return `MCP: ${snakeToTitle(withoutPrefix)}`;
}

// 从 url 取 hostname
function hostnameOf(url: string): string {
  let s: string = url;
  const proto: number = s.indexOf('://');
  if (proto >= 0) {
    s = s.substring(proto + 3);
  }
  const at: number = s.indexOf('@');
  if (at >= 0) {
    s = s.substring(at + 1);
  }
  let end: number = s.length;
  const slash: number = s.indexOf('/');
  if (slash >= 0 && slash < end) {
    end = slash;
  }
  const q: number = s.indexOf('?');
  if (q >= 0 && q < end) {
    end = q;
  }
  const col: number = s.indexOf(':');
  if (col >= 0 && col < end) {
    end = col;
  }
  return s.substring(0, end);
}

// 数一数入参里某数组字段的长度（todos 等）
function inputArrayLength(input: Record<string, Object> | null, key: string): number {
  if (input === null) {
    return 0;
  }
  const v: Object = input[key];
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return (v as Object[]).length;
  }
  return 0;
}

// 是否编辑类工具（决定 footer 是否出「允许所有编辑」）
export function isEditToolName(name: string): boolean {
  return name === 'Edit' || name === 'MultiEdit' || name === 'Write' || name === 'NotebookEdit';
}

// 是否答题类工具（footer 三选一：P7 专用 footer；P5 通用 footer 不挂）
export function isAskToolName(name: string): boolean {
  return name === 'AskUserQuestion' || name === 'ask_user_question' || name === 'request_user_input';
}

// 主入口：工具调用 → 展示数据（对照 web getToolPresentation）
export function getToolPresentation(tool: ChatToolCall): ToolPresentation {
  const p: ToolPresentation = new ToolPresentation();
  const name: string = tool.name;
  const input: Record<string, Object> | null = tool.input;
  const desc: string = tool.description;

  // MCP 工具
  if (name.indexOf('mcp__') === 0) {
    p.icon = '🧩';
    p.title = formatMCPTitle(name);
    p.subtitle = '';
    p.minimal = true;
    return p;
  }

  switch (name) {
    case 'Bash':
      p.icon = '⌨️';
      p.title = desc !== '' ? desc : t('pres.bash');
      p.subtitle = getInputStrAny(input, ['command', 'cmd']);
      p.minimal = true;
      return p;
    case 'Read':
      p.icon = '👁️';
      p.title = pathTitle(input, t('pres.read'));
      p.minimal = true;
      return p;
    case 'Edit':
      p.icon = '📝';
      p.title = pathTitle(input, t('pres.edit'));
      p.minimal = true;
      return p;
    case 'MultiEdit': {
      p.icon = '📝';
      const file: string = getInputStrAny(input, ['file_path', 'path']);
      const count: number = inputArrayLength(input, 'edits');
      if (file === '') {
        p.title = t('pres.edit');
      } else if (count > 1) {
        p.title = t('pres.multiEdit', { file: file, count: count });
      } else {
        p.title = file;
      }
      p.minimal = true;
      return p;
    }
    case 'Write': {
      p.icon = '📝';
      p.title = pathTitle(input, t('pres.write'));
      const content: string = getInputStrAny(input, ['content', 'text']);
      if (content !== '') {
        const lines: number = content.split('\n').length;
        p.subtitle = lines > 1 ? t('pres.lines', { n: lines }) : t('pres.chars', { n: content.length });
      }
      p.minimal = true;
      return p;
    }
    case 'CodexDiff': {
      // 对照上游 knownTools.tsx:413-432：icon 📝(FileDiff)、title 'Diff'、subtitle=+++ 行取 basename、
      //   minimal = unified_diff.length>=2000 || 行数>=50（大 diff 折叠进 sheet，小 diff 内联展示）。
      p.icon = '📝';
      p.title = t('diff.title');
      const unified: string = getInputStrAny(input, ['unified_diff']);
      if (unified !== '') {
        const parsed: CodexDiffParsed = parseUnifiedDiff(unified);
        if (parsed.fileName !== '') {
          p.subtitle = basenameOfPath(parsed.fileName);
        }
        const lineCount: number = unified.split('\n').length;
        p.minimal = unified.length >= 2000 || lineCount >= 50;
      } else {
        p.minimal = true;
      }
      return p;
    }
    case 'Glob':
      p.icon = '🔎';
      p.title = getInputStrAny(input, ['pattern']);
      if (p.title === '') {
        p.title = t('pres.searchFiles');
      }
      p.minimal = true;
      return p;
    case 'Grep': {
      p.icon = '👁️';
      const pattern: string = getInputStrAny(input, ['pattern']);
      p.title = pattern !== '' ? `grep(pattern: ${pattern})` : t('pres.searchContent');
      p.minimal = true;
      return p;
    }
    case 'LS':
      p.icon = '🔎';
      p.title = pathTitle(input, t('pres.listFiles'));
      p.minimal = true;
      return p;
    case 'TodoWrite': {
      p.icon = '💡';
      p.title = t('pres.todoList');
      const count: number = inputArrayLength(input, 'todos');
      p.subtitle = count > 0 ? t('pres.items', { n: count }) : '';
      p.minimal = count === 0;
      return p;
    }
    case 'update_plan': {
      p.icon = '📋';
      const steps = extractUpdatePlanChecklist(input, tool.result);
      p.title = steps.length > 0 ? t('pres.planSteps', { n: steps.length }) : t('pres.plan');
      p.minimal = steps.length === 0;   // 有步骤 → 内联清单（showInline）
      return p;
    }
    case 'WebFetch': {
      p.icon = '🌐';
      const url: string = getInputStrAny(input, ['url']);
      p.title = url !== '' ? hostnameOf(url) : t('pres.fetchPage');
      p.subtitle = url;
      p.minimal = true;
      return p;
    }
    case 'WebSearch': {
      p.icon = '🌐';
      const query: string = getInputStrAny(input, ['query']);
      p.title = query !== '' ? query : t('pres.webSearch');
      p.subtitle = query !== '' ? truncateStr(query, 80) : '';
      p.minimal = true;
      return p;
    }
    case 'Task':
    case 'Agent': {
      p.icon = '🚀';
      const d: string = getInputStrAny(input, ['description']);
      p.title = d !== '' ? d : (name === 'Task' ? t('pres.task') : t('pres.startAgent'));
      const prompt: string = getInputStrAny(input, ['prompt']);
      p.subtitle = prompt !== '' ? truncateStr(prompt, 120) : getInputStrAny(input, ['subagent_type', 'name']);
      // 子代理嵌套（children）后置；当前无 children → minimal
      p.minimal = true;
      return p;
    }
    case 'Skill': {
      p.icon = '🧩';
      const skill: string = getInputStrAny(input, ['skill']);
      p.title = skill !== '' ? t('pres.skill', { name: skill }) : t('pres.skillLabel');
      p.minimal = true;
      return p;
    }
    case 'ExitPlanMode':
    case 'exit_plan_mode':
      p.icon = '📋';
      p.title = t('pres.exitPlan');
      // 计划正文视图 P6 接（MarkdownText 渲染 input.plan）
      p.minimal = false;
      return p;
    case 'AskUserQuestion':
    case 'ask_user_question':
    case 'request_user_input': {
      p.icon = '❓';
      const questions: Object[] = inputQuestions(input);
      const count: number = questions.length;
      const firstKey: string = name === 'request_user_input' ? 'id' : 'header';
      const firstField: string = firstQuestionField(questions, firstKey);
      if (count > 1) {
        p.title = t('pres.questionCount', { n: count });
      } else {
        p.title = firstField !== '' ? firstField : t('pres.question');
      }
      const question: string = firstQuestionField(questions, 'question');
      if (count > 1 && question !== '') {
        p.subtitle = truncateStr(question, 100) + t('pres.moreCount', { n: count - 1 });
      } else if (question !== '') {
        p.subtitle = truncateStr(question, 120);
      }
      p.minimal = true;
      return p;
    }
    case 'CodexBash': {
      // 对照上游 knownTools.tsx:144-176：icon 按 parsed_cmd[0].type（read→👁️/write→📝/else 终端）；
      //   title 单 read cmd→name 路径，否则 desc??终端；subtitle command(string|[]|cmd)；minimal=输出皆空。
      const pcmd: ParsedCmd | null = parsedCmdFirst(input);
      if (pcmd !== null && pcmd.type === 'read') {
        p.icon = '👁️';
      } else if (pcmd !== null && pcmd.type === 'write') {
        p.icon = '📝';
      } else {
        p.icon = '⌨️';
      }
      if (pcmd !== null && pcmd.type === 'read' && pcmd.name !== '' && parsedCmdIsSingle(input)) {
        p.title = pcmd.name;
      } else {
        p.title = desc !== '' ? desc : t('pres.terminal');
      }
      p.subtitle = commandStr(input);
      p.minimal = bashOutputEmpty(tool.result);
      return p;
    }
    case 'shell_command':
    case 'run_shell_command':
      // 对照上游 knownTools.tsx:205-209（shell_command）+ run_shell_command 归入（上游无条目，body 已当 bash）。
      p.icon = '⌨️';
      p.title = desc !== '' ? desc : t('pres.terminal');
      p.subtitle = commandStr(input);
      p.minimal = true;
      return p;
    case 'CodexPatch': {
      // 对照上游 knownTools.tsx:397-411 + CodexPatchView：icon 📝、title「应用更改」、subtitle 首文件 basename（多文件 +N）。
      p.icon = '📝';
      p.title = t('pres.applyChanges');
      const files: string[] = codexPatchFiles(input);
      if (files.length === 1) {
        p.subtitle = basenameOfPath(files[0]);
      } else if (files.length > 1) {
        p.subtitle = t('pres.patchFiles', { name: basenameOfPath(files[0]), n: files.length - 1 });
      }
      p.minimal = true;
      return p;
    }
    case 'CodexPermission': {
      // 对照上游 knownTools.tsx:178-186：icon ❓、title tool?「权限：tool」:「权限请求」、subtitle message??command。
      p.icon = '❓';
      const toolName: string = getInputStrAny(input, ['tool']);
      p.title = toolName !== '' ? t('pres.permission', { tool: toolName }) : t('pres.permissionRequest');
      p.subtitle = getInputStrAny(input, ['message', 'command']);
      p.minimal = true;
      return p;
    }
    default: {
      // 未知工具：字段探测兜底（file_path/command/pattern/url/query/name）
      p.icon = '🔧';
      const filePath: string = getInputStrAny(input, ['file_path', 'path', 'filePath', 'file']);
      const command: string = getInputStrAny(input, ['command', 'cmd']);
      const pattern: string = getInputStrAny(input, ['pattern']);
      const url: string = getInputStrAny(input, ['url']);
      const query: string = getInputStrAny(input, ['query']);
      const nm: string = getInputStrAny(input, ['name']);
      const subtitle: string = firstNonEmpty([filePath, command, pattern, url, query, nm]);
      // 若工具名等于某字段值，提升语义标题（避免标题副标题同字符串重复）
      let title: string = name;
      if (subtitle !== '' && subtitle === title) {
        if (filePath !== '') {
          title = t('pres.read');
        } else if (command !== '') {
          title = t('pres.runCommand');
        } else if (pattern !== '') {
          title = t('pres.search');
        } else if (url !== '') {
          title = t('pres.openLink');
        } else if (query !== '') {
          title = t('pres.query');
        }
      }
      p.title = title;
      p.subtitle = subtitle !== '' && subtitle !== title ? truncateStr(subtitle, 80) : '';
      p.minimal = true;
      return p;
    }
  }
}

// 路径类标题：file_path|path|file，缺省 fallback
function pathTitle(input: Record<string, Object> | null, fallback: string): string {
  const f: string = getInputStrAny(input, ['file_path', 'path', 'file']);
  return f !== '' ? f : fallback;
}

function firstNonEmpty(values: string[]): string {
  for (let i = 0; i < values.length; i++) {
    if (values[i] !== '') {
      return values[i];
    }
  }
  return '';
}

// CodexBash parsed_cmd 首条解析结果（type: read/write/…；name: 文件名）
class ParsedCmd {
  type: string = '';
  name: string = '';
}

// 取 input.parsed_cmd[0] 的 {type, name}；非数组/空/首条非对象 → null（对照上游 CodexBash icon/title 判定）
function parsedCmdFirst(input: Record<string, Object> | null): ParsedCmd | null {
  if (input === null) {
    return null;
  }
  const arr: Object = input['parsed_cmd'];
  if (!Array.isArray(arr) || (arr as Object[]).length === 0) {
    return null;
  }
  const first: Object = (arr as Object[])[0];
  if (first === null || first === undefined || typeof first !== 'object' || Array.isArray(first)) {
    return null;
  }
  const rec: Record<string, Object> = first as Record<string, Object>;
  const t: Object = rec['type'];
  const n: Object = rec['name'];
  const out: ParsedCmd = new ParsedCmd();
  out.type = typeof t === 'string' ? t : '';
  out.name = typeof n === 'string' ? n : '';
  return out;
}

// input.parsed_cmd 是否恰好一条（单 read cmd 时 title 用文件名）
function parsedCmdIsSingle(input: Record<string, Object> | null): boolean {
  if (input === null) {
    return false;
  }
  const arr: Object = input['parsed_cmd'];
  return Array.isArray(arr) && (arr as Object[]).length === 1;
}

// CodexBash minimal：stdout 与 stderr 均 trim 空 → true（有输出 → 内联展示）
function bashOutputEmpty(result: Object | null): boolean {
  const stdio: { stdout: string; stderr: string } | null = extractStdoutStderr(result);
  if (stdio === null) {
    return true;
  }
  return stdio.stdout.trim() === '' && stdio.stderr.trim() === '';
}

// 取 input.questions 数组（答题工具）
function inputQuestions(input: Record<string, Object> | null): Object[] {
  if (input === null) {
    return [];
  }
  const v: Object = input['questions'];
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return v as Object[];
  }
  return [];
}

// 取 questions[0][field] 字符串（trim）
function firstQuestionField(questions: Object[], field: string): string {
  if (questions.length === 0) {
    return '';
  }
  const first: Object = questions[0];
  if (first === null || first === undefined || typeof first !== 'object') {
    return '';
  }
  const v: Object = (first as Record<string, Object>)[field];
  if (typeof v === 'string') {
    return v.trim();
  }
  return '';
}
