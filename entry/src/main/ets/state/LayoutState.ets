// 布局状态：状态栏/导航条安全区高度 + 窗口引用 + 状态栏图标色。
//
// 为 ChatPage HDS 沉浸光感服务（ignoreLayoutSafeArea 后内容延伸到状态栏，需读 topAvoidHeight 做首项占位）。
// 照搬 berry3 AppLayoutState（topAvoidHeight/bottomAvoidHeight）+ ThemeColorManager（状态栏图标色）范式。
//
// 状态栏图标色：setWindowLayoutFullScreen(true) 后系统不再自动随 setColorMode 调状态栏图标色，
//   需显式 setWindowSystemBarProperties（照搬 berry ThemeColorManager:330）。
//   EntryAbility 启动设初始值；ThemeService 明暗切换时重设。

import { AppStorageV2, window } from '@kit.ArkUI';

@ObservedV2
export class LayoutState {
  /** 顶部安全区高度（状态栏，vp）—— ChatPage List 首项占位用 */
  @Trace topAvoidHeight: number = 0;
  /** 底部安全区高度（手势导航条，vp） */
  @Trace bottomAvoidHeight: number = 0;
}

// 全局单例（AppStorageV2 共享，跨页面/Ability 实例一致）
let _state: LayoutState | null = null;
export function getLayoutState(): LayoutState {
  if (_state === null) {
    _state = AppStorageV2.connect(LayoutState, () => new LayoutState())!;
  }
  return _state;
}

// 窗口引用（运行时资源，不入 AppStorageV2；EntryAbility 启动存入）
let _mainWindow: window.Window | null = null;
export function setMainWindow(win: window.Window): void {
  _mainWindow = win;
}

// 状态栏图标色：暗色→浅图标 / 亮色→深图标（照搬 chatcube getHdsStatusBarContentColor 色值）。
//   全屏后系统不自动管，需显式设。mainWindow 未就绪时静默跳过（EntryAbility 存窗口后会再调一次）。
export function applyStatusBarColor(isDark: boolean): void {
  if (_mainWindow === null) {
    return;
  }
  try {
    _mainWindow.setWindowSystemBarProperties({
      statusBarContentColor: isDark ? '#F5F7FA' : '#1F2329'
    });
  } catch (e) {
    // 状态栏图标色可选；失败不阻塞 UI
  }
}
