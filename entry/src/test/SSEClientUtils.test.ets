// SSEClientUtils 纯逻辑单测 —— 对照 WHATWG SSE 规范 + 原 SSEClient 帧解析
// 覆盖 SSEFrameParser.feed（单事件 / 多行 data \n 合并 / CRLF / 注释 / 冒号空格剥离 /
//   无冒号字段 / event+id 字段 / 跨块边界 / 单 chunk 多事件 / 空事件不派发 / 未知字段忽略 /
//   lastEventId 跨 reset 保留 / reset 清缓冲）+ buildEventsUrl（token/visibility/all/sessionId/machineId + 编码 + 顺序）。

import { describe, it, expect } from '@ohos/hypium';
import { SSEFrameParser, buildEventsUrl } from '../main/ets/api/SSEClientUtils';

// 把多次 feed 的结果汇总（模拟流式分块到达）
function feedAll(parser: SSEFrameParser, chunks: string[]): string[] {
  const all: string[] = [];
  for (let i = 0; i < chunks.length; i++) {
    const ev = parser.feed(chunks[i]);
    for (let j = 0; j < ev.length; j++) {
      all.push(ev[j]);
    }
  }
  return all;
}

export default function sseClientUtilsTest(): void {
  describe('SSEFrameParser.feed', () => {
    it('parses a single data event', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data:hello\n\n');
      expect(ev.length).assertEqual(1);
      expect(ev[0]).assertEqual('hello');
    });

    it('joins multiple data lines with \\n', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data:a\ndata:b\n\n');
      expect(ev.length).assertEqual(1);
      expect(ev[0]).assertEqual('a\nb');
    });

    it('handles CRLF line endings', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data:hello\r\n\r\n');
      expect(ev.length).assertEqual(1);
      expect(ev[0]).assertEqual('hello');
    });

    it('ignores comment lines starting with :', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed(': heartbeat\ndata:hello\n\n');
      expect(ev.length).assertEqual(1);
      expect(ev[0]).assertEqual('hello');
    });

    it('strips one leading space after the colon', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data: hello\n\n');
      expect(ev[0]).assertEqual('hello');
    });

    it('keeps additional spaces after the first', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data:  two spaces\n\n');
      expect(ev[0]).assertEqual(' two spaces');
    });

    it('produces no event for a bare data field with no value', 0, () => {
      const p = new SSEFrameParser();
      expect(p.feed('data\n\n').length).assertEqual(0);
      expect(p.feed('data:\n\n').length).assertEqual(0);
    });

    it('appends an empty line for data: with empty value', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('data:x\ndata:\n\n');
      expect(ev[0]).assertEqual('x\n');
    });

    it('records lastEventId from id: field', 0, () => {
      const p = new SSEFrameParser();
      p.feed('id:42\ndata:hello\n\n');
      expect(p.lastEventId).assertEqual('42');
    });

    it('parses the event: field without affecting data', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('event:add\ndata:hello\n\n');
      expect(ev[0]).assertEqual('hello');
    });

    it('ignores unknown fields like retry:', 0, () => {
      const p = new SSEFrameParser();
      const ev = p.feed('retry:5000\ndata:hello\n\n');
      expect(ev[0]).assertEqual('hello');
    });

    it('does not dispatch an empty event (blank lines only)', 0, () => {
      const p = new SSEFrameParser();
      expect(p.feed('\n\n').length).assertEqual(0);
    });

    it('handles a frame split across chunks', 0, () => {
      const p = new SSEFrameParser();
      expect(p.feed('data:hel').length).assertEqual(0);   // 不完整行，缓冲
      const ev = p.feed('lo\n\n');
      expect(ev.length).assertEqual(1);
      expect(ev[0]).assertEqual('hello');
    });

    it('parses multiple events in one chunk', 0, () => {
      const p = new SSEFrameParser();
      const ev = feedAll(p, ['data:a\n\ndata:b\n\n']);
      expect(ev.length).assertEqual(2);
      expect(ev[0]).assertEqual('a');
      expect(ev[1]).assertEqual('b');
    });

    it('preserves lastEventId across reset()', 0, () => {
      const p = new SSEFrameParser();
      p.feed('id:99\ndata:x\n\n');
      p.reset();
      expect(p.lastEventId).assertEqual('99');
      const ev = p.feed('data:y\n\n');
      expect(ev[0]).assertEqual('y');
    });

    it('reset() clears the partial line buffer', 0, () => {
      const p = new SSEFrameParser();
      p.feed('data:par');          // 不完整，缓冲
      p.reset();                   // 清掉
      const ev = p.feed('tial\n\n');
      expect(ev.length).assertEqual(0);   // 'tial' 当成无值字段，无事件
    });
  });

  describe('buildEventsUrl', () => {
    it('builds token + visibility when logged in', 0, () => {
      expect(buildEventsUrl('http://h:3006', 'jwt123', false, '', ''))
        .assertEqual('http://h:3006/api/events?token=jwt123&visibility=visible');
    });

    it('omits token when empty (not logged in)', 0, () => {
      expect(buildEventsUrl('http://h', '', false, '', ''))
        .assertEqual('http://h/api/events?visibility=visible');
    });

    it('adds all=true when subscribing to all sessions', 0, () => {
      expect(buildEventsUrl('http://h', 't', true, '', ''))
        .assertEqual('http://h/api/events?token=t&visibility=visible&all=true');
    });

    it('adds sessionId and machineId when set', 0, () => {
      expect(buildEventsUrl('http://h', 't', false, 's1', 'm1'))
        .assertEqual('http://h/api/events?token=t&visibility=visible&sessionId=s1&machineId=m1');
    });

    it('URL-encodes token / sessionId / machineId special chars', 0, () => {
      const url = buildEventsUrl('http://h', 'a b&c', false, 's x', 'm/y');
      expect(url).assertEqual('http://h/api/events?token=a%20b%26c&visibility=visible&sessionId=s%20x&machineId=m%2Fy');
    });

    it('uses baseUrl verbatim (caller strips trailing slash)', 0, () => {
      // buildEventsUrl 不去尾斜杠——由 SSEClient.baseUrl 负责；此处钉住契约
      expect(buildEventsUrl('http://h:3006/', 't', false, '', ''))
        .assertEqual('http://h:3006//api/events?token=t&visibility=visible');
    });
  });
}
