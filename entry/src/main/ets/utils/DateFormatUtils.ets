// 日期 / 时间格式化纯函数（消息时间戳 + 跨日日期分隔用）。
// 语义对照 chatcube utils/DateFormatUtils.ets（MIT，保留版权）：今天 / 昨天 / M月D日 / YYYY年M月D日 分档，
// 以及「首条或跨日显示分隔」规则。纯函数无副作用，可被 LocalUnit 直接测试。
// timestamp <= 0 一律视为无值（对齐 ChatBlock.createdAt 的「0 = null」约定），返回空串 / 不显示。

import { t } from '../i18n/Translate';

/**
 * 日期分隔文本：今天 / 昨天 / 同年 M月D日 / 跨年 YYYY年M月D日。ts<=0 返回空。
 */
export function formatDateDivider(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const date: Date = new Date(timestamp);
  const now: Date = new Date();
  // 当日 / 昨日零点（只比年月日）
  const today0: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday0: Date = new Date(today0.getTime() - 24 * 60 * 60 * 1000);
  const message0: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  if (message0.getTime() === today0.getTime()) {
    return t('date.today');
  }
  if (message0.getTime() === yesterday0.getTime()) {
    return t('date.yesterday');
  }
  if (date.getFullYear() === now.getFullYear()) {
    return t('date.monthDay', { m: date.getMonth() + 1, d: date.getDate() });
  }
  return t('date.yearMonthDay', { y: date.getFullYear(), m: date.getMonth() + 1, d: date.getDate() });
}

/**
 * 是否在 currentTs 处插入日期分隔：
 *   - currentTs<=0（无值）→ 永不显示
 *   - previousTs<=0（无前条，即首条）→ 显示
 *   - 否则：与上一条不同日 → 显示
 * 取 number（0 表无）而非 nullable，对齐 ChatBlock.createdAt 约定、便于 ForEach 内联调用。
 */
export function shouldShowDateDivider(currentTs: number, previousTs: number): boolean {
  if (currentTs <= 0) {
    return false;
  }
  if (previousTs <= 0) {
    return true;
  }
  const cur: Date = new Date(currentTs);
  const prev: Date = new Date(previousTs);
  return cur.getFullYear() !== prev.getFullYear()
    || cur.getMonth() !== prev.getMonth()
    || cur.getDate() !== prev.getDate();
}

/**
 * 消息时间 HH:mm（24 时制，两位补零）。ts<=0 返回空。
 * 对照上游 formatMessageTimestamp 的「同日仅显示时分」：因日期已由 DateDivider 承载，
 * 故每条消息的时间恒只取时分（与上游 same-day 分支一致）。
 */
export function formatClock(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const d: Date = new Date(timestamp);
  const h: number = d.getHours();
  const m: number = d.getMinutes();
  const hh: string = h < 10 ? `0${h}` : `${h}`;
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  return `${hh}:${mm}`;
}

/**
 * 消息调用时间 HH:mm:ss（24 时制，秒级，对照上游 MessageMetadata 的 Invoke 秒精度）。
 * ts<=0 返回空。用于每消息元数据脚注（formatClock 仅到分，此处补秒以区分气泡时间戳）。
 */
export function formatClockSeconds(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }
  const d: Date = new Date(timestamp);
  const h: number = d.getHours();
  const m: number = d.getMinutes();
  const s: number = d.getSeconds();
  const hh: string = h < 10 ? `0${h}` : `${h}`;
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const ss: string = s < 10 ? `0${s}` : `${s}`;
  return `${hh}:${mm}:${ss}`;
}
