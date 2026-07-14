// HapticService —— 触感反馈的响应式状态 + 持久化 + 震动执行。
//
// 架构（镜像 ThemeService/TerminalToolDisplayService，简化版）：
//   @ObservedV2 HapticsState{@Trace enabled} 经 AppStorageV2 应用级共享单例；
//   SettingsPage 读 getHapticsState().enabled 建立刷新依赖；切换 setEnabled → 改 @Trace → 即时重渲染。
//   tap(event)：enabled 门控 → 读纯层 hapticEffectFor → 调 @ohos.vibrator（@kit.MiscKit）。
//   fire-and-forget（.then 双空回调 + try/catch），失败静默不炸 UI。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回；无 context（纯 state + 持久化）。
//
// 拆层（项目范式）：意图→效果映射 + pref 归一在 chat/Haptics.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.MiscKit（vibrator）+ @kit.ArkUI（@ObservedV2/@Trace/AppStorageV2）+ PreferencesService，留真机验证。

import { vibrator } from '@kit.MiscKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import {
  HapticEvent,
  hapticEffectFor,
  normalizeHapticsPref,
  hapticsPrefToEnabled,
  hapticsEnabledToPref,
  DEFAULT_HAPTICS_PREF
} from '../chat/Haptics';

@ObservedV2
export class HapticsState {
  @Trace enabled: boolean = true;
}

let _state: HapticsState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getThemeState）
export function getHapticsState(): HapticsState {
  if (_state === null) {
    _state = AppStorageV2.connect(HapticsState, () => new HapticsState())!;
  }
  return _state;
}

export class HapticService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(): Promise<void> {
    let pref = DEFAULT_HAPTICS_PREF;
    try {
      const stored: string = await getPreferencesService().getString(
        PreferenceKeys.HAPTICS_ENABLED,
        DEFAULT_HAPTICS_PREF
      );
      pref = normalizeHapticsPref(stored);
    } catch (e) {
      // 读失败默认开
    }
    getHapticsState().enabled = hapticsPrefToEnabled(pref);
  }

  // 设置页切换调：改 enabled @Trace + 持久化 pref 串
  static async setEnabled(enabled: boolean): Promise<void> {
    getHapticsState().enabled = enabled;
    try {
      await getPreferencesService().putString(PreferenceKeys.HAPTICS_ENABLED, hapticsEnabledToPref(enabled));
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  // 触发触感反馈：enabled 门控 → 读效果 → 调 vibrator（fire-and-forget，失败静默）。
  //   调用方无需 await；频繁交互（如 send）零阻塞。
  static tap(event: HapticEvent): void {
    if (!getHapticsState().enabled) { return; }
    try {
      const e = hapticEffectFor(event);
      vibrator.startVibration(
        { type: 'time', duration: e.durationMs },
        { id: 0, usage: 'notification' }
      ).then(() => {}, () => {});   // 双空回调：成功/失败均不处理
    } catch (e) {
      // 同步异常静默（如设备无震动器）
    }
  }

  static get currentEnabled(): boolean {
    return getHapticsState().enabled;
  }
}
