import {
  hdsMaterial,
  ScrollEffectType,
  TitleBarStyleOptions,
  TitleBarContentOptions,
  HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationMenuItemOptions,
  BlurStrategy,
  DividerShowType
} from '@kit.UIDesignKit';
import { LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import { PaletteColors } from '../theme/ThemeService';

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
 * @param staticBlur 真=静止磨砂（Web 容器页无 Scroller，不滚动联动，originalStyle 恒磨砂）；缺省=滚动联动（GRADIENT_BLUR）。
 */
export function hdsTitleBarStyle(bg: string, staticBlur?: boolean): TitleBarStyleOptions {
  // 静止磨砂（Web 容器页 Terminal/Voice：ArkUI 无 Scroller，不滚动联动）：
  //   不设 scrollEffectOpts（不依赖 scroller），originalStyle 直接放磨砂态（bg E6 + blurRadius 26）。
  //   systemMaterialEffect ADAPTIVE 仍带（走系统合成器模拟器可渲染；Web 背后磨砂真机确认，E6 半透明兜底防穿帮）。
  if (staticBlur) {
    return {
      originalStyle: {
        backgroundStyle: {
          backgroundColor: withAlpha(bg, 'E6'),
          maskExtraHeight: 20,
          blurRadius: 26
        }
      },
      blurStrategy: BlurStrategy.ENABLE,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
  }
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

// —— 原生页 titleBar 工厂（向 ChatPage / chatcube buildHdsTopNavigationTitleBarOptionsForNativePage 看齐）——
//   根因（ChatPage:2986 注释 + berry3 FloatingToolbar 注释）：systemMaterialEffect 只有官方 titleBar 容器可用，
//   没有独立光感钮组件——手搓 Button+backgroundBlurStyle 不是真液态。故简单页统一走原生 backIcon + menu + title，
//   钮由系统 systemMaterialEffect 渲染真液态玻璃，contentStyle 给三级背景色（模拟器也有可见圆形磨砂底）。

/** contentStyle：原生 titleBar 钮/标题样式（对齐 ChatPage:3512-3525 / chatcube HdsVisualEffectUtil:145-158）。
 *   menu/backIcon 走系统三级背景色 + 主图标色（系统色自适应明暗）→ 即使模拟器不跑 blur，钮也有可见圆形磨砂底。
 *   title 走调色板色（随主题）。 */
export function hdsContentStyle(textPrimary: string, textSecondary: string): HdsTitleBarContentStyle {
  return {
    titleStyle: { mainTitleColor: textPrimary, subTitleColor: textSecondary },
    menuStyle: {
      backgroundColor: $r('sys.color.comp_background_tertiary'),
      iconColor: $r('sys.color.icon_primary')
    },
    backIconStyle: {
      backgroundColor: $r('sys.color.comp_background_tertiary'),
      iconColor: $r('sys.color.icon_primary')
    }
  };
}

/** 菜单项图标 helper（SymbolGlyphModifier 统一 fontSize 20；字色交系统 menuStyle.iconColor 渲染）。 */
export function nativeMenuIcon(symbol: Resource): SymbolGlyphModifier {
  const icon: SymbolGlyphModifier = new SymbolGlyphModifier(symbol);
  icon.fontSize(20);
  return icon;
}

/** 系统原生菜单项（对齐 ChatPage titleBarMenuItems 的单项构造）。 */
export function nativeMenuItem(label: ResourceStr, icon: SymbolGlyphModifier,
  action: () => void): HdsNavigationMenuItemOptions {
  return {
    content: {
      label: label,
      icon: icon,
      action: action
    }
  };
}

/** 系统原生返回钮（titleBar.content.backIcon）：由系统 systemMaterialEffect 渲染真·液态玻璃圆钮。 */
export function nativeBackIcon(action: () => void): HdsNavigationBackButtonItemOptions {
  const icon: SymbolGlyphModifier = new SymbolGlyphModifier($r('sys.symbol.chevron_backward'));
  icon.fontSize(20);
  return {
    icon: icon,
    action: action
  };
}

/** buildNativePageTitleBar 配置。 */
export interface NativeTitleBarCfg {
  /** 原生 mainTitle（无 stackBuilder 时用）；有 stackBuilder 时被占位 ' ' 取代。 */
  title: ResourceStr;
  /** 返回动作（通常 navPathStack.pop）。 */
  backAction: () => void;
  /** 菜单项（非空才挂 menu）；常驻栏直接图标 + 其余溢出到系统⋯ 下拉。 */
  menuItems?: Array<HdsNavigationMenuItemOptions>;
  /** 直接显示的菜单图标数（余溢出到⋯）；缺省 1（对齐 ChatPage：1 常驻 + ⋯ 下拉）。 */
  menuMaxCount?: number;
  /** 真=静止磨砂（Web 容器页无 Scroller）；缺省=滚动联动（GRADIENT_BLUR）。 */
  staticBlur?: boolean;
  /** 自定义标题列构建器（给=mainTitle 占位 ' ' + stackBuilder；不给=纯原生 mainTitle）。
   *   用于需动态染色副标题的页（Terminal/Voice 状态文字），其余简单页走纯原生 mainTitle。 */
  stackBuilder?: () => void;
}

/** 原生页 titleBar 全配置工厂：返回完整 HdsNavigationTitleBarOptions（content + style + 安全区）。
 *   style 复用 hdsTitleBarStyle 的静止磨砂/滚动联动 + 注入 hdsContentStyle（钮三级背景色）。 */
export function buildNativePageTitleBar(c: PaletteColors, cfg: NativeTitleBarCfg): HdsNavigationTitleBarOptions {
  const cs: HdsTitleBarContentStyle = hdsContentStyle(c.textPrimary, c.textSecondary);
  const staticBlur: boolean = cfg.staticBlur === true;
  const menuMaxCount: number = cfg.menuMaxCount !== undefined ? cfg.menuMaxCount : 1;

  // style：静止磨砂（Web 容器页）或 滚动联动（默认）；contentStyle 注入钮/标题样式。
  let style: TitleBarStyleOptions;
  if (staticBlur) {
    style = {
      originalStyle: {
        backgroundStyle: {
          backgroundColor: withAlpha(c.bg, 'E6'),
          maskExtraHeight: 20,
          blurRadius: 26
        },
        contentStyle: cs
      },
      blurStrategy: BlurStrategy.ENABLE,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
  } else {
    style = {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
        blurEffectiveStartOffset: LengthMetrics.vp(0),
        blurEffectiveEndOffset: LengthMetrics.vp(28)
      },
      originalStyle: {
        backgroundStyle: {
          backgroundColor: withAlpha(c.bg, '00'),
          maskExtraHeight: 20,
          blurRadius: 0
        },
        contentStyle: cs
      },
      scrollEffectStyle: {
        backgroundStyle: {
          backgroundColor: withAlpha(c.bg, 'E6'),
          maskExtraHeight: 20,
          blurRadius: 26
        },
        contentStyle: cs
      },
      blurStrategy: BlurStrategy.ENABLE,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
  }

  // content：title（stackBuilder 时占位）/ divider OFF / backIcon / 可选 menu / 可选 stackBuilder。
  const content: TitleBarContentOptions = {
    title: cfg.stackBuilder !== undefined ? { mainTitle: ' ' } : { mainTitle: cfg.title },
    divider: { showType: DividerShowType.OFF },
    backIcon: nativeBackIcon(cfg.backAction)
  };
  if (cfg.menuItems !== undefined && cfg.menuItems.length > 0) {
    content.menu = {
      maxCount: menuMaxCount,
      value: cfg.menuItems
    };
  }
  if (cfg.stackBuilder !== undefined) {
    content.stackBuilder = cfg.stackBuilder;
  }

  return {
    content: content,
    style: style,
    avoidLayoutSafeArea: true,
    enableComponentSafeArea: false
  };
}
