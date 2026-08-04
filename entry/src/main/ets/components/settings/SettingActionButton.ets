// 设置页胶囊操作按钮（对照 berry3 components/SettingActionButton.ets）。
// ButtonType.Capsule + stateEffect:true + height 48，三档色映射 PaletteColors：
// - primary  = primary(蓝) + 白字(bubbleUserText)：确认 / 主操作
// - danger   = error(红) + 白字：危险操作（退出登录等）
// - secondary= surfaceSelected(浅底) + textPrimary(深字)：次要操作
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

export type SettingActionStyle = 'primary' | 'secondary' | 'danger';

@ComponentV2
export struct SettingActionButton {
  /** 按钮文案 */
  @Param label: string = '';
  /** 样式档位 */
  @Param style: SettingActionStyle = 'primary';
  /** 是否启用（false 整体置灰不可点） */
  @Param isEnabled: boolean = true;
  /** 点击回调 */
  @Event onPress: () => void = () => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  /** 背景色：按 style 映射语义色 */
  @Computed get bgColor(): string {
    if (this.style === 'primary') {
      return this.c.primary;
    }
    if (this.style === 'danger') {
      return this.c.error;
    }
    return this.c.surfaceSelected;
  }

  /** 前景色：secondary 浅底深字，primary/danger 深底白字 */
  @Computed get fgColor(): string {
    return this.style === 'secondary' ? this.c.textPrimary : this.c.bubbleUserText;
  }

  build() {
    // stateEffect:true 强制按压反馈；Capsule 胶囊形
    Button(this.label, { type: ButtonType.Capsule, stateEffect: true })
      .height(48)
      .fontSize(fs(14))
      .fontColor(this.fgColor)
      .backgroundColor(this.bgColor)
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1 : 0.4)
      .onClick(() => {
        if (this.isEnabled) {
          this.onPress();
        }
      })
  }
}
