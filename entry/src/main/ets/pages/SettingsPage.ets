import { getConnectionService } from '../services/ConnectionService';
import { getSSEClient } from '../api/SSEClient';
import { getPreferencesService } from '../services/PreferencesService';
import { AppStorageKeys, PreferenceKeys } from '../config/Keys';
import { window } from '@kit.ArkUI';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { fs, paletteOf, PaletteColors, getThemeState, ThemeService, ThemeMode, FontScaleMode } from '../theme/ThemeService';
import { TerminalToolDisplayService, TerminalToolDisplayMode } from '../services/TerminalToolDisplayService';
import { showToast } from '../utils/Toast';
import { t, I18nService, LanguageChoice } from '../i18n/I18nService';
import { VoiceSettingsService } from '../services/VoiceSettingsService';
import { VOICE_LANGUAGES, VoiceLanguage, findLanguageByCode, getLanguageDisplayName } from '../chat/VoiceLanguages';
import { VOICE_PRESETS, VoicePreset, getPresetDisplayName } from '../chat/VoiceVoices';
import {
  ChatSurfaceColorPreference,
  ChatSurfaceColorPreset,
  getPickerValue,
  normalizeHexColor,
  toPresetPreference,
  toCustomPreference
} from '../chat/ChatSurfaceColors';
import { ChatSurfaceColorsService } from '../services/ChatSurfaceColorsService';

// 设置页（NavDestination）—— 主题/字号/语言/输入 + 连接信息 + 关于 + 退出登录
// UI 对照 chatcube 设置类页面（NavDestination + 分组信息行 + 危险操作按钮），V2 状态管理
// 退出登录镜像登录流程：ConnectionService.clear + SSEClient.disconnect + loadContent(LoginPage)
// 主题：浅色/深色/跟随系统 → ThemeService.setMode(mode, UIAbilityContext)；当前 mode 经 getThemeState().mode（@Trace）高亮
// 语言：跟随系统/中文/English → I18nService.setChoice(choice)；所有 t() 读 locale @Trace 即时随切换重渲染
// 关于：版本（bundleManager）+ 开源协议 AGPL-3.0 + GitHub 源代码（外链 startAbility）
// 通过 router_map.json 注册（SettingsPageBuilder），由 Index 的 NavPathStack.pushPath('SettingsPage') 触发

@ComponentV2
struct SettingsPage {
  @Local hubUrl: string = '';
  @Local namespace: string = '';
  @Local tokenMask: string = '';
  @Local isLoggingOut: boolean = false;
  @Local enterToSend: boolean = false;       // 回车发送（默认关；设置页 Toggle 改 + 持久化）
  @Local versionName: string = '';           // 关于：版本号（bundleManager 取）
  @Local langChoice: LanguageChoice = 'system';   // 语言选择高亮用（与 I18nService.currentChoice 同步）
  @Local voiceSheetOpen: boolean = false;          // 语音设置选择器 sheet 开关（bindSheet 双向）
  @Local voiceSheetMode: 'lang' | 'voice' = 'lang'; // 当前 sheet 内容：识别语言 / 声音
  @Local surfaceSheetOpen: boolean = false;         // 气泡配色选择器 sheet 开关（bindSheet 双向）
  @Local surfaceSheetMode: 'tool' | 'user' = 'tool'; // 当前 sheet 内容：工具组背景 / 用户消息背景
  @Local customHex: string = '';                    // 自定义 hex 输入（sheet 内 TextInput 双向）

  // 主题（读 @Trace isDark/mode 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get mode(): ThemeMode { return getThemeState().mode; }
  private get fontScaleMode(): FontScaleMode { return ThemeService.currentFontScaleMode; }

  // 切字号：纯 JS 调色板无关，无需 context（setFontScale 仅更 state.fontScale @Trace + 持久化）
  private selectFontScale(scaleMode: FontScaleMode): void {
    ThemeService.setFontScale(scaleMode);
  }

