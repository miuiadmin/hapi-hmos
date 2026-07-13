import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { getHubClient } from '../api/HubClient';
import { getSSEClient } from '../api/SSEClient';
import { fs, paletteOf, PaletteColors, getThemeState, ThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { showToast } from '../utils/Toast';
import { ensureMicrophonePermission } from '../utils/Permission';
import { AgentState, AgentStateRequest, parseAgentState } from '../chat/AgentState';
import { ChatMessage, parseMessage, mergeMessage } from '../models/Message';
import { SyncEvent, SyncEventType } from '../models/SyncEvent';
import { Session, VoiceTelemetryEvent } from '../models/Types';
import { uuid } from '../chat/TerminalInput';
import { formatVoiceStartedContext, formatNewSingleMessage, formatReadyEvent,
  formatPermissionRequest, extractLastAssistantSpeakable } from '../chat/VoiceFormatters';
import { VoiceSettingsService } from '../services/VoiceSettingsService';
import { getElevenLabsCodeFromPreference } from '../chat/VoiceLanguages';

// 语音页（NavDestination）—— 对照 hapi web/src/realtime/RealtimeVoiceSession.tsx
//   Web 组件托管 ElevenLabs Conversational AI（rawfile/voice/voice.html + elevenlabs-client.min.js）：
//     - 数据面（WebRTC 双向音频 / conversation 生命周期）全在 Web 内 JS 直连，不过 ArkTS↔JS 桥
//     - ArkTS 经 runJavaScript 调 bootVoice/endVoice/toggleMute/sendUserText/applyTheme
//     - JS 经 javaScriptProxy(HostBridge) 回报 onStatus/onMode + 派发 client tool（onClientToolSent/onClientToolPerm）
//   协议对照 hub web/routes/voice.ts（3 REST 端点；WebRTC 直连 ElevenLabs，不经 socket.io 鉴权）。
//
// ⚠️ 与 TerminalPage 的差异：
//   1) 本页【订阅 SSE】（终端页不订阅）——复用 ChatPage 事件子集，为 client tool 派发（权限队列）+ 上下文回灌播种
//   2) 本页【不需 jwt/socket.io】——用 Hub 发的 conversationToken 直连 ElevenLabs WebRTC
//   3) Web 组件需 .onPermissionRequest 钩子（mic-only）——berry3 命门：grant 前须先拿系统 MICROPHONE
//
// ⚠️ berry3 避坑（同 TerminalPage）：runJavaScript 在 Web 被遮挡时静默失效 → 本页 Web 恒为主内容；
//    javaScriptProxy 只暴露方法 → HostBridge 仅声明方法、JS 侧不对其赋属性。

// 路由参数（ChatPage 顶栏「⋯→语音」→ pushPath VoicePage）
export class VoiceRouteParams {
  sessionId: string = '';
}

// 语音连接状态（对照上游 useConversation status：disconnected/connecting/connected/disconnecting）
type VoiceState = 'idle' | 'connecting' | 'connected' | 'error' | 'disconnected';

// 通话模式（SDK onModeChange：'speaking' | 'listening'）
type VoiceMode = 'speaking' | 'listening' | 'idle';

// bootVoice(cfg) 的入参（JSON.stringify 后作为 JS 对象字面量传入 Web；对照 web baseSessionConfig + 标签）
interface VoiceBootCfg {
  conversationToken: string;
  sessionId: string;
  initialContext: string;
  language: string;
  voiceId: string;
  labels: VoiceLabels;
}

// 传给 voice.html 的本地化标签（Web 中心区 mode 文案）
interface VoiceLabels {
  connecting: string;
  listening: string;
  speaking: string;
  ended: string;
  error: string;
}

// client tool 魔法返回串（对照 web realtimeClientTools.ts 逐字）——指导 agent 只说 "sent"/"done"
const SENT_MAGIC: string = "sent [DO NOT say anything else, simply say 'sent']";
const DONE_MAGIC: string = "done [DO NOT say anything else, simply say 'done']";

// JS→ArkTS 桥宿主：方法签名与 voice.html 调用一致。JS→ArkTS 仅调方法；ArkTS 内部持有 sessionId 等字段。
//   onClientToolSent/onClientToolPerm【同步返魔法串】+【异步派发 Hub 调用】（fire-and-forget）。
class VoiceHostBridge {
  // —— 普通回调（组件注入，写 @Local）——
  onReadyCb: () => void = (): void => {};
  onStatusCb: (state: string, msg: string) => void = (s: string, m: string): void => {};
  onModeCb: (m: string) => void = (m: string): void => {};
  // —— 取当前权限请求 requestId（agentState.requests 的首个 key；无则 ''；组件实现读 @Local）——
  currentRequestIdCb: () => string = (): string => { return ''; };

  // sessionId（client tool 派发用；javaScriptProxy 不赋属性 → 用方法注入，非 JS 调）
  private sessionId: string = '';

  setSessionId(id: string): void { this.sessionId = id; }

  onReady(): void { this.onReadyCb(); }

  // JS→ArkTS 状态回报（恒 2 参，msg 空时 ''）
  onStatus(state: string, msg: string): void { this.onStatusCb(state, msg); }

  onMode(m: string): void { this.onModeCb(m); }

  // messageCodingAgent：校验 message → 后台 sendMessage → 同步返魔法串（对照 realtimeClientTools.messageCodingAgent）
  //   真实消息靠 SSE message-received 回推（VoicePage 订阅会 mergeMessage），此处 fire-and-forget。
  onClientToolSent(message: string): string {
    const msg: string = message !== null && message !== undefined ? message.trim() : '';
    if (msg === '') {
      return 'error (invalid message parameter)';
    }
    if (this.sessionId === '') {
      return 'error (no active session)';
    }
    getHubClient().sendMessage(this.sessionId, msg, uuid()).catch((): void => {});
    return SENT_MAGIC;
  }

  // processPermissionRequest：读当前权限 requestId → allow→approve / deny→deny；无请求返 error 串
  //   decision 仅认 'allow'/'deny'（上游实时校验），其余返 invalid 串指导 agent。
  onClientToolPerm(decision: string): string {
    if (decision !== 'allow' && decision !== 'deny') {
      return "error (invalid decision parameter, expected 'allow' or 'deny')";
    }
    if (this.sessionId === '') {
      return 'error (no active session)';
    }
    const requestId: string = this.currentRequestIdCb();
    if (requestId === '') {
      return 'error (no active permission request)';
    }
    const sid: string = this.sessionId;
    if (decision === 'allow') {
      getHubClient().approvePermission(sid, requestId).catch((): void => {});
    } else {
      getHubClient().denyPermission(sid, requestId).catch((): void => {});
    }
    return DONE_MAGIC;
  }
}

@ComponentV2
struct VoicePage {
  @Local sessionId: string = '';
  @Local sessionActive: boolean = true;      // session.active（inactive 不 boot）
  @Local sessionTitle: string = '';           // 顶栏标题（优先 summary，回退 path/默认）
  @Local sessionPath: string = '';            // 会话工作目录（Phase 3 回灌 formatSessionFull 用）
  @Local state: VoiceState = 'idle';
  @Local mode: VoiceMode = 'idle';
  @Local errorMsg: string = '';               // 错误文案（state=error；token/连接/SDK 错误）
  @Local micGranted: boolean = false;         // 系统级 MICROPHONE 已授权
  @Local muted: boolean = false;              // 麦克风静音（SDK setMicMuted）
  @Local manualInput: string = '';            // 手动文本输入（打字回灌，对照上游 sendTextMessage）

  // —— SSE 事件子集状态（client tool 派发 + 上下文回灌用）——
  @Local messages: ChatMessage[] = [];        // 本会话消息（播种 + message-received 增量；Phase 3 回灌源）
  @Local agentState: AgentState | null = null; // 权限请求队列（onClientToolPerm 读 requests 首个 key）
  @Local isThinking: boolean = false;         // agent 生成中（Phase 3 ready 事件用）

  @Local booted: boolean = false;             // bootVoice 已发（幂等防重）
  @Local pageReady: boolean = false;          // Web onPageEnd（voice.html 加载完）
  @Local sessionSeeded: boolean = false;      // fetchSession+fetchMessages 完成（boot 前置，保证 initialContext 有上下文）

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: VoiceHostBridge = new VoiceHostBridge();
  private sseListenerId: number = -1;
  // @Local 持有主题单例 → @Monitor('theme.isDark') 可观测根（同 TerminalPage）
  @Local theme: ThemeState = getThemeState();
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    // 桥回调 → 写组件 @Local
    this.bridge.onReadyCb = (): void => {
      // JS onReady 作为 onPageEnd 的备份信号（两者其一到位即触发 boot）
      this.pageReady = true;
      this.bootIfReady();
    };
    this.bridge.onStatusCb = (state: string, msg: string): void => {
      if (state === 'connected') {
        this.state = 'connected';
        this.errorMsg = '';
        this.reportTelemetry('session_start', 'Voice session connected');
      } else if (state === 'connecting') {
        if (this.state !== 'connected') { this.state = 'connecting'; }
      } else if (state === 'disconnected') {
        // 仅从已连接态断开才报 session_end（避初始/失败 boot 误报）
        const wasConnected: boolean = this.state === 'connected';
        this.state = 'disconnected';
        this.booted = false;   // 允许重连/重试
        if (wasConnected) {
          this.reportTelemetry('session_end', 'Voice session disconnected');
        }
      } else if (state === 'error') {
        this.state = 'error';
        this.errorMsg = msg !== '' ? msg : t('voice.state.error');
        this.booted = false;
        this.reportTelemetry('session_error', this.errorMsg);
      }
    };
    this.bridge.onModeCb = (m: string): void => {
      if (m === 'speaking' || m === 'listening') {
        this.mode = m;
      } else {
        this.mode = 'idle';
      }
    };
    this.bridge.currentRequestIdCb = (): string => {
      const as: AgentState | null = this.agentState;
      if (as === null) { return ''; }
      const keys: string[] = Object.keys(as.requests);
      return keys.length > 0 ? keys[0] : '';
    };
  }

  // 路由就绪（NavDestination.onReady）：取 sessionId → 注入桥 → 申请 mic + 播种 session/messages + boot
  private async onRouteReady(sid: string): Promise<void> {
    this.sessionId = sid;
    this.bridge.setSessionId(sid);
    this.addSSEListener();

    // 申请系统级麦克风授权（berry3 命门：onPermissionRequest grant 前必须先拿系统授权）
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && ctx !== null) {
      this.micGranted = await ensureMicrophonePermission(ctx as common.UIAbilityContext);
    } else {
      this.micGranted = false;
    }

    // 播种 session（校验 active + 取 title/agentState/thinking）+ messages（Phase 3 回灌源）
    try {
      const session: Session = await getHubClient().fetchSession(sid);
      this.sessionActive = session.active;
      this.sessionTitle = this.resolveTitle(session);
      this.sessionPath = session.path;
      this.setAgentState(parseAgentState(session.agentStateRaw));
      this.isThinking = session.thinking;
    } catch (e) {
      this.sessionActive = false;
      this.state = 'error';
      this.errorMsg = e instanceof Error ? e.message : t('voice.state.error');
      return;
    }
    try {
      this.messages = await getHubClient().fetchMessages(sid);
    } catch (_e) {
      this.messages = [];   // 消息拉取失败不阻断语音（仅影响回灌）
    }

    if (!this.sessionActive) {
      this.state = 'error';
      this.errorMsg = t('voice.sessionInactive');
      return;
    }
    this.sessionSeeded = true;   // 播种完成 → 允许 boot（initialContext 此时含会话上下文）
    this.bootIfReady();
  }

  // 标题：用会话工作目录 path，回退默认标题（Session 无 name/summary 字段，summary 在列表页 SessionSummary）
  private resolveTitle(session: Session): string {
    if (session.path !== '') { return session.path; }
    return t('voice.title');
  }

  // 启动语音会话（页面就绪 + mic 授权 + session 活跃 时调一次）
  private bootIfReady(): void {
    if (this.booted || this.state === 'connected') { return; }
    if (!this.pageReady || !this.micGranted || !this.sessionActive || !this.sessionSeeded
      || this.sessionId === '') { return; }
    this.booted = true;
    this.state = 'connecting';
    this.doBoot();
  }

  // 拉 token → bootVoice(cfg)；token 不允许 → 错误态 + booted 复位（供重试）
  private async doBoot(): Promise<void> {
    // 语音语言/声音读持久化设置（VoiceSettingsService；Phase 4）。
    //   voiceId=''=Hub 默认 agent；language=''=自动检测（getElevenLabsCodeFromPreference 不支持的 locale/自动→''，不覆盖）。
    const voiceId: string = VoiceSettingsService.currentVoiceId;
    const language: string = getElevenLabsCodeFromPreference(VoiceSettingsService.currentLang);
    let tokenResult;
    try {
      tokenResult = await getHubClient().fetchVoiceToken(voiceId);
    } catch (e) {
      this.state = 'error';
      this.errorMsg = e instanceof Error ? e.message : t('voice.tokenFailed');
      this.booted = false;
      return;
    }
    if (!tokenResult.allowed || tokenResult.token === '') {
      this.state = 'error';
      this.errorMsg = tokenResult.error !== '' ? tokenResult.error : t('voice.notAllowed');
      this.booted = false;
      return;
    }
    // 初始上下文 = 整会话回灌（对照 voiceHooks.onVoiceStarted → initialConversationContext）。
    //   summary 留空（Session 无 summary 字段，列表页 SessionSummary 才有）。
    const initialContext: string = formatVoiceStartedContext(this.sessionId, this.sessionPath, '',
      this.messages);
    const cfg: VoiceBootCfg = {
      conversationToken: tokenResult.token,
      sessionId: this.sessionId,
      initialContext: initialContext,
      language: language,
      voiceId: voiceId,
      labels: this.voiceLabels()
    };
    this.runJs('bootVoice(' + JSON.stringify(cfg) + ')');
  }

  // 中心区 mode 文案标签（随 locale 即时；切语言时下次 boot 生效）
  private voiceLabels(): VoiceLabels {
    return {
      connecting: t('voice.label.connecting'),
      listening: t('voice.label.listening'),
      speaking: t('voice.label.speaking'),
      ended: t('voice.label.ended'),
      error: t('voice.label.error')
    };
  }

  private setAgentState(state: AgentState): void {
    this.agentState = state;
  }

  // —— SSE 事件子集（复用 ChatPage 模式：全局连接，按 sessionId 过滤）——
  private addSSEListener(): void {
    this.sseListenerId = getSSEClient().addListener({
      onEvent: (event: SyncEvent) => { this.onSSEEvent(event); }
    });
  }

  private onSSEEvent(event: SyncEvent): void {
    if (event.sessionId !== this.sessionId) { return; }
    const type: string = event.type;
    if (type === SyncEventType.MESSAGE_RECEIVED) {
      const msgRaw: Record<string, Object> | null = event.getObject('message');
      if (msgRaw !== null) {
        const msg: ChatMessage = parseMessage(msgRaw);
        this.messages = mergeMessage(this.messages, msg);
        // 语音已连接 → 回灌新消息上下文（对照 voiceHooks.onMessages → sendContextualUpdate/pushContext）
        if (this.state === 'connected') {
          const ctx: string | null = formatNewSingleMessage(this.sessionId, msg);
          if (ctx !== null) {
            this.runJs('pushContext(' + JSON.stringify(ctx) + ')');
          }
        }
      }
    } else if (type === SyncEventType.SESSION_UPDATED) {
      this.handleSessionUpdated(event);
    }
  }

  // thinking / active / 标题 / agentState（防御性：session 对象内或事件顶层均可）—— 镜像 ChatPage 子集
  //   + 语音上下文回灌（Phase 3）：thinking true→false → ready 事件；新权限请求 → 权限提示。仅 connected 态推。
  private handleSessionUpdated(event: SyncEvent): void {
    const sessionObj: Record<string, Object> | null = event.getObject('session');
    let nowThinking: boolean | null = null;     // null = 本次事件未提及 thinking
    let newAgentState: AgentState | null = null;
    if (sessionObj !== null) {
      if (sessionObj['thinking'] === true) { nowThinking = true; }
      else if (sessionObj['thinking'] === false) { nowThinking = false; }
      if (sessionObj['active'] === false) {
        this.sessionActive = false;
      }
      const metaVal: Object | undefined = sessionObj['metadata'];
      if (metaVal !== null && metaVal !== undefined && typeof metaVal === 'object') {
        const meta: Record<string, Object> = metaVal as Record<string, Object>;
        const nameVal: Object = meta['name'];
        if (typeof nameVal === 'string' && nameVal !== '') {
          this.sessionTitle = nameVal;
        }
      }
      const asVal: Object | undefined = sessionObj['agentState'];
      if (asVal !== null && asVal !== undefined && typeof asVal === 'object') {
        newAgentState = parseAgentState(asVal as Record<string, Object>);
      }
    } else {
      if (event.raw['thinking'] === true) { nowThinking = true; }
      else if (event.raw['thinking'] === false) { nowThinking = false; }
    }

    // 先取旧值再更新，以便检测转换
    const wasThinking: boolean = this.isThinking;
    if (nowThinking !== null) { this.isThinking = nowThinking; }

    // ready 事件：thinking true→false（agent 本回合完成），仅语音已连接时回灌（对照 voiceHooks.onReady）
    if (wasThinking && nowThinking === false && this.state === 'connected') {
      const lastText: string | null = extractLastAssistantSpeakable(this.messages);
      const readyText: string = formatReadyEvent(this.sessionId, lastText);
      this.runJs('pushText(' + JSON.stringify(readyText) + ')');
    }

    // 权限请求：agentState 更新后，新出现的 requestId → 回灌权限提示（对照 voiceHooks.onPermissionRequested）
    if (newAgentState !== null) {
      const prevKeys: string[] = this.agentState !== null ? Object.keys(this.agentState.requests) : [];
      this.setAgentState(newAgentState);
      if (this.state === 'connected') {
        this.pushPermissionRequests(newAgentState, prevKeys);
      }
    }
  }

  // 新增的权限请求逐条回灌（pushText，agent 须据此询问 allow/deny）
  private pushPermissionRequests(newState: AgentState, prevKeys: string[]): void {
    const newKeys: string[] = Object.keys(newState.requests);
    for (let i = 0; i < newKeys.length; i++) {
      const reqId: string = newKeys[i];
      if (prevKeys.indexOf(reqId) === -1) {
        const req: AgentStateRequest = newState.requests[reqId];
        const txt: string = formatPermissionRequest(this.sessionId, reqId, req.tool,
          this.stringifyArgs(req.arguments));
        this.runJs('pushText(' + JSON.stringify(txt) + ')');
      }
    }
  }

  // 权限请求入参 → JSON 串（null/异常 → 'null'）
  private stringifyArgs(args: Object | null): string {
    if (args === null) { return 'null'; }
    try {
      return JSON.stringify(args);
    } catch (e) {
      return 'null';
    }
  }

  // 主题变化 → 重推 voice.html 主题（@Monitor 驱动；仅 Web 可见时有效，本页恒可见）
  @Monitor('theme.isDark')
  onThemeChange(monitor: IMonitor): void {
    this.runJs('applyTheme(' + getThemeState().isDark + ')');
  }

  // 切静音：写本地态 + 推 SDK（仅 connected 态有意义）
  private toggleMute(): void {
    if (this.state !== 'connected') { return; }
    this.muted = !this.muted;
    this.runJs('toggleMute(' + this.muted + ')');
  }

  // 手动文本发送：当作用户消息推 SDK（触发 agent 回应；对照上游 sendTextMessage）
  private sendManual(): void {
    const text: string = this.manualInput.trim();
    if (text === '' || this.state !== 'connected') { return; }
    this.runJs('sendUserText(' + JSON.stringify(text) + ')');
    this.manualInput = '';
  }

  // 结束通话：推 endVoice（SDK endSession → onStatusChange disconnected）
  private endCall(): void {
    if (this.state === 'disconnected' || this.state === 'idle') { return; }
    this.runJs('endVoice()');
  }

  // 统一 runJavaScript（fire-and-forget；失败静默）
  private runJs(script: string): void {
    try {
      this.controller.runJavaScript(script);
    } catch (e) {
      // 控制器未就绪等：忽略
    }
  }

  // 上报语音遥测（fire-and-forget；对照 hub /api/voice/telemetry：stage+message 必填，余可选）。
  //   sessionId 未就绪（路由未 ready）时跳过。阶段：session_start/session_end/session_error。
  private reportTelemetry(stage: string, message: string): void {
    if (this.sessionId === '') { return; }
    const ev: VoiceTelemetryEvent = new VoiceTelemetryEvent();
    ev.stage = stage;
    ev.message = message;
    ev.sessionId = this.sessionId;
    ev.voiceId = VoiceSettingsService.currentVoiceId;
    ev.language = getElevenLabsCodeFromPreference(VoiceSettingsService.currentLang);
    getHubClient().sendVoiceTelemetry(ev).catch((): void => {});
  }

  aboutToDisappear(): void {
    // 离开页：断 voice（SDK endSession → 关 WebRTC）。页面销毁时 JS 上下文随之终止。
    this.runJs('endVoice()');
    if (this.sseListenerId !== -1) {
      getSSEClient().removeListener(this.sseListenerId);
      this.sseListenerId = -1;
    }
  }

  // 状态 → 色点
  private statusColor(): string {
    if (this.state === 'connected') { return this.c.success; }
    if (this.state === 'connecting') { return this.c.warning; }
    if (this.state === 'error') { return this.c.error; }
    if (this.state === 'disconnected') { return this.c.textTertiary; }
    return this.c.textTertiary;   // idle
  }

  // 状态 → 文案
  private statusLabel(): string {
    if (!this.sessionActive) { return t('voice.sessionInactive'); }
    if (this.state === 'connecting') { return t('voice.state.connecting'); }
    if (this.state === 'connected') {
      return this.mode === 'listening' ? t('voice.label.listening')
        : this.mode === 'speaking' ? t('voice.label.speaking')
        : t('voice.state.connected');
    }
    if (this.state === 'error') {
      return this.errorMsg !== '' ? this.errorMsg : t('voice.state.error');
    }
    if (this.state === 'disconnected') { return t('voice.label.ended'); }
    return t('voice.state.idle');
  }

  private titleText(): string {
    return this.sessionTitle !== '' ? this.sessionTitle : t('voice.title');
  }

  // —— 顶栏：返回 + 标题 + 状态色点 + 文案 ——
  @Builder
  private TopBar() {
    Row({ space: 10 }) {
      Text('‹')
        .fontSize(fs(26))
        .fontColor(this.c.textSecondary)
        .width(36)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { if (this.navPathStack !== null) { this.navPathStack.pop(); } })
      Column({ space: 2 }) {
        Text(this.titleText())
          .fontSize(fs(15))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.statusLabel())
          .fontSize(fs(12))
          .fontColor(this.statusColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 状态色点（Column 圆点，复用既有样式原语）
      Column()
        .width(9)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(this.statusColor())
    }
    .width('100%')
    .padding({ left: 8, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.c.bg)
    .border({ width: { bottom: 0.5 }, color: this.c.border })
  }

  // 错误 / 未授权 / 非活跃 横幅（含重试按钮；mic 未授权单独提示去设置授权）
  @Builder
  private StatusBanner() {
    if (!this.sessionActive || this.state === 'error' || (!this.micGranted && this.sessionActive && this.state === 'idle')) {
      Row({ space: 8 }) {
        Text('⚠').fontSize(fs(14)).fontColor(this.c.error)
        Text(this.bannerMessage())
          .fontSize(fs(13))
          .fontColor(this.c.error)
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.canRetry()) {
          Text(t('voice.retry'))
            .fontSize(fs(13))
            .fontColor(this.c.primary)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(this.c.surface)
            .borderRadius(8)
            .onClick(() => { this.retry(); })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.c.errorBg)
    }
  }

  private bannerMessage(): string {
    if (!this.sessionActive) { return t('voice.sessionInactive'); }
    if (!this.micGranted) { return t('voice.micDenied'); }
    return this.errorMsg !== '' ? this.errorMsg : t('voice.state.error');
  }

  // 可重试：未授权（重试会再弹系统授权）或 token/连接错误（重试重拉 token）
  private canRetry(): boolean {
    if (!this.sessionActive) { return false; }
    return !this.micGranted || this.state === 'error';
  }

  private async retry(): Promise<void> {
    if (!this.micGranted) {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx !== undefined && ctx !== null) {
        this.micGranted = await ensureMicrophonePermission(ctx as common.UIAbilityContext);
      }
      if (!this.micGranted) {
        showToast(t('voice.micDeniedHint'));
        return;
      }
    }
    this.state = 'idle';
    this.errorMsg = '';
    this.bootIfReady();
  }

  // 底部控制栏：静音切换 + 手动输入 + 结束通话（Web 主内容渲染波形/mode，此栏不遮挡 Web）
  @Builder
  private VoiceBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // 静音切换（仅 connected 态可用）
        Text(this.muted ? '🔇' : '🎤')
          .fontSize(fs(20))
          .fontColor(this.state === 'connected' ? this.c.textPrimary : this.c.textTertiary)
          .width(44).height(44).textAlign(TextAlign.Center)
          .backgroundColor(this.c.surface).borderRadius(22)
          .opacity(this.state === 'connected' ? 1 : 0.4)
          .onClick(() => { this.toggleMute(); })
        TextInput({ text: this.manualInput, placeholder: t('voice.inputPlaceholder') })
          .fontSize(fs(15))
          .layoutWeight(1)
          .backgroundColor(this.c.surface)
          .borderRadius(22)
          .height(44)
          .enabled(this.state === 'connected')
          .onChange((v: string) => { this.manualInput = v; })
          .onSubmit(() => { this.sendManual(); })
        // 结束通话（红，仅连接中/连接态可用）
        Text(t('voice.endCall'))
          .fontSize(fs(14))
          .fontColor(this.c.bubbleUserText)
          .backgroundColor(this.state === 'connected' || this.state === 'connecting' ? this.c.error : this.c.textTertiary)
          .borderRadius(22)
          .height(44)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Center)
          .onClick(() => { this.endCall(); })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 12 })
    .backgroundColor(this.c.bg)
    .border({ width: { top: 0.5 }, color: this.c.border })
  }

  build() {
    NavDestination() {
      Column() {
        this.TopBar()
        this.StatusBanner()
        // 语音渲染（Web 托管 ElevenLabs；恒为主内容，不被遮挡；中心区渲染波形 + mode 文案）
        Web({ src: 'resource://rawfile/voice/voice.html', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .layoutWeight(1)
          .width('100%')
          .backgroundColor(this.c.bg)
          .javaScriptProxy({
            object: this.bridge,
            name: 'HostBridge',
            methodList: ['onReady', 'onStatus', 'onMode', 'onClientToolSent', 'onClientToolPerm'],
            controller: this.controller
          })
          // mic 权限钩子（berry3 命门）：SDK getUserMedia 触发此处；系统授权 + mic-only → grant，否则 deny
          .onPermissionRequest((event: OnPermissionRequestEvent) => {
            const resources: string[] = event.request.getAccessibleResource();
            if (resources.length === 0) {
              event.request.deny();
              return;
            }
            // 仅放行麦克风资源，且需系统授权已拿（micGranted）；摄像头等一律 deny
            let hasMic: boolean = false;
            for (let i = 0; i < resources.length; i++) {
              if (resources[i] === 'TYPE_AUDIO_CAPTURE') { hasMic = true; }
            }
            if (hasMic && this.micGranted) {
              event.request.grant(['TYPE_AUDIO_CAPTURE']);
            } else {
              event.request.deny();
            }
          })
          .onPageEnd(() => {
            this.pageReady = true;
            // 初始主题（Web 默认 light；按当前主题校准一次）
            this.runJs('applyTheme(' + getThemeState().isDark + ')');
            this.bootIfReady();
          })
        this.VoiceBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.bg)
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as VoiceRouteParams;
      if (param !== null && param !== undefined && param.sessionId !== '') {
        this.onRouteReady(param.sessionId);
      }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function VoicePageBuilder(name: string, param: Object) {
  VoicePage()
}
