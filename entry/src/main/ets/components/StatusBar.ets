import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs } from '../theme/ThemeService';
import { AgentState } from '../chat/AgentState';
import { getDeviceNetworkState, DeviceNetworkState } from '../services/DeviceNetworkService';
import { resolveStatusBarState, VIBING_MESSAGES } from '../chat/StatusBarStatus';

// 顶部常驻细状态行：色点 + 文案。对照上游 AssistantChat/StatusBar（ getConnectionStatus）。
// 状态优先级：设备离线/SSE 未连(灰) → 权限待批(橙) → 思考中(蓝 + 随机 vibing 动词) → 在线(绿)。
// 省略上游 voice-connecting / backgroundTaskCount 两态（鸿蒙 ChatPage 不可达）；pulse v1 静态色点。
//
// 自管一条独立 SSE onStateChange 监听者（与宿主页/ConnectionBanner 互不影响）；设备在线态读
//   @Local net（@ObservedV2@Trace 应用级单例，变更即触发重渲染）。isThinking/agentState 由 ChatPage 传入。
@ComponentV2
export struct StatusBar {
  @Param isThinking: boolean = false;
  @Param agentState: AgentState | null = null;
  @Local sseState: SSEConnectionState = 'idle';
  @Local net: DeviceNetworkState = getDeviceNetworkState();
  @Local vibingIndex: number = 0;   // 思考动词随机下标（aboutToAppear 滚一次；注入纯层保可测）
  private listenerId: number = -1;

  // 仅有 pending 权限请求（对照上游 Object.keys(requests).length > 0；不含已决/controlledByUser）
  private get hasPermissions(): boolean {
    return this.agentState !== null && Object.keys(this.agentState.requests).length > 0;
  }

  aboutToAppear(): void {
    const sse = getSSEClient();
    this.sseState = sse.getState();
    this.listenerId = sse.addListener({
      onEvent: (_event: SyncEvent) => {},
      onStateChange: (state: SSEConnectionState) => { this.sseState = state; }
    });
    this.vibingIndex = Math.floor(Math.random() * VIBING_MESSAGES.length);
  }

  aboutToDisappear(): void {
    if (this.listenerId !== -1) {
      getSSEClient().removeListener(this.listenerId);
      this.listenerId = -1;
    }
  }

  build() {
    const sseOpen: boolean = this.sseState === 'open';
    const state = resolveStatusBarState(this.net.online, sseOpen, this.hasPermissions, this.isThinking, this.vibingIndex);
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 })
        .fill(state.color)
      Text(state.label)
        .fontSize(fs(12))
        .fontColor(state.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }
}
