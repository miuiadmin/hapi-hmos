// VoiceFormatters 单测 —— 语音上下文回灌格式化纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test / Message.test 范式：同步断言，手造 ChatMessage。
//   覆盖 formatMessage（user/agent text+tool-call/event/null）+ extractLastAssistantSpeakable（反向/多块拼接/
//   跳过 user）+ formatNewMessages（排序/过滤 null/头）+ formatHistory（MAX_HISTORY 截断）+
//   formatSessionFull / formatVoiceStartedContext + formatPermissionRequest + formatReadyEvent（含 text/缺省/空白）+
//   formatSessionOnline/Offline/Focus。
//   注：codex {type:'message',message:string} 文本提取为已知限制（parseMessage 不捕），此处不测。

import { describe, it, expect } from '@ohos/hypium';
import { ChatMessage } from '../main/ets/models/Message';
import { NormalizedAgentContent } from '../main/ets/chat/NormalizedContent';
import {
  formatMessage,
  extractLastAssistantSpeakable,
  formatNewMessages,
  formatHistory,
  formatSessionFull,
  formatVoiceStartedContext,
  formatPermissionRequest,
  formatReadyEvent,
  formatSessionOnline,
  formatSessionOffline,
  formatSessionFocus
} from '../main/ets/chat/VoiceFormatters';

// user 消息（role=user，text=入参）
function userMsg(seq: number, text: string): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = 'id-' + seq;
  m.seq = seq;
  m.role = 'user';
  m.text = text;
  return m;
}

// agent 消息（role=agent，blocks=入参；m.text 留空，formatMessage 走 blocks）
function agentMsg(seq: number, blocks: NormalizedAgentContent[]): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = 'id-' + seq;
  m.seq = seq;
  m.role = 'agent';
  m.blocks = blocks;
  return m;
}

function textBlock(text: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'text';
  b.text = text;
  return b;
}

function toolCallBlock(name: string): NormalizedAgentContent {
  const b: NormalizedAgentContent = new NormalizedAgentContent();
  b.type = 'tool-call';
  b.name = name;
  return b;
}

function eventMsg(seq: number): ChatMessage {
  const m: ChatMessage = new ChatMessage();
  m.id = 'id-' + seq;
  m.seq = seq;
  m.role = 'event';
  return m;
}

