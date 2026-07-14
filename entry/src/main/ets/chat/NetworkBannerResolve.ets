// NetworkBannerResolve —— 连接横幅显示决策纯逻辑层（无 @kit，LocalUnit 可加载）。
//
// 给定「设备在线 + SSE 状态」→ 显示哪种横幅。设备离线优先级最高，压制 SSE 重连/断开文案：
//   设备无网时 SSE 必然连不上，"正在重新连接 / 连接已断开" 会误导用户以为是 Hub 故障，
//   实则手机没网；设备离线改显根因提示（connection.deviceOffline）。
//
// 拆层（项目范式）：不 import SSEClient 的 SSEConnectionState（SSEClient.ets 顶部 import @kit.NetworkKit，
//   会传染 @kit 进纯层，同 Translate 拆层教训）。本层自定同形 union NetworkSseState；
//   ConnectionBanner 侧持 SSEConnectionState 值直接传入（结构兼容，无需 as）。

// SSE 连接状态（同形 SSEClient.SSEConnectionState，本层独立定义以避 @kit 传染）
export type NetworkSseState = 'idle' | 'connecting' | 'open' | 'reconnecting' | 'closed';

// 横幅显示种类
export type NetworkBannerKind = 'none' | 'device-offline' | 'sse-reconnecting' | 'sse-closed';

// 横幅显示决策：设备离线优先（压制 SSE 文案）；设备在线时按 SSE 状态沿用既有分支。
//   - !deviceOnline → 'device-offline'（无论 SSE 何态，根因=无网）
//   - reconnecting  → 'sse-reconnecting'（中性底「正在重新连接…」）
//   - closed        → 'sse-closed'（error 底「连接已断开」）
//   - 其余          → 'none'（收起）
export function resolveNetworkBanner(deviceOnline: boolean, sseState: NetworkSseState): NetworkBannerKind {
  if (!deviceOnline) {
    return 'device-offline';
  }
  if (sseState === 'reconnecting') {
    return 'sse-reconnecting';
  }
  if (sseState === 'closed') {
    return 'sse-closed';
  }
  return 'none';
}
