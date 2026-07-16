// ToastService —— 服务端 SSE toast 的响应态单例（应用级共享，纯瞬态）。
//
// 架构（镜像 SyncStateService / DeviceNetworkService 的 @ObservedV2 + AppStorageV2.connect 范式）：
//   @ObservedV2 ToastState{@Trace current: ServerToastData|null} 经 AppStorageV2 应用级共享单例。
//   ServerToastOverlay 读 getToastState().current（@Trace）建立刷新依赖 → current 变即重渲染。
//   AppStorageV2 为内存态（非 PersistentStorageV2），进程重启即清空 → 不残留上次未消失的 toast。
//
//   单卡替换（移动端简化）：上游 toast-context.tsx 用数组堆叠多卡 + 每卡独立 6s timer；此处简化为单 current
//   （新 toast 覆盖旧 + 重置 6s 自动消失），更贴合手机通知 UX、组件更简。
//   token 防误关：每次 show 自增 token；timer 回调比对 token，仅当 current 仍是本次设的才清除
//   （避免后到的 toast 被前一个 toast 的过期 timer 误关，对照 SyncStateService 单 timer + clearTimeout 范式）。
//
//   ToastService.show / dismiss 为静态方法（避与 utils/Toast.showToast 函数同名冲突；Index.showServerToast 改用本服务）。
//   仅 @kit.ArkUI（AppStorageV2）+ setTimeout，无其它 @kit。

import { AppStorageV2 } from '@kit.ArkUI';

// 对照上游 toast-context.tsx:19 TOAST_DURATION_MS
const TOAST_DURATION_MS: number = 6000;

// 单条 toast 数据（token 为内部防误关用，UI 不读）
export class ServerToastData {
  title: string = '';
  body: string = '';
  sessionId: string = '';
  token: number = 0;
}

@ObservedV2
export class ToastState {
  @Trace current: ServerToastData | null = null;
}

let _state: ToastState | null = null;
let _tokenSeq: number = 0;     // 防误关 token 单调递增（模块级，非 Math.random/Date.now）
let _timerId: number = -1;     // 自动消失 timer 句柄（clearTimeout 防泄漏）

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getSyncState / getDeviceNetworkState）
export function getToastState(): ToastState {
  if (_state === null) {
    _state = AppStorageV2.connect(ToastState, () => new ToastState())!;
  }
  return _state;
}

export class ToastService {
  // 显一条 toast（覆盖旧 + 重置 6s 自动消失）。token 自增 + clear 旧 timer + arm 新 timer。
  static show(title: string, body: string, sessionId: string): void {
    const s: ToastState = getToastState();
    _tokenSeq = _tokenSeq + 1;
    const tok: number = _tokenSeq;
    const d: ServerToastData = new ServerToastData();
    d.title = title;
    d.body = body;
    d.sessionId = sessionId;
    d.token = tok;
    s.current = d;
    if (_timerId !== -1) { clearTimeout(_timerId); }
    _timerId = setTimeout((): void => {
      _timerId = -1;
      const s2: ToastState = getToastState();
      const cur: ServerToastData | null = s2.current;
      if (cur !== null && cur.token === tok) { s2.current = null; }   // 仅当仍是本次 toast 才清
    }, TOAST_DURATION_MS);
  }

  // 手动关闭（✕ 点击或跳转后）。
  static dismiss(): void {
    getToastState().current = null;
    if (_timerId !== -1) { clearTimeout(_timerId); _timerId = -1; }
  }
}
