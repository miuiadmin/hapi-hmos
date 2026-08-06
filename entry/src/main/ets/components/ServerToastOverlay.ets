// ServerToastOverlay —— 服务端 toast 悬浮卡（可点击跳会话）。
//
// 鸿蒙原生 promptAction.showToast() 不可点击，故自建悬浮卡（对照 web ToastProvider 渲染 + 上游点击跳会话）。
//   读 getToastState().current（@Trace）→ current 非空显卡片：
//     - 整卡 onClick → ToastService.dismiss + onTap(sessionId)（跳会话，委托上层 Index.openSessionById）；
//     - ✕ → ToastService.dismiss。
//   挂载：Index.build() 的 Stack 内（Navigation 之上，TopStart 对齐），跨页可见（盖在所有页面之上）。
//   ★全屏沉浸（setWindowLayoutFullScreen）后顶部须补 topAvoidHeight 状态栏避让（topInset），否则顶进状态栏被遮挡。
//   空态 Visibility.None（不占位、不拦截点击）；外层 Row hitTestBehavior(Transparent) → 卡片外区域穿透到下层
//   （卡片只在顶部一小条，下方/两侧空白处点击直达 Navigation）。
//
// 范式合成：ConnectionBanner（读应用级 @ObservedV2 单例）+ QueuedMessagesBar（@Event 委托父）。

import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { getToastState, ToastState, ToastService, ServerToastData } from '../services/ToastService';
import { getLayoutState } from '../state/LayoutState';

@ComponentV2
export struct ServerToastOverlay {
  @Local toastState: ToastState = getToastState();
  @Event onTap: (sessionId: string) => void = (sessionId: string): void => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 全屏沉浸（EntryAbility setWindowLayoutFullScreen）后窗口从 y=0 起，状态栏压在内容之上。
  //   本卡是 Stack 顶部悬浮（TopStart），若仅 top:8 会顶进状态栏、上半截被系统状态栏遮挡
  //   （看似「高度不对 + 层级不对」）→ 顶部须补状态栏避让高度 topAvoidHeight，把卡片推到状态栏下方。
  //   读 @Trace topAvoidHeight（旋转/折叠自动刷新）。
  private get topInset(): number {
    return getLayoutState().topAvoidHeight + 8;
  }

  build() {
    Row() {
      // 卡片（点击跳会话）
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          if (this.toastState.current !== null) {
            Text(this.toastState.current.title)
              .fontSize(fs(14))
              .fontWeight(FontWeight.Bold)
              .fontColor(this.c.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.toastState.current.body !== '') {
              Text(this.toastState.current.body)
                .fontSize(fs(12))
                .fontColor(this.c.textSecondary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // ✕ 关闭（点击区域不触卡片 onClick：ArkUI 子节点 onClick 优先消费，不冒泡到父）
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(fs(15))
            .fontColor([this.c.textTertiary])
        }
        .width(28)
        .height(28)
        .justifyContent(FlexAlign.Center)
        .borderRadius(14)
        .onClick(() => { ToastService.dismiss(); })
      }
      .width('100%')
      .padding({ left: 14, right: 8, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(this.c.surface)
      .onClick(() => {
        const cur: ServerToastData | null = this.toastState.current;
        if (cur === null) { return; }
        ToastService.dismiss();                          // 点卡片即移除（上游点击 toast = 移除 + 跳转）
        if (cur.sessionId !== '') { this.onTap(cur.sessionId); }
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topInset })
    .hitTestBehavior(HitTestMode.Transparent)
    .visibility(this.toastState.current !== null ? Visibility.Visible : Visibility.None)
  }
}
