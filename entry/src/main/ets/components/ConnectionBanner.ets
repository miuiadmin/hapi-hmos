import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 连接状态横幅：SSE 重连 / 断开时顶部细条提示（对照上游 ReconnectingBanner/OfflineBanner）。
// 自注册一条独立 SSE onStateChange 监听者（与宿主页的监听者互不影响）；aboutToAppear 先读 getState()
// 取当前态（页面挂载时连接可能已在重连），后续靠 onStateChange 转换更新。
// 仅 reconnecting/closed 显形（open/idle/connecting 用 Visibility.None 收起——常态已有 header 徽章覆盖）：
//   reconnecting → 中性底「⟳ 正在重新连接…」；closed → error 底白字「⚠ 连接已断开，实时更新暂停」。
@ComponentV2
export struct ConnectionBanner {
  @Local sseState: SSEConnectionState = 'idle';
  private listenerId: number = -1;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    const sse = getSSEClient();
    this.sseState = sse.getState();
    this.listenerId = sse.addListener({
      onEvent: (_event: SyncEvent) => {},                  // 横幅只关心状态转换，不处理事件
      onStateChange: (state: SSEConnectionState) => { this.sseState = state; }
    });
  }

  aboutToDisappear(): void {
    if (this.listenerId !== -1) {
      getSSEClient().removeListener(this.listenerId);
      this.listenerId = -1;
    }
  }

  build() {
    Row({ space: 8 }) {
      if (this.sseState === 'reconnecting') {
        LoadingProgress().width(14).height(14).color(this.c.textSecondary)
        Text('正在重新连接…')
          .fontSize(fs(12))
          .fontColor(this.c.textSecondary)
      } else {
        Text('⚠').fontSize(fs(12)).fontColor(this.c.bubbleUserText)
        Text('连接已断开，实时更新暂停')
          .fontSize(fs(12))
          .fontColor(this.c.bubbleUserText)
      }
    }
    .width('100%')
    .height(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.sseState === 'closed' ? this.c.error : this.c.surface)
    .visibility(
      (this.sseState === 'reconnecting' || this.sseState === 'closed') ? Visibility.Visible : Visibility.None
    )
  }
}
