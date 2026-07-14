// 前台重同步门控纯逻辑层（无 @kit，LocalUnit 可测）。
//   对照上游 SyncingBanner 的「离开 30s 门控」：切后台超 30s 回前台才触发重同步横幅。
//   纯函数不调 Date.now()（保持可测），由调用方（EntryAbility）传 now（app 代码可用 Date.now()）。
//   阈值 30000ms（对照上游）；lastHideAt=0（从未后台）→ 不触发（首次前台不算重同步）。

export const RESYNC_THRESHOLD_MS: number = 30000;

// 是否需要重同步：now - lastHideAt > 阈值（lastHideAt=0 → false，避首启误触）。
export function shouldResync(now: number, lastHideAt: number): boolean {
  if (lastHideAt === 0) { return false; }
  return now - lastHideAt > RESYNC_THRESHOLD_MS;
}
