// EventPresentation —— 对齐 web/src/chat/presentation.ts getEventPresentation。
// 纯逻辑层（无 @kit）：AgentEvent → { icon, text }，供 ChatPage 渲染居中灰条系统消息
//   （#1 系统消息条 / #4 限额提示）。覆盖当前产出的 type：api-error / microcompact / compact /
//   limit-warning / limit-reached；其余 type（switch / title-changed / permission-mode-changed /
//   message / turn-duration / thread-goal* / token-count）随其解析一并 deferred 或已由专属渲染路径
//   处理（turn-duration→脚注、thread-goal→chip、token-count→用量条），命中则走通用 JSON.stringify 回退
//   （对照 presentation.ts:209-213）。
//
//   时间格式化移植 presentation.ts:3-27 的语义，但改用项目既有 DateFormatUtils（formatClock /
//   formatDateDivider，手写、确定性、随 i18n locale）替代上游 toLocaleString（locale 不可控、不利于单测）：
//     formatResetTime：今日→HH:mm；非今日→「M月D日 HH:mm」。
//     formatUnixTimestamp：恒「M月D日 HH:mm」。timestamp 容忍秒（<1e12 → ×1000，对照 normalizeTimestamp）。

import { AgentEvent } from '../models/Types';
import { formatClock, formatDateDivider } from '../utils/DateFormatUtils';
import { t } from '../i18n/Translate';

export class EventPresentation {
  icon: string = '';   // '' = 无图标（上游 null；居中灰条不显图标）
  text: string = '';
}

// <1e12 视为秒级 → ×1000（对照 presentation.ts:3-6 normalizeTimestamp）。
function normalizeTimestampMs(value: number): number {
  return value < 1000000000000 ? value * 1000 : value;
}

// 限额重置时间：今日→HH:mm；非今日→「日期 HH:mm」（对照 presentation.ts:14-27 formatResetTime）。
function formatResetTime(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const ms: number = normalizeTimestampMs(ts);
  const date: Date = new Date(ms);
  const now: Date = new Date();
  const isToday: boolean = date.getFullYear() === now.getFullYear()
    && date.getMonth() === now.getMonth()
    && date.getDate() === now.getDate();
  const clock: string = formatClock(ms);
  if (isToday) {
    return clock;
  }
  const day: string = formatDateDivider(ms);
  return day + ' ' + clock;
}

// 完整时间戳「日期 HH:mm」（对照 presentation.ts:8-12 formatUnixTimestamp，恒带日期）。
function formatUnixTimestamp(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const ms: number = normalizeTimestampMs(ts);
  return formatDateDivider(ms) + ' ' + formatClock(ms);
}

// 限额类型标签：five_hour→5-hour、seven_day→7-day、其余下划线→空格
//   （对照 presentation.ts:59-64 formatLimitType，手写下划线扫描免 regex）。
function formatLimitType(limitType: string): string {
  if (limitType === '') {
    return '';
  }
  if (limitType === 'five_hour') {
    return '5-hour';
  }
  if (limitType === 'seven_day') {
    return '7-day';
  }
  let out: string = '';
  for (let i = 0; i < limitType.length; i++) {
    out += limitType.charAt(i) === '_' ? ' ' : limitType.charAt(i);
  }
  return out;
}

// 类型标签 → 带括号后缀（空标签 → ''；对照 presentation.ts:174-175/181-182 suffix 构造）。
function limitTypeSuffix(limitType: string): string {
  const label: string = formatLimitType(limitType);
  return label !== '' ? ` (${label})` : '';
}

// AgentEvent → { icon, text }（对照 presentation.ts:143-214 getEventPresentation）。
export function getEventPresentation(event: AgentEvent): EventPresentation {
  const p: EventPresentation = new EventPresentation();

  if (event.type === 'api-error') {
    if (event.maxRetries > 0 && event.retryAttempt >= event.maxRetries) {
      p.icon = '⚠️';
      p.text = t('event.apiErrorMaxRetries');
    } else if (event.maxRetries > 0) {
      p.icon = '⏳';
      p.text = t('event.apiErrorRetrying', { n: event.retryAttempt, m: event.maxRetries });
    } else if (event.retryAttempt > 0) {
      p.icon = '⏳';
      p.text = t('event.apiErrorRetryingSimple');
    } else {
      p.icon = '⚠️';
      p.text = t('event.apiError');
    }
    return p;
  }

  if (event.type === 'microcompact') {
    // saved≥1000 →「NK」（对照 presentation.ts:193-195，阈值 1000，非 formatTokenCount 的 1k）。
    const saved: number = event.tokensSaved;
    const savedStr: string = saved >= 1000 ? `${Math.round(saved / 1000)}K` : `${saved}`;
    p.icon = '📦';
    p.text = t('event.contextCompactedSaved', { saved: savedStr });
    return p;
  }

  if (event.type === 'compact') {
    p.icon = '📦';
    p.text = t('event.conversationCompacted');
    return p;
  }

  if (event.type === 'limit-warning') {
    const pct: number = Math.round(event.utilization * 100);
    const suffix: string = limitTypeSuffix(event.limitType);
    p.icon = '⚠️';
    if (event.endsAt > 0) {
      p.text = t('event.usageLimitWarning', { pct: pct, suffix: suffix, resets: formatResetTime(event.endsAt) });
    } else {
      p.text = t('event.usageLimitWarningNoReset', { pct: pct, suffix: suffix });
    }
    return p;
  }

  if (event.type === 'limit-reached') {
    const suffix: string = limitTypeSuffix(event.limitType);
    p.icon = '⏳';
    if (event.endsAt > 0) {
      p.text = t('event.usageLimitReached', { suffix: suffix, time: formatUnixTimestamp(event.endsAt) });
    } else {
      p.text = t('event.usageLimitReachedNoTime', { suffix: suffix });
    }
    return p;
  }

  // 通用回退（对照 presentation.ts:209-213）：未知 type → JSON 串；不可序列化 → type 串。
  try {
    p.text = JSON.stringify(event);
  } catch (e) {
    p.text = event.type;
  }
  return p;
}
