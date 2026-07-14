import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { getDeviceNetworkState, DeviceNetworkState } from '../services/DeviceNetworkService';
import { resolveNetworkBanner } from '../chat/NetworkBannerResolve';

// 连接状态横幅：SSE 重连 / 断开 + 设备离线时顶部细条提示（对照上游 ReconnectingBanner/OfflineBanner）。
// 自注册一条独立 SSE onStateChange 监听者（与宿主页的监听者互不影响）；aboutToAppear 先读 getState()
// 取当前态（页面挂载时连接可能已在重连），后续靠 onStateChange 转换更新。
//
// 显示决策（chat/NetworkBannerResolve 纯层，可测）：设备离线优先级最高，压制 SSE 文案——
//   设备无网时 SSE 必然连不上，"正在重新连接/连接已断开" 会误导（看似 Hub 故障，实为手机没网），
//   故离线改显根因「设备已离线」(connection.deviceOffline)。
//   - device-offline    → error 底白字「⚠ 设备已离线，请检查网络连接」（无论 SSE 何态）
//   - sse-reconnecting  → 中性底「⟳ 正在重新连接…」（仅设备在线时）
//   - sse-closed        → error 底白字「⚠ 连接已断开，实时更新暂停」（仅设备在线时）
//   - 其余 → Visibility.None 收起（常态已有 header 徽章覆盖）
// 设备在线态读 @Local net（@ObservedV2@Trace 应用级单例，变更即触发重渲染），同 Index/ChatPage 持 sync/theme 范式。
@ComponentV2
export struct ConnectionBanner {
  @Local sseState: SSEConnectionState = 'idle';
  @Local net: DeviceNetworkState = getDeviceNetworkState();
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
    const kind = resolveNetworkBanner(this.net.online, this.sseState);
    Row({ space: 8 }) {
      if (kind === 'device-offline') {
        Text('⚠').fontSize(fs(12)).fontColor(this.c.bubbleUserText)
        Text(t('connection.deviceOffline'))
          .fontSize(fs(12))
          .fontColor(this.c.bubbleUserText)
      } else if (kind === 'sse-reconnecting') {
        LoadingProgress().width(14).height(14).color(this.c.textSecondary)
        Text(t('connection.reconnecting'))
          .fontSize(fs(12))
          .fontColor(this.c.textSecondary)
      } else if (kind === 'sse-closed') {
        Text('⚠').fontSize(fs(12)).fontColor(this.c.bubbleUserText)
        Text(t('connection.disconnected'))
          .fontSize(fs(12))
          .fontColor(this.c.bubbleUserText)
      }
    }
    .width('100%')
    .height(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(kind === 'device-offline' || kind === 'sse-closed' ? this.c.error : this.c.surface)
    .visibility(kind === 'none' ? Visibility.None : Visibility.Visible)
  }
}
