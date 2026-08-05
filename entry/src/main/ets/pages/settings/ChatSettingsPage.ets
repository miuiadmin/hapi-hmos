// 聊天设置子页（输入 / 触感 / 终端工具卡 / 终端字号 / 会话列表 / 气泡配色）。
// 逻辑从旧 SettingsPage 迁移（语义不变，UI 用 SettingCard）。
// 气泡配色 sheet（SurfaceColorSheet）内部保留自定义行（swatch 圆点特殊，不适合 ListItemGroup 内 SettingCard）。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { getLayoutState } from '../../state/LayoutState';
import { hdsTitleBarStyle } from '../../components/HdsTitleBarStyle';
import { t } from '../../i18n/I18nService';
import { getPreferencesService } from '../../services/PreferencesService';
import { PreferenceKeys } from '../../config/Keys';
import { TerminalToolDisplayService } from '../../services/TerminalToolDisplayService';
import { TerminalToolDisplayMode } from '../../chat/TerminalToolDisplay';
import { TerminalFontSizeService } from '../../services/TerminalFontSizeService';
import { VALID_TERMINAL_FONT_SIZES } from '../../chat/TerminalFontSize';
import { SessionPreviewLimitService } from '../../services/SessionPreviewLimitService';
import { PinInProgressService } from '../../services/PinInProgressService';
import { HapticService } from '../../services/HapticService';
import {
  ChatSurfaceColorPreference,
  ChatSurfaceColorPreset,
  getPickerValue,
  normalizeHexColor,
  toPresetPreference,
  toCustomPreference
} from '../../chat/ChatSurfaceColors';
import { ChatSurfaceColorsService } from '../../services/ChatSurfaceColorsService';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';
import { resolveRowRadius } from '../../components/settings/RowRadiusUtil';
import { SheetDialog } from '../../components/settings/SheetDialog';
import { buildSheetOptions, SheetOverrides } from '../../components/settings/SheetOptionsFactory';

@Builder
export function ChatSettingsPageBuilder(name: string, param: Object) {
  ChatSettingsPage()
}

