// AgentFlavor 单测 —— flavor 徽章纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言。钉 FLAVOR_BADGES 6 已知 + 未知回落 + normalizeFlavor 归一。

import { describe, it, expect } from '@ohos/hypium';
import {
  FLAVOR_BADGES,
  UNKNOWN_FLAVOR_BADGE,
  normalizeFlavor,
  flavorBadge,
  flavorLabel,
  flavorColorHex
} from '../main/ets/chat/AgentFlavor';

export default function agentFlavorTest(): void {
  describe('AgentFlavor — FLAVOR_BADGES 钉表（6 已知）', () => {
    it("claude → 'Cl' / #d97706", 0, () => {
      expect(FLAVOR_BADGES['claude'].label).assertEqual('Cl');
      expect(FLAVOR_BADGES['claude'].bgHex).assertEqual('#d97706');
    });
    it("codex → 'Cx' / #111827", 0, () => {
      expect(FLAVOR_BADGES['codex'].label).assertEqual('Cx');
      expect(FLAVOR_BADGES['codex'].bgHex).assertEqual('#111827');
    });
    it("cursor → 'Cu' / #0f766e", 0, () => {
      expect(FLAVOR_BADGES['cursor'].label).assertEqual('Cu');
      expect(FLAVOR_BADGES['cursor'].bgHex).assertEqual('#0f766e');
    });
    it("gemini → 'Gm' / #2563eb", 0, () => {
      expect(FLAVOR_BADGES['gemini'].label).assertEqual('Gm');
      expect(FLAVOR_BADGES['gemini'].bgHex).assertEqual('#2563eb');
    });
    it("kimi → 'Km' / #7c3aed", 0, () => {
      expect(FLAVOR_BADGES['kimi'].label).assertEqual('Km');
      expect(FLAVOR_BADGES['kimi'].bgHex).assertEqual('#7c3aed');
    });
    it("opencode → 'Op' / #15803d", 0, () => {
      expect(FLAVOR_BADGES['opencode'].label).assertEqual('Op');
      expect(FLAVOR_BADGES['opencode'].bgHex).assertEqual('#15803d');
    });
    it("恰好 6 项（无多余/缺失）", 0, () => {
      expect(Object.keys(FLAVOR_BADGES).length).assertEqual(6);
    });
    it("bgHex 均为 '#rrggbb' 7 字符格式", 0, () => {
      const keys: string[] = Object.keys(FLAVOR_BADGES);
      for (let i = 0; i < keys.length; i++) {
        const hex: string = FLAVOR_BADGES[keys[i]].bgHex;
        expect(hex.length).assertEqual(7);
        expect(hex.charAt(0)).assertEqual('#');
      }
    });
  });

  describe('AgentFlavor — UNKNOWN 回落', () => {
    it("UNKNOWN label = 'Un'", 0, () => {
      expect(UNKNOWN_FLAVOR_BADGE.label).assertEqual('Un');
    });
    it('UNKNOWN bgHex 非空中性色', 0, () => {
      expect(UNKNOWN_FLAVOR_BADGE.bgHex).assertEqual('#6b7280');
    });
  });

  describe('AgentFlavor — normalizeFlavor', () => {
    it('小写透传', 0, () => {
      expect(normalizeFlavor('claude')).assertEqual('claude');
    });
    it('大写转小写（Claude → claude）', 0, () => {
      expect(normalizeFlavor('Claude')).assertEqual('claude');
    });
    it('全大写（CLAUDE → claude）', 0, () => {
      expect(normalizeFlavor('CLAUDE')).assertEqual('claude');
    });
    it('去首尾空白（" claude " → claude）', 0, () => {
      expect(normalizeFlavor(' claude ')).assertEqual('claude');
    });
    it('混合大小写 + 空白（" Gemini " → gemini）', 0, () => {
      expect(normalizeFlavor(' Gemini ')).assertEqual('gemini');
    });
    it('空串 → 空串（查表落 UNKNOWN）', 0, () => {
      expect(normalizeFlavor('')).assertEqual('');
    });
  });

  describe('AgentFlavor — flavorBadge / flavorLabel / flavorColorHex', () => {
    it('已知 flavor（大小写/空白经归一）查表命中', 0, () => {
      expect(flavorBadge('claude').label).assertEqual('Cl');
      expect(flavorBadge('CLAUDE').label).assertEqual('Cl');
      expect(flavorBadge(' gemini ').label).assertEqual('Gm');
    });
    it('未知 flavor → UNKNOWN 徽章', 0, () => {
      expect(flavorBadge('foobar').label).assertEqual('Un');
      expect(flavorBadge('foobar').bgHex).assertEqual('#6b7280');
    });
    it("空串 flavor → UNKNOWN（'Un'）", 0, () => {
      expect(flavorBadge('').label).assertEqual('Un');
    });
    it('flavorLabel = badge.label', 0, () => {
      expect(flavorLabel('codex')).assertEqual('Cx');
      expect(flavorLabel('unknown')).assertEqual('Un');
    });
    it('flavorColorHex = badge.bgHex', 0, () => {
      expect(flavorColorHex('cursor')).assertEqual('#0f766e');
      expect(flavorColorHex('nope')).assertEqual('#6b7280');
    });
  });
}
