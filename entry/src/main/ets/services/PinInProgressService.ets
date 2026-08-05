// PinInProgressService —— 「置顶进行中会话」开关的响应式状态 + 持久化（v0.26.0 对照 web usePinInProgressSessions）。
//
// 架构（镜像 SessionPreviewLimitService）：
//   @ObservedV2 PinInProgressState{@Trace enabled} 经 AppStorageV2 应用级共享单例；
//   Index.sessionRows getter 读 enabled（@Trace 改 → getter 重算，活跃会话即时抽到「进行中」分区）。
//   init 在 EntryAbility.bootstrap（loadContent 前、PreferencesService.initialize 之后）从 Preferences 读回。
//
// 默认关（对照 web DEFAULT_PIN_IN_PROGRESS_SESSIONS = false）：关时活跃会话仍按目录分组，不抽顶。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';

// 默认值（对照 web DEFAULT_PIN_IN_PROGRESS_SESSIONS）
export const DEFAULT_PIN_IN_PROGRESS_SESSIONS: boolean = false;

@ObservedV2
export class PinInProgressState {
  @Trace enabled: boolean = DEFAULT_PIN_IN_PROGRESS_SESSIONS;
}

let _state: PinInProgressState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存
export function getPinInProgressState(): PinInProgressState {
  if (_state === null) {
    _state = AppStorageV2.connect(PinInProgressState, () => new PinInProgressState())!;
  }
  return _state;
}

export class PinInProgressService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let enabled: boolean = DEFAULT_PIN_IN_PROGRESS_SESSIONS;
    try {
      enabled = await getPreferencesService().getBoolean(
        PreferenceKeys.PIN_IN_PROGRESS_SESSIONS,
        DEFAULT_PIN_IN_PROGRESS_SESSIONS
      );
    } catch (e) {
      // 读失败默认关
    }
    getPinInProgressState().enabled = enabled;
  }

  // 设置页切换调：改 enabled @Trace（Index sessionRows getter 即时重算）+ 持久化
  static async setEnabled(enabled: boolean): Promise<void> {
    getPinInProgressState().enabled = enabled;
    try {
      await getPreferencesService().putBoolean(PreferenceKeys.PIN_IN_PROGRESS_SESSIONS, enabled);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  // 设置页 getter 读（对照 HapticService.currentEnabled / SessionPreviewLimitService.currentLimit）。
  static get currentEnabled(): boolean {
    return getPinInProgressState().enabled;
  }
}
