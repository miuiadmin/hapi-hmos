// ToastLocalize —— 对照 web/src/App.tsx:245-297 translateIncomingToast
// 纯层（零 @kit）：服务端 SSE toast（data:{title,body,sessionId,url}）按 title 字面量分类 + 本地化。
//   SSE toast 无 severity/type，纯按 title.trim() 比对 4 个上游字面量（Ready for input / Permission Request /
//   Task completed / Task failed），命中→查 i18n 表；unknown→原样（上游 fallback 不 trim）。
//   Ready 类额外解析 body 的「X is waiting in Y」→ 插值 {agent}/{session}（替上游 /^(.+)\s+is waiting in\s+(.+)$/i，
//   手写 indexOf 切分，取原大小写）。
//   classifyToastTitle / parseReadyBody 不依赖 t（纯可测）；localizeToast 才调 t（从 i18n/Translate）。
//   忠实取舍：Ready body 多次出现分隔符时，上游贪婪正则取最后；端口 indexOf 取首个（会话名含该子串的极端场景
//   略异，服务端输出单空格常态下一致）。

import { t } from '../i18n/Translate';

export type ToastKind = 'ready' | 'permission' | 'taskCompleted' | 'taskFailed' | 'unknown';

// 本地化后的 title/body 文本对（ArkTS 类对象，避对象字面量）。
export class ToastText {
  title: string = '';
  body: string = '';
}

// Ready 类 body 解析结果（agent / session）。
export class ReadyBody {
  agent: string = '';
  session: string = '';
}

// title 分类：title.trim() 逐字比对 4 个上游字面量；皆不中→unknown。
export function classifyToastTitle(title: string): ToastKind {
  const n: string = title.trim();
  if (n === 'Ready for input') { return 'ready'; }
  if (n === 'Permission Request') { return 'permission'; }
  if (n === 'Task completed') { return 'taskCompleted'; }
  if (n === 'Task failed') { return 'taskFailed'; }
  return 'unknown';
}

// Ready 类 body 解析：替上游 /^(.+)\s+is waiting in\s+(.+)$/i。
//   body.trim() → lower 后 indexOf(' is waiting in ') 切两段；命中→各段取原 trimmed 子串（保大小写）。
//   开头即分隔（sep<=0）/ 任一段空 → null（上游 (.+) 至少一字符）。
export function parseReadyBody(body: string): ReadyBody | null {
  const trimmed: string = body.trim();
  const sep: string = ' is waiting in ';
  const lower: string = trimmed.toLowerCase();
  const idx: number = lower.indexOf(sep);
  if (idx <= 0) { return null; }   // <=0：未命中(-1) 或开头即分隔(0)
  const agent: string = trimmed.substring(0, idx).trim();
  const session: string = trimmed.substring(idx + sep.length).trim();
  if (agent === '' || session === '') { return null; }
  const out: ReadyBody = new ReadyBody();
  out.agent = agent;
  out.session = session;
  return out;
}

// 本地化（仅本函数调 t）：按 classifyToastTitle 分支查 i18n；已知类 body 取 trim 后（上游 normalizedBody），
//   unknown 取原 title/body（上游 fallback 不 trim）。Ready 命中→插值 {agent}/{session}，未命中→body 原文(trim)。
export function localizeToast(title: string, body: string): ToastText {
  const kind: ToastKind = classifyToastTitle(title);
  const normalizedBody: string = body.trim();
  const out: ToastText = new ToastText();
  if (kind === 'ready') {
    out.title = t('toast.ready.title');
    const parsed: ReadyBody | null = parseReadyBody(body);
    out.body = parsed !== null
      ? t('toast.ready.body', { agent: parsed.agent, session: parsed.session })
      : normalizedBody;
    return out;
  }
  if (kind === 'permission') {
    out.title = t('toast.permission.title');
    out.body = normalizedBody;
    return out;
  }
  if (kind === 'taskCompleted') {
    out.title = t('toast.task.completed');
    out.body = normalizedBody;
    return out;
  }
  if (kind === 'taskFailed') {
    out.title = t('toast.task.failed');
    out.body = normalizedBody;
    return out;
  }
  // unknown → 原样（上游 fallback 不 trim）
  out.title = title;
  out.body = body;
  return out;
}
