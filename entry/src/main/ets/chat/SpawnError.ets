// spawn 错误诊断纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 web/src/utils/formatRunnerSpawnError.ts：
//     getLastSpawnError(runnerState) → {message, at?} | null
//     formatRunnerSpawnError(machine) → "message (at 本地化)" | "message" | null
//   本层只做文案拼接（message + 时间）；时间复用 DateFormatUtils 纯函数（Translate 纯层）。
//   Machine 字段的解析（runnerState.lastSpawnError）在 models/Types.ets parseMachine。

import { formatDateDivider, formatClock } from '../utils/DateFormatUtils';

/**
 * 格式化机器上次 spawn 错误为诊断文案。
 *   - message 空 → ''（无错误，调用方据此不显示）
 *   - at>0 → "message (日期 时分)"（本地化，如「今天 15:30」/「7月14日 15:30」）
 *   - at<=0 → "message"（无时间戳）
 * 对照上游 formatRunnerSpawnError：有 at 时追加括号内本地化时间。
 */
export function formatMachineSpawnError(message: string, at: number): string {
  if (message === '') {
    return '';
  }
  if (at > 0) {
    const date = formatDateDivider(at);
    const clock = formatClock(at);
    if (date !== '' && clock !== '') {
      return `${message} (${date} ${clock})`;
    }
  }
  return message;
}