export default function voiceFormattersTest(): void {
  // —— formatMessage ——
  describe('VoiceFormatters — formatMessage user/agent/event', () => {
    it('user 文本 → "User sent message: <text>..."（逐字）', 0, () => {
      const f: string | null = formatMessage(userMsg(1, 'list the files'));
      expect(f).assertEqual('User sent message: \n<text>list the files</text>');
    });
    it('agent 文本块 → "Claude Code: <text>..."（逐字）', 0, () => {
      const f: string | null = formatMessage(agentMsg(1, [textBlock('done.')]));
      expect(f).assertEqual('Claude Code: \n<text>done.</text>');
    });
    it('agent text+tool_use 混合 → 两行（LIMITED_TOOL_CALLS 仅工具名）', 0, () => {
      const f: string | null = formatMessage(agentMsg(1, [textBlock('Here is the result.'), toolCallBlock('Bash')]));
      expect(f !== null).assertTrue();
      const s: string = f as string;
      expect(s.indexOf('Claude Code: \n<text>Here is the result.</text>')).assertGreaterOrEqual(0);
      expect(s.indexOf('Claude Code is using Bash')).assertGreaterOrEqual(0);
      expect(s.indexOf('with arguments')).assertEqual(-1);   // LIMITED：不含入参
    });
    it('agent 仅 tool-call（无 text）→ "Claude Code is using X"', 0, () => {
      const f: string | null = formatMessage(agentMsg(1, [toolCallBlock('Read')]));
      expect(f).assertEqual('Claude Code is using Read');
    });
    it('agent 多 text 块 → 各自一行，\\n\\n 连接', 0, () => {
      const f: string | null = formatMessage(agentMsg(1, [textBlock('Part one.'), textBlock('Part two.')]));
      expect(f).assertEqual('Claude Code: \n<text>Part one.</text>\n\nClaude Code: \n<text>Part two.</text>');
    });
    it('event 消息 → null', 0, () => {
      expect(formatMessage(eventMsg(1))).assertNull();
    });
    it('空 user 文本 → null', 0, () => {
      expect(formatMessage(userMsg(1, '   '))).assertNull();
    });
    it('agent 空 blocks + 空 text → null', 0, () => {
      expect(formatMessage(agentMsg(1, []))).assertNull();
    });
    it('agent text 块首尾空白 → trim', 0, () => {
      const f: string | null = formatMessage(agentMsg(1, [textBlock('  hi  ')]));
      expect(f).assertEqual('Claude Code: \n<text>hi</text>');
    });
  });

  // —— extractLastAssistantSpeakable ——
  describe('VoiceFormatters — extractLastAssistantSpeakable', () => {
    it('空历史 → null', 0, () => {
      expect(extractLastAssistantSpeakable([])).assertNull();
    });
    it('取最新 agent 文本（trim）', 0, () => {
      const msgs: ChatMessage[] = [
        userMsg(1, 'hello'),
        agentMsg(2, [textBlock('first reply')]),
        agentMsg(3, [textBlock('  latest reply  ')])
      ];
      expect(extractLastAssistantSpeakable(msgs)).assertEqual('latest reply');
    });
    it('跳过尾部 user，读更早的 agent 文本', 0, () => {
      const msgs: ChatMessage[] = [
        agentMsg(1, [textBlock('done with the refactor')]),
        userMsg(2, 'thanks')
      ];
      expect(extractLastAssistantSpeakable(msgs)).assertEqual('done with the refactor');
    });
    it('agent 多 text 块 → \\n\\n 拼接', 0, () => {
      const msgs: ChatMessage[] = [agentMsg(1, [textBlock('Part one.'), textBlock('Part two.')])];
      expect(extractLastAssistantSpeakable(msgs)).assertEqual('Part one.\n\nPart two.');
    });
    it('仅 user/event 历史 → null', 0, () => {
      const msgs: ChatMessage[] = [userMsg(1, 'hi'), eventMsg(2)];
      expect(extractLastAssistantSpeakable(msgs)).assertNull();
    });
  });

  // —— formatNewMessages ——
  describe('VoiceFormatters — formatNewMessages', () => {
    it('含会话头 + 消息文案', 0, () => {
      const upd: string | null = formatNewMessages('session-1', [agentMsg(1, [textBlock('Local database is 2.43 GiB.')])]);
      expect(upd !== null).assertTrue();
      const s: string = upd as string;
      expect(s.indexOf('New messages in session: session-1')).assertGreaterOrEqual(0);
      expect(s.indexOf('Local database is 2.43 GiB.')).assertGreaterOrEqual(0);
    });
    it('按 seq 排序（乱序入参 → 升序输出）', 0, () => {
      const upd: string | null = formatNewMessages('s', [
        agentMsg(3, [textBlock('third')]),
        agentMsg(1, [textBlock('first')]),
        agentMsg(2, [textBlock('second')])
      ]);
      expect(upd !== null).assertTrue();
      const s: string = upd as string;
      const i1: number = s.indexOf('first');
      const i2: number = s.indexOf('second');
      const i3: number = s.indexOf('third');
      expect(i1 < i2 && i2 < i3).assertTrue();
    });
    it('全部不可朗读（event）→ null', 0, () => {
      expect(formatNewMessages('s', [eventMsg(1), eventMsg(2)])).assertNull();
    });
  });

  // —— formatHistory ——
  describe('VoiceFormatters — formatHistory', () => {
    it('含会话头 + join', 0, () => {
      const h: string = formatHistory('s', [userMsg(1, 'hi'), agentMsg(2, [textBlock('hello')])]);
      expect(h.indexOf('History of messages in session: s')).assertGreaterOrEqual(0);
      expect(h.indexOf('User sent message: \n<text>hi</text>')).assertGreaterOrEqual(0);
      expect(h.indexOf('Claude Code: \n<text>hello</text>')).assertGreaterOrEqual(0);
    });
    it('超过 MAX_HISTORY(50) → 仅最近 50 条', 0, () => {
      const all: ChatMessage[] = [];
      for (let i = 0; i < 60; i++) {
        all.push(userMsg(i + 1, 'm' + (i + 1)));
      }
      const h: string = formatHistory('s', all);
      // 前 10 条（m1..m10）应被截掉，仅 m11..m60 留下
      expect(h.indexOf('m1<')).assertEqual(-1);   // m1 后跟 </text>，"m1<" 不会出现于 m1 本条
      expect(h.indexOf('<text>m10</text>')).assertEqual(-1);
      expect(h.indexOf('<text>m11</text>')).assertGreaterOrEqual(0);
      expect(h.indexOf('<text>m60</text>')).assertGreaterOrEqual(0);
    });
  });

  // —— formatSessionFull / formatVoiceStartedContext ——
  describe('VoiceFormatters — formatSessionFull / 启动上下文', () => {
    it('formatSessionFull 含 ID/path/summary/历史结构', 0, () => {
      const s: string = formatSessionFull('sid-1', '/home/user/proj', 'A great project',
        [userMsg(1, 'hi')]);
      expect(s.indexOf('# Session ID: sid-1')).assertGreaterOrEqual(0);
      expect(s.indexOf('# Project path: /home/user/proj')).assertGreaterOrEqual(0);
      expect(s.indexOf('# Session summary:\nA great project')).assertGreaterOrEqual(0);
      expect(s.indexOf('## Session Summary')).assertGreaterOrEqual(0);
      expect(s.indexOf('## Our interaction history so far')).assertGreaterOrEqual(0);
      expect(s.indexOf('History of messages in session: sid-1')).assertGreaterOrEqual(0);
    });
    it('summary 为空 → 不含 ## Session Summary 块', 0, () => {
      const s: string = formatSessionFull('sid', '/p', '', []);
      expect(s.indexOf('## Session Summary')).assertEqual(-1);
      expect(s.indexOf('# Session summary:\n')).assertGreaterOrEqual(0);   // 头仍含空 summary 行
    });
    it('formatVoiceStartedContext 前缀 "THIS IS AN ACTIVE SESSION:"', 0, () => {
      const s: string = formatVoiceStartedContext('sid', '/p', 'sum', []);
      expect(s.indexOf('THIS IS AN ACTIVE SESSION: \n\n')).assertEqual(0);
      expect(s.indexOf('# Session ID: sid')).assertGreaterOrEqual(0);
    });
  });

  // —— formatPermissionRequest ——
  describe('VoiceFormatters — formatPermissionRequest', () => {
    it('含 request_id/tool_name/tool_args 三段', 0, () => {
      const s: string = formatPermissionRequest('sid', 'req-9', 'Bash', '{"command":"rm -rf /"}');
      expect(s.indexOf('Claude Code is requesting permission to use Bash (session sid):')).assertGreaterOrEqual(0);
      expect(s.indexOf('<request_id>req-9</request_id>')).assertGreaterOrEqual(0);
      expect(s.indexOf('<tool_name>Bash</tool_name>')).assertGreaterOrEqual(0);
      expect(s.indexOf('<tool_args>{"command":"rm -rf /"}</tool_args>')).assertGreaterOrEqual(0);
    });
  });

  // —— formatReadyEvent ——
  describe('VoiceFormatters — formatReadyEvent', () => {
    const sid: string = '9d04335d-2b90-4941-98a7-eb414823f0e0';
    it('有 agent 文本 → 嵌入 <text>...</text>', 0, () => {
      const text: string = 'Added full-text search to the API module.';
      const ev: string = formatReadyEvent(sid, text);
      expect(ev.indexOf('coding agent finished working')).assertGreaterOrEqual(0);
      expect(ev.indexOf('<text>' + text + '</text>')).assertGreaterOrEqual(0);
      expect(ev.indexOf('Claude Code')).assertEqual(-1);
    });
    it('null → 回退文案', 0, () => {
      const ev: string = formatReadyEvent(sid, null);
      expect(ev.indexOf('Use the latest agent message already present in context')).assertGreaterOrEqual(0);
      expect(ev.indexOf('Claude Code')).assertEqual(-1);
    });
    it('空白文本 → 视为缺失（回退文案）', 0, () => {
      const ev: string = formatReadyEvent(sid, '   ');
      expect(ev.indexOf('Use the latest agent message already present in context')).assertGreaterOrEqual(0);
    });
  });

  // —— 会话状态 ——
  describe('VoiceFormatters — 会话状态串', () => {
    it('formatSessionOnline', 0, () => {
      expect(formatSessionOnline('sid')).assertEqual('Session came online: sid');
    });
    it('formatSessionOffline', 0, () => {
      expect(formatSessionOffline('sid')).assertEqual('Session went offline: sid');
    });
    it('formatSessionFocus', 0, () => {
      expect(formatSessionFocus('sid')).assertEqual('Session became focused: sid');
    });
  });
}
