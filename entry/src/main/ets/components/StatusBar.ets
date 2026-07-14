import { getSSEClient, SSEConnectionState } from '../api/SSEClient';
import { SyncEvent } from '../models/SyncEvent';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { AgentState } from '../chat/AgentState';
import { getDeviceNetworkState, DeviceNetworkState } from '../services/DeviceNetworkService';
import { resolveStatusBarState, VIBING_MESSAGES } from '../chat/StatusBarStatus';
import {
  shouldShowReasoningChip,
  shouldShowFastChip,
  shouldShowCollaborationChip,
  shouldShowPermissionChip,
  permissionModeTone,
  toneColor,
  normalizeReasoningEffort
} from '../chat/StatusBarChips';
import { permissionModeDisplayName, collaborationModeDisplayName } from '../models/Types';
import { t } from '../i18n/I18nService';

// 顶部常驻细状态行：左 色点 + 文案；右 模式 chip 簇。对照上游 AssistantChat/StatusBar。
// 左侧状态优先级：设备离线/SSE 未连(灰) → 权限待批(橙) → 思考中(蓝 + 随机 vibing 动词) → 在线(绿)。
//   省略上游 voice-connecting / backgroundTaskCount 两态（鸿蒙 ChatPage 不可达）；pulse v1 静态色点。
// 右侧 chip 簇（对照 StatusBar.tsx:248-274 固定序，goal 留 follow-up）：
//   reasoning(codex/opencode,灰) → fast(codex+fast,绿) → collaboration(codex+plan,蓝) → permission(非default,色调)。
//
// 自管一条独立 SSE onStateChange 监听者（与宿主页/ConnectionBanner 互不影响）；设备在线态读
//   @Local net（@ObservedV2@Trace 应用级单例，变更即触发重渲染）。isThinking/agentState/5 模式由 ChatPage 传入。
@ComponentV2
export struct StatusBar {
  @Param isThinking: boolean = false;
  @Param agentState: AgentState | null = null;
  @Param permissionMode: string = '';          // /permission-mode；非 default 且 flavor 域允许才显
  @Param collaborationMode: string = '';        // codex 协作；plan 才显
  @Param modelReasoningEffort: string = '';     // codex/opencode 推理努力；reasoning chip label
  @Param model: string = '';                    // fast 判定（含 mini/fast）
  @Param flavor: string = '';                   // codex/opencode/cursor/…；门控各 chip
  @Local sseState: SSEConnectionState = 'idle';
  @Local net: DeviceNetworkState = getDeviceNetworkState();
  @Local vibingIndex: number = 0;   // 思考动词随机下标（aboutToAppear 滚一次；注入纯层保可测）
  private listenerId: number = -1;

  // 主题（读 @Trace isDark 建立刷新依赖）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 仅有 pending 权限请求（对照上游 Object.keys(requests).length > 0；不含已决/controlledByUser）
  private get hasPermissions(): boolean {
    return this.agentState !== null && Object.keys(this.agentState.requests).length > 0;
  }

  // reasoning chip label：default → 专门 key；否则 reasoning {effort}（对照 StatusBar.tsx:126-130）
  private reasoningLabel(): string {
    const token: string = normalizeReasoningEffort(this.modelReasoningEffort);
    if (token === 'default') { return t('statusBar.reasoningDefault'); }
    return t('statusBar.reasoning', { effort: token });
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

  @Builder
  ModeChip(text: string, color: string) {
    Text(text)
      .fontSize(fs(12))
      .fontColor(color)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  build() {
    const sseOpen: boolean = this.sseState === 'open';
    const state = resolveStatusBarState(this.net.online, sseOpen, this.hasPermissions, this.isThinking, this.vibingIndex);
    Row({ space: 6 }) {
      // 左：连接色点 + 文案（吃满剩余宽度，右侧 chip 不被挤压）
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
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      // 右：模式 chip 簇（shrink，固定序 reasoning → fast → collaboration → permission；goal 留 follow-up）
      Row({ space: 8 }) {
        if (shouldShowReasoningChip(this.flavor)) {
          this.ModeChip(this.reasoningLabel(), this.c.textTertiary)
        }
        if (shouldShowFastChip(this.flavor, this.model, this.modelReasoningEffort)) {
          this.ModeChip(t('statusBar.fast'), this.c.success)
        }
        if (shouldShowCollaborationChip(this.flavor, this.collaborationMode)) {
          this.ModeChip(collaborationModeDisplayName(this.collaborationMode), this.c.primary)
        }
        if (shouldShowPermissionChip(this.permissionMode, this.flavor)) {
          this.ModeChip(permissionModeDisplayName(this.permissionMode), toneColor(permissionModeTone(this.permissionMode), this.c))
        }
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }
}
