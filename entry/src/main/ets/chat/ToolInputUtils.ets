// 工具入参/结果提取工具（对照 web ToolCard 各 view 的字段读取 + 结果文本提取）
// 纯函数，无 ArkUI 依赖。供 Presentation / ToolCardViews / 结果视图使用。

// 从工具入参取字符串字段（file_path / command / pattern / url / description 等），缺失或非 string → ''
export function getInputStr(input: Record<string, Object> | null, key: string): string {
  if (input === null) {
    return '';
  }
  const v: Object = input[key];
  return typeof v === 'string' ? v : '';
}

// 键是否存在且为 string（区分「空串值」与「缺失」：Edit 的 old_string 合法可为 ''，故需此判定）
export function hasInputStr(input: Record<string, Object> | null, key: string): boolean {
  if (input === null) {
    return false;
  }
  return typeof input[key] === 'string';
}

// 多候选键取首个非空字符串（对照 web getInputStringAny：如 file_path|path|file、command|cmd）
export function getInputStrAny(input: Record<string, Object> | null, keys: string[]): string {
  if (input === null) {
    return '';
  }
  for (let i = 0; i < keys.length; i++) {
    const v: Object = input[keys[i]];
    if (typeof v === 'string' && v !== '') {
      return v;
    }
  }
  return '';
}

// 截断（按字符数），超出加省略号
export function truncateStr(s: string, max: number): string {
  if (max <= 0 || s.length <= max) {
    return s;
  }
  return s.substring(0, max) + '…';
}

// <tool_use_error>…</tool_use_error> 标签剥离（对照 web _results.tsx parseToolUseError）
// 手写扫描器（非正则，避 s-flag dotall 限制）：仅取首对 tag 的 inner（trim），不管外层文本。
const TOOL_USE_ERROR_OPEN: string = '<tool_use_error>';
const TOOL_USE_ERROR_CLOSE: string = '</tool_use_error>';

export function parseToolUseError(message: string): { isToolUseError: boolean; errorMessage: string | null } {
  const openIdx: number = message.indexOf(TOOL_USE_ERROR_OPEN);
  if (openIdx < 0) {
    return { isToolUseError: false, errorMessage: null };
  }
  const innerStart: number = openIdx + TOOL_USE_ERROR_OPEN.length;
  const closeIdx: number = message.indexOf(TOOL_USE_ERROR_CLOSE, innerStart);
  if (closeIdx < 0) {
    return { isToolUseError: false, errorMessage: null };
  }
  return { isToolUseError: true, errorMessage: message.substring(innerStart, closeIdx).trim() };
}

// 单个内容块取文本：string 直返；对象优先 type==='text' 的 text，次取裸 text（对照 web extractTextFromContentBlock）
function extractTextFromContentBlock(block: Object | null | undefined): string | null {
  if (typeof block === 'string') {
    return block;
  }
  if (block === null || block === undefined || typeof block !== 'object') {
    return null;
  }
  const r: Record<string, Object> = block as Record<string, Object>;
  const btype: Object = r['type'];
  const btext: Object = r['text'];
  if (btype === 'text' && typeof btext === 'string') {
    return btext;
  }
  if (typeof btext === 'string') {
    return btext;
  }
  return null;
}

// flat 字符串字段优先序（对照 web extractTextFromResult：content→text→output→error→message）
const RESULT_FLAT_KEYS: string[] = ['content', 'text', 'output', 'error', 'message'];

