// MessageMetadata 单测 —— 每消息元数据脚注纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言（assertEqual / assertTrue）。
//   buildMessageMetadataLabels：Invoke/Duration/Model/Tier/Usage 组合；turnCount 鸿蒙 N/A 不覆盖。
//   附带 formatClockSeconds（HH:mm:ss）模式 + ts<=0 空串（DateFormatUtils 无既有测，就近补）。
//   附带 formatDurationSeconds（毫秒→X.Xs，手写避 toFixed）。

import { describe, it, expect } from '@ohos/hypium';
import { UsageData } from '../main/ets/models/Message';
import { buildMessageMetadataLabels, formatDurationSeconds } from '../main/ets/chat/MessageMetadata';
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
    it('全空（invokedAt=0 / durationMs=-1 / usage=null / model=""）→ []', 0, () => {
      expect(buildMessageMetadataLabels(0, -1, null, '').length).assertEqual(0);
    });
    it('仅 invokedAt → 1 条 Invoke 标签', 0, () => {
      const ts: number = 1700000000000; // 任意正 epoch-ms
      const labels: string[] = buildMessageMetadataLabels(ts, -1, null, '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual(`调用 ${formatClockSeconds(ts)}`);
    });
    it('仅 model → 1 条 model 标签（裸名）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, null, 'claude-sonnet-5');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('claude-sonnet-5');
    });
    it('仅 usage（standard tier）→ 1 条 usage，不显 tier', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, usage(5000, 3000, 'standard'), '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
  });

  describe('buildMessageMetadataLabels — Duration 门控', () => {
    it('durationMs=-1 不显 Duration', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, null, '');
      expect(labels.length).assertEqual(0);
    });
    it('durationMs=0 也显（显式 nullish 检查，对照上游 MessageMetadata.tsx:37）→ 耗时: 0.0s', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, 0, null, '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('耗时: 0.0s');
    });
    it('durationMs=1500 → 耗时: 1.5s', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, 1500, null, '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('耗时: 1.5s');
    });
    it('Duration 排在 Invoke 之后、Model 之前（顺序 Invoke→Duration→Model）', 0, () => {
      const ts: number = 1700000000000;
      const labels: string[] = buildMessageMetadataLabels(ts, 23450, null, 'claude-sonnet-5');
      expect(labels.length).assertEqual(3);
      expect(labels[0]).assertEqual(`调用 ${formatClockSeconds(ts)}`);
      expect(labels[1]).assertEqual('耗时: 23.4s');
      expect(labels[2]).assertEqual('claude-sonnet-5');
    });
  });

  describe('buildMessageMetadataLabels — Tier 门控', () => {
    it('priority tier 显 tier 标签（model 缺失时）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, usage(5000, 3000, 'priority'), '');
      expect(labels.length).assertEqual(2);
      expect(labels[0]).assertEqual('priority 档');
      expect(labels[1]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('STANDARD（大写）不显 tier（大小写不敏感）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, usage(5000, 3000, 'STANDARD'), '');
      expect(labels.length).assertEqual(1);
      expect(labels[0]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('空 tier 不显 tier 标签', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, usage(5000, 3000, ''), '');
      expect(labels.length).assertEqual(1);
    });
  });

  describe('buildMessageMetadataLabels — 全标签组合', () => {
    it('invoke + duration + model + priority tier + usage → 5 条，顺序 Invoke→Duration→Model→Tier→Usage', 0, () => {
      const ts: number = 1700000000000;
      const labels: string[] = buildMessageMetadataLabels(ts, 56700, usage(5000, 3000, 'priority'), 'claude-sonnet-5');
      expect(labels.length).assertEqual(5);
      expect(labels[0]).assertEqual(`调用 ${formatClockSeconds(ts)}`);
      expect(labels[1]).assertEqual('耗时: 56.7s');
      expect(labels[2]).assertEqual('claude-sonnet-5');
      expect(labels[3]).assertEqual('priority 档');
      expect(labels[4]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
    it('model + standard tier → 不显 tier（2 条：Model + Usage）', 0, () => {
      const labels: string[] = buildMessageMetadataLabels(0, -1, usage(5000, 3000, 'standard'), 'claude-sonnet-5');
      expect(labels.length).assertEqual(2);
      expect(labels[0]).assertEqual('claude-sonnet-5');
      expect(labels[1]).assertEqual('8k tokens（入 5k / 出 3k）');
    });
  });

  describe('formatDurationSeconds — 毫秒→X.X 串', () => {
    it('0 → 0.0', 0, () => {
      expect(formatDurationSeconds(0)).assertEqual('0.0');
    });
    it('999 → 0.9（向下取整到一位小数）', 0, () => {
      expect(formatDurationSeconds(999)).assertEqual('0.9');
    });
    it('1500 → 1.5', 0, () => {
      expect(formatDurationSeconds(1500)).assertEqual('1.5');
    });
    it('12345 → 12.3', 0, () => {
      expect(formatDurationSeconds(12345)).assertEqual('12.3');
    });
    it('56700 → 56.7', 0, () => {
      expect(formatDurationSeconds(56700)).assertEqual('56.7');
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
