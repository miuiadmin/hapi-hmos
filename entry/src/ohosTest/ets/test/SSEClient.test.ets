// SSEClient 设备端公开行为测试（ohosTest / ARunit）—— 不连真 Hub。
// SSEClient 的核心分帧/URL 逻辑已抽到 SSEClientUtils 由 LocalUnit 覆盖；此处只验证：
//   单例、监听者 add/remove、多监听者状态广播、connect() 未登录早退（不发网络）、disconnect()。
// 所有断言都走确定性的早退分支（hubUrl 或 jwt 为空 → setState('closed')），不触发 openStream/网络。

import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { getSSEClient, SSEConnectionState } from '../../../main/ets/api/SSEClient';
import { getConnectionService } from '../../../main/ets/services/ConnectionService';

export default function sseClientTest(): void {
  describe('SSEClient singleton', () => {
    it('getInstance returns the same instance', 0, () => {
      expect(getSSEClient() === getSSEClient()).assertTrue();
    });
  });

  describe('SSEClient listeners', () => {
    beforeEach(() => {
      // ConnectionService 是全局单例；每个用例前重置为未登录态，保证 connect() 走早退分支（不发网络）
      const conn = getConnectionService();
      conn.hubUrl = '';
      conn.jwt = '';
      conn.apiToken = '';
    });

    it('addListener returns increasing ids', 0, () => {
      const sse = getSSEClient();
      const id1 = sse.addListener({ onEvent: () => {} });
      const id2 = sse.addListener({ onEvent: () => {} });
      expect(id2 > id1).assertTrue();
      sse.removeListener(id1);
      sse.removeListener(id2);
    });

    it('notifies all listeners on state change', 0, () => {
      const sse = getSSEClient();
      let s1: SSEConnectionState = 'idle';
      let s2: SSEConnectionState = 'idle';
      const id1 = sse.addListener({ onEvent: () => {}, onStateChange: (st: SSEConnectionState) => { s1 = st; } });
      const id2 = sse.addListener({ onEvent: () => {}, onStateChange: (st: SSEConnectionState) => { s2 = st; } });
      sse.connect();   // 未登录 → setState('closed') → 两个监听者都收 'closed'
      expect(s1).assertEqual('closed');
      expect(s2).assertEqual('closed');
      sse.removeListener(id1);
      sse.removeListener(id2);
    });

    it('does not notify a removed listener', 0, () => {
      const sse = getSSEClient();
      let s1: SSEConnectionState = 'idle';
      let s2: SSEConnectionState = 'idle';
      const id1 = sse.addListener({ onEvent: () => {}, onStateChange: (st: SSEConnectionState) => { s1 = st; } });
      const id2 = sse.addListener({ onEvent: () => {}, onStateChange: (st: SSEConnectionState) => { s2 = st; } });
      sse.removeListener(id1);
      sse.connect();
      expect(s1).assertEqual('idle');     // 已注销，不再收
      expect(s2).assertEqual('closed');   // 仍收
      sse.removeListener(id2);
    });

    it('connect() with hubUrl but empty jwt goes to closed (no stream)', 0, () => {
      const sse = getSSEClient();
      const conn = getConnectionService();
      conn.hubUrl = 'http://127.0.0.1:3006';
      conn.jwt = '';   // 有 hubUrl 无 jwt → 仍早退
      let st: SSEConnectionState = 'idle';
      const id = sse.addListener({ onEvent: () => {}, onStateChange: (s: SSEConnectionState) => { st = s; } });
      sse.connect();
      expect(st).assertEqual('closed');
      sse.removeListener(id);
    });

    it('disconnect() sets state to closed', 0, () => {
      const sse = getSSEClient();
      let st: SSEConnectionState = 'idle';
      const id = sse.addListener({ onEvent: () => {}, onStateChange: (s: SSEConnectionState) => { st = s; } });
      sse.disconnect();
      expect(st).assertEqual('closed');
      sse.removeListener(id);
    });
  });
}