// 递归提取结果文本（对照 web extractTextFromResult）。返回 null 表示未命中；depth > 2 截断。
//   string → 剥 tool_use_error 后原样
//   Array  → 各内容块文本换行拼接
//   object → flat 字符串字段 → content 数组 → 嵌套 output.{content,text} → 嵌套 error.{message,error} → 递归 result/data
function extractTextDeep(result: Object | null | undefined, depth: number): string | null {
  if (depth > 2) {
    return null;
  }
  if (result === null || result === undefined) {
    return null;
  }
  if (typeof result === 'string') {
    const tue: { isToolUseError: boolean; errorMessage: string | null } = parseToolUseError(result);
    return tue.isToolUseError ? (tue.errorMessage ?? '') : result;
  }
  if (Array.isArray(result)) {
    const arr: Object[] = result as Object[];
    const parts: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const t: string | null = extractTextFromContentBlock(arr[i]);
      if (t !== null && t.length > 0) {
        parts.push(t);
      }
    }
    return parts.length > 0 ? parts.join('\n') : null;
  }
  if (typeof result !== 'object') {
    return null;
  }
  const rec: Record<string, Object> = result as Record<string, Object>;

  // flat 字符串字段
  for (let i = 0; i < RESULT_FLAT_KEYS.length; i++) {
    const v: Object = rec[RESULT_FLAT_KEYS[i]];
    if (typeof v === 'string') {
      return v;
    }
  }

  // content 为数组
  const contentVal: Object = rec['content'];
  if (Array.isArray(contentVal)) {
    const carr: Object[] = contentVal as Object[];
    const parts: string[] = [];
    for (let i = 0; i < carr.length; i++) {
      const t: string | null = extractTextFromContentBlock(carr[i]);
      if (t !== null && t.length > 0) {
        parts.push(t);
      }
    }
    if (parts.length > 0) {
      return parts.join('\n');
    }
  }

  // 嵌套 output.{content,text}
  const outputVal: Object = rec['output'];
  if (outputVal !== null && outputVal !== undefined && typeof outputVal === 'object' && !Array.isArray(outputVal)) {
    const orec: Record<string, Object> = outputVal as Record<string, Object>;
    if (typeof orec['content'] === 'string') {
      return orec['content'] as string;
    }
    if (typeof orec['text'] === 'string') {
      return orec['text'] as string;
    }
  }

  // 嵌套 error.{message,error}
  const errorVal: Object = rec['error'];
  if (errorVal !== null && errorVal !== undefined && typeof errorVal === 'object' && !Array.isArray(errorVal)) {
    const erec: Record<string, Object> = errorVal as Record<string, Object>;
    if (typeof erec['message'] === 'string') {
      return erec['message'] as string;
    }
    if (typeof erec['error'] === 'string') {
      return erec['error'] as string;
    }
  }

  // 递归 result
  const resultVal: Object = rec['result'];
  if (resultVal !== null && resultVal !== undefined && typeof resultVal === 'object' && !Array.isArray(resultVal)) {
    const nested: string | null = extractTextDeep(resultVal, depth + 1);
    if (nested !== null) {
      return nested;
    }
  }

  // 递归 data
  const dataVal: Object = rec['data'];
  if (dataVal !== null && dataVal !== undefined && typeof dataVal === 'object' && !Array.isArray(dataVal)) {
    const nested: string | null = extractTextDeep(dataVal, depth + 1);
    if (nested !== null) {
      return nested;
    }
  }

  return null;
}

// 从 tool_result.content 提取可展示文本（公开 API，契约 (Object|null)→string 不变）。
//   string（含 <tool_use_error> 剥离）/ Array<内容块> / 嵌套对象（递归 result/data、output/error 嵌套，深度 ≤2）
export function extractResultText(content: Object | null): string {
  return extractTextDeep(content, 0) ?? '';
}

// Bash 结果：从对象取 {stdout, stderr}（含 output 嵌套），任一非空即返回；否则 null
export function extractStdoutStderr(result: Object | null): { stdout: string; stderr: string } | null {
  if (result === null || result === undefined || typeof result !== 'object' || Array.isArray(result)) {
    return null;
  }
  const rec: Record<string, Object> = result as Record<string, Object>;
  const stdoutRaw: Object = rec['stdout'];
  const stderrRaw: Object = rec['stderr'];
  const stdout: string = typeof stdoutRaw === 'string' ? stdoutRaw : '';
  const stderr: string = typeof stderrRaw === 'string' ? stderrRaw : '';
  if (stdout !== '' || stderr !== '') {
    return { stdout, stderr };
  }
  // 嵌套 output.stdout/stderr
  const nested: Object = rec['output'];
  if (nested !== null && nested !== undefined && typeof nested === 'object' && !Array.isArray(nested)) {
    const nr: Record<string, Object> = nested as Record<string, Object>;
    const ns: string = typeof nr['stdout'] === 'string' ? nr['stdout'] as string : '';
    const ne: string = typeof nr['stderr'] === 'string' ? nr['stderr'] as string : '';
    if (ns !== '' || ne !== '') {
      return { stdout: ns, stderr: ne };
    }
  }
  return null;
}

