// 主题服务：单例状态 + 全局取值器 + 明暗解析 + 持久化 + 系统色彩模式同步。
//
// 架构（详见 memory「主题系统」）：颜色统一走 JS 调色板（markdown_hybrid 吃 number，原生 $r 无法触发其缓存重建）；
//   组件通过 getThemeState().isDark 读 @Trace 建立刷新依赖（V2 细粒度观察，chatcube 实证）。
//
// 明暗解析要点（对照 chatcube EntryAbility）：
//   - setColorMode(LIGHT/DARK) 后 context.config.colorMode 反映的是「应用覆盖值」而非系统真实值；
//   - 故「跟随系统」须依赖 _systemDark 缓存：init 时在覆盖前读 context.config.colorMode 记录，onConfigurationUpdate 更新。
//   - setColorMode 本身只影响系统面（状态栏等），失败不影响 JS 调色板驱动 → try/catch 静默。

import { AppStorageV2 } from '@kit.ArkUI';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ThemeState, ThemeMode } from './ThemeState';
import { getPreferencesService } from '../services/PreferencesService';
import { PreferenceKeys } from '../config/Keys';

// barrel：组件只需 import 自本文件即可拿到 paletteOf / PaletteColors / toArgb / ThemeState / getThemeState
export { paletteOf, PaletteColors, toArgb } from './Palette';
export { ThemeState, ThemeMode } from './ThemeState';

let _state: ThemeState | null = null;
// 系统真实明暗缓存（mode==='system' 时 isDark 取它）
let _systemDark: boolean = false;

// 字号缩放档位（设置页三选；存档位字符串，state.fontScale 存数值因子）
export type FontScaleMode = 'small' | 'default' | 'large';
const FONT_SCALE_FACTOR: Record<FontScaleMode, number> = {
  'small': 0.9,
  'default': 1.0,
  'large': 1.2
};

// 全局字号缩放取值器：组件每个 .fontSize(N) 套 fs(N)，读 fontScale @Trace 即时随设置页重渲染。
//   Math.round 保整数 vp（ArkUI fontSize 支持小数，但整数避免亚像素模糊）；下限 1。
export function fs(base: number): number {
  const scaled: number = Math.round(base * getThemeState().fontScale);
  return scaled < 1 ? 1 : scaled;
}

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存；所有组件/页面都调它取主题（不持 @Local、不逐处 connect）
export function getThemeState(): ThemeState {
  if (_state === null) {
    _state = AppStorageV2.connect(ThemeState, () => new ThemeState())!;
  }
  return _state;
}

function toColorModeConstant(mode: ThemeMode): ConfigurationConstant.ColorMode {
  if (mode === 'light') {
    return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  }
  if (mode === 'dark') {
    return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }
  return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;   // system → 跟随系统
}

// 实际明暗：light→false / dark→true / system→_systemDark 缓存
function resolveIsDark(mode: ThemeMode): boolean {
  if (mode === 'light') {
    return false;
  }
  if (mode === 'dark') {
    return true;
  }
  return _systemDark;
}

// 读系统真实明暗（须在 setColorMode 覆盖前调用，否则读到的是应用覆盖值）
function readSystemDark(context: common.UIAbilityContext): boolean {
  return context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
}

// 应用色彩模式（仅系统面一致性；JS 调色板才是 UI 真实色源）
function setAppColorMode(context: common.UIAbilityContext, colorMode: ConfigurationConstant.ColorMode): void {
  try {
    context.getApplicationContext().setColorMode(colorMode);
  } catch (e) {
    // 系统面色彩可选；失败不影响 JS 调色板
  }
}

export class ThemeService {
  // EntryAbility.bootstrap 在 loadContent 前调（必须在 PreferencesService.initialize 之后，因读 mode）
  static async init(context: common.UIAbilityContext): Promise<void> {
    let mode: ThemeMode = 'system';
    try {
      const stored: string = await getPreferencesService().getString(PreferenceKeys.THEME_MODE, 'system');
      if (stored === 'light' || stored === 'dark' || stored === 'system') {
        mode = stored;
      }
    } catch (e) {
      // 读失败默认 system
    }

    // 覆盖前记录系统真实明暗
    _systemDark = readSystemDark(context);

    const state: ThemeState = getThemeState();
    state.mode = mode;
    state.isDark = resolveIsDark(mode);
    setAppColorMode(context, toColorModeConstant(mode));

    // 字号缩放（独立于主题，但同走 Preferences；缺省 default）
    let scaleMode: FontScaleMode = 'default';
    try {
      const storedScale: string = await getPreferencesService().getString(PreferenceKeys.FONT_SCALE, 'default');
      if (storedScale === 'small' || storedScale === 'large') {
        scaleMode = storedScale;
      }
    } catch (e) {
      // 读失败默认 default
    }
    state.fontScale = FONT_SCALE_FACTOR[scaleMode];
  }

  // 设置页切换主题调
  static async setMode(mode: ThemeMode, context: common.UIAbilityContext): Promise<void> {
    const state: ThemeState = getThemeState();
    state.mode = mode;
    state.isDark = resolveIsDark(mode);
    setAppColorMode(context, toColorModeConstant(mode));
    try {
      await getPreferencesService().putString(PreferenceKeys.THEME_MODE, mode);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  // EntryAbility.onConfigurationUpdate 调：系统明暗变化 → 缓存；system 模式下同步 isDark
  static applySystemColorMode(systemDark: boolean): void {
    _systemDark = systemDark;
    const state: ThemeState = getThemeState();
    if (state.mode === 'system') {
      state.isDark = systemDark;
    }
  }

  // 设置页切字号调（无需 context——纯 JS 调色板无关，仅 state + 持久化）
  static async setFontScale(scaleMode: FontScaleMode): Promise<void> {
    const state: ThemeState = getThemeState();
    state.fontScale = FONT_SCALE_FACTOR[scaleMode];
    try {
      await getPreferencesService().putString(PreferenceKeys.FONT_SCALE, scaleMode);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentMode(): ThemeMode {
    return getThemeState().mode;
  }

  static get currentFontScaleMode(): FontScaleMode {
    const s: number = getThemeState().fontScale;
    if (s < 0.95) { return 'small'; }
    if (s > 1.05) { return 'large'; }
    return 'default';
  }
}
