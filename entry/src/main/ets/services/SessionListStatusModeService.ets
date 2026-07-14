// SessionListStatusModeService —— 会话列表状态模式的响应式状态 + 持久化。
//
// 架构（镜像 TerminalToolDisplayService）：
//   @ObservedV2 SessionListStatusModeState{@Trace mode} 经 AppStorageV2 应用级共享单例；
//   Index SessionItem 读 currentMode（detailed 才显 attention 指示器；对照上游 useSessionListStatusMode）。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回；无 context。
//
// 拆层：纯类型/归一化在 chat/SessionListStatusMode.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI + PreferencesService 持久化，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import {
  SessionListStatusMode,
  DEFAULT_SESSION_LIST_STATUS_MODE,
  normalizeSessionListStatusMode
} from '../chat/SessionListStatusMode';

@ObservedV2
export class SessionListStatusModeState {
  @Trace mode: SessionListStatusMode = DEFAULT_SESSION_LIST_STATUS_MODE;
}

let _state: SessionListStatusModeState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存
export function getSessionListStatusModeState(): SessionListStatusModeState {
  if (_state === null) {
    _state = AppStorageV2.connect(SessionListStatusModeState, () => new SessionListStatusModeState())!;
  }
  return _state;
}

export class SessionListStatusModeService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let mode: SessionListStatusMode = DEFAULT_SESSION_LIST_STATUS_MODE;
    try {
      const stored: string = await getPreferencesService().getString(
        PreferenceKeys.SESSION_LIST_STATUS_MODE,
        DEFAULT_SESSION_LIST_STATUS_MODE
      );
      mode = normalizeSessionListStatusMode(stored);
    } catch (e) {
      // 读失败默认 standard
    }
    getSessionListStatusModeState().mode = mode;
  }

  // 设置页切换调：改 mode @Trace（Index SessionItem 即时重渲染）+ 持久化
  static async setMode(mode: SessionListStatusMode): Promise<void> {
    getSessionListStatusModeState().mode = mode;
    try {
      await getPreferencesService().putString(PreferenceKeys.SESSION_LIST_STATUS_MODE, mode);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentMode(): SessionListStatusMode {
    return getSessionListStatusModeState().mode;
  }
}
