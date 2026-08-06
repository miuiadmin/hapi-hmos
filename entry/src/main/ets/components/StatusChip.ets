// StatusChip —— 会话状态指示（小色点 + 小字）：在线 / 离线 / 权限请求 / 思考中(随机 vibing 英文)。
//   2026-08-06：从 ComposerToolbar 状态 chip 抽出，移至 ContextStatusBar（CTX 用量条）左边，
//   变小字省空间（原 Capsule 大 chip → fs11 小色点+小字，与 ctx 用量同规格同行）。
//   自管 SSE 连接态 + 设备网络态 + vibingIndex（监听搬自旧 ComposerToolbar，逻辑不变）。
//   决策/文案纯函数复用 chat/StatusBarStatus.ets（resolveStatusBarState / pickVibingMessage / VIBING_MESSAGES）。
import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs } from '../theme/ThemeService';
import { AgentState } from '../chat/AgentState';
import { getDeviceNetworkState, DeviceNetworkState } from '../services/DeviceNetworkService';
import { resolveStatusBarState, VIBING_MESSAGES, StatusBarState } from '../chat/StatusBarStatus';

@ComponentV2
export struct StatusChip {
  @Param isThinking: boolean = false;
  @Param agentState: AgentState | null = null;
  @Local sseState: SSEConnectionState = 'idle';
  @Local net: DeviceNetworkState = getDeviceNetworkState();
  @Local vibingIndex: number = 0;
  private listenerId: number = -1;

  // 仅 pending 权限请求（对照旧 StatusBar.hasPermissions / ComposerToolbar 同名 getter）
  private get hasPermissions(): boolean {
    return this.agentState !== null && Object.keys(this.agentState.requests).length > 0;
  }

  // 状态决策（对照 getConnectionStatus）：离线 → 权限 → 思考(vibing) → 在线
  private get state(): StatusBarState {
    return resolveStatusBarState(this.net.online, this.sseState === 'open', this.hasPermissions, this.isThinking, this.vibingIndex);
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
    Row({ space: 4 }) {
      // 静态色点（ArkUI 无 animate-pulse 直配；状态色 = state.color）
      Circle({ width: 6, height: 6 }).fill(this.state.color)
      Text(this.state.label)
        .fontSize(fs(11))
        .fontColor(this.state.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }
}
