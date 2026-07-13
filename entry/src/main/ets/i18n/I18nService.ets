// 国际化服务：响应式 locale 状态（@kit 依赖）+ 系统语言探测 + 持久化。
//
// 架构对照 ThemeService（JS 驱动，非原生 $r 资源）：
//   - UI 组件在 build() 内调 t('key') → 内部读 getI18nState().locale（@Trace）→ 建立 V2 刷新依赖；
//     setChoice 改 locale → 全部读 t() 的 UI 组件即时重渲染（同 getThemeState().isDark 机制）。
//   - locale 表为 JS Record（i18n/locales/zh-CN.ets + en.ets），扁平 dotted key（对照上游 locales/*）。
//   - 持久化存「选择」(system|zh-CN|en)，state 存「解析后 locale」(zh-CN|en)——同 ThemeMode(light/dark/system)→isDark。
//
// 翻译查表 / 插值逻辑下沉到无 @kit 的 Translate.ets（纯逻辑层）：
//   - UI 侧本文件的 t() 调 translate(getI18nState().locale, ...) —— 直接读 @Trace，响应式正确。
//   - 纯逻辑文件（Types/Message/Outline/Presentation/DateFormatUtils/HubClientUtils）直接 import
//     Translate 的 t()，locale 经下面 setTranslateLocale() 同步 —— 这样 LocalUnit 单测 import 纯逻辑时不带入 @kit。
//   - 两个 t() 输出一致（locale 同步），只是 locale 来源不同（UI=@Trace，逻辑=模块级变量）。
//
// t() 三级回落：当前 locale → 中文（兜底）→ key 本身（上游同款）。

import { AppStorageV2 } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { getPreferencesService } from '../services/PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import { translate, setTranslateLocale } from './Translate';

// 语言选择（持久化值；system=跟随系统）
export type LanguageChoice = 'system' | 'zh-CN' | 'en';
// 实际生效 locale（t() 查表用）—— 从 Translate 复用类型（再导出供外部按需用）
export type Locale = 'zh-CN' | 'en';

@ObservedV2
export class I18nState {
  // 解析后生效 locale；UI 组件经 t()→getI18nState().locale 读它建 V2 刷新依赖
  @Trace locale: Locale = 'zh-CN';
}

let _state: I18nState | null = null;
// 当前语言选择缓存（currentChoice getter 用；init/setChoice 同步更新）
let _choice: LanguageChoice = 'system';

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（同 getThemeState）
export function getI18nState(): I18nState {
  if (_state === null) {
    _state = AppStorageV2.connect(I18nState, () => new I18nState())!;
  }
  return _state;
}

// 系统语言探测（@kit.LocalizationKit）：zh*→zh-CN，余→en；失败默认中文
function detectSystemLocale(): Locale {
  try {
    const sys: string = i18n.System.getSystemLanguage();   // BCP-47，如 'zh-Hans-CN' / 'en-US'
    if (sys.toLowerCase().startsWith('zh')) {
      return 'zh-CN';
    }
    return 'en';
  } catch (e) {
    return 'zh-CN';
  }
}

function resolveLocale(choice: LanguageChoice): Locale {
  if (choice === 'zh-CN') { return 'zh-CN'; }
  if (choice === 'en') { return 'en'; }
  return detectSystemLocale();
}

// 响应式翻译查表（UI 侧用）：直接读 @Trace locale → setChoice 改 locale 时所有读 t() 的组件重渲染。
export function t(key: string, params?: Record<string, string | number>): string {
  return translate(getI18nState().locale, key, params);
}

export class I18nService {
  // EntryAbility.bootstrap 在 loadContent 前调（须在 PreferencesService.initialize 之后）
  static async init(context: common.UIAbilityContext): Promise<void> {
    let choice: LanguageChoice = 'system';
    try {
      const stored: string = await getPreferencesService().getString(PreferenceKeys.LANGUAGE, 'system');
      if (stored === 'zh-CN' || stored === 'en' || stored === 'system') {
        choice = stored;
      }
    } catch (e) {
      // 读失败默认 system
    }
    _choice = choice;
    const loc: Locale = resolveLocale(choice);
    getI18nState().locale = loc;
    setTranslateLocale(loc);          // 同步纯逻辑侧 locale（Types/Message/Outline/… 的 t()）
  }

  // 设置页切换语言调（即时改 locale 触发重渲染 + 持久化 choice）
  static async setChoice(choice: LanguageChoice): Promise<void> {
    _choice = choice;
    const loc: Locale = resolveLocale(choice);
    getI18nState().locale = loc;
    setTranslateLocale(loc);          // 同步纯逻辑侧 locale
    try {
      await getPreferencesService().putString(PreferenceKeys.LANGUAGE, choice);
    } catch (e) {
      // 持久化失败不影响本次切换
    }
  }

  static get currentChoice(): LanguageChoice {
    return _choice;
  }
}
