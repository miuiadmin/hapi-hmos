// VoiceSettingsService —— 语音语言/声音的响应式状态 + 持久化。
//
// 架构（镜像 TerminalToolDisplayService）：
//   @ObservedV2 VoiceSettingsState{@Trace voiceLang, @Trace voiceId} 经 AppStorageV2 应用级共享单例；
//   VoicePage.doBoot 读 currentLang/voiceId（boot 时取最新，无需响应式）；
//   SettingsPage 切换 setLang/setVoice → 改 @Trace → 持久化（下次进语音页生效）。
//   init 在 EntryAbility.bootstrap（loadContent 前）从 Preferences 读回。
//
// 拆层：语言表/映射在 chat/VoiceLanguages.ets、声音表在 chat/VoiceVoices.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI（@ObservedV2/@Trace/AppStorageV2）+ PreferencesService 持久化，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';

@ObservedV2
export class VoiceSettingsState {
  @Trace voiceLang: string = '';   // locale 码；''=自动检测
  @Trace voiceId: string = '';     // ElevenLabs voice id；''=Hub 默认 agent
}

let _state: VoiceSettingsState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getTerminalToolDisplayState）
export function getVoiceSettingsState(): VoiceSettingsState {
  if (_state === null) {
    _state = AppStorageV2.connect(VoiceSettingsState, () => new VoiceSettingsState())!;
  }
  return _state;
}

export class VoiceSettingsService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后，因读 Preferences）
  static async init(): Promise<void> {
    try {
      const lang: string = await getPreferencesService().getString(PreferenceKeys.VOICE_LANG, '');
      const vid: string = await getPreferencesService().getString(PreferenceKeys.VOICE_ID, '');
      getVoiceSettingsState().voiceLang = lang;
      getVoiceSettingsState().voiceId = vid;
    } catch (e) {
      // 读失败默认自动检测 + Hub 默认声
    }
  }

  // 设置页切换调：改 @Trace + 持久化（下次进语音页生效）
  static async setLang(code: string): Promise<void> {
    getVoiceSettingsState().voiceLang = code;
    try {
      await getPreferencesService().putString(PreferenceKeys.VOICE_LANG, code);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static async setVoice(id: string): Promise<void> {
    getVoiceSettingsState().voiceId = id;
    try {
      await getPreferencesService().putString(PreferenceKeys.VOICE_ID, id);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentLang(): string { return getVoiceSettingsState().voiceLang; }
  static get currentVoiceId(): string { return getVoiceSettingsState().voiceId; }
}
