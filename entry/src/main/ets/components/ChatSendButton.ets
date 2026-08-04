import { AttachmentMetadata } from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 发送键独立子组件（呼吸动画隔离）：
//   breathOpacity/sendIconTrigger 等 @Local 下沉至此 → setInterval 850ms 翻转只重渲本 Button，
//   不再整体重建 ChatPage（根治生成中卡顿、输入框被撑大）。对照 chatcube ChatInputBar。
//   @Param 与父 @Local 单向同步；@Monitor 观察 @Param（arkts-new-monitor 官方支持，API 12+）。
//   子组件 build 仅一固定 Button，派生 @Local 变更只改属性、不增删 UINode → 无「UINode added during
//   re-render」风险，@Monitor 内同步改 @Local 免 setTimeout(0)（对照 chatcube ChatInputBar:669-676）。
@ComponentV2
export struct ChatSendButton {
  // —— 父下传可观测输入（@Param 与父 @Local 单向同步）——
  @Param isThinking: boolean = false;
  @Param inputText: string = '';
  @Param pendingAttachments: AttachmentMetadata[] = [];
  // —— 子→父输出（调父 handleSend/handleStop；无参）——
  @Event onSend: () => void = () => {};
  @Event onStop: () => void = () => {};

  // —— 仅本按钮读写、无外部消费者（迁自 ChatPage）——
  @Local breathOpacity: number = 1;                 // pause 呼吸透明度（生成中且无内容时 1↔0.35 循环）
  @Local sendIconTrigger: number = 0;               // 发送键 ReplaceSymbolEffect 触发器（hasContent/isThinking 翻转 bump）
  @Local sendBtnScale: number = 1;                  // 发送键状态切换弹跳（isThinking 起 0.9 回弹）
  @Local sendBtnPressed: boolean = false;           // 发送键按下态（阴影放大 + 0.95 缩放）
  private breatheTimerId: number = -1;              // 呼吸 setInterval 句柄
  private lastHasContent: boolean = false;          // 上次 hasContent（仅翻转时 bump 触发器，省冗余变形）

  // 主题（读 @Trace isDark 自建刷新依赖；不把调色板当 @Param 下传）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  // #RRGGBB → #AA{{RRGGBB}}（HarmonyOS 八位色 alpha 在前）
  private withAlpha(color: string, alphaHex: string): string {
    if (color.startsWith('#') && color.length === 7) {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return color;
  }
  // 自身副本（操作 @Param；ChatPage 同名方法保留服务 textarea 回车发送）
  private composerHasContent(): boolean {
    return this.inputText.trim() !== '' || this.pendingAttachments.length > 0;
  }
  // 发送键图标：生成中+空→pause(呼吸)；生成中+有内容→排队发送实心纸飞机；非生成中按内容态。
  private sendSymbol(): Resource {
    if (this.isThinking) {
      return this.composerHasContent() ? $r('sys.symbol.paperplane_right_fill') : $r('sys.symbol.pause');
    }
    if (this.composerHasContent()) { return $r('sys.symbol.paperplane_right_fill'); }
    return $r('sys.symbol.paperplane');
  }
  // 发送键透明度（恒 1，仅 blocking 附件才 0.45；本项目无该态→恒 1）
  private sendOpacity(): number { return 1; }

  // —— 呼吸：仅「生成中且无新内容」(pause 态) 跑；1↔0.35，850ms ——
  private updateBreathing(): void {
    if (this.isThinking && !this.composerHasContent()) {
      this.startBreathing();
    } else {
      this.stopBreathing();
    }
  }
  private startBreathing(): void {
    if (this.breatheTimerId >= 0) { return; }
    this.breathOpacity = 1;
    this.breatheTimerId = setInterval((): void => {
      this.breathOpacity = this.breathOpacity > 0.8 ? 0.35 : 1;
    }, 850);
  }
  private stopBreathing(): void {
    if (this.breatheTimerId >= 0) {
      clearInterval(this.breatheTimerId);
      this.breatheTimerId = -1;
    }
    this.breathOpacity = 1;
  }

  // 发送键状态切换弹跳（isThinking 起 0.9 回弹到 1）
  private animateSendButton(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.sendBtnScale = this.isThinking ? 0.9 : 1;
    });
  }

  // 生成中态翻转：bump 变形 + 同步呼吸 + 弹跳（无需 setTimeout，见上类注释）。
  @Monitor('isThinking')
  onThinkingChanged(): void {
    this.sendIconTrigger++;
    this.lastHasContent = this.composerHasContent();
    this.updateBreathing();
    this.animateSendButton();
  }
  // 内容态翻转才 bump（省冗余变形；生成中 pause↔paperplane 切换亦由此驱动）+ 同步呼吸。
  @Monitor('inputText', 'pendingAttachments')
  onComposerContentChanged(): void {
    const hasContent = this.composerHasContent();
    this.updateBreathing();
    if (hasContent === this.lastHasContent) { return; }
    this.lastHasContent = hasContent;
    this.sendIconTrigger++;
  }

  aboutToAppear(): void {
    this.lastHasContent = this.composerHasContent();
    this.updateBreathing();
  }

  aboutToDisappear(): void {
    this.stopBreathing();
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      SymbolGlyph(this.sendSymbol())
        .fontSize(this.isThinking ? fs(20) : fs(22))
        .fontColor([this.c.bubbleUserText])
        .symbolEffect(new ReplaceSymbolEffect(EffectScope.WHOLE), this.sendIconTrigger)
        .opacity(this.breathOpacity)
        .animation({ duration: 850, curve: Curve.EaseInOut })
    }
    .width(40)
    .height(40)
    .backgroundColor(this.c.primary)
    .opacity(this.sendOpacity())
    .shadow({
      radius: this.sendBtnPressed ? 24 : 16,
      color: this.withAlpha(this.c.primary, this.sendBtnPressed ? '66' : '40'),
      offsetX: 0,
      offsetY: this.sendBtnPressed ? 6 : 4
    })
    .scale({
      x: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale,
      y: this.sendBtnPressed ? 0.95 * this.sendBtnScale : this.sendBtnScale
    })
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) { this.sendBtnPressed = true; }
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.sendBtnPressed = false; }
    })
    .onClick(() => {
      // 排队混合：生成中 + 有新内容 → 排队发送；生成中 + 空 → 停止；否则有内容才发。
      if (this.isThinking) {
        if (this.composerHasContent()) { this.onSend(); } else { this.onStop(); }
        return;
      }
      if (this.composerHasContent()) { this.onSend(); }
    })
  }
}