@ComponentV2
struct ChatSettingsPage {
  @Local enterToSend: boolean = false;
  @Local surfaceSheetOpen: boolean = false;
  @Local surfaceSheetMode: 'tool' | 'user' = 'tool';
  @Local customHex: string = '';
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  // HDS 液态顶栏（全屏沉浸后回归 berry3 范式）：scroller 驱动滚动联动；titleBarStyle 随主题（c.bg）刷新。
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }
  private get hapticsEnabled(): boolean { return HapticService.currentEnabled; }
  private get terminalToolMode(): TerminalToolDisplayMode { return TerminalToolDisplayService.currentMode; }
  private get terminalFontSize(): number { return TerminalFontSizeService.currentSize; }
  private get sessionPreviewLimit(): number { return SessionPreviewLimitService.currentLimit; }
  private get pinInProgressEnabled(): boolean { return PinInProgressService.currentEnabled; }

  aboutToAppear(): void {
    this.loadEnterToSend();
  }

  private loadEnterToSend(): void {
    getPreferencesService().getBoolean(PreferenceKeys.ENTER_TO_SEND, false)
      .then((v: boolean) => { this.enterToSend = v; })
      .catch(() => {});
  }
  private saveEnterToSend(isOn: boolean): void {
    this.enterToSend = isOn;
    getPreferencesService().putBoolean(PreferenceKeys.ENTER_TO_SEND, isOn).catch(() => {});
  }
  private setHapticsEnabled(isOn: boolean): void { HapticService.setEnabled(isOn); }
  private selectTerminalToolDisplay(mode: TerminalToolDisplayMode): void { TerminalToolDisplayService.setMode(mode); }
  private selectTerminalFontSize(size: number): void { TerminalFontSizeService.setSize(size); }
  private setPinInProgress(on: boolean): void { PinInProgressService.setEnabled(on); }
  private onPreviewLimitChange(value: string): void {
    const n: number = parseInt(value, 10);
    if (isNaN(n)) { return; }
    SessionPreviewLimitService.setLimit(n);
  }

  // —— 气泡配色（读 ChatSurfaceColorsService @Trace；切换即时重渲染，reapply 同步重 mix）——
  private prefDisplayName(pref: ChatSurfaceColorPreference): string {
    if (pref === 'default') { return t('settings.chat.surfaceColor.default'); }
    if (pref === 'preset:soft-blue') { return t('settings.chat.surfaceColor.softBlue'); }
    if (pref === 'preset:soft-green') { return t('settings.chat.surfaceColor.softGreen'); }
    if (pref === 'preset:soft-yellow') { return t('settings.chat.surfaceColor.softYellow'); }
    if (pref.startsWith('custom:')) { return pref.substring('custom:'.length); }
    return t('settings.chat.surfaceColor.default');
  }
  private currentSurfacePref(): ChatSurfaceColorPreference {
    return this.surfaceSheetMode === 'tool'
      ? ChatSurfaceColorsService.currentToolGroupPref
      : ChatSurfaceColorsService.currentUserMessagePref;
  }
  private openSurfaceSheet(mode: 'tool' | 'user'): void {
    this.surfaceSheetMode = mode;
    const pref: ChatSurfaceColorPreference = this.currentSurfacePref();
    this.customHex = pref.startsWith('custom:') ? pref.substring('custom:'.length) : '#';
    this.surfaceSheetOpen = true;
  }
  private pickSurfacePreset(preset: ChatSurfaceColorPreset): void {
    const pref: ChatSurfaceColorPreference = toPresetPreference(preset);
    if (this.surfaceSheetMode === 'tool') {
      ChatSurfaceColorsService.setToolGroupBg(pref);
    } else {
      ChatSurfaceColorsService.setUserMessageBg(pref);
    }
    this.surfaceSheetOpen = false;
  }
  private onCustomHexChange(hex: string): void {
    this.customHex = hex;
    const normalized: string | null = normalizeHexColor(hex);
    if (normalized === null) { return; }
    const pref: ChatSurfaceColorPreference = toCustomPreference(hex);
    if (this.surfaceSheetMode === 'tool') {
      ChatSurfaceColorsService.setToolGroupBg(pref);
    } else {
      ChatSurfaceColorsService.setUserMessageBg(pref);
    }
  }
  private customSwatch(): string {
    const normalized: string | null = normalizeHexColor(this.customHex);
    return normalized !== null ? normalized : getPickerValue('default');
  }

  // SurfaceColorSheet 的 bindSheet 视觉配置：白身(c.bg) + 毛玻璃 + 无把手 + LARGE 档。
  private get surfaceSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.LARGE],
      onDisappear: () => { this.surfaceSheetOpen = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
  }

  build() {
    HdsNavDestination() {
      List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（HdsNavDestination ignoreLayoutSafeArea 后内容从 y=0 起；+56 titleBar 高 +8 间距）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)
        // ── 输入 ──
        ListItem() { SettingSectionTitle({ text: t('settings.section.input') }) }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.enterToSend'), suffixType: 'switch',
              switchIsOn: this.enterToSend, rowPosition: 'first',
              onSwitchChange: (v: boolean) => { this.saveEnterToSend(v); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.haptics'), suffixType: 'switch',
              switchIsOn: this.hapticsEnabled, rowPosition: 'last',
              onSwitchChange: (v: boolean) => { this.setHapticsEnabled(v); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg).borderRadius($r('app.float.setting_card_radius')).clip(true)

        // ── 终端工具卡显示 ──
        ListItem() { SettingSectionTitle({ text: t('settings.chat.terminalToolDisplay') }) }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.chat.terminalToolDisplay.compact'), suffixType: 'check',
              isChecked: this.terminalToolMode === 'compact', rowPosition: 'first',
              onItemClick: () => { this.selectTerminalToolDisplay('compact'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.chat.terminalToolDisplay.detailed'), suffixType: 'check',
              isChecked: this.terminalToolMode === 'detailed', rowPosition: 'last',
              onItemClick: () => { this.selectTerminalToolDisplay('detailed'); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg).borderRadius($r('app.float.setting_card_radius')).clip(true)

        // ── 终端字号（5 档）──
        ListItem() { SettingSectionTitle({ text: t('settings.terminal.fontSize') }) }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: `${VALID_TERMINAL_FONT_SIZES[0]}`, suffixType: 'check',
              isChecked: this.terminalFontSize === VALID_TERMINAL_FONT_SIZES[0], rowPosition: 'first',
              onItemClick: () => { this.selectTerminalFontSize(VALID_TERMINAL_FONT_SIZES[0]); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: `${VALID_TERMINAL_FONT_SIZES[1]}`, suffixType: 'check',
              isChecked: this.terminalFontSize === VALID_TERMINAL_FONT_SIZES[1], rowPosition: 'middle',
              onItemClick: () => { this.selectTerminalFontSize(VALID_TERMINAL_FONT_SIZES[1]); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: `${VALID_TERMINAL_FONT_SIZES[2]}`, suffixType: 'check',
              isChecked: this.terminalFontSize === VALID_TERMINAL_FONT_SIZES[2], rowPosition: 'middle',
              onItemClick: () => { this.selectTerminalFontSize(VALID_TERMINAL_FONT_SIZES[2]); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: `${VALID_TERMINAL_FONT_SIZES[3]}`, suffixType: 'check',
              isChecked: this.terminalFontSize === VALID_TERMINAL_FONT_SIZES[3], rowPosition: 'middle',
              onItemClick: () => { this.selectTerminalFontSize(VALID_TERMINAL_FONT_SIZES[3]); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: `${VALID_TERMINAL_FONT_SIZES[4]}`, suffixType: 'check',
              isChecked: this.terminalFontSize === VALID_TERMINAL_FONT_SIZES[4], rowPosition: 'last',
              onItemClick: () => { this.selectTerminalFontSize(VALID_TERMINAL_FONT_SIZES[4]); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg).borderRadius($r('app.float.setting_card_radius')).clip(true)

        // ── 会话列表（预览行数 + 置顶进行中）──
        ListItem() { SettingSectionTitle({ text: t('settings.chat.sessionList') }) }
        ListItemGroup() {
          // 预览行数：自定义 TextInput 行（SettingCard 无 TextInput suffix，局部 Row 对齐卡片尺寸）
          ListItem() { this.previewLimitRow() }
          // 置顶进行中会话（对照上游 pinInProgressSessions：活跃会话抽到「进行中」分区）
          ListItem() {
            SettingCard({
              primaryText: t('settings.chat.pinInProgress'),
              secondaryText: t('settings.chat.pinInProgress.desc'),
              suffixType: 'switch',
              switchIsOn: this.pinInProgressEnabled, rowPosition: 'last',
              onSwitchChange: (v: boolean) => { this.setPinInProgress(v); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg).borderRadius($r('app.float.setting_card_radius')).clip(true)

        // ── 气泡配色（tap 开 sheet）──
        ListItem() { SettingSectionTitle({ text: t('settings.chat.surfaceColor') }) }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.chat.surfaceColor.toolGroup'),
              suffixText: this.prefDisplayName(ChatSurfaceColorsService.currentToolGroupPref),
              suffixType: 'textAndArrow', rowPosition: 'first',
              onItemClick: () => { this.openSurfaceSheet('tool'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.chat.surfaceColor.userMessage'),
              suffixText: this.prefDisplayName(ChatSurfaceColorsService.currentUserMessagePref),
              suffixType: 'textAndArrow', rowPosition: 'last',
              onItemClick: () => { this.openSurfaceSheet('user'); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg).borderRadius($r('app.float.setting_card_radius')).clip(true)

        ListItem() { Row().height(24) }.selectable(false)
        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
      .bindSheet(this.surfaceSheetOpen!!, this.SurfaceColorSheet(), this.surfaceSheetOpts)
    }
    .titleBar({
      content: {
        title: { mainTitle: t('settings.chat.title') },
        divider: { showType: DividerShowType.OFF }
      },
      style: this.titleBarStyle,
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideTitleBar(false, true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(this.c.surface)
    .onReady((context: NavDestinationContext) => { this.navPathStack = context.pathStack; })
    .onBackPressed(() => { this.navPathStack?.pop(); return true; })
  }

  // 预览行数行：label + TextInput（数字 1–99）；尺寸对齐 SettingCard（padding/minHeight/咬合圆角）
  @Builder previewLimitRow() {
    Row() {
      Text(t('settings.chat.sessionPreviewLimit'))
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      TextInput({ text: `${this.sessionPreviewLimit}`, placeholder: '8' })
        .type(InputType.Number)
        .width(72)
        .height(40)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .backgroundColor(this.c.surface)
        .borderRadius(8)
        .textAlign(TextAlign.Center)
        .onChange((value: string) => { this.onPreviewLimitChange(value); })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: $r('app.float.setting_card_padding_h'), right: $r('app.float.setting_card_padding_h'),
      top: $r('app.float.setting_card_padding_v'), bottom: $r('app.float.setting_card_padding_v')
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(resolveRowRadius('first'))
  }

  // 气泡配色选择器 sheet（工具组/用户消息两态；4 预设 + 自定义 hex 输入）—— berry3 弹窗设计系统：
  //   SheetDialog 标题栏（白头）+ 白身(c.bg) + SettingCard(cardBackground + swatchColor) 灰卡色点选择器项。
  @Builder SurfaceColorSheet() {
    Column() {
      SheetDialog({
        title: this.surfaceSheetMode === 'tool'
          ? t('settings.chat.surfaceColor.toolGroup')
          : t('settings.chat.surfaceColor.userMessage'),
        showCloseButton: true,
        onClose: () => { this.surfaceSheetOpen = false; }
      })
      Scroll() {
        Column({ space: 12 }) {
          SettingCard({
            primaryText: t('settings.chat.surfaceColor.default'),
            swatchColor: getPickerValue('default'),
            suffixType: 'check',
            isChecked: this.currentSurfacePref() === 'default',
            rowPosition: 'single', cardBackground: true,
            onItemClick: (): void => { this.pickSurfacePreset('default'); }
          })
          SettingCard({
            primaryText: t('settings.chat.surfaceColor.softBlue'),
            swatchColor: getPickerValue('preset:soft-blue'),
            suffixType: 'check',
            isChecked: this.currentSurfacePref() === 'preset:soft-blue',
            rowPosition: 'single', cardBackground: true,
            onItemClick: (): void => { this.pickSurfacePreset('soft-blue'); }
          })
          SettingCard({
            primaryText: t('settings.chat.surfaceColor.softGreen'),
            swatchColor: getPickerValue('preset:soft-green'),
            suffixType: 'check',
            isChecked: this.currentSurfacePref() === 'preset:soft-green',
            rowPosition: 'single', cardBackground: true,
            onItemClick: (): void => { this.pickSurfacePreset('soft-green'); }
          })
          SettingCard({
            primaryText: t('settings.chat.surfaceColor.softYellow'),
            swatchColor: getPickerValue('preset:soft-yellow'),
            suffixType: 'check',
            isChecked: this.currentSurfacePref() === 'preset:soft-yellow',
            rowPosition: 'single', cardBackground: true,
            onItemClick: (): void => { this.pickSurfacePreset('soft-yellow'); }
          })
          this.SurfaceCustomRow()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  // 自定义 hex 输入行（灰卡浮白底：swatch 预览 + 标签 + TextInput；每键校验，合法即应用）
  @Builder SurfaceCustomRow() {
    Row() {
      Circle({ width: 18, height: 18 })
        .fill(this.customSwatch())
        .stroke(this.c.border)
        .strokeWidth(0.5)
      Text(t('settings.chat.surfaceColor.custom'))
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .margin({ left: 12 })
      TextInput({ text: this.customHex, placeholder: '#rrggbb' })
        .fontSize(fs(14))
        .fontColor(this.c.textPrimary)
        .backgroundColor(this.c.bg)
        .borderRadius(8)
        .height(40)
        .margin({ left: 12 })
        .layoutWeight(1)
        .onChange((value: string) => { this.onCustomHexChange(value); })
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: $r('app.float.setting_card_padding_h'), right: $r('app.float.setting_card_padding_h'),
      top: $r('app.float.setting_card_padding_v'), bottom: $r('app.float.setting_card_padding_v')
    })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.c.surface)
    .borderRadius($r('app.float.setting_card_radius'))
  }
}