  // 切语言：setChoice 改 locale @Trace（全局 t() 重渲染）+ 持久化 choice；本地 langChoice 同步高亮
  private selectLanguage(choice: LanguageChoice): void {
    this.langChoice = choice;
    I18nService.setChoice(choice);
  }

  // 终端工具卡片显示模式（读 @Trace mode 建立刷新依赖；切换即时重渲染 ✓ 高亮）
  private get terminalToolMode(): TerminalToolDisplayMode {
    return TerminalToolDisplayService.currentMode;
  }

  // —— 语音设置（读 VoiceSettingsService @Trace；切换即时重渲染，下次进语音页生效）——
  // 当前识别语言显示名（''=自动检测）
  private get voiceLangLabel(): string {
    const lang: VoiceLanguage | null = findLanguageByCode(VoiceSettingsService.currentLang);
    if (lang === null) { return t('settings.voice.autoDetect'); }
    return getLanguageDisplayName(lang);
  }
  // 当前声音显示名（''=Hub 默认；预设 id 取本地化名）
  private get voiceIdLabel(): string {
    const id: string = VoiceSettingsService.currentVoiceId;
    if (id === '') { return t('settings.voice.hubDefault'); }
    return getPresetDisplayName(id, I18nService.locale);
  }
  // 打开选择器（mode 区分语言/声音）
  private openVoiceSheet(mode: 'lang' | 'voice'): void {
    this.voiceSheetMode = mode;
    this.voiceSheetOpen = true;
  }
  // 选识别语言：持久化 + 关 sheet（@Trace 改 → voiceLangLabel 即时刷新）
  private pickLang(code: string): void {
    VoiceSettingsService.setLang(code);
    this.voiceSheetOpen = false;
  }
  // 选声音：持久化 + 关 sheet
  private pickVoice(id: string): void {
    VoiceSettingsService.setVoice(id);
    this.voiceSheetOpen = false;
  }

  // —— 气泡配色（读 ChatSurfaceColorsService @Trace；切换即时重渲染，reapply 同步重 mix）——
  // 取色器显示色（swatch 用；default→中性灰，preset/custom→其强调色）
  private pickerColorOf(pref: ChatSurfaceColorPreference): string {
    return getPickerValue(pref);
  }
  // 偏好 → 行内短名（default→「默认」/ preset→预设名 / custom→hex 串）
  private prefDisplayName(pref: ChatSurfaceColorPreference): string {
    if (pref === 'default') { return t('settings.chat.surfaceColor.default'); }
    if (pref === 'preset:soft-blue') { return t('settings.chat.surfaceColor.softBlue'); }
    if (pref === 'preset:soft-green') { return t('settings.chat.surfaceColor.softGreen'); }
    if (pref === 'preset:soft-yellow') { return t('settings.chat.surfaceColor.softYellow'); }
    if (pref.startsWith('custom:')) { return pref.substring('custom:'.length); }
    return t('settings.chat.surfaceColor.default');
  }
  // 打开选择器（mode 区分工具组/用户消息）；customHex 预填当前 custom 值
  private openSurfaceSheet(mode: 'tool' | 'user'): void {
    this.surfaceSheetMode = mode;
    const pref: ChatSurfaceColorPreference = mode === 'tool'
      ? ChatSurfaceColorsService.currentToolGroupPref
      : ChatSurfaceColorsService.currentUserMessagePref;
    this.customHex = pref.startsWith('custom:') ? pref.substring('custom:'.length) : '#';
    this.surfaceSheetOpen = true;
  }
  // 选预设：setXxx 改 @Trace（reapply 同步重 mix + 持久化）+ 关 sheet
  private pickSurfacePreset(preset: ChatSurfaceColorPreset): void {
    const pref: ChatSurfaceColorPreference = toPresetPreference(preset);
    if (this.surfaceSheetMode === 'tool') {
      ChatSurfaceColorsService.setToolGroupBg(pref);
    } else {
      ChatSurfaceColorsService.setUserMessageBg(pref);
    }
    this.surfaceSheetOpen = false;
  }
  // 自定义 hex 输入：合法（#rrggbb）即应用 toCustomPreference（每键校验，完整 7 字符时生效一次）
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
  // 当前选项是否选中（对照 sheet 内 PickerOptionRow 高亮）
  private isSurfacePrefSelected(pref: ChatSurfaceColorPreference): boolean {
    const current: ChatSurfaceColorPreference = this.surfaceSheetMode === 'tool'
      ? ChatSurfaceColorsService.currentToolGroupPref
      : ChatSurfaceColorsService.currentUserMessagePref;
    return current === pref;
  }

