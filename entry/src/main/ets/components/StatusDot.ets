// StatusDot —— 会话列表四态状态点（@ComponentV2 叶子组件）。
//
// 照 chatcube TypingDots.ets 范式：独立叶子组件，动画状态（@Local dotOpacity）自持，不波及父列表
//   （避页面级 @Local 周期翻转 → 整页重建坑，见记忆 arkui-page-local-periodic-update-rebuild）。
//   pulsing 时 opacity 呼吸（0.65↔1.0，半周期 ~900ms 对齐 paseo PulsingStatusDot），aboutToDisappear
//   清 timer 防泄漏。列表 ForEach 回收 → 本组件 aboutToDisappear → clearInterval；复用 → aboutToAppear 重启。
// pulsing 翻转（running↔idle）由 @Param 携带，@Monitor('pulsing') 响应启停（避 @Param 变化后旧 timer 残留）。

@ComponentV2
export struct StatusDot {
  @Param color: string = '';
  @Param pulsing: boolean = false;
  @Param dotSize: number = 8;
  @Local private dotOpacity: number = 1.0;
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    if (this.pulsing) {
      this.startPulse();
    }
  }

  aboutToDisappear(): void {
    this.stopPulse();
  }

  // pulsing @Param 翻转时启停动画（会话从 running→idle：true→false 停；idle→running：false→true 起）。
  @Monitor('pulsing')
  onPulsingChange(): void {
    if (this.pulsing) {
      this.startPulse();
    } else {
      this.stopPulse();
    }
  }

  // 半周期 900ms 交替 0.65/1.0；animateTo 800ms EaseInOut 过渡（呼吸感）。
  private startPulse(): void {
    if (this.pulseTimer !== -1) {
      return;
    }
    let high: boolean = false;
    this.applyOpacity(high);
    high = true;
    this.pulseTimer = setInterval(() => {
      this.applyOpacity(high);
      high = !high;
    }, 900);
  }

  private stopPulse(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
    this.dotOpacity = 1.0;
  }

  private applyOpacity(high: boolean): void {
    const next: number = high ? 1.0 : 0.65;
    try {
      this.getUIContext().animateTo({ duration: 800, curve: Curve.EaseInOut }, () => {
        this.dotOpacity = next;
      });
    } catch (_e) {
      this.dotOpacity = next;
    }
  }

  build() {
    Column()
      .width(this.dotSize)
      .height(this.dotSize)
      .borderRadius(this.dotSize / 2)
      .backgroundColor(this.color)
      .opacity(this.dotOpacity)
  }
}
