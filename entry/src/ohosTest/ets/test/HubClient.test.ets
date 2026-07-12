// HubClient 设备端公开行为测试（ohosTest / ARunit）—— 不连真 Hub。
// HubClient 的网络方法（health/authenticate/fetchSessions/...）都需真 Hub，属集成测试范畴（未选）。
// 此处只验证：单例（同时确认模块在设备上能加载，@kit.NetworkKit 静态初始化不崩）+ ApproveOptions 默认值。
//   审批 body 拼装 / 登录错误归类等纯逻辑已抽到 HubClientUtils 由 LocalUnit 覆盖。

import { describe, it, expect } from '@ohos/hypium';
import { getHubClient, ApproveOptions } from '../../../main/ets/api/HubClient';

export default function hubClientTest(): void {
  describe('HubClient singleton', () => {
    it('getInstance returns the same instance', 0, () => {
      expect(getHubClient() === getHubClient()).assertTrue();
    });
  });

  describe('ApproveOptions defaults', () => {
    it('has empty mode/decision, empty allowTools, null answers', 0, () => {
      const o: ApproveOptions = new ApproveOptions();
      expect(o.mode).assertEqual('');
      expect(o.decision).assertEqual('');
      expect(o.allowTools.length).assertEqual(0);
      expect(o.answers === null).assertTrue();
    });
  });
}
