// StatusBarChips 单测 —— 顶部状态行右侧 chip 簇纯逻辑层（零 @kit，LocalUnit 可加载）。
//   对照 web StatusBar.tsx + shared/src/modes.ts。覆盖 permissionModeTone（各 mode 色调）/
//   isPermissionModeAllowedForFlavor（flavor 域校验）/ normalizeReasoningEffort（归一）/
//   isCodexFastMode（fast 判定）/ toneColor（tone→调色板）/ 4 个 chip 可见性谓词。

import { describe, it, expect } from '@ohos/hypium';
import {
  permissionModeTone,
  isPermissionModeAllowedForFlavor,
  normalizeReasoningEffort,
  isCodexFastMode,
  toneColor,
  shouldShowReasoningChip,
  shouldShowFastChip,
  shouldShowCollaborationChip,
  shouldShowPermissionChip,
  shouldShowGoalChip
} from '../main/ets/chat/StatusBarChips';
import { LIGHT, DARK } from '../main/ets/theme/Palette';

export default function statusBarChipsTest(): void {
  // —— permissionModeTone ——
  describe('StatusBarChips — permissionModeTone', () => {
    it('plan/ask → info', 0, () => {
      expect(permissionModeTone('plan')).assertEqual('info');
      expect(permissionModeTone('ask')).assertEqual('info');
    });
    it('acceptEdits/read-only/safe-yolo → warning', 0, () => {
      expect(permissionModeTone('acceptEdits')).assertEqual('warning');
      expect(permissionModeTone('read-only')).assertEqual('warning');
      expect(permissionModeTone('safe-yolo')).assertEqual('warning');
    });
    it('bypassPermissions/yolo → danger', 0, () => {
      expect(permissionModeTone('bypassPermissions')).assertEqual('danger');
      expect(permissionModeTone('yolo')).assertEqual('danger');
    });
    it('default/未知 → neutral', 0, () => {
      expect(permissionModeTone('default')).assertEqual('neutral');
      expect(permissionModeTone('whatever')).assertEqual('neutral');
      expect(permissionModeTone('')).assertEqual('neutral');
    });
  });

  // —— isPermissionModeAllowedForFlavor ——
  describe('StatusBarChips — isPermissionModeAllowedForFlavor', () => {
    it('claude：acceptEdits ✓，read-only ✗', 0, () => {
      expect(isPermissionModeAllowedForFlavor('acceptEdits', 'claude')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('read-only', 'claude')).assertFalse();
    });
    it('codex：read-only/safe-yolo/yolo ✓，acceptEdits ✗', 0, () => {
      expect(isPermissionModeAllowedForFlavor('read-only', 'codex')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('safe-yolo', 'codex')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('yolo', 'codex')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('acceptEdits', 'codex')).assertFalse();
    });
    it('gemini/kimi 共用 codex 域：read-only ✓', 0, () => {
      expect(isPermissionModeAllowedForFlavor('read-only', 'gemini')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('read-only', 'kimi')).assertTrue();
    });
    it('opencode：plan ✓，acceptEdits ✗', 0, () => {
      expect(isPermissionModeAllowedForFlavor('plan', 'opencode')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('acceptEdits', 'opencode')).assertFalse();
    });
    it('cursor：ask ✓', 0, () => {
      expect(isPermissionModeAllowedForFlavor('ask', 'cursor')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('safe-yolo', 'cursor')).assertFalse();
    });
    it('default 全 flavor ✓', 0, () => {
      expect(isPermissionModeAllowedForFlavor('default', 'claude')).assertTrue();
      expect(isPermissionModeAllowedForFlavor('default', 'codex')).assertTrue();
    });
  });

  // —— normalizeReasoningEffort ——
  describe('StatusBarChips — normalizeReasoningEffort', () => {
    it('空/default（任意大小写）→ default', 0, () => {
      expect(normalizeReasoningEffort('')).assertEqual('default');
      expect(normalizeReasoningEffort('default')).assertEqual('default');
      expect(normalizeReasoningEffort('DEFAULT')).assertEqual('default');
      expect(normalizeReasoningEffort('  Default  ')).assertEqual('default');
    });
    it('low/High/  xhigh  → 小写去空白', 0, () => {
      expect(normalizeReasoningEffort('low')).assertEqual('low');
      expect(normalizeReasoningEffort('High')).assertEqual('high');
      expect(normalizeReasoningEffort('  xhigh  ')).assertEqual('xhigh');
    });
  });

  // —— isCodexFastMode ——
  describe('StatusBarChips — isCodexFastMode', () => {
    it('effort none/minimal/low → true（任意 model）', 0, () => {
      expect(isCodexFastMode('gpt-5', 'none')).assertTrue();
      expect(isCodexFastMode('gpt-5', 'minimal')).assertTrue();
      expect(isCodexFastMode('gpt-5', 'low')).assertTrue();
    });
    it('effort high + 普通 model → false', 0, () => {
      expect(isCodexFastMode('claude-sonnet', 'high')).assertFalse();
    });
    it('model 含 mini/fast → true（任意 effort）', 0, () => {
      expect(isCodexFastMode('gpt-mini', 'high')).assertTrue();
      expect(isCodexFastMode('codex-fast-latest', 'high')).assertTrue();
      expect(isCodexFastMode('o4-mini-2024', 'xhigh')).assertTrue();
    });
    it('大小写不敏感：MINI/FAST/  Low  ', 0, () => {
      expect(isCodexFastMode('GPT-MINI', 'high')).assertTrue();
      expect(isCodexFastMode('model', '  Low  ')).assertTrue();
    });
    it('effort + model 都不命中 → false', 0, () => {
      expect(isCodexFastMode('claude-opus', 'xhigh')).assertFalse();
      expect(isCodexFastMode('', '')).assertFalse();
    });
  });

  // —— toneColor ——
  describe('StatusBarChips — toneColor', () => {
    it('info→primary / warning→warning / danger→error / success→success', 0, () => {
      expect(toneColor('info', LIGHT)).assertEqual(LIGHT.primary);
      expect(toneColor('warning', LIGHT)).assertEqual(LIGHT.warning);
      expect(toneColor('danger', LIGHT)).assertEqual(LIGHT.error);
      expect(toneColor('success', LIGHT)).assertEqual(LIGHT.success);
    });
    it('neutral/未知 → textTertiary', 0, () => {
      expect(toneColor('neutral', LIGHT)).assertEqual(LIGHT.textTertiary);
      expect(toneColor('??', LIGHT)).assertEqual(LIGHT.textTertiary);
    });
    it('dark 调色板同样映射', 0, () => {
      expect(toneColor('info', DARK)).assertEqual(DARK.primary);
      expect(toneColor('danger', DARK)).assertEqual(DARK.error);
    });
  });

  // —— chip 可见性谓词 ——
  describe('StatusBarChips — chip 可见性谓词', () => {
    it('shouldShowReasoningChip：codex/opencode ✓，claude/gemini ✗', 0, () => {
      expect(shouldShowReasoningChip('codex')).assertTrue();
      expect(shouldShowReasoningChip('opencode')).assertTrue();
      expect(shouldShowReasoningChip('claude')).assertFalse();
      expect(shouldShowReasoningChip('gemini')).assertFalse();
    });
    it('shouldShowFastChip：仅 codex + fast 命中', 0, () => {
      expect(shouldShowFastChip('codex', 'gpt-mini', 'high')).assertTrue();
      expect(shouldShowFastChip('codex', 'gpt-5', 'low')).assertTrue();
      expect(shouldShowFastChip('codex', 'gpt-5', 'high')).assertFalse();
      expect(shouldShowFastChip('opencode', 'gpt-mini', 'high')).assertFalse();   // 仅 codex
      expect(shouldShowFastChip('claude', 'gpt-mini', 'high')).assertFalse();     // 仅 codex
    });
    it('shouldShowCollaborationChip：仅 codex + plan', 0, () => {
      expect(shouldShowCollaborationChip('codex', 'plan')).assertTrue();
      expect(shouldShowCollaborationChip('codex', 'default')).assertFalse();
      expect(shouldShowCollaborationChip('claude', 'plan')).assertFalse();
    });
    it('shouldShowPermissionChip：非 default + flavor 域允许', 0, () => {
      expect(shouldShowPermissionChip('acceptEdits', 'claude')).assertTrue();
      expect(shouldShowPermissionChip('read-only', 'codex')).assertTrue();
      // default / 空 → 不显
      expect(shouldShowPermissionChip('default', 'claude')).assertFalse();
      expect(shouldShowPermissionChip('', 'claude')).assertFalse();
      // flavor 域不允许 → 不显（acceptEdits 不在 codex 域）
      expect(shouldShowPermissionChip('acceptEdits', 'codex')).assertFalse();
    });
    it('shouldShowGoalChip：仅 codex + 有 goal（hasGoal:boolean）', 0, () => {
      expect(shouldShowGoalChip('codex', true)).assertTrue();
      expect(shouldShowGoalChip('codex', false)).assertFalse();     // 无有效 goal
      expect(shouldShowGoalChip('claude', true)).assertFalse();      // 仅 codex
      expect(shouldShowGoalChip('opencode', true)).assertFalse();    // 仅 codex
    });
  });
}
