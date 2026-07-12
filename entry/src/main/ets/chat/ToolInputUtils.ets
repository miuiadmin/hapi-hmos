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

// 从 tool_result.content 提取可展示文本。content 形态多样：
//   string                            → 原样
//   Array<{type:'text', text:string}> → 拼接各 text（Anthropic 标准格式）
//   Array<string>                     → 换行拼接
//   其它对象                           → 尽力取 .text/.output/.message，否则 ''
export function extractResultText(content: Object | null): string {
  if (content === null || content === undefined) {
    return '';
  }
  if (typeof content === 'string') {
    return content;
  }
  if (Array.isArray(content)) {
    const arr: Object[] = content as Object[];
    const parts: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item: Object = arr[i];
      if (typeof item === 'string') {
        parts.push(item);
      } else if (item !== null && item !== undefined && typeof item === 'object') {
        const rec: Record<string, Object> = item as Record<string, Object>;
        const t: Object = rec['text'];
        if (typeof t === 'string') {
          parts.push(t);
        }
      }
    }
    return parts.join('\n');
  }
  if (typeof content === 'object') {
    const rec: Record<string, Object> = content as Record<string, Object>;
    const keys: string[] = ['text', 'output', 'message', 'content'];
    for (let i = 0; i < keys.length; i++) {
      const v: Object = rec[keys[i]];
      if (typeof v === 'string') {
        return v;
      }
    }
  }
  return '';
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
