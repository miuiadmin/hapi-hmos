// ChatSurfaceColorsService —— 聊天气泡自定义配色的响应式状态 + 持久化 + 主题重 resolve。
//
// 架构（镜像 TerminalToolDisplayService / VoiceSettingsService）：
//   @ObservedV2 ChatSurfaceColorsState{@Trace toolGroupBg, @Trace userMessageBg} 经 AppStorageV2 应用级共享单例；
//   @Trace 存 resolve 后的 hex（''=用 palette 默认），消费点 ToolCard/ChatPage 直读触发 V2 重渲染。
//   偏好串（'default'|'preset:soft-x'|'custom:#hex'）存非 @Trace 实例字段（UI 不直接读，仅供 reapply 重 resolve）。
//
//   关键：base/ratio 随 isDark 变（上游 surface base 与 ratio 矩阵均明暗分叉）→ 主题切换必调 reapply(isDark) 重 mix。
//     isDark 由调用方传入（init/reapply 参数），本服务缓存 _isDark 供 setXxx 复用——
//     避免反向 import ThemeService 造成 ThemeService↔本服务 的导入环（根因修复：paletteOf 取自 leaf Palette）。
//
//   决策（对照 plan C）：tool-group base = paletteOf(isDark).surface（与上游中性面 1:1）；
//     user-message base = paletteOf(isDark).primary（染现有蓝气泡，文字保持白）。
//
// 拆层：纯算法在 chat/ChatSurfaceColors.ets（无 @kit，LocalUnit 可测）；
//   本文件仅 @kit.ArkUI + PreferencesService 持久化 + Palette 调色板，留真机验证。

import { AppStorageV2 } from '@kit.ArkUI';
import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import { paletteOf } from '../theme/Palette';
import {
  ChatSurfaceColorPreference,
  DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE,
  parseChatSurfaceColorPreference,
  resolveSurfaceColor
} from '../chat/ChatSurfaceColors';

@ObservedV2
export class ChatSurfaceColorsState {
  // resolve 后的 hex；''=用 palette 默认（消费点 x || palette.fallback）
  @Trace toolGroupBg: string = '';
  @Trace userMessageBg: string = '';
  // 偏好串（非 @Trace；reapply 时据此 + 当前 isDark 重 resolve）
  toolGroupPref: ChatSurfaceColorPreference = DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE;
  userMessagePref: ChatSurfaceColorPreference = DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE;
}

let _state: ChatSurfaceColorsState | null = null;
// isDark 缓存：init/reapply 由调用方传入；setXxx 复用（ThemeService 改 isDark 后同步 reapply 保持新鲜）
let _isDark: boolean = false;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getTerminalToolDisplayState）
export function getChatSurfaceColorsState(): ChatSurfaceColorsState {
  if (_state === null) {
    _state = AppStorageV2.connect(ChatSurfaceColorsState, () => new ChatSurfaceColorsState())!;
  }
  return _state;
}

// 偏好 + isDark → resolve（null→'' 表用 palette 默认）
function resolveToHex(pref: ChatSurfaceColorPreference, isDark: boolean, base: string): string {
  const resolved: string | null = resolveSurfaceColor(pref, isDark, base);
  return resolved !== null ? resolved : '';
}

// 按 _isDark + palette base 重 resolve两 @Trace 字段（setXxx / reapply 共用）
function resolveNow(): void {
  const state: ChatSurfaceColorsState = getChatSurfaceColorsState();
  const palette = paletteOf(_isDark);
  state.toolGroupBg = resolveToHex(state.toolGroupPref, _isDark, palette.surface);
  state.userMessageBg = resolveToHex(state.userMessagePref, _isDark, palette.primary);
}

export class ChatSurfaceColorsService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize / ThemeService.init 之后，
  //   因读 Preferences + isDark 由调用方传入）
  static async init(isDark: boolean): Promise<void> {
    _isDark = isDark;
    let toolPref: ChatSurfaceColorPreference = DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE;
    let userPref: ChatSurfaceColorPreference = DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE;
    try {
      const rawTool: string = await getPreferencesService().getString(
        PreferenceKeys.TOOL_GROUP_BG,
        DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE
      );
      const rawUser: string = await getPreferencesService().getString(
        PreferenceKeys.USER_MESSAGE_BG,
        DEFAULT_CHAT_SURFACE_COLOR_PREFERENCE
      );
      toolPref = parseChatSurfaceColorPreference(rawTool);
      userPref = parseChatSurfaceColorPreference(rawUser);
    } catch (e) {
      // 读失败默认 default（不染）
    }
    const state: ChatSurfaceColorsState = getChatSurfaceColorsState();
    state.toolGroupPref = toolPref;
    state.userMessagePref = userPref;
    resolveNow();
  }

  // 设置页切换工具组背景调：解析 + 持久化偏好串 + 重 resolve（用缓存 _isDark）
  static async setToolGroupBg(pref: ChatSurfaceColorPreference): Promise<void> {
    const state: ChatSurfaceColorsState = getChatSurfaceColorsState();
    state.toolGroupPref = pref;
    resolveNow();
    try {
      await getPreferencesService().putString(PreferenceKeys.TOOL_GROUP_BG, pref);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  // 设置页切换用户消息背景调
  static async setUserMessageBg(pref: ChatSurfaceColorPreference): Promise<void> {
    const state: ChatSurfaceColorsState = getChatSurfaceColorsState();
    state.userMessagePref = pref;
    resolveNow();
    try {
      await getPreferencesService().putString(PreferenceKeys.USER_MESSAGE_BG, pref);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  // 主题（isDark）变化时调：刷新缓存 + 重 resolve 两 @Trace 字段。
  //   ThemeService.setMode / applySystemColorMode 改 isDark 后同步调（避浅深切换后气泡色不更新）。
  static reapply(isDark: boolean): void {
    _isDark = isDark;
    resolveNow();
  }

  static get currentToolGroupBg(): string { return getChatSurfaceColorsState().toolGroupBg; }
  static get currentUserMessageBg(): string { return getChatSurfaceColorsState().userMessageBg; }
  static get currentToolGroupPref(): ChatSurfaceColorPreference {
    return getChatSurfaceColorsState().toolGroupPref;
  }
  static get currentUserMessagePref(): ChatSurfaceColorPreference {
    return getChatSurfaceColorsState().userMessagePref;
  }
}
