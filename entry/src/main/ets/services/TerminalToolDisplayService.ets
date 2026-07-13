// TerminalToolDisplayService —— 终端工具卡片显示模式的响应式状态 + 持久化。
//
// 架构（镜像 ThemeService，简化版）：
//   @ObservedV2 TerminalToolDisplayState{@Trace mode} 经 AppStorageV2 应用级共享单例；
//   ToolCard 经 getTerminalToolDisplayState().mode 读 @Trace 建立刷新依赖（同 getThemeState().isDark 机制）——
//   设置页切换 setMode → 改 mode → 全量 ToolCard 即时重渲染，无需 @Param 透传。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回；无 context（纯 state + 持久化）。
//
// 拆层（项目范式）：纯判定/parse 在 chat/TerminalToolDisplay.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI（@ObservedV2/@Trace/AppStorageV2 装饰与共享）+ PreferencesService 持久化，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import {
  TerminalToolDisplayMode,
  DEFAULT_TERMINAL_TOOL_DISPLAY_MODE,
  parseTerminalToolDisplayMode
} from '../chat/TerminalToolDisplay';

@ObservedV2
export class TerminalToolDisplayState {
  @Trace mode: TerminalToolDisplayMode = DEFAULT_TERMINAL_TOOL_DISPLAY_MODE;
}

let _state: TerminalToolDisplayState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getThemeState）
export function getTerminalToolDisplayState(): TerminalToolDisplayState {
  if (_state === null) {
    _state = AppStorageV2.connect(TerminalToolDisplayState, () => new TerminalToolDisplayState())!;
  }
  return _state;
}

export class TerminalToolDisplayService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后，因读 Preferences）
  static async init(): Promise<void> {
    let mode: TerminalToolDisplayMode = DEFAULT_TERMINAL_TOOL_DISPLAY_MODE;
    try {
      const stored: string = await getPreferencesService().getString(
        PreferenceKeys.TERMINAL_TOOL_DISPLAY_MODE,
        DEFAULT_TERMINAL_TOOL_DISPLAY_MODE
      );
      mode = parseTerminalToolDisplayMode(stored);
    } catch (e) {
      // 读失败默认 compact
    }
    getTerminalToolDisplayState().mode = mode;
  }

  // 设置页切换调：改 mode @Trace（全量 ToolCard 重渲染）+ 持久化
  static async setMode(mode: TerminalToolDisplayMode): Promise<void> {
    getTerminalToolDisplayState().mode = mode;
    try {
      await getPreferencesService().putString(PreferenceKeys.TERMINAL_TOOL_DISPLAY_MODE, mode);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentMode(): TerminalToolDisplayMode {
    return getTerminalToolDisplayState().mode;
  }
}
