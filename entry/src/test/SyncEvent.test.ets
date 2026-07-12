// SyncEvent 纯逻辑单测 —— 对照 hapi shared/src/schemas.ts SyncEventSchema
// 覆盖 parseSyncEvent（合法 / 非法 JSON / 无 type / type 非 string）与
//   SyncEvent 访问器 getString / getNumber / getObject + sessionId/machineId/namespace getter。

import { describe, it, expect } from '@ohos/hypium';
import { parseSyncEvent, SyncEvent, SyncEventType } from '../main/ets/models/SyncEvent';

export default function syncEventTest(): void {
  describe('parseSyncEvent', () => {
    it('parses a valid event with a string type', 0, () => {
      const ev: SyncEvent | null = parseSyncEvent('{"type":"session-added","sessionId":"s1"}');
      expect(ev !== null).assertTrue();
      if (ev !== null) {
        expect(ev.type).assertEqual('session-added');
      }
    });

    it('returns null for invalid JSON', 0, () => {
      expect(parseSyncEvent('not json') === null).assertTrue();
    });

    it('returns null when type is missing', 0, () => {
      expect(parseSyncEvent('{"foo":1}') === null).assertTrue();
    });

    it('returns null when type is not a string', 0, () => {
      expect(parseSyncEvent('{"type":123}') === null).assertTrue();
    });
  });

  describe('SyncEvent accessors', () => {
    // 一条带各类型字段的事件，供访问器测试
    function sample(): SyncEvent | null {
      return parseSyncEvent('{"type":"message-received","sessionId":"s1","machineId":"m1",' +
        '"namespace":"ns","seq":7,"data":{"k":"v"}}');
    }

    it('getString returns a present string or empty', 0, () => {
      const ev: SyncEvent | null = sample();
      expect(ev !== null).assertTrue();
      if (ev !== null) {
        expect(ev.getString('sessionId')).assertEqual('s1');
        expect(ev.getString('missing')).assertEqual('');
        expect(ev.getString('seq')).assertEqual(''); // 非字符串 → ''
      }
    });

    it('getNumber returns a present number or 0', 0, () => {
      const ev: SyncEvent | null = sample();
      expect(ev !== null).assertTrue();
      if (ev !== null) {
        expect(ev.getNumber('seq')).assertEqual(7);
        expect(ev.getNumber('missing')).assertEqual(0);
        expect(ev.getNumber('sessionId')).assertEqual(0); // 非数字 → 0
      }
    });

    it('getObject returns a nested object or null', 0, () => {
      const ev: SyncEvent | null = sample();
      expect(ev !== null).assertTrue();
      if (ev !== null) {
        const data = ev.getObject('data');
        expect(data !== null).assertTrue();
        if (data !== null) {
          expect(data['k']).assertEqual('v');
        }
        expect(ev.getObject('missing') === null).assertTrue();
        expect(ev.getObject('sessionId') === null).assertTrue(); // 字符串非对象 → null
      }
    });

    it('exposes sessionId / machineId / namespace convenience getters', 0, () => {
      const ev: SyncEvent | null = sample();
      expect(ev !== null).assertTrue();
      if (ev !== null) {
        expect(ev.sessionId).assertEqual('s1');
        expect(ev.machineId).assertEqual('m1');
        expect(ev.namespace).assertEqual('ns');
      }
    });
  });

  describe('SyncEventType constants', () => {
    it('exposes the documented event type literals', 0, () => {
      // 仅静态常量存在性回归（防手改）
      expect(SyncEventType.SESSION_ADDED).assertEqual('session-added');
      expect(SyncEventType.MESSAGE_RECEIVED).assertEqual('message-received');
      expect(SyncEventType.HEARTBEAT).assertEqual('heartbeat');
      expect(SyncEventType.CONNECTION_CHANGED).assertEqual('connection-changed');
    });
  });
}
