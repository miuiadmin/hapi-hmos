import { hdsMaterial, ScrollEffectType, TitleBarStyleOptions, BlurStrategy } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

// HDS 液态 titleBar 共享配置（消除多页重复 + 统一 ChatPage/berry3 设置页范式）。
//   照搬 ChatPage:3381-3407 的 titleBar.style 内联配置 + berry3 SettingsPage/AdvancedSettingsPage 范式：
//   GRADIENT_BLUR 滚动联动（静止透明 00 / 滚动半透明 E6 + blurRadius 26）+ systemMaterialEffect ADAPTIVE
//   （走系统合成器，模拟器可渲染，区别于通用 backgroundBlurStyle 模拟器 no-op）+ maskExtraHeight:20 过渡带。

/** #RRGGBB → #AA{{RRGGBB}}（HarmonyOS 八位色 alpha 在前）。 */
export function withAlpha(color: string, alphaHex: string): string {
  if (color.startsWith('#') && color.length === 7) {
    return `#${alphaHex}${color.substring(1)}`;
  }
  return color;
}

/**
 * HDS 液态 titleBar style 工厂。
 * @param bg 页面底色（静止态透明 / 滚动态半透明随此色）；随主题切换由调用方 getter 重取（c.bg）。
 */
export function hdsTitleBarStyle(bg: string): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,                                       // 滚动联动：静止透明/滚动磨砂（chatcube/berry3 同款）
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(28)
    },
    originalStyle: {                                                  // 静止态：透明背景 + blurRadius 0（首项可见）
      backgroundStyle: {
        backgroundColor: withAlpha(bg, '00'),
        maskExtraHeight: 20,                                          // 渐变过渡带（解决「边缘硬线无过渡」，竖屏 20）
        blurRadius: 0
      }
    },
    scrollEffectStyle: {                                              // 滚动态：bg 半透明 E6 + blurRadius 26 + 过渡带
      backgroundStyle: {
        backgroundColor: withAlpha(bg, 'E6'),
        maskExtraHeight: 20,
        blurRadius: 26
      }
    },
    blurStrategy: BlurStrategy.ENABLE,
    systemMaterialEffect: {                                           // 系统级材质（走系统合成器，模拟器渲染）
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    }
  };
}