  // 切终端工具卡片显示：setMode 改 mode @Trace（全量 ToolCard 重渲染）+ 持久化
  private selectTerminalToolDisplay(mode: TerminalToolDisplayMode): void {
    TerminalToolDisplayService.setMode(mode);
  }

  private navPathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    const conn = getConnectionService();
    this.hubUrl = conn.hubUrl;
    this.namespace = conn.namespace;
    this.tokenMask = this.maskToken(conn.apiToken);
    this.loadEnterToSend();
    this.langChoice = I18nService.currentChoice;
    this.loadVersionName();
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

  // 版本号（bundleManager 同步取 versionName；失败留空）
  private loadVersionName(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = '';
    }
  }

  // Token 脱敏：仅显示末 4 位
  private maskToken(token: string): string {
    if (token.length === 0) {
      return t('settings.tokenNotSet');
    }
    if (token.length <= 4) {
      return '••••';
    }
    return `••••••••${token.substring(token.length - 4)}`;
  }

  // 切主题：取宿主 UIAbilityContext 调 ThemeService.setMode（同步更新 state + setColorMode + 持久化）
  private selectTheme(mode: ThemeMode): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined || ctx === null) {
      return;
    }
    ThemeService.setMode(mode, ctx as common.UIAbilityContext);
  }

  // 退出登录确认弹窗（UIContext.showAlertDialog，对照官方 ts-methods-alert-dialog-box）
  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: t('settings.logout'),
      message: t('settings.logoutConfirm'),
      autoCancel: true,
      confirm: {
        value: t('settings.logout'),
        action: () => { this.doLogout(); }
      }
    });
  }

  // 执行退出：断 SSE + 清连接 + 切回登录页
  private async doLogout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      getSSEClient().disconnect();
      await getConnectionService().clear();
      this.switchToLogin();
    } catch (e) {
      this.isLoggingOut = false;
      showToast(t('settings.logoutFailed'));
    }
  }

  // 窗口级跳转回登录页（与 LoginPage.switchToMainContent 对称）
  private switchToLogin(): void {
    const stage = AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE);
    if (stage !== undefined) {
      stage.loadContent('pages/LoginPage');
    }
  }

  // 打开 GitHub 源代码（https 走 viewData + browsable 唤浏览器；对照 MarkdownText.openSafeLink）
  private openGitHub(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      showToast(t('common.cannotOpenLink'));
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: 'https://github.com/miuiadmin/hapi-hmos'
    };
    (hostContext as common.UIAbilityContext).startAbility(want)
      .catch((): void => { showToast(t('common.noAppToOpen')); });
  }

  // 分组标题（对照 chatcube 设置分组小标题）
  @Builder
  private SectionHeader(title: string) {
    Text(title)
      .fontSize(fs(13))
      .fontColor(this.c.textTertiary)
      .width('100%')
      .padding({ left: 16, top: 22, bottom: 8 })
  }

  // 信息行（标签 + 值，对照 chatcube 设置项 Row）
  @Builder
  private InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      Text(value)
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  // 单选行（label + 当前选中 ✓；主题/字号/语言共用）
  @Builder
  private SelectRow(label: string, selected: boolean, onSelect: () => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      if (selected) {
        Text('✓')
          .fontSize(fs(16))
          .fontColor(this.c.primary)
      }
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onSelect(); })
  }

  // 字号选项行（label + 样例预览 + 当前选中 ✓；小/默认/大三档）
  @Builder
  private FontRow(label: string, sample: string, scaleMode: FontScaleMode) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      Text(sample)
        .fontSize(fs(13))
        .fontColor(this.c.textTertiary)
        .margin({ right: 12 })
      if (this.fontScaleMode === scaleMode) {
        Text('✓')
          .fontSize(fs(16))
          .fontColor(this.c.primary)
      }
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.selectFontScale(scaleMode); })
  }

  // 开关行（label + Toggle Switch；回车发送等布尔偏好）
  @Builder
  private ToggleRow(label: string, isOn: boolean, onToggle: (isOn: boolean) => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.c.primary)
        .onChange((value: boolean) => { onToggle(value); })
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  // 语音设置项行（label + 当前值 + ›；tap 开选择器 sheet）
  @Builder
  private VoicePickerRow(label: string, value: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      Text(value)
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '55%' })
      Text('›')
        .fontSize(fs(16))
        .fontColor(this.c.textTertiary)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onTap(); })
  }

  // 选择器选项行（label + 当前选中 ✓）
  @Builder
  private PickerOptionRow(label: string, selected: boolean, onSelect: () => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      if (selected) {
        Text('✓')
          .fontSize(fs(16))
          .fontColor(this.c.primary)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onSelect(); })
  }

  // 语音设置选择器 sheet（语言/声音两态；Scroll 承载长列表，对照 ImagePreviewSheet bindSheet 范式）
  @Builder
  private VoicePickerSheet() {
    Column() {
      Row() {
        Text(this.voiceSheetMode === 'lang' ? t('settings.voice.language') : t('settings.voice.voice'))
          .fontSize(fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
        Text('✕')
          .fontSize(fs(18))
          .fontColor(this.c.textSecondary)
          .onClick(() => { this.voiceSheetOpen = false; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
      .backgroundColor(this.c.bg)

      Scroll() {
        Column() {
          if (this.voiceSheetMode === 'lang') {
            ForEach(VOICE_LANGUAGES, (lang: VoiceLanguage) => {
              this.PickerOptionRow(getLanguageDisplayName(lang),
                VoiceSettingsService.currentLang === lang.code,
                (): void => { this.pickLang(lang.code); })
            }, (lang: VoiceLanguage) => lang.code)
          } else {
            this.PickerOptionRow(t('settings.voice.hubDefault'),
              VoiceSettingsService.currentVoiceId === '',
              (): void => { this.pickVoice(''); })
            ForEach(VOICE_PRESETS, (v: VoicePreset) => {
              this.PickerOptionRow(getPresetDisplayName(v.id, I18nService.locale),
                VoiceSettingsService.currentVoiceId === v.id,
                (): void => { this.pickVoice(v.id); })
            }, (v: VoicePreset) => v.id)
          }
        }
        .width('100%')
        .backgroundColor(this.c.bg)
      }
      .layoutWeight(1)
      .backgroundColor(this.c.bg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.bg)
  }

  // 气泡配色项行（label + swatch 圆点 + 当前值短名 + ›；tap 开选择器 sheet）
  @Builder
  private SurfaceColorRow(label: string, pref: ChatSurfaceColorPreference, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      Circle({ width: 16, height: 16 })
        .fill(this.pickerColorOf(pref))
        .stroke(this.c.border)
        .strokeWidth(0.5)
        .margin({ right: 8 })
      Text(this.prefDisplayName(pref))
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '40%' })
      Text('›')
        .fontSize(fs(16))
        .fontColor(this.c.textTertiary)
        .margin({ left: 6 })
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onTap(); })
  }

  // 选择器选项行（swatch 圆点 + label + 当前选中 ✓）
  @Builder
  private SurfaceOptionRow(label: string, swatch: string, selected: boolean, onSelect: () => void) {
    Row() {
      Circle({ width: 18, height: 18 })
        .fill(swatch)
        .stroke(this.c.border)
        .strokeWidth(0.5)
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
        .margin({ left: 12 })
      if (selected) {
        Text('✓')
          .fontSize(fs(16))
          .fontColor(this.c.primary)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onSelect(); })
  }

  // 自定义 hex 输入行（swatch 预览 + 标签 + TextInput；每键校验，合法即应用）
  @Builder
  private SurfaceCustomRow() {
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
        .backgroundColor(this.c.surface)
        .borderRadius(8)
        .height(40)
        .margin({ left: 12 })
        .layoutWeight(1)
        .onChange((value: string) => { this.onCustomHexChange(value); })
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  // 气泡配色选择器 sheet（工具组/用户消息两态；4 预设 + 自定义 hex 输入）
  @Builder
  private SurfaceColorSheet() {
    Column() {
      Row() {
        Text(this.surfaceSheetMode === 'tool'
          ? t('settings.chat.surfaceColor.toolGroup')
          : t('settings.chat.surfaceColor.userMessage'))
          .fontSize(fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
        Text('✕')
          .fontSize(fs(18))
          .fontColor(this.c.textSecondary)
          .onClick(() => { this.surfaceSheetOpen = false; })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
      .backgroundColor(this.c.bg)

      Scroll() {
        Column() {
          this.SurfaceOptionRow(t('settings.chat.surfaceColor.default'),
            getPickerValue('default'),
            this.isSurfacePrefSelected('default'),
            (): void => { this.pickSurfacePreset('default'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SurfaceOptionRow(t('settings.chat.surfaceColor.softBlue'),
            getPickerValue('preset:soft-blue'),
            this.isSurfacePrefSelected('preset:soft-blue'),
            (): void => { this.pickSurfacePreset('soft-blue'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SurfaceOptionRow(t('settings.chat.surfaceColor.softGreen'),
            getPickerValue('preset:soft-green'),
            this.isSurfacePrefSelected('preset:soft-green'),
            (): void => { this.pickSurfacePreset('soft-green'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SurfaceOptionRow(t('settings.chat.surfaceColor.softYellow'),
            getPickerValue('preset:soft-yellow'),
            this.isSurfacePrefSelected('preset:soft-yellow'),
            (): void => { this.pickSurfacePreset('soft-yellow'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SurfaceCustomRow()
        }
        .width('100%')
        .backgroundColor(this.c.bg)
      }
      .layoutWeight(1)
      .backgroundColor(this.c.bg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.bg)
  }

  // 自定义 hex 预览 swatch（合法→归一化色；非法→中性灰 placeholder）
  private customSwatch(): string {
    const normalized: string | null = normalizeHexColor(this.customHex);
    return normalized !== null ? normalized : getPickerValue('default');
  }

  build() {
    NavDestination() {
      Column() {
        // 主题分组（浅色/深色/跟随系统）
        this.SectionHeader(t('settings.section.theme'))
        Column() {
          this.SelectRow(t('settings.theme.light'), this.mode === 'light', (): void => { this.selectTheme('light'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SelectRow(t('settings.theme.dark'), this.mode === 'dark', (): void => { this.selectTheme('dark'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SelectRow(t('settings.theme.system'), this.mode === 'system', (): void => { this.selectTheme('system'); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 字号分组（小/默认/大；全量 fontSize 经 fs() 缩放，切换即时生效）
        this.SectionHeader(t('settings.section.fontSize'))
        Column() {
          this.FontRow(t('settings.fontSize.small'), 'Aa', 'small')
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.FontRow(t('settings.fontSize.default'), 'Aa', 'default')
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.FontRow(t('settings.fontSize.large'), 'Aa', 'large')
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 语言分组（跟随系统/中文/English）
        this.SectionHeader(t('settings.section.language'))
        Column() {
          this.SelectRow(t('settings.language.system'), this.langChoice === 'system', (): void => { this.selectLanguage('system'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SelectRow(t('settings.language.zhCN'), this.langChoice === 'zh-CN', (): void => { this.selectLanguage('zh-CN'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SelectRow(t('settings.language.en'), this.langChoice === 'en', (): void => { this.selectLanguage('en'); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 输入分组（回车发送开关，默认关：Enter=换行多行输入；开=Enter 直接发送）
        this.SectionHeader(t('settings.section.input'))
        Column() {
          this.ToggleRow(t('settings.enterToSend'), this.enterToSend, (v: boolean): void => { this.saveEnterToSend(v); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 终端工具卡片分组（compact 仅 header 降噪 / detailed 内联命令预览；对照上游 settings.chat.terminalToolDisplay）
        this.SectionHeader(t('settings.chat.terminalToolDisplay'))
        Column() {
          this.SelectRow(t('settings.chat.terminalToolDisplay.compact'), this.terminalToolMode === 'compact', (): void => { this.selectTerminalToolDisplay('compact'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SelectRow(t('settings.chat.terminalToolDisplay.detailed'), this.terminalToolMode === 'detailed', (): void => { this.selectTerminalToolDisplay('detailed'); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 语音分组（识别语言 + 声音；tap 开 sheet 选择器，对照上游 voice 设置。下次进语音页生效）
        this.SectionHeader(t('settings.voice.title'))
        Column() {
          this.VoicePickerRow(t('settings.voice.language'), this.voiceLangLabel, (): void => { this.openVoiceSheet('lang'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.VoicePickerRow(t('settings.voice.voice'), this.voiceIdLabel, (): void => { this.openVoiceSheet('voice'); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)
        .bindSheet(this.voiceSheetOpen!!, this.VoicePickerSheet(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          backgroundColor: this.c.bg,
          onDisappear: () => { this.voiceSheetOpen = false; }
        })

        // 气泡配色分组（工具组背景 + 用户消息背景；tap 开 sheet 选择器，对照上游 useChatSurfaceColors）
        this.SectionHeader(t('settings.chat.surfaceColor'))
        Column() {
          this.SurfaceColorRow(t('settings.chat.surfaceColor.toolGroup'),
            ChatSurfaceColorsService.currentToolGroupPref,
            (): void => { this.openSurfaceSheet('tool'); })
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.SurfaceColorRow(t('settings.chat.surfaceColor.userMessage'),
            ChatSurfaceColorsService.currentUserMessagePref,
            (): void => { this.openSurfaceSheet('user'); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)
        .bindSheet(this.surfaceSheetOpen!!, this.SurfaceColorSheet(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          backgroundColor: this.c.bg,
          onDisappear: () => { this.surfaceSheetOpen = false; }
        })

        // 连接信息分组
        this.SectionHeader(t('settings.section.connection'))
        Column() {
          this.InfoRow(t('settings.hubUrl'), this.hubUrl)
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.InfoRow(t('settings.namespace'), this.namespace)
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.InfoRow(t('settings.accessToken'), this.tokenMask)
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 说明
        Text(t('settings.connectionHint'))
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .padding({ left: 16, top: 10 })

        // 关于分组（版本 + 开源协议 + GitHub 源代码）
        this.SectionHeader(t('settings.section.about'))
        Column() {
          this.InfoRow(t('settings.about.version'), this.versionName)
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          this.InfoRow(t('settings.about.license'), t('settings.about.licenseValue'))
          Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 16 })
          Row() {
            Text(t('settings.about.sourceCode'))
              .fontSize(fs(15))
              .fontColor(this.c.textPrimary)
              .layoutWeight(1)
            Text(t('settings.about.sourceCodeValue'))
              .fontSize(fs(14))
              .fontColor(this.c.primary)
          }
          .width('100%')
          .height(54)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.openGitHub(); })
        }
        .width('100%')
        .backgroundColor(this.c.bg)

        // 退出登录（危险操作，线框红字）
        Button(this.isLoggingOut ? t('settings.loggingOut') : t('settings.logout'))
          .width('100%')
          .height(50)
          .margin({ top: 32, left: 16, right: 16 })
          .backgroundColor(this.c.bg)
          .fontColor(this.c.error)
          .borderRadius(12)
          .enabled(!this.isLoggingOut)
          .onClick(() => this.confirmLogout())
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.c.surface)
    }
    .title(t('settings.title'))
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}
