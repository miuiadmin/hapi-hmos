// MessageMetadata 单测 —— 每消息元数据脚注纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言（assertEqual / assertTrue）。
//   buildMessageMetadataLabels：Invoke/Model/Tier/Usage 组合；Duration/turnCount 延后（见计划）不覆盖。
//   附带 formatClockSeconds（HH:mm:ss）模式 + ts<=0 空串（DateFormatUtils 无既有测，就近补）。

import { describe, it, expect } from '@ohos/hypium';
import { UsageData } from '../main/ets/models/Message';
import { buildMessageMetadataLabels } from '../main/ets/chat/MessageMetadata';
import { formatClockSeconds } from '../main/ets/utils/DateFormatUtils';

function usage(input: number, output: number, tier: string = ''): UsageData {
  const u: UsageData = new UsageData();
  u.inputTokens = input;
  u.outputTokens = output;
  u.serviceTier = tier;
  return u;
}

export default function messageMetadataTest(): void {
  describe('buildMessageMetadataLabels — 空与单标签', () => {
    it('全空（invokedAt=0 / usage=null / model=""）→ []', 0, () => {
      expect(buildMessageMetadataLabels(0, null, '').length).assertEqual(0);
    });
    it('仅 invokedAt → 1 条 Invoke 标签', 0, () => {
      const ts: number = 1700000000000; // 任意正 epoch-ms
      const labels: string[] = buildMessageMetadataLabels(ts, null, '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual(`调用 ${formatClockSeconds(ts)}`);
    });
    it('仅 model → 1 条 model 标签（裸名）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, null, 'claude-sonnet-5');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('claude-sonnet-5');
    });
    it('仅 usage（standard tier）→ 1 条 usage，不显 tier', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, usage(5000, 3000, 'standard'), '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
  });

  describe('buildMessageMetadataLabels — Tier 门控', () => {
    it('priority tier 显 tier 标签（model 缺失时）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, usage(5000, 3000, 'priority'), '');
      expect(labels.length).assertEqual(2);
      expect(labels[0]).assertEqual('priority 档');
      expect(labels[1]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('STANDARD（大写）不显 tier（大小写不敏感）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, usage(5000, 3000, 'STANDARD'), '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('空 tier 不显 tier 标签', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, usage(5000, 3000, ''), '');
      expect(labels.length).assertEqual(1);
    });
  });

  describe('buildMessageMetadataLabels — 全标签组合', () => {
    it('invoke + model + priority tier + usage → 4 条，顺序 Invoke→Model→Tier→Usage', 0, () => {
      const ts: number = 1700000000000;
      const labels: string[] = buildMessageMetadataLabels(ts, usage(5000, 3000, 'priority'), 'claude-sonnet-5');
      expect(labels.length).assertEqual(4);
      expect(labels[0]).assertEqual(`调用 ${formatClockSeconds(ts)}`);
      expect(labels[1]).assertEqual('claude-sonnet-5');
      expect(labels[2]).assertEqual('priority 档');
      expect(labels[3]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('model + standard tier → 不显 tier（2 条：Model + Usage）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, usage(5000, 3000, 'standard'), 'claude-sonnet-5');
      expect(labels.length).assertEqual(2);
      expect(labels[0]).assertEqual('claude-sonnet-5');
      expect(labels[1]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
  });

  describe('formatClockSeconds', () => {
    it('ts<=0 返回空串', 0, () => {
      expect(formatClockSeconds(0)).assertEqual('');
      expect(formatClockSeconds(-100)).assertEqual('');
    });
    it('合法 ts → HH:mm:ss（8 字符、每段两位数字）', 0, () => {
      const s: string = formatClockSeconds(1700000000000);
      expect(s.length).assertEqual(8);
      // 每段两位数字：HH:MM:SS（手写校验，不依赖正则）
      const ok: boolean = s.charAt(2) === ':' && s.charAt(5) === ':'
        && s.charAt(0) >= '0' && s.charAt(0) <= '9'
        && s.charAt(1) >= '0' && s.charAt(1) <= '9'
        && s.charAt(3) >= '0' && s.charAt(3) <= '9'
        && s.charAt(4) >= '0' && s.charAt(4) <= '9'
        && s.charAt(6) >= '0' && s.charAt(6) <= '9'
        && s.charAt(7) >= '0' && s.charAt(7) <= '9';
      expect(ok).assertTrue();
    });
  });
}