// 文本是否多行（决定结果用 CodeBlock 还是普通 Text，对照上游 getMutationResultRenderMode）
export function isMultilineText(text: string): boolean {
  return text.split('\n').length > 3;
}

// 看起来像 JSON（{...} / [...]）
export function looksLikeJson(text: string): boolean {
  const t: string = text.trim();
  return (t.indexOf('{') === 0 && t.lastIndexOf('}') === t.length - 1)
    || (t.indexOf('[') === 0 && t.lastIndexOf(']') === t.length - 1);
}

// 看起来像 HTML（文档片段）
export function looksLikeHtml(text: string): boolean {
  const t: string = text.trimStart();
  return t.startsWith('<!DOCTYPE') || t.startsWith('<html') || t.startsWith('<div') || t.startsWith('<span');
}

// 取路径末段（标题里显短文件名用；对照上游 utils/path basename）。`/` 与 `\` 分隔，手写无 regex。
export function basenameOfPath(path: string): string {
  const i: number = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  return i >= 0 ? path.substring(i + 1) : path;
}

// 终端类工具的命令串：input.command 是 string 直返；是 Array 过滤 string 后 join(' ')；否则回落 cmd 键。
//   （对照上游 CodexBash/shell_command subtitle：command 字符串或 command[] 拼接。供 Presentation + ToolCardViews 共用。）
export function commandStr(input: Record<string, Object> | null): string {
  if (input !== null) {
    const cmd: Object = input['command'];
    if (typeof cmd === 'string') {
      return cmd;
    }
    if (Array.isArray(cmd)) {
      const arr: Object[] = cmd as Object[];
      const parts: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          parts.push(arr[i] as string);
        }
      }
      return parts.join(' ');
    }
  }
  return getInputStrAny(input, ['cmd']);
}

// CodexPatch（apply_patch）改动文件名列表：input.changes 是对象（文件→改动映射）→ Object.keys；否则 []。
//   （对照上游 CodexPatchView：Object.keys(input.changes)。不展开改动内容，仅列文件名，忠实上游。）
export function codexPatchFiles(input: Record<string, Object> | null): string[] {
  if (input === null) {
    return [];
  }
  const changes: Object = input['changes'];
  if (changes === null || changes === undefined || typeof changes !== 'object' || Array.isArray(changes)) {
    return [];
  }
  return Object.keys(changes as Record<string, Object>);
}

// NotebookEdit（Claude Jupyter）cell 编辑字段：cell_id / cell_type / edit_mode / new_source。
//   上游 input: unknown 且从不命名这些字段（仅 notebook_path/edit_mode 进头）；端口增强：结构化 cell body。
//   全 string，缺失/非串 → ''（与 getInputStrAny 哨兵一致）。
export class NotebookEditFields {
  cellId: string = '';
  cellType: string = '';   // 'markdown' | 'code' | ''
  editMode: string = '';   // 'insert' | 'replace' | 'delete' | ''（与头 subtitle 同源，body 不强依赖）
  newSource: string = '';
}

export function extractNotebookEditFields(input: Record<string, Object> | null): NotebookEditFields {
  const f: NotebookEditFields = new NotebookEditFields();
  if (input === null) {
    return f;
  }
  f.cellId = getInputStrAny(input, ['cell_id']);
  f.cellType = getInputStrAny(input, ['cell_type']);
  f.editMode = getInputStrAny(input, ['edit_mode']);
  f.newSource = getInputStrAny(input, ['new_source']);
  return f;
}

// cell 元信息行：`cellType · #cellId`（cellId 截断 12 防溢出）。手写循环拼（不用 spread/replace）。双空 → ''。
export function formatNotebookCellMeta(cellType: string, cellId: string): string {
  const parts: string[] = [];
  if (cellType !== '') {
    parts.push(cellType);
  }
  if (cellId !== '') {
    parts.push('#' + truncateStr(cellId, 12));
  }
  return parts.join(' · ');
}
