// NetworkBannerResolve 单测 —— 连接横幅显示决策纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言（assertEqual）。
//   钉「设备离线压制 SSE 文案」优先级（离线 ×5 SSE 态恒 device-offline）+ 在线时 SSE 分支映射。

import { describe, it, expect } from '@ohos/hypium';
import { resolveNetworkBanner } from '../main/ets/chat/NetworkBannerResolve';

export default function networkBannerResolveTest(): void {
  describe('NetworkBannerResolve — 设备离线优先（压制任意 SSE 状态）', () => {
    it("离线 + idle → 'device-offline'", 0, () => {
      expect(resolveNetworkBanner(false, 'idle')).assertEqual('device-offline');
    });
    it("离线 + connecting → 'device-offline'", 0, () => {
      expect(resolveNetworkBanner(false, 'connecting')).assertEqual('device-offline');
    });
    it("离线 + open → 'device-offline'", 0, () => {
      expect(resolveNetworkBanner(false, 'open')).assertEqual('device-offline');
    });
    it("离线 + reconnecting → 'device-offline'（压制 SSE 重连文案）", 0, () => {
      expect(resolveNetworkBanner(false, 'reconnecting')).assertEqual('device-offline');
    });
    it("离线 + closed → 'device-offline'（压制 SSE 断开文案）", 0, () => {
      expect(resolveNetworkBanner(false, 'closed')).assertEqual('device-offline');
    });
  });

  describe('NetworkBannerResolve — 设备在线时按 SSE 状态映射', () => {
    it("在线 + reconnecting → 'sse-reconnecting'", 0, () => {
      expect(resolveNetworkBanner(true, 'reconnecting')).assertEqual('sse-reconnecting');
    });
    it("在线 + closed → 'sse-closed'", 0, () => {
      expect(resolveNetworkBanner(true, 'closed')).assertEqual('sse-closed');
    });
    it("在线 + idle → 'none'", 0, () => {
      expect(resolveNetworkBanner(true, 'idle')).assertEqual('none');
    });
    it("在线 + connecting → 'none'", 0, () => {
      expect(resolveNetworkBanner(true, 'connecting')).assertEqual('none');
    });
    it("在线 + open → 'none'", 0, () => {
      expect(resolveNetworkBanner(true, 'open')).assertEqual('none');
    });
  });
}
