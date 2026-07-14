// DeviceNetworkService —— 设备级网络在线状态的响应式探测（@ohos.net.connection）。
//
// 架构（镜像 SyncStateService 单例范式）：
//   @ObservedV2 DeviceNetworkState{@Trace online} 经 AppStorageV2 应用级共享单例。
//   ConnectionBanner 读 getDeviceNetworkState().online（@Trace）建立刷新依赖；离线时压制 SSE 文案
//   （显示决策在 chat/NetworkBannerResolve.ets 纯层，无 @kit，LocalUnit 可测）。
//
//   init()：connection.hasDefaultNet() 初始探测 + createNetConnection().on 注册变更回调。
//     on('netAvailable')   → online=true
//     on('netUnavailable') → online=false
//     netLost 不映射离线（可能仅切网 wifi→蜂窝，靠 netUnavailable 兜底「全无网」）；
//       若实测「飞行模式」只发 netLost 不发 netUnavailable，在 netLost 回调补 hasDefaultNet() 探测。
//   乐观默认 online=true：探测/注册失败保持在线（宁可漏报不误报，避启动即恒显离线）。
//   一次注册常驻：系统级监听，进程存活即回调（onForeground/onBackground 不动；进程被杀重启则 init 重跑）。
//
//   context-free：createNetConnection() / hasDefaultNet() 是模块级 API，无需 ability context
//   （同 SyncStateService / HapticService 无参 init）。@kit.NetworkKit 仅在本新文件，HubClient 不动。

import { connection } from '@kit.NetworkKit';
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class DeviceNetworkState {
  @Trace online: boolean = true;   // 乐观默认在线（启动到首次探测前不误报）
}

let _state: DeviceNetworkState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getSyncState / getHapticsState）
export function getDeviceNetworkState(): DeviceNetworkState {
  if (_state === null) {
    _state = AppStorageV2.connect(DeviceNetworkState, () => new DeviceNetworkState())!;
  }
  return _state;
}

// 网络变更监听句柄（一次注册，模块级单实例）
let _netConn: connection.NetConnection | null = null;

export class DeviceNetworkService {
  // EntryAbility.bootstrap 在 loadContent 前调（无参，context-free）。
  static async init(): Promise<void> {
    // 1. 初始探测当前是否有默认网络（异步）
    try {
      getDeviceNetworkState().online = await connection.hasDefaultNet();
    } catch (e) {
      // 探测失败保持乐观在线（不误报）
    }
    // 2. 注册网络变更监听（一次注册，系统线程回调）
    if (_netConn === null) {
      _netConn = connection.createNetConnection();
      _netConn.on('netAvailable', (_data: connection.NetHandle) => {
        getDeviceNetworkState().online = true;
      });
      _netConn.on('netUnavailable', () => {
        getDeviceNetworkState().online = false;
      });
      // netLost 不映射离线：可能仅切网（wifi↔蜂窝），靠 netUnavailable 兜底全无网。
      try {
        await _netConn.register();
      } catch (e) {
        // 注册失败保持乐观在线（监听缺失，但仍按初始探测值显示）
      }
    }
  }

  // 手动设置在线态（测试/调试用）
  static setOnline(online: boolean): void {
    getDeviceNetworkState().online = online;
  }

  static get isOnline(): boolean {
    return getDeviceNetworkState().online;
  }
}
