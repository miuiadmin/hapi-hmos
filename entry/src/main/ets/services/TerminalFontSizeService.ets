// TerminalFontSizeService —— 终端字号的响应式状态 + 持久化。
//
// 架构（镜像 TerminalToolDisplayService）：
//   @ObservedV2 TerminalFontSizeState{@Trace fontSize} 经 AppStorageV2 应用级共享单例；
//   TerminalPage 读 currentSize（boot 用）+ @Monitor('fontSizeState.fontSize') 实时 applyFontSize（不需重启）。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回；无 context。
//
// 拆层：纯常量/归一化在 chat/TerminalFontSize.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI + PreferencesService 持久化，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import {
  DEFAULT_TERMINAL_FONT_SIZE,
  normalizeTerminalFontSize
} from '../chat/TerminalFontSize';

@ObservedV2
export class TerminalFontSizeState {
  @Trace fontSize: number = DEFAULT_TERMINAL_FONT_SIZE;
}

let _state: TerminalFontSizeState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存
export function getTerminalFontSizeState(): TerminalFontSizeState {
  if (_state === null) {
    _state = AppStorageV2.connect(TerminalFontSizeState, () => new TerminalFontSizeState())!;
  }
  return _state;
}

export class TerminalFontSizeService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let size: number = DEFAULT_TERMINAL_FONT_SIZE;
    try {
      const stored: number = await getPreferencesService().getNumber(
        PreferenceKeys.TERMINAL_FONT_SIZE,
        DEFAULT_TERMINAL_FONT_SIZE
      );
      size = normalizeTerminalFontSize(stored);
    } catch (e) {
      // 读失败默认 13
    }
    getTerminalFontSizeState().fontSize = size;
  }

  // 设置页切换调：改 fontSize @Trace（TerminalPage @Monitor 实时 applyFontSize）+ 持久化
  static async setSize(size: number): Promise<void> {
    const normalized: number = normalizeTerminalFontSize(size);
    getTerminalFontSizeState().fontSize = normalized;
    try {
      await getPreferencesService().putNumber(PreferenceKeys.TERMINAL_FONT_SIZE, normalized);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentSize(): number {
    return getTerminalFontSizeState().fontSize;
  }
}
