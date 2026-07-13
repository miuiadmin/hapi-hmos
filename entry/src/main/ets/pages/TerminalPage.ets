import { webview } from '@kit.ArkWeb';
import { pasteboard } from '@kit.BasicServicesKit';
import { getHubClient } from '../api/HubClient';
import { getConnectionService } from '../services/ConnectionService';
import { fs, paletteOf, PaletteColors, getThemeState, ThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';
import { showToast } from '../utils/Toast';
import {
  QUICK_INPUT_ROWS,
  applyModifierState,
  shouldResetModifiers,
  uuid,
  QuickKey,
  ModifierState,
  classifyTerminalError,
  TerminalErrorInfo
} from '../chat/TerminalInput';

// 终端页（NavDestination）—— 对照 hapi web /sessions/$sessionId/terminal
//   Web 组件托管 xterm.js + socket.io-client（rawfile/terminal/terminal.html）：
//     - 渲染 + 数据面（PTY 输出→term.write / 用户输入→terminal:write）全在 Web 内 JS 直连，不过 ArkTS↔JS 桥
//     - ArkTS 经 runJavaScript 调 bootTerminal/sendInput/applyTheme/disconnectTerminal/focusTerminal
//     - JS 经 javaScriptProxy(HostBridge) 回报 onReady/onError/onExit/onReconnecting → 写 @Local 状态
//   协议对照 shared/src/socket.ts 的 /terminal namespace（ws-only，JWT auth；terminalId 客户端生成、重连复用）。
//
// ⚠️ berry3 避坑：runJavaScript 在 Web 被遮挡时静默失效 → 本页 Web 恒为主内容、不被 sheet/overlay 遮挡；
//    javaScriptProxy 只暴露方法 → HostBridge 仅声明方法、JS 侧不对其赋属性。

// 路由参数（ChatPage 顶栏「>_」→ pushPath TerminalPage）
export class TerminalRouteParams {
  sessionId: string = '';
}

// 终端连接状态（对照上游 useTerminalSocket 的 status）
type TerminalState = 'idle' | 'connecting' | 'ready' | 'reconnecting' | 'error' | 'exited';

// bootTerminal(cfg) 的入参（JSON.stringify 后作为 JS 对象字面量传入 Web）
interface TerminalBootCfg {
  hubUrl: string;
  jwt: string;
  sessionId: string;
  terminalId: string;
  theme: XtermTheme;
}

// xterm theme（背景/前景/光标；主题切换时 applyTheme 重推）
interface XtermTheme {
  background: string;
  foreground: string;
  cursor: string;
}

// JS→ArkTS 桥宿主：方法签名与 terminal.html 调用一致。每方法经回调写回组件 @Local
//   （ArkWeb 在 UI 线程触发这些方法，回调闭包持有 struct 引用）。
class TerminalHostBridge {
  onReadyCb: () => void = (): void => {};
  onErrorCb: (m: string) => void = (m: string): void => {};
  onExitCb: (c: number) => void = (c: number): void => {};
  onReconnectingCb: () => void = (): void => {};
  onCopyCb: (text: string) => void = (text: string): void => {};
  onReady(): void { this.onReadyCb(); }
  onError(message: string): void { this.onErrorCb(message); }
  onExit(code: number): void { this.onExitCb(code); }
  onReconnecting(): void { this.onReconnectingCb(); }
  onCopy(text: string): void { this.onCopyCb(text); }
}

@ComponentV2
struct TerminalPage {
  @Local sessionId: string = '';
  @Local cwd: string = '';                 // 工作目录（顶栏副标题；fetchSession.session.path）
  @Local terminalId: string = '';          // 终端实例标识（每页一个，重连复用）
  @Local sessionActive: boolean = true;    // session.active（inactive 不 boot，置不可用）
  @Local state: TerminalState = 'idle';
  @Local errorMsg: string = '';            // 错误文案（state=error）
  @Local exitCode: number = -1;            // 退出码（state=exited；-1=无）
  @Local manualInput: string = '';         // 自由输入框文本
  @Local ctrlActive: boolean = false;      // Ctrl 修饰键切换态
  @Local altActive: boolean = false;       // Alt 修饰键切换态
  @Local booted: boolean = false;          // bootTerminal 已发（幂等防重）
  @Local pageReady: boolean = false;       // Web onPageEnd（终端.html 加载完）
  @Local quotaMax: number = -1;            // 配额超限时的 max（-1=非配额；terminal:error 文案分类得）
  @Local findOpen: boolean = false;        // FindBar 展开
  @Local findQuery: string = '';           // 查找文本
  @Local findCaseSensitive: boolean = false; // 查找大小写敏感
  @Local actionSheetOpen: boolean = false;   // ⋯ 动作面板显隐（复制/粘贴/全选/查找）

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TerminalHostBridge = new TerminalHostBridge();
  // @Local 持有主题单例 → 作为 @Monitor('theme.isDark') 的可观测根（@Monitor 根须被 @Local/@Param 等装饰；
  //   ThemeState 为 @ObservedV2、isDark 为 @Trace → 嵌套属性变化可监听，见 arkts-new-monitor.md）。
  @Local theme: ThemeState = getThemeState();
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    // 桥回调 → 写组件 @Local 状态
    this.bridge.onReadyCb = (): void => { this.state = 'ready'; };
    // terminal:error 文案分类（协议不变：Hub 无 quota 事件，配额走 error 文案）
    //   → quota 置 quotaMax，StatusBanner 显配额专用态；其余 generic 文案照常显
    this.bridge.onErrorCb = (m: string): void => {
      const info: TerminalErrorInfo = classifyTerminalError(m);
      this.state = 'error';
      this.errorMsg = m;
      this.quotaMax = info.kind === 'quota' ? info.max : -1;
    };
    this.bridge.onExitCb = (code: number): void => { this.state = 'exited'; this.exitCode = code; };
    this.bridge.onReconnectingCb = (): void => { this.state = 'reconnecting'; };
    // 复制选区：JS 读 term.getSelection() 经桥回传文本；空→toast 无选区，非空写剪贴板
    //   （复用 ChatPage.copyToClipboard 同款 pasteboard 写 + promise 链，回调签名保持 () => void）
    this.bridge.onCopyCb = (text: string): void => {
      if (text === '') {
        showToast(t('terminal.noSelection'));
        return;
      }
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data)
        .then((): void => { showToast(t('terminal.copySuccess')); })
        .catch((): void => { showToast(t('terminal.copyFailed')); });
    };
  }

  // 路由就绪（NavDestination.onReady）：取 sessionId → 校验 active + 生成 terminalId + boot
  private async onRouteReady(sid: string): Promise<void> {
    this.sessionId = sid;
    this.terminalId = uuid();
    this.state = 'connecting';
    try {
      const session = await getHubClient().fetchSession(this.sessionId);
      this.sessionActive = session.active;
      this.cwd = session.path;
      if (!session.active) {
        this.state = 'error';
        this.errorMsg = t('terminal.sessionInactive');
        return;
      }
    } catch (e) {
      this.sessionActive = false;
      this.state = 'error';
      this.errorMsg = e instanceof Error ? e.message : t('terminal.cliDisconnected');
      return;
    }
    this.bootIfReady();
  }

  // 启动终端（页面就绪 + session 活跃 + 已有 terminalId 时调一次）
  private bootIfReady(): void {
    if (this.booted || !this.sessionActive || this.sessionId === '' || this.terminalId === '') {
      return;
    }
    if (!this.pageReady) { return; }   // Web 未加载完则等 onPageEnd 再触发
    this.booted = true;
    const cfg: TerminalBootCfg = {
      hubUrl: getConnectionService().hubUrl,
      jwt: getConnectionService().jwt,
      sessionId: this.sessionId,
      terminalId: this.terminalId,
      theme: this.xtermTheme()
    };
    this.runJs('bootTerminal(' + JSON.stringify(cfg) + ')');
  }

  // 当前调色板 → xterm theme（背景=bg，前景=textPrimary，光标=primary）
  private xtermTheme(): XtermTheme {
    const p: PaletteColors = paletteOf(getThemeState().isDark);
    return { background: p.bg, foreground: p.textPrimary, cursor: p.primary };
  }

  // 主题变化 → 重推 xterm theme（@Monitor 驱动；berry3 避坑：仅 Web 可见时有效，本页恒可见）
  @Monitor('theme.isDark')
  onThemeChange(monitor: IMonitor): void {
    if (!this.booted) { return; }
    this.runJs('applyTheme(' + JSON.stringify(this.xtermTheme()) + ')');
  }

  // 快捷键 tap：修饰键切换 / seq 经 applyModifierState 合成后 sendInput
  private onQuickKey(key: QuickKey): void {
    if (!this.inputEnabled()) { return; }
    if (key.kind === 'ctrl') {
      this.ctrlActive = !this.ctrlActive; this.altActive = false; this.focusTerm(); return;
    }
    if (key.kind === 'alt') {
      this.altActive = !this.altActive; this.ctrlActive = false; this.focusTerm(); return;
    }
    const mod: ModifierState = { ctrl: this.ctrlActive, alt: this.altActive };
    const seq: string = applyModifierState(key.seq, mod);
    this.sendSeq(seq);
    if (shouldResetModifiers(key.seq, mod)) {
      this.ctrlActive = false;
      this.altActive = false;
    }
    this.focusTerm();
  }

  // 发一段序列到终端（仅 ready 态；对照 sendInput）
  private sendSeq(seq: string): void {
    if (this.state !== 'ready') { return; }
    this.runJs('sendInput(' + JSON.stringify(seq) + ')');
  }

  // 自由输入框「发送」：整段文本一次发出 + 清空 + 回焦
  private sendManual(): void {
    const text: string = this.manualInput;
    if (text === '' || !this.inputEnabled()) { return; }
    this.sendSeq(text);
    this.manualInput = '';
    this.focusTerm();
  }

  private focusTerm(): void { this.runJs('focusTerminal()'); }

  // —— ⋯ 菜单动作（鸿蒙增值；上游 web 终端无复制/查找 UI，靠浏览器原生）——
  // 复制选区：JS 读 term.getSelection() 经 onCopy 桥异步回传（结果在 aboutToAppear 的 onCopyCb 处理）
  private copySelection(): void {
    this.runJs('copySelection()');
  }

  // 全选（移动端拖选不稳，全选+复制是保底路径）
  private selectAllTerm(): void {
    this.runJs('selectAllTerm()');
  }

  // 粘贴：读系统剪贴板 → 非空经 sendInput 发到终端；空/非文本 → toast
  private paste(): void {
    pasteboard.getSystemPasteboard().getData()
      .then((data: pasteboard.PasteData): void => {
        const text: string = data.getPrimaryText();
        if (text === '') {
          showToast(t('terminal.pasteEmpty'));
          return;
        }
        this.sendSeq(text);
        this.focusTerm();
      })
      .catch((): void => { showToast(t('terminal.pasteEmpty')); });
  }

  // 展开 FindBar
  private openFind(): void { this.findOpen = true; }

  // 查找：推 findNext 到 JS（空 query → 清高亮）
  private runFind(next: boolean): void {
    const q: string = this.findQuery;
    const fn: string = next ? 'findNext' : 'findPrev';
    if (q === '') {
      this.runJs('clearFind()');
      return;
    }
    this.runJs(fn + '(' + JSON.stringify(q) + ', ' + this.findCaseSensitive + ')');
  }

  // 关 FindBar：清高亮 + 复位
  private closeFind(): void {
    this.findOpen = false;
    this.findQuery = '';
    this.runJs('clearFind()');
  }

  // 输入是否可用：session 活跃 且 已 ready
  private inputEnabled(): boolean {
    return this.sessionActive && this.state === 'ready';
  }

  // 状态 → 色点
  private statusColor(): string {
    if (this.state === 'ready') { return this.c.success; }
    if (this.state === 'connecting' || this.state === 'reconnecting') { return this.c.warning; }
    if (this.state === 'error') { return this.c.error; }
    return this.c.textTertiary;   // idle / exited
  }

  // 状态 → 文案（错误态带 Hub 上报的 message）
  //   配额态（quotaMax>=0）显本地化配额文案 —— 与 StatusBanner 一致，避免顶栏副标题漏 Hub 原始英文
  private statusLabel(): string {
    if (!this.sessionActive) { return t('terminal.sessionInactive'); }
    if (this.state === 'connecting') { return t('terminal.state.connecting'); }
    if (this.state === 'ready') { return t('terminal.state.ready'); }
    if (this.state === 'reconnecting') { return t('terminal.state.reconnecting'); }
    if (this.state === 'error') {
      if (this.quotaMax >= 0) { return t('terminal.quotaExceeded', { max: this.quotaMax }); }
      return this.errorMsg !== '' ? this.errorMsg : t('terminal.state.error');
    }
    if (this.state === 'exited') {
      return this.exitCode >= 0
        ? t('terminal.exitWithCode', { code: this.exitCode })
        : t('terminal.state.exited');
    }
    return '';
  }

  private titleText(): string {
    return this.cwd !== '' ? this.cwd : t('terminal.title');
  }

  // 统一 runJavaScript（fire-and-forget；失败静默，不影响后续交互）
  private runJs(script: string): void {
    try {
      this.controller.runJavaScript(script);
    } catch (e) {
      // 控制器未就绪等：忽略
    }
  }

  aboutToDisappear(): void {
    // 离开页：断 socket（Hub 收 disconnect 即关 PTY）。页面销毁时 JS 上下文随之中止，socket 亦会关闭。
    this.runJs('disconnectTerminal()');
  }

  // —— 顶栏：返回 + 标题/cwd + 状态色点 + 文案 ——
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

      // 状态色点（对照上游 ConnectionIndicator；Column 圆点，复用既有样式原语）
      Column()
        .width(9)
        .height(9)
        .borderRadius(4.5)
        .backgroundColor(this.statusColor())

      // ⋯ 动作菜单（鸿蒙增值：收纳复制/粘贴/全选/查找；bindSheet 主题面板，与 SessionActionMenu 同款范式）
      Text('⋯')
        .fontSize(fs(22))
        .fontColor(this.c.textPrimary)
        .width(36)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.actionSheetOpen = true; })
    }
    .width('100%')
    .padding({ left: 8, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.c.bg)
    .border({ width: { bottom: 0.5 }, color: this.c.border })
  }

  // ⋯ 动作面板（复用 SessionActionMenu 同款行样式：主题化 + tap 关闭）
  @Builder
  private TerminalActionSheet() {
    Column() {
      Row() {
        Text(t('terminal.copy')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%').height(52).padding({ left: 20, right: 20 }).alignItems(VerticalAlign.Center)
      .onClick(() => { this.actionSheetOpen = false; this.copySelection(); })

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      Row() {
        Text(t('terminal.paste')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%').height(52).padding({ left: 20, right: 20 }).alignItems(VerticalAlign.Center)
      .onClick(() => { this.actionSheetOpen = false; this.paste(); })

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      Row() {
        Text(t('terminal.selectAll')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%').height(52).padding({ left: 20, right: 20 }).alignItems(VerticalAlign.Center)
      .onClick(() => { this.actionSheetOpen = false; this.selectAllTerm(); })

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      Row() {
        Text(t('terminal.find')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%').height(52).padding({ left: 20, right: 20 }).alignItems(VerticalAlign.Center)
      .onClick(() => { this.actionSheetOpen = false; this.openFind(); })
    }
    .width('100%')
    .backgroundColor(this.c.bg)
    .padding({ bottom: 20 })
  }

  // 错误/退出/不可用 横幅（对照上游 errorMessage / exitInfo / inactive 提示）
  //   配额超限（quotaMax>=0）显专用文案 + 琥珀色，区别于 generic 红色错误
  @Builder
  private StatusBanner() {
    if (!this.sessionActive || this.state === 'error' || this.state === 'exited') {
      Row({ space: 8 }) {
        Text('⚠')
          .fontSize(fs(14))
          .fontColor(this.state === 'exited' ? this.c.textTertiary : (this.quotaMax >= 0 ? this.c.warning : this.c.error))
        Text(this.quotaMax >= 0
          ? t('terminal.quotaExceeded', { max: this.quotaMax })
          : this.statusLabel())
          .fontSize(fs(13))
          .fontColor(this.state === 'exited' ? this.c.textTertiary : (this.quotaMax >= 0 ? this.c.warning : this.c.error))
          .layoutWeight(1)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.state === 'exited' ? this.c.surface : this.c.errorBg)
    }
  }

  // 自由输入框 + 发送
  @Builder
  private ManualInput() {
    Row({ space: 8 }) {
      TextInput({ text: this.manualInput, placeholder: t('terminal.inputPlaceholder') })
        .fontSize(fs(15))
        .layoutWeight(1)
        .backgroundColor(this.c.surface)
        .borderRadius(8)
        .enabled(this.inputEnabled())
        .onChange((v: string) => { this.manualInput = v; })
        .onSubmit(() => { this.sendManual(); })
      Text(t('terminal.send'))
        .fontSize(fs(14))
        .fontColor(this.inputEnabled() ? this.c.bubbleUserText : this.c.textTertiary)
        .backgroundColor(this.inputEnabled() ? this.c.primary : this.c.surface)
        .borderRadius(8)
        .padding({ left: 14, right: 14, top: 9, bottom: 9 })
        .onClick(() => { this.sendManual(); })
    }
    .width('100%')
  }

  // 一行快捷键（修饰键 Ctrl/Alt 高亮当前切换态）
  @Builder
  private QuickKeyRow(row: QuickKey[]) {
    Row({ space: 0 }) {
      ForEach(row, (k: QuickKey) => {
        Text(k.label)
          .fontSize(fs(13))
          .fontColor(this.quickKeyActive(k) ? this.c.bubbleUserText : this.c.textPrimary)
          .backgroundColor(this.quickKeyActive(k) ? this.c.primary : this.c.surface)
          .layoutWeight(1)
          .height(38)
          .textAlign(TextAlign.Center)
          .margin({ left: 2, right: 2 })
          .borderRadius(6)
          .opacity(this.inputEnabled() ? 1 : 0.4)
          .onClick(() => { this.onQuickKey(k); })
      }, (k: QuickKey) => k.label)
    }
    .width('100%')
  }

  // 修饰键是否处于激活高亮
  private quickKeyActive(k: QuickKey): boolean {
    if (k.kind === 'ctrl') { return this.ctrlActive; }
    if (k.kind === 'alt') { return this.altActive; }
    return false;
  }

  // 查找栏（SearchAddon；仅 ready 态可用；鸿蒙增值，上游无）
  //   TextInput 实时 findNext / Aa 大小写切换 / ‹ › 翻页 / ✕ 关闭清高亮
  @Builder
  private FindBar() {
    Row({ space: 6 }) {
      TextInput({ text: this.findQuery, placeholder: t('terminal.findPlaceholder') })
        .fontSize(fs(14))
        .layoutWeight(1)
        .backgroundColor(this.c.surface)
        .borderRadius(8)
        .height(38)
        .enabled(this.inputEnabled())
        .onChange((v: string) => {
          this.findQuery = v;
          this.runFind(true);
        })
      // Aa：大小写敏感切换（激活高亮）
      Text(this.findCaseSensitive ? 'Aa' : 'aa')
        .fontSize(fs(13))
        .fontWeight(this.findCaseSensitive ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.findCaseSensitive ? this.c.bubbleUserText : this.c.textSecondary)
        .backgroundColor(this.findCaseSensitive ? this.c.primary : this.c.surface)
        .borderRadius(8)
        .width(38).height(38).textAlign(TextAlign.Center)
        .onClick(() => {
          this.findCaseSensitive = !this.findCaseSensitive;
          if (this.findQuery !== '') { this.runFind(true); }
        })
      Text('‹')
        .fontSize(fs(20)).fontColor(this.c.textPrimary)
        .backgroundColor(this.c.surface).borderRadius(8)
        .width(38).height(38).textAlign(TextAlign.Center)
        .onClick(() => { this.runFind(false); })
      Text('›')
        .fontSize(fs(20)).fontColor(this.c.textPrimary)
        .backgroundColor(this.c.surface).borderRadius(8)
        .width(38).height(38).textAlign(TextAlign.Center)
        .onClick(() => { this.runFind(true); })
      Text('✕')
        .fontSize(fs(15)).fontColor(this.c.textSecondary)
        .width(38).height(38).textAlign(TextAlign.Center)
        .onClick(() => { this.closeFind(); })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.c.bg)
    .border({ width: { top: 0.5 }, color: this.c.border })
  }

  // 底部输入区：自由输入框 + 快捷键栏（对照上游 QUICK_INPUT_ROWS）
  @Builder
  private InputBar() {
    Column({ space: 6 }) {
      this.ManualInput()
      ForEach(QUICK_INPUT_ROWS, (row: QuickKey[]) => {
        this.QuickKeyRow(row)
      }, (row: QuickKey[], idx: number) => `qk-${idx}`)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 10 })
    .backgroundColor(this.c.bg)
    .border({ width: { top: 0.5 }, color: this.c.border })
  }

  build() {
    NavDestination() {
      Column() {
        this.TopBar()
        this.StatusBanner()
        // 终端渲染（Web 托管 xterm.js + socket.io-client；恒为主内容，不被遮挡）
        Web({ src: 'resource://rawfile/terminal/terminal.html', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .layoutWeight(1)
          .width('100%')
          .backgroundColor(this.c.bg)
          .javaScriptProxy({
            object: this.bridge,
            name: 'HostBridge',
            methodList: ['onReady', 'onError', 'onExit', 'onReconnecting', 'onCopy'],
            controller: this.controller
          })
          .onPageEnd(() => {
            this.pageReady = true;
            this.bootIfReady();
          })
        if (this.findOpen) {
          this.FindBar()
        }
        this.InputBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.bg)
      .bindSheet(this.actionSheetOpen, this.TerminalActionSheet(), {
        detents: [SheetSize.FIT_CONTENT],
        dragBar: true,
        showClose: false,
        onDisappear: (): void => { this.actionSheetOpen = false; }
      })
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
      const param = context.pathInfo.param as TerminalRouteParams;
      if (param !== null && param !== undefined && param.sessionId !== '') {
        this.onRouteReady(param.sessionId);
      }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function TerminalPageBuilder(name: string, param: Object) {
  TerminalPage()
}
