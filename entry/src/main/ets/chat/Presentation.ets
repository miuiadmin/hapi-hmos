// Presentation —— 对齐 web/src/components/ToolCard/knownTools.tsx
// 纯数据注册表：按工具名返回 { icon(emoji), title, subtitle, minimal }。无 ArkUI 依赖、无组件。
// ArkUI 无动态组件引用，Presentation 只出数据；ToolCard 据此渲染 header，卡片体特化视图在 components/ToolCardViews（P6）按名 if-chain 派发。
// emoji 替代上游 SVG 图标（ArkUI 原生渲染，无需资源文件）。

import { ChatToolCall } from './ChatBlock';
import { getInputStrAny, truncateStr } from './ToolInputUtils';
import { extractUpdatePlanChecklist } from './Checklist';

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

// 取路径末段（标题里显示短文件名用）
function basenameOf(path: string): string {
  const i: number = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.substring(i + 1) : path;
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
      p.title = desc !== '' ? desc : '终端';
      p.subtitle = getInputStrAny(input, ['command', 'cmd']);
      p.minimal = true;
      return p;
    case 'Read':
      p.icon = '👁️';
      p.title = pathTitle(input, '读取文件');
      p.minimal = true;
      return p;
    case 'Edit':
      p.icon = '📝';
      p.title = pathTitle(input, '编辑文件');
      p.minimal = true;
      return p;
    case 'MultiEdit': {
      p.icon = '📝';
      const file: string = getInputStrAny(input, ['file_path', 'path']);
      const count: number = inputArrayLength(input, 'edits');
      if (file === '') {
        p.title = '编辑文件';
      } else if (count > 1) {
        p.title = `${file}（${count} 处）`;
      } else {
        p.title = file;
      }
      p.minimal = true;
      return p;
    }
    case 'Write': {
      p.icon = '📝';
      p.title = pathTitle(input, '写入文件');
      const content: string = getInputStrAny(input, ['content', 'text']);
      if (content !== '') {
        const lines: number = content.split('\n').length;
        p.subtitle = lines > 1 ? `${lines} 行` : `${content.length} 字符`;
      }
      p.minimal = true;
      return p;
    }
    case 'Glob':
      p.icon = '🔎';
      p.title = getInputStrAny(input, ['pattern']);
      if (p.title === '') {
        p.title = '搜索文件';
      }
      p.minimal = true;
      return p;
    case 'Grep': {
      p.icon = '👁️';
      const pattern: string = getInputStrAny(input, ['pattern']);
      p.title = pattern !== '' ? `grep(pattern: ${pattern})` : '搜索内容';
      p.minimal = true;
      return p;
    }
    case 'LS':
      p.icon = '🔎';
      p.title = pathTitle(input, '列出文件');
      p.minimal = true;
      return p;
    case 'TodoWrite': {
      p.icon = '💡';
      p.title = '待办清单';
      const count: number = inputArrayLength(input, 'todos');
      p.subtitle = count > 0 ? `${count} 项` : '';
      p.minimal = count === 0;
      return p;
    }
    case 'update_plan': {
      p.icon = '📋';
      const steps = extractUpdatePlanChecklist(input, tool.result);
      p.title = steps.length > 0 ? `计划（${steps.length} 步）` : '计划';
      p.minimal = steps.length === 0;   // 有步骤 → 内联清单（showInline）
      return p;
    }
    case 'WebFetch': {
      p.icon = '🌐';
      const url: string = getInputStrAny(input, ['url']);
      p.title = url !== '' ? hostnameOf(url) : '抓取网页';
      p.subtitle = url;
      p.minimal = true;
      return p;
    }
    case 'WebSearch': {
      p.icon = '🌐';
      const query: string = getInputStrAny(input, ['query']);
      p.title = query !== '' ? query : '网页搜索';
      p.subtitle = query !== '' ? truncateStr(query, 80) : '';
      p.minimal = true;
      return p;
    }
    case 'Task':
    case 'Agent': {
      p.icon = '🚀';
      const d: string = getInputStrAny(input, ['description']);
      p.title = d !== '' ? d : (name === 'Task' ? '任务' : '启动 Agent');
      const prompt: string = getInputStrAny(input, ['prompt']);
      p.subtitle = prompt !== '' ? truncateStr(prompt, 120) : getInputStrAny(input, ['subagent_type', 'name']);
      // 子代理嵌套（children）后置；当前无 children → minimal
      p.minimal = true;
      return p;
    }
    case 'Skill': {
      p.icon = '🧩';
      const skill: string = getInputStrAny(input, ['skill']);
      p.title = skill !== '' ? `技能: ${skill}` : '技能';
      p.minimal = true;
      return p;
    }
    case 'ExitPlanMode':
    case 'exit_plan_mode':
      p.icon = '📋';
      p.title = '计划方案';
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
        p.title = `${count} 个问题`;
      } else {
        p.title = firstField !== '' ? firstField : '问题';
      }
      const question: string = firstQuestionField(questions, 'question');
      if (count > 1 && question !== '') {
        p.subtitle = truncateStr(question, 100) + `（还有 ${count - 1} 个）`;
      } else if (question !== '') {
        p.subtitle = truncateStr(question, 120);
      }
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
          title = '读取文件';
        } else if (command !== '') {
          title = '运行命令';
        } else if (pattern !== '') {
          title = '搜索';
        } else if (url !== '') {
          title = '打开链接';
        } else if (query !== '') {
          title = '查询';
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
