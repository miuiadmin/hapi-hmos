// SyncStateService —— 前台重同步横幅的响应式状态（纯瞬态，无 Preferences）。
//
// 架构（镜像 TerminalToolDisplayService 单例范式，但不持久化——同步态是会话级瞬态）：
//   @ObservedV2 SyncState{@Trace syncing, @Trace resyncSeq} 经 AppStorageV2 应用级共享单例。
//   - syncing：横幅显隐（SyncingBanner 读 @Trace）。
//   - resyncSeq：重同步序号（Index/ChatPage @Monitor('sync.resyncSeq') → reload → endSync）。
//   EntryAbility.onForeground 在 shouldResync 门控后调 beginSync（syncing=true + resyncSeq++ + 10s 自动清除）。
//   - sessionListSeq：会话列表静默刷新序号（对照 web pin mutation onSuccess→invalidateQueries(['sessions'])）。
//     hub 对 pin 变更不广播 session-updated SSE（sessionCache.setSessionPinMode 只写 store+refresh 内存），
//     ChatPage 置顶成功后 bump → Index @Monitor 重拉列表；不带 syncing 横幅（低频轻量刷新）。
//
//   10s setTimeout：beginSync 起 arm，endSync/再次 beginSync clearTimeout 防泄漏（避多 timer 叠加）。
//   纯门控函数 shouldResync 在 chat/SyncResync.ets（无 @kit，LocalUnit 可测）；本服务仅 @kit.ArkUI + setTimeout。

import { AppStorageV2 } from '@kit.ArkUI';

// 自动清除超时（对照上游 SyncingBanner 10s 自动消失）
const SYNC_AUTO_CLEAR_MS: number = 10000;

@ObservedV2
export class SyncState {
  @Trace syncing: boolean = false;
  @Trace resyncSeq: number = 0;
  // 会话列表静默刷新序号（详见类头注释；pin 变更无 SSE，跨页通知 Index 重拉）
  @Trace sessionListSeq: number = 0;
}

let _state: SyncState | null = null;
// 自动清除定时器句柄（clearTimeout 防泄漏；模块级单 timer）
let _autoClearId: number = -1;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存
export function getSyncState(): SyncState {
  if (_state === null) {
    _state = AppStorageV2.connect(SyncState, () => new SyncState())!;
  }
  return _state;
}

export class SyncStateService {
  // 开始同步：syncing=true + resyncSeq++（触发页面 reload）+ arm 10s 自动清除。
  //   清旧 timer 再 arm 新（连续 beginSync 不叠加多 timer）。
  static beginSync(): void {
    const s: SyncState = getSyncState();
    s.syncing = true;
    s.resyncSeq = s.resyncSeq + 1;
    if (_autoClearId !== -1) { clearTimeout(_autoClearId); }
    _autoClearId = setTimeout((): void => { SyncStateService.endSync(); }, SYNC_AUTO_CLEAR_MS);
  }

  // 结束同步：syncing=false + clear timer（页面 reload 完成或自动清除调用）。
  static endSync(): void {
    getSyncState().syncing = false;
    if (_autoClearId !== -1) { clearTimeout(_autoClearId); _autoClearId = -1; }
  }

  // 会话列表静默刷新（对照 web invalidateQueries(['sessions'])）：sessionListSeq++，
  //   Index @Monitor('sync.sessionListSeq') 重拉列表。与 beginSync 不同：不显横幅、不 arm 定时器。
  static bumpSessionList(): void {
    const s: SyncState = getSyncState();
    s.sessionListSeq = s.sessionListSeq + 1;
  }

  static get isSyncing(): boolean { return getSyncState().syncing; }
}
