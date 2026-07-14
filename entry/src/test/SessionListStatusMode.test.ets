// SessionListStatusMode 单测 —— 会话列表状态模式纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 TerminalToolDisplay.test 范式：同步断言。
//   覆盖 DEFAULT / normalizeSessionListStatusMode（两合法值透传 + 非法回落 standard）。

import { describe, it, expect } from '@ohos/hypium';
import {
  SessionListStatusMode,
  DEFAULT_SESSION_LIST_STATUS_MODE,
  normalizeSessionListStatusMode
} from '../main/ets/chat/SessionListStatusMode';

export default function sessionListStatusModeTest(): void {
  describe('SessionListStatusMode — 默认值', () => {
    it('DEFAULT = standard', 0, () => {
      expect(DEFAULT_SESSION_LIST_STATUS_MODE).assertEqual('standard');
    });
  });

  describe('SessionListStatusMode — normalizeSessionListStatusMode 合法值透传', () => {
    it('standard → standard', 0, () => {
      expect(normalizeSessionListStatusMode('standard')).assertEqual('standard');
    });
    it('detailed → detailed', 0, () => {
      expect(normalizeSessionListStatusMode('detailed')).assertEqual('detailed');
    });
  });

  describe('SessionListStatusMode — normalizeSessionListStatusMode 非法值回落 standard', () => {
    it('空串 → standard', 0, () => {
      expect(normalizeSessionListStatusMode('')).assertEqual('standard');
    });
    it('非法串 garbage → standard', 0, () => {
      expect(normalizeSessionListStatusMode('garbage')).assertEqual('standard');
    });
    it('大小写敏感：Standard(大写 S) → standard（严格 ===）', 0, () => {
      expect(normalizeSessionListStatusMode('Standard')).assertEqual('standard');
    });
    it('compact(终端工具模式串) → standard（不串值）', 0, () => {
      expect(normalizeSessionListStatusMode('compact')).assertEqual('standard');
    });
  });
}
