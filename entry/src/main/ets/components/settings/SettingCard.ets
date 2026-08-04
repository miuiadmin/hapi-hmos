// 设置页列表卡片（对照 berry3 components/SettingCard.ets，颜色改走 JS 调色板）。
//
// suffixType 枚举驱动 7 种右侧元素（不用 @BuilderParam：V2 下方法引用传 @BuilderParam 在
// update func 丢绑定会闪退）。拆 clickableRow / staticRow 两 @Builder：可点击行
// (arrow/textAndArrow/check/loading/none) 挂按压态+onClick；switch/select 行整行不可点
// （交互在子组件自身），无按压态，避免「按压有灰底但点击无效」误导。
//
// 颜色映射（berry3 sys token → PaletteColors）：
//   font_primary→textPrimary / font_secondary→textSecondary / warning(danger)→error /
//   comp_background_secondary(按压灰底)→surfaceSelected / icon_tertiary(chevron)→textTertiary /
//   brand(勾选)→primary。
// 字号：主标题 fs(16) Medium / 副标题 fs(13)（对齐 berry3 Subtitle_M / Body_S）。
import { resolveRowRadius, RowPosition } from './RowRadiusUtil';
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';

export type SettingSuffixType = 'none' | 'arrow' | 'textAndArrow' | 'switch' | 'select' | 'check' | 'loading';

@ComponentV2
export struct SettingCard {
  /** 主标题 */
  @Param primaryText: string = '';
  /** 副标题（空串=不显示） */
  @Param secondaryText: string = '';
  /** 右侧 suffix 类型 */
  @Param suffixType: SettingSuffixType = 'none';
  /** switch 当前开关态 */
  @Param switchIsOn: boolean = false;
  /** switch 变更回调 */
  @Event onSwitchChange: (isOn: boolean) => void = () => {};
  /** select 当前显示文本 */
  @Param selectValue: string = '';
  /** select 选项（string[]，非 SelectOption[]） */
  @Param selectOptions: string[] = [];
  /** select 选中索引 */
  @Param selectIndex: number = 0;
  /** select 选中回调 */
  @Event onSelect: (index: number) => void = () => {};
  /** textAndArrow 文本 */
  @Param suffixText: string = '';
  /** check 选中态（单选成员行；选中显示 checkmark） */
  @Param isChecked: boolean = false;
  /** 行点击回调（arrow/textAndArrow/check/loading/none 可点）。注：不能用 onClick，与 ArkUI 内置方法同名冲突 */
  @Event onItemClick: () => void = () => {};
  /** 是否可点击（false 走 staticRow：无按压态无 onClick，用于只读信息行如版本/协议/连接信息） */
  @Param clickable: boolean = true;
  /** 是否启用（false 整行置灰：onClick 不响应 + .enabled 阻断 + Toggle/Select 不可操作） */
  @Param isEnabled: boolean = true;
  /** 行在外卡中的位置，驱动按压灰底 borderRadius 咬合外卡圆角。⚠️ 须配合 ListItemGroup.clip(true)+padding 清零 */
  @Param rowPosition: RowPosition = 'single';
  /** 危险操作卡片（如退出登录）：主/副标题改 error 红 */
  @Param isDanger: boolean = false;
  /** 左侧图标方块图标（null=不渲染方块；设置首页莫兰迪彩色图标用） */
  @Param iconSymbol: Resource | null = null;
  /** 左侧图标方块底色（JS 莫兰迪色 string；iconSymbol 为 null 时忽略） */
  @Param iconBgColor: string = '';
  /** 左侧色点（非空=渲染 18×18 圆色点；气泡配色选择器项用，与图标方块互斥场景各自使用） */
  @Param swatchColor: string = '';
  /** 独立白卡模式（true=常态底改 c.bg 白，用于选择器项浮灰底 sheet；false=透明承 ListItemGroup 白底，设置列表用） */
  @Param cardBackground: boolean = false;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  /** 禁用态透明度 */
  @Computed get rowOpacity(): number {
    return this.isEnabled ? 1 : 0.4;
  }

  /** 是否整行可点：switch/select 交互在子组件不可点；只读行（clickable=false）不可点 */
  @Computed get isClickable(): boolean {
    return this.clickable && this.suffixType !== 'switch' && this.suffixType !== 'select';
  }

  build() {
    if (this.isClickable) {
      this.clickableRow();
    } else {
      this.staticRow();
    }
  }

