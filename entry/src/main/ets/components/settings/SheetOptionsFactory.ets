// SheetOptionsFactory —— bindSheet 半模态弹窗统一视觉配置工厂（对照 berry3 utils/SheetOptionsFactory.ets）。
//
// 【为什么】收口「全站一致 4 字段」：背景白身（c.bg，调用点传）+ 毛玻璃 COMPONENT_ULTRA_THICK +
//   无系统把手 + 无系统关闭按钮（关闭靠 SheetDialog 标题栏右上角灰圆 ✕）。detents/height/onWillDismiss
//   因各弹窗差异大，由调用点透传覆盖。
//
// 【hapi-hmos 颜色走 JS 调色板】工厂不接受 $r('app.color.sheet_background')，而是调用点传 this.c.bg
//   （响应式：组件 rebuild 时 options 重算，主题切换随之刷新）。⚠️ 调用点传覆写参数须经「具名 interface
//   标注的 const」承接再传入（ArkTS 严格模式禁传参对象字面量）。
//
// 【ArkTS 严格模式】无对象展开 {...base, ...overrides}：工厂接受显式覆写参数，内部分支一次性 return
//   完整 SheetOptions，返回值用 const: SheetOptions 承接（带字段字面量须具名 interface 标注）。

/** 弹窗视觉覆写参数：仅写需覆盖默认值的字段，其余走工厂默认（白底 + 毛玻璃 + 无把手 + 无系统关闭）。 */
export interface SheetOverrides {
  /** 档位（与 height 二选一）；不传默认 [FIT_CONTENT, LARGE] */
  detents?: [(SheetSize | Length), (SheetSize | Length)?, (SheetSize | Length)?];
  /** 固定高度档（与 detents 二选一） */
  height?: SheetSize | Length;
  /** 毛玻璃样式（默认 COMPONENT_ULTRA_THICK） */
  blurStyle?: BlurStyle;
  /** 背景色（默认调用点传入的白身 c.bg） */
  backgroundColor?: ResourceColor;
  /** 关闭前拦截 */
  onWillDismiss?: (action: DismissSheetAction) => void;
  /** 软键盘避让模式 */
  keyboardAvoidMode?: SheetKeyboardAvoidMode;
  /** 是否启用遮罩外交互 */
  enableOutsideInteractive?: boolean;
  /** sheet 消失后的回调 */
  onDisappear?: () => void;
}

/**
 * 构建 bindSheet 统一视觉配置。
 * @param bgColor sheet 白身背景色（调用点传 this.c.bg；可被 o.backgroundColor 覆写）
 * @param o 覆写参数（可选，须经 const: SheetOverrides 承接再传入）；不传则全走默认
 * @returns SheetOptions，可直接作为 bindSheet 第三参数
 */
export function buildSheetOptions(bgColor: ResourceColor, o?: SheetOverrides): SheetOptions {
  if (o !== undefined) {
    // height 与 detents 互斥：传 height 走固定档，否则用 detents（默认首档贴合内容）
    const useHeight: boolean = o.height !== undefined;
    const opts: SheetOptions = {
      backgroundColor: o.backgroundColor ?? bgColor,
      blurStyle: o.blurStyle ?? BlurStyle.COMPONENT_ULTRA_THICK,
      dragBar: false,
      showClose: false,
      height: useHeight ? o.height : undefined,
      detents: useHeight ? undefined : (o.detents ?? [SheetSize.FIT_CONTENT, SheetSize.LARGE]),
      onWillDismiss: o.onWillDismiss,
      keyboardAvoidMode: o.keyboardAvoidMode,
      enableOutsideInteractive: o.enableOutsideInteractive,
      onDisappear: o.onDisappear
    };
    return opts;
  }
  // o 缺省：全走默认（白身 + 毛玻璃 + 无把手 + 无系统关闭 + [FIT_CONTENT, LARGE]）
  const def: SheetOptions = {
    backgroundColor: bgColor,
    blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
    dragBar: false,
    showClose: false,
    height: undefined,
    detents: [SheetSize.FIT_CONTENT, SheetSize.LARGE],
    onWillDismiss: undefined,
    keyboardAvoidMode: undefined,
    enableOutsideInteractive: undefined,
    onDisappear: undefined
  };
  return def;
}
