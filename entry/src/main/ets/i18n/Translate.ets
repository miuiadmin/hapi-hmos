// 纯翻译层 —— 无 @kit / 无 ArkUI 依赖，LocalUnit 单测可直接 import。
//
// 与 I18nService 的分工：
//   - 本模块只管「按 locale 查表 + {name} 插值」，locale 是一个模块级变量（默认 zh-CN）。
//   - I18nService（@kit 依赖）管 @Trace 响应式 locale 状态 + 系统语言探测 + 持久化，
//     并在 init/setChoice 同步调 setTranslateLocale，让纯逻辑侧 t() 与 UI 侧同语言。
//   - 纯逻辑文件（Types / Message / Outline / Presentation / DateFormatUtils / HubClientUtils）
//     从「本模块」import t —— 不引入 @kit，LocalUnit 可加载（parse/format 单测不受影响）。
//   - UI 文件继续从 I18nService import t（响应式版：直接读 @Trace locale，随语言切换重渲染）。
//
// 选择不把响应式 t() 放这里：避免通过函数指针间接读 @Trace（V2 依赖追踪对直接属性读最稳）。
// 两个 t() 输出一致（locale 经 setTranslateLocale 同步），只是 locale 来源不同。
//
// t() 三级回落：当前 locale → 中文（兜底）→ key 本身（对照上游 web locales）。

import { zhCN } from './locales/zh-CN';
import { en } from './locales/en';

// 实际生效 locale（t() 查表用）；I18nService.init/setChoice 同步更新
export type Locale = 'zh-CN' | 'en';

let _locale: Locale = 'zh-CN';

// 供 I18nService 同步纯逻辑侧 locale（UI 侧由 @Trace state.locale 驱动）
export function setTranslateLocale(locale: Locale): void {
  _locale = locale;
}

export function getTranslateLocale(): Locale {
  return _locale;
}

// 插值 {name} → params[name]；未命中保留原 {name}（上游同款）。
// 手写扫描：ArkTS 对 String.replace 回调支持不稳，故不用正则 replace-fn。
export function interpolate(str: string, params?: Record<string, string | number>): string {
  if (params === undefined) { return str; }
  let out: string = '';
  let i: number = 0;
  while (i < str.length) {
    const ch: string = str.charAt(i);
    if (ch === '{') {
      const end: number = str.indexOf('}', i);
      if (end > i) {
        const name: string = str.substring(i + 1, end);
        const v: string | number | undefined = params[name];
        if (v !== undefined) {
          out += typeof v === 'number' ? v.toString() : v;
        } else {
          out += str.substring(i, end + 1);
        }
        i = end + 1;
        continue;
      }
    }
    out += ch;
    i++;
  }
  return out;
}

// 显式 locale 查表（I18nService.t 响应式版用：传 @Trace locale）
export function translate(locale: Locale, key: string, params?: Record<string, string | number>): string {
  const primary: Record<string, string> = locale === 'en' ? en : zhCN;
  const v: string | undefined = primary[key];
  if (v !== undefined) { return interpolate(v, params); }
  const fb: string | undefined = zhCN[key];
  if (fb !== undefined) { return interpolate(fb, params); }
  return interpolate(key, params);
}

// 便捷查表（纯逻辑侧用）：locale 取模块级 _locale（由 I18nService 同步）。
// LocalUnit 未调 setTranslateLocale 时默认 zh-CN，单测断言中文即匹配。
export function t(key: string, params?: Record<string, string | number>): string {
  return translate(_locale, key, params);
}