  /** 可点击行：满宽灰底 + resolveRowRadius 咬合外卡圆角的按压高亮 */
  @Builder clickableRow() {
    Row() {
      this.iconNode();
      this.swatchNode();
      this.textLabel();
      this.suffixNode();
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: $r('app.float.setting_card_padding_h'),
      right: $r('app.float.setting_card_padding_h'),
      top: $r('app.float.setting_card_padding_v'),
      bottom: $r('app.float.setting_card_padding_v')
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(resolveRowRadius(this.rowPosition))
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({
      pressed: { .backgroundColor(this.c.surfaceSelected) },
      normal: { .backgroundColor(this.cardBackground ? this.c.bg : Color.Transparent) }
    })
    .enabled(this.isEnabled)
    .opacity(this.rowOpacity)
    .onClick(() => {
      if (this.isEnabled) {
        this.onItemClick();
      }
    })
  }

  /** 不可点击行（switch/select）：同满宽咬合 + resolveRowRadius 圆角，无按压态无 onClick */
  @Builder staticRow() {
    Row() {
      this.iconNode();
      this.swatchNode();
      this.textLabel();
      this.suffixNode();
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: $r('app.float.setting_card_padding_h'),
      right: $r('app.float.setting_card_padding_h'),
      top: $r('app.float.setting_card_padding_v'),
      bottom: $r('app.float.setting_card_padding_v')
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(resolveRowRadius(this.rowPosition))
    .enabled(this.isEnabled)
    .opacity(this.rowOpacity)
  }

  /** 左侧图标方块（可选）：36×36 r8 莫兰迪底 + 白 SymbolGlyph，iOS 风彩色方块白图标 */
  @Builder iconNode() {
    if (this.iconSymbol !== null) {
      Column() {
        SymbolGlyph(this.iconSymbol)
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius($r('sys.float.corner_radius_level4'))
      .backgroundColor(this.iconBgColor)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      // margin({right:12}) 而非父 Row({space:12})：父 Row 被 SettingCard 全场景共用，
      // 加 space 改变 textLabel↔suffixNode 间距；图标槽仅首页用，局部 margin 最小侵入
      .margin({ right: 12 })
    }
  }

  /** 左侧色点（可选）：非空渲染 18×18 圆色点 + 0.5 边框（气泡配色选择器项用） */
  @Builder swatchNode() {
    if (this.swatchColor.length > 0) {
      Circle({ width: 18, height: 18 })
        .fill(this.swatchColor)
        .stroke(this.c.border)
        .strokeWidth(0.5)
        .margin({ right: 12 })
    }
  }

  /** 左侧文字区：主标题 + 副标题（副标题空串不渲染） */
  @Builder textLabel() {
    Column() {
      Text(this.primaryText)
        .fontSize(fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDanger ? this.c.error : this.c.textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.secondaryText.length > 0) {
        Text(this.secondaryText)
          .fontSize(fs(13))
          .fontColor(this.isDanger ? this.c.error : this.c.textSecondary)
          .opacity(this.isDanger ? 0.7 : 1)
          .margin({ top: 2 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 右侧 suffix：按 suffixType 渲染单一元素 */
  @Builder suffixNode() {
    if (this.suffixType === 'switch') {
      Toggle({ type: ToggleType.Switch, isOn: this.switchIsOn })
        .selectedColor(this.c.primary)
        .enabled(this.isEnabled)
        .onChange((isOn: boolean) => { this.onSwitchChange(isOn); })
    } else if (this.suffixType === 'select') {
      // 原生 Select 默认带边框+下拉箭头；当前照搬 berry3 写法（脱皮真机验证后必要时降级 Text+bindMenu）
      Select(this.selectOptions.map((v: string): SelectOption => ({ value: v })))
        .enabled(this.isEnabled)
        .selected(this.selectIndex)
        .value(this.selectValue)
        .onSelect((index: number) => { this.onSelect(index); })
        .font({ size: 14 })
        .fontColor(this.c.textSecondary)
        .selectedOptionFontColor(this.c.primary)
        .selectedOptionBgColor(this.c.surfaceSelected)
        .optionFontColor(this.c.textPrimary)
        .backgroundColor(Color.Transparent)
        .borderRadius($r('sys.float.corner_radius_level4'))
        .menuBackgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .padding({ left: 10, right: 8 })
    } else if (this.suffixType === 'textAndArrow') {
      Row() {
        Text(this.suffixText)
          .fontSize(fs(13))
          .fontColor(this.c.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 140 })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.c.textTertiary])
          .margin({ left: 4 })
      }
    } else if (this.suffixType === 'arrow') {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.c.textTertiary])
    } else if (this.suffixType === 'check') {
      // 单选成员行：选中显示 checkmark + primary，未选空（iOS 设置单选范式）
      if (this.isChecked) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.c.primary])
      }
    } else if (this.suffixType === 'loading') {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(this.c.textTertiary)
    }
  }
}
