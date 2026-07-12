// Types 纯逻辑单测 —— 对照 hapi shared/src 的会话解析（SessionSummary / Session）
// 覆盖 pick* 安全取值、parseSessionSummary（含 metadata / todoProgress / title / summaryText）、
//   parseSessionsResponse（数组解析 + 过滤 + 非法输入）、parseSessionDetail（session 信封 + agentStateRaw）。

import { describe, it, expect } from '@ohos/hypium';
import {
  pickStr,
  pickNum,
  pickBool,
  pickObj,
  parseSessionSummary,
  parseSessionsResponse,
  parseSessionDetail
} from '../main/ets/models/Types';

function rec(json: string): Record<string, Object> {
  return JSON.parse(json) as Record<string, Object>;
}

export default function typesTest(): void {
  describe('pick helpers', () => {
    it('pickStr returns the string or empty', 0, () => {
      expect(pickStr(rec('{"a":"hi"}'), 'a')).assertEqual('hi');
      expect(pickStr(rec('{"a":5}'), 'a')).assertEqual('');
      expect(pickStr(rec('{}'), 'a')).assertEqual('');
    });
    it('pickNum returns the number or 0', 0, () => {
      expect(pickNum(rec('{"a":7}'), 'a')).assertEqual(7);
      expect(pickNum(rec('{"a":"x"}'), 'a')).assertEqual(0);
      expect(pickNum(rec('{}'), 'a')).assertEqual(0);
    });
    it('pickBool returns the boolean or false', 0, () => {
      expect(pickBool(rec('{"a":true}'), 'a')).assertTrue();
      expect(pickBool(rec('{"a":1}'), 'a')).assertFalse();
      expect(pickBool(rec('{}'), 'a')).assertFalse();
    });
    it('pickObj returns a non-array object or null', 0, () => {
      expect(pickObj(rec('{"a":{"x":1}}'), 'a') !== null).assertTrue();
      expect(pickObj(rec('{"a":5}'), 'a') === null).assertTrue(); // 非对象
      expect(pickObj(rec('{"a":null}'), 'a') === null).assertTrue();
      expect(pickObj(rec('{}'), 'a') === null).assertTrue();
    });
  });

  describe('parseSessionSummary', () => {
    it('parses all top-level fields, metadata, summary and todoProgress', 0, () => {
      const s = parseSessionSummary(rec(
        '{"id":"s1","active":true,"thinking":false,"activeAt":100,"updatedAt":200,' +
        '"pendingRequestsCount":2,"backgroundTaskCount":3,"model":"claude-sonnet","effort":"high",' +
        '"metadata":{"name":"My Chat","path":"/work/repo","machineId":"m1","summary":{"text":"doing stuff"},"flavor":"hapi"},' +
        '"todoProgress":{"completed":4,"total":7}}'));
      expect(s.id).assertEqual('s1');
      expect(s.active).assertTrue();
      expect(s.thinking).assertFalse();
      expect(s.activeAt).assertEqual(100);
      expect(s.updatedAt).assertEqual(200);
      expect(s.pendingRequestsCount).assertEqual(2);
      expect(s.backgroundTaskCount).assertEqual(3);
      expect(s.model).assertEqual('claude-sonnet');
      expect(s.effort).assertEqual('high');
      expect(s.todoCompleted).assertEqual(4);
      expect(s.todoTotal).assertEqual(7);
      expect(s.metadata !== null).assertTrue();
      if (s.metadata !== null) {
        expect(s.metadata.name).assertEqual('My Chat');
        expect(s.metadata.path).assertEqual('/work/repo');
        expect(s.metadata.machineId).assertEqual('m1');
        expect(s.metadata.summaryText).assertEqual('doing stuff');
        expect(s.metadata.flavor).assertEqual('hapi');
      }
    });

    it('title prefers metadata.name', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"Named","path":"/p"}}'));
      expect(s.title).assertEqual('Named');
    });

    it('title falls back to the last path segment when name is empty', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"","path":"/work/repo"}}'));
      expect(s.title).assertEqual('repo');
    });

    it('title returns the whole path when it has no slash', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"","path":"repo"}}'));
      expect(s.title).assertEqual('repo');
    });

    it('title falls back to id when name and path are both empty', 0, () => {
      const s = parseSessionSummary(rec('{"id":"sX","metadata":{"name":"","path":""}}'));
      expect(s.title).assertEqual('sX');
    });

    it('title falls back to id when metadata is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"sY"}'));
      expect(s.title).assertEqual('sY');
    });

    it('summaryText comes from metadata.summary.text', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"summary":{"text":"sum"}}}'));
      expect(s.summaryText).assertEqual('sum');
    });

    it('summaryText is empty when metadata has no summary', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"x"}}'));
      expect(s.summaryText).assertEqual('');
    });

    it('summaryText is empty when metadata is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1"}'));
      expect(s.summaryText).assertEqual('');
    });

    it('leaves todoCompleted/todoTotal at 0 when todoProgress is absent', 0, () => {
      const s = parseSessionSummary(rec('{"id":"s1","metadata":{"name":"x"}}'));
      expect(s.todoCompleted).assertEqual(0);
      expect(s.todoTotal).assertEqual(0);
    });
  });

  describe('parseSessionsResponse', () => {
    it('parses a sessions array', 0, () => {
      const json: string = '{"sessions":[' +
        '{"id":"a","metadata":{"name":"A"}},' +
        '{"id":"b","metadata":{"name":"B"}}' +
        ']}';
      const list = parseSessionsResponse(json);
      expect(list.length).assertEqual(2);
      expect(list[0].id).assertEqual('a');
      expect(list[0].title).assertEqual('A');
      expect(list[1].title).assertEqual('B');
    });

    it('returns an empty array for invalid JSON', 0, () => {
      expect(parseSessionsResponse('not json').length).assertEqual(0);
    });

    it('returns an empty array when sessions is missing', 0, () => {
      expect(parseSessionsResponse('{"foo":1}').length).assertEqual(0);
    });

    it('returns an empty array when sessions is not an array', 0, () => {
      expect(parseSessionsResponse('{"sessions":"nope"}').length).assertEqual(0);
    });

    it('filters out non-object entries', 0, () => {
      const json: string = '{"sessions":["str",123,null,{"id":"ok","metadata":{"name":"OK"}}]}';
      const list = parseSessionsResponse(json);
      expect(list.length).assertEqual(1);
      expect(list[0].id).assertEqual('ok');
    });
  });

  describe('parseSessionDetail', () => {
    it('parses the session envelope with all fields and agentStateRaw', 0, () => {
      const s = parseSessionDetail(
        '{"session":{"id":"s1","namespace":"ns","seq":5,"createdAt":1,"updatedAt":2,' +
        '"active":true,"activeAt":3,"thinking":true,"model":"m","effort":"low","agentStateVersion":9,' +
        '"agentState":{"controlledByUser":true,"requests":{}}}}');
      expect(s.id).assertEqual('s1');
      expect(s.namespace).assertEqual('ns');
      expect(s.seq).assertEqual(5);
      expect(s.createdAt).assertEqual(1);
      expect(s.updatedAt).assertEqual(2);
      expect(s.active).assertTrue();
      expect(s.activeAt).assertEqual(3);
      expect(s.thinking).assertTrue();
      expect(s.model).assertEqual('m');
      expect(s.effort).assertEqual('low');
      expect(s.agentStateVersion).assertEqual(9);
      expect(s.agentStateRaw !== null).assertTrue();
      if (s.agentStateRaw !== null) {
        expect(s.agentStateRaw['controlledByUser']).assertTrue();
      }
    });

    it('returns a default Session for invalid JSON', 0, () => {
      const s = parseSessionDetail('not json');
      expect(s.id).assertEqual('');
      expect(s.agentStateRaw === null).assertTrue();
    });

    it('returns a default Session when the session key is missing', 0, () => {
      const s = parseSessionDetail('{"foo":1}');
      expect(s.id).assertEqual('');
      expect(s.agentStateRaw === null).assertTrue();
    });

    it('leaves nullable fields empty when absent', 0, () => {
      const s = parseSessionDetail('{"session":{"id":"s1"}}');
      expect(s.id).assertEqual('s1');
      expect(s.model).assertEqual('');
      expect(s.effort).assertEqual('');
      expect(s.seq).assertEqual(0);
      expect(s.agentStateRaw === null).assertTrue();
    });
  });
}
