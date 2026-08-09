// 语音设置子页（识别语言 / 声音）—— tap 开 sheet 选择器。
// 逻辑从旧 SettingsPage 迁移：voiceLangLabel / voiceIdLabel / openVoiceSheet / pickLang / pickVoice。
// 单分组（无 SectionTitle，顶部 List padding 留白）。VoicePickerSheet 走 berry3 弹窗设计系统：
//   SheetDialog 统一标题栏 + 白身(c.bg) + SettingCard(cardBackground) 灰卡浮白底选择器项。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t, getI18nState } from '../../i18n/I18nService';
import { VoiceSettingsService } from '../../services/VoiceSettingsService';
import { VOICE_LANGUAGES, VoiceLanguage, findLanguageByCode, getLanguageDisplayName } from '../../chat/VoiceLanguages';
import { VOICE_PRESETS, VoicePreset, getPresetDisplayName } from '../../chat/VoiceVoices';
import { SettingCard } from '../../components/settings/SettingCard';
import { SheetDialog } from '../../components/settings/SheetDialog';
import { buildSheetOptions, SheetOverrides } from '../../components/settings/SheetOptionsFactory';
import { HdsNavDestination, HdsNavDestinationTitleMode, TitleBarStyleOptions, DividerShowType } from '@kit.UIDesignKit';
import { getLayoutState } from '../../state/LayoutState';
import { hdsTitleBarStyle } from '../../components/HdsTitleBarStyle';
import { getHubClient } from '../../api/HubClient';
import { getConnectionService } from '../../services/ConnectionService';
import { DEFAULT_NAMESPACE } from '../../models/HubConfig';
import { HapticService } from '../../services/HapticService';
import { showToast } from '../../utils/Toast';
import { TranscriptionCredentialStatus, MaskedCredentialStatus } from '../../models/Types';

interface CredProvider {
  key: string;          // 'openai' | 'elevenlabs' | 'deepgram' | 'groq' | 'openaiCompatible' | 'geminiLive' | 'qwenRealtime'
  labelKey: string;     // i18n key
  compatible: boolean;  // openaiCompatible 多 baseUrl/model/apiKey 字段
}

const CRED_PROVIDERS: CredProvider[] = [
  { key: 'openai', labelKey: 'settings.voice.credentials.openai', compatible: false },
  { key: 'elevenlabs', labelKey: 'settings.voice.credentials.elevenlabs', compatible: false },
  { key: 'deepgram', labelKey: 'settings.voice.credentials.deepgram', compatible: false },
  { key: 'groq', labelKey: 'settings.voice.credentials.groq', compatible: false },
  { key: 'openaiCompatible', labelKey: 'settings.voice.credentials.openaiCompatible', compatible: true },
  { key: 'geminiLive', labelKey: 'settings.voice.credentials.geminiLive', compatible: false },
  { key: 'qwenRealtime', labelKey: 'settings.voice.credentials.qwenRealtime', compatible: false }
];

@Builder
export function VoiceSettingsPageBuilder(name: string, param: Object) {
  VoiceSettingsPage()
}

@ComponentV2
struct VoiceSettingsPage {
  @Local voiceSheetOpen: boolean = false;
  @Local voiceSheetMode: 'lang' | 'voice' = 'lang';
  // 凭证区（owner-gated，镜像上游 TranscriptionProviderOnboard）
  @Local isOwner: boolean = false;
  @Local creds: TranscriptionCredentialStatus = new TranscriptionCredentialStatus();
  @Local credsLoading: boolean = false;
  @Local credsError: string = '';
  @Local credSheetOpen: boolean = false;          // 凭证编辑 sheet
  @Local editingKey: string = '';                 // 当前编辑的 provider key
  @Local saving: boolean = false;
  @Local editApiKey: string = '';
  @Local editBaseUrl: string = '';
  @Local editModel: string = '';
  private navPathStack: NavPathStack | null = null;

  aboutToAppear(): void {
    this.isOwner = getConnectionService().namespace === DEFAULT_NAMESPACE;
    if (this.isOwner) { this.loadCredentials(); }
  }

  private async loadCredentials(): Promise<void> {
    this.credsLoading = true;
    this.credsError = '';
    try {
      this.creds = await getHubClient().fetchTranscriptionCredentials();
    } catch (e) {
      this.credsError = t('settings.voice.credentials.loadFailed');
    } finally {
      this.credsLoading = false;
    }
  }

  // 取某 provider 的展示态（openaiCompatible 合成 MaskedCredentialStatus）
  private statusOf(key: string): MaskedCredentialStatus {
    const c = this.creds;
    if (key === 'openai') { return c.openai; }
    if (key === 'elevenlabs') { return c.elevenlabs; }
    if (key === 'deepgram') { return c.deepgram; }
    if (key === 'groq') { return c.groq; }
    if (key === 'geminiLive') { return c.geminiLive; }
    if (key === 'qwenRealtime') { return c.qwenRealtime; }
    if (key === 'openaiCompatible') {
      const m: MaskedCredentialStatus = new MaskedCredentialStatus();
      m.configured = c.openaiCompatible.configured;
      m.source = c.openaiCompatible.source;
      m.hint = c.openaiCompatible.apiKey.hint;
      m.editable = c.openaiCompatible.baseUrlEditable || c.openaiCompatible.modelEditable || c.openaiCompatible.apiKey.editable;
      return m;
    }
    return new MaskedCredentialStatus();
  }

  // 状态文案：已配置显示来源+脱敏 hint；未配置显示「未配置」
  private providerSuffix(key: string): string {
    const m = this.statusOf(key);
    if (!m.configured) { return t('settings.voice.credentials.notConfigured'); }
    const src: string = m.source === 'env' ? t('settings.voice.credentials.sourceEnv')
      : m.source === 'settings' ? t('settings.voice.credentials.sourceSettings') : '';
    if (m.hint !== '') { return src !== '' ? `${src} · ${m.hint}` : m.hint; }
    return src !== '' ? src : t('settings.voice.credentials.configured');
  }

  private openCredEditor(p: CredProvider): void {
    if (this.saving) { return; }
    this.editingKey = p.key;
    this.editApiKey = '';
    if (p.compatible) {
      this.editBaseUrl = this.creds.openaiCompatible.baseUrl;
      this.editModel = this.creds.openaiCompatible.model;
    } else {
      this.editBaseUrl = '';
      this.editModel = '';
    }
    this.credSheetOpen = true;
  }

  // 构造 PUT body（sparse Record）：string=设置，null=清除，省略=不变
  //   值用 Object | null（ArkTS Object 非空，须显式 null 联合才能承载「清除」语义）
  private buildCredBody(clear: boolean): Record<string, Object | null> {
    const body: Record<string, Object | null> = {};
    const key = this.editingKey;
    if (key === '') { return body; }
    if (key === 'openaiCompatible') {
      const compat: Record<string, Object | null> = {};
      const c = this.creds.openaiCompatible;
      if (clear) {
        if (c.baseUrlEditable) { compat['baseUrl'] = null; }
        if (c.modelEditable) { compat['model'] = null; }
        if (c.apiKey.editable) { compat['apiKey'] = null; }
      } else {
        const b = this.editBaseUrl.trim();
        const mo = this.editModel.trim();
        const ak = this.editApiKey.trim();
        if (c.baseUrlEditable && b !== '') { compat['baseUrl'] = b; }
        if (c.modelEditable && mo !== '') { compat['model'] = mo; }
        if (c.apiKey.editable && ak !== '') { compat['apiKey'] = ak; }
      }
      body['openaiCompatible'] = compat;
    } else {
      if (clear) {
        body[key] = null;
      } else {
        const ak = this.editApiKey.trim();
        if (ak !== '') { body[key] = ak; }
      }
    }
    return body;
  }

  private async applyCredUpdate(clear: boolean): Promise<void> {
    if (this.editingKey === '' || this.saving) { return; }
    this.saving = true;
    try {
      const next = await getHubClient().updateTranscriptionCredentials(this.buildCredBody(clear));
      if (next.error !== '') {
        showToast(next.error);
      } else {
        this.creds = next;
        HapticService.tap('success');
        this.credSheetOpen = false;
        this.editingKey = '';
      }
    } catch (e) {
      showToast(t('settings.voice.credentials.updateFailed'));
    } finally {
      this.saving = false;
    }
  }

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  // HDS 液态 titleBar：scroller 联动滚动磨砂 + style 随主题（c.bg）刷新（对照 ChatPage/berry3 设置页范式）
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

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
    return getPresetDisplayName(id, getI18nState().locale);
  }

  private openVoiceSheet(mode: 'lang' | 'voice'): void {
    this.voiceSheetMode = mode;
    this.voiceSheetOpen = true;
  }
  private pickLang(code: string): void {
    VoiceSettingsService.setLang(code);
    this.voiceSheetOpen = false;
  }
  private pickVoice(id: string): void {
    VoiceSettingsService.setVoice(id);
    this.voiceSheetOpen = false;
  }

  // VoicePickerSheet 的 bindSheet 视觉配置：白身(c.bg) + 毛玻璃 + 无把手 + LARGE 档。
  // 覆写参数用具名 interface 标注的 const 承接（ArkTS 严格模式禁传参对象字面量）。
  private get voiceSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.LARGE],
      onDisappear: () => { this.voiceSheetOpen = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
  }

  // 凭证编辑 sheet 视觉配置（同白身 LARGE 档；独立 sheetOpen flag）
  private get credSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.LARGE],
      onDisappear: () => { this.credSheetOpen = false; this.editingKey = ''; }
    };
    return buildSheetOptions(this.c.bg, ov);
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（HdsNavDestination ignoreLayoutSafeArea 后内容从 y=0 起；+56 titleBar 高 +8 间距）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.voice.language'),
              suffixText: this.voiceLangLabel, suffixType: 'textAndArrow', rowPosition: 'first',
              onItemClick: () => { this.openVoiceSheet('lang'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.voice.voice'),
              suffixText: this.voiceIdLabel, suffixType: 'textAndArrow', rowPosition: 'last',
              onItemClick: () => { this.openVoiceSheet('voice'); }
            })
          }
        }
        .divider({
          strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
          startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
        })
        .backgroundColor(this.c.bg)
        .borderRadius($r('app.float.setting_card_radius'))
        .clip(true)

        // 凭证区（owner-gated；镜像上游 TranscriptionProviderOnboard）
        if (this.isOwner) {
          ListItemGroup({ header: this.CredentialsHeader() }) {
            if (this.credsLoading) {
              ListItem() {
                SettingCard({
                  primaryText: t('settings.voice.credentials.loading'),
                  suffixType: 'loading', rowPosition: 'single'
                })
              }
            } else if (this.credsError !== '') {
              ListItem() {
                SettingCard({
                  primaryText: this.credsError, suffixType: 'none',
                  suffixText: t('settings.voice.credentials.retry'), rowPosition: 'single',
                  onItemClick: () => { this.loadCredentials(); }
                })
              }
            } else {
              ForEach(CRED_PROVIDERS, (p: CredProvider, idx: number) => {
                ListItem() {
                  SettingCard({
                    primaryText: t(p.labelKey),
                    suffixText: this.providerSuffix(p.key),
                    suffixType: 'textAndArrow',
                    rowPosition: idx === 0 ? 'first' : (idx === CRED_PROVIDERS.length - 1 ? 'last' : 'middle'),
                    onItemClick: () => { this.openCredEditor(p); }
                  })
                }
              }, (p: CredProvider) => p.key)
            }
          }
          .divider({
            strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
            startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
          })
          .backgroundColor(this.c.bg)
          .borderRadius($r('app.float.setting_card_radius'))
          .clip(true)
        }

        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
      .bindSheet(this.voiceSheetOpen!!, this.VoicePickerSheet(), this.voiceSheetOpts)

      // 凭证编辑 sheet 独立 0×0 锚点（同节点叠多 bindSheet 仅一个生效，须独立节点）
      Row().width(0).height(0)
        .bindSheet(this.credSheetOpen!!, this.CredentialEditor(), this.credSheetOpts)
      }
    }
    .titleBar({
      content: {
        title: { mainTitle: t('settings.voice.title') },
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

  // 语音设置选择器 sheet（语言/声音两态）—— berry3 弹窗设计系统：
  //   SheetDialog 统一标题栏（白头）+ 白身(c.bg，由 bindSheet 提供) + SettingCard 灰卡浮白底选择器项。
  //   根 Column 不设底色（透 bindSheet 白身）；标题栏 SheetDialog 自带 c.bg 白头。
  @Builder VoicePickerSheet() {
    Column() {
      SheetDialog({
        title: this.voiceSheetMode === 'lang' ? t('settings.voice.language') : t('settings.voice.voice'),
        showCloseButton: true,
        onClose: () => { this.voiceSheetOpen = false; }
      })
      Scroll() {
        Column({ space: 12 }) {
          if (this.voiceSheetMode === 'lang') {
            ForEach(VOICE_LANGUAGES, (lang: VoiceLanguage) => {
              SettingCard({
                primaryText: getLanguageDisplayName(lang),
                suffixType: 'check',
                isChecked: VoiceSettingsService.currentLang === lang.code,
                rowPosition: 'single',
                cardBackground: true,
                onItemClick: (): void => { this.pickLang(lang.code); }
              })
            }, (lang: VoiceLanguage) => lang.code)
          } else {
            SettingCard({
              primaryText: t('settings.voice.hubDefault'),
              suffixType: 'check',
              isChecked: VoiceSettingsService.currentVoiceId === '',
              rowPosition: 'single',
              cardBackground: true,
              onItemClick: (): void => { this.pickVoice(''); }
            })
            ForEach(VOICE_PRESETS, (v: VoicePreset) => {
              SettingCard({
                primaryText: getPresetDisplayName(v.id, getI18nState().locale),
                suffixType: 'check',
                isChecked: VoiceSettingsService.currentVoiceId === v.id,
                rowPosition: 'single',
                cardBackground: true,
                onItemClick: (): void => { this.pickVoice(v.id); }
              })
            }, (v: VoicePreset) => v.id)
          }
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

  // —— 凭证编辑 sheet 用的派生态 ——
  private get editingLabel(): string {
    for (let i = 0; i < CRED_PROVIDERS.length; i++) {
      if (CRED_PROVIDERS[i].key === this.editingKey) { return t(CRED_PROVIDERS[i].labelKey); }
    }
    return '';
  }
  private get editingIsCompatible(): boolean { return this.editingKey === 'openaiCompatible'; }
  private get editingEditable(): boolean {
    if (this.editingKey === '') { return false; }
    return this.statusOf(this.editingKey).editable;
  }
  private get editingConfigured(): boolean {
    if (this.editingKey === '') { return false; }
    return this.statusOf(this.editingKey).configured;
  }
  private get apiKeyPlaceholder(): string {
    const hint = this.statusOf(this.editingKey).hint;
    return hint !== '' ? hint : t('settings.voice.credentials.apiKeyPlaceholder');
  }

  @Builder CredentialsHeader() {
    Column() {
      Text(t('settings.voice.credentials.title'))
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .margin({ left: 16, right: 16, bottom: 6, top: 14 })
      Text(t('settings.voice.credentials.manageHint'))
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
        .margin({ left: 16, right: 16, bottom: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 凭证编辑 sheet（镜像上游 TranscriptionProviderOnboard 的编辑表单）
  @Builder CredentialEditor() {
    Column() {
      SheetDialog({
        title: this.editingLabel,
        showCloseButton: true,
        onClose: () => { this.credSheetOpen = false; this.editingKey = ''; }
      })
      Scroll() {
        Column({ space: 14 }) {
          if (this.editingKey !== '') {
            // 环境变量锁定 → 不可在此修改
            if (!this.editingEditable) {
              Text(t('settings.voice.credentials.envLocked'))
                .fontSize(fs(14))
                .fontColor(this.c.textSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding({ left: 4, right: 4, top: 4 })
            } else {
              // openaiCompatible：baseUrl / model（仅各自可编辑时显示）
              if (this.editingIsCompatible) {
                if (this.creds.openaiCompatible.baseUrlEditable) {
                  this.FieldLabel(t('settings.voice.credentials.baseUrl'))
                  TextInput({ text: this.editBaseUrl, placeholder: 'https://...' })
                    .fontSize(fs(15))
                    .fontColor(this.c.textPrimary)
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .width('100%')
                    .onChange((v: string) => { this.editBaseUrl = v; })
                }
                if (this.creds.openaiCompatible.modelEditable) {
                  this.FieldLabel(t('settings.voice.credentials.model'))
                  TextInput({ text: this.editModel, placeholder: 'gpt-4o-transcribe' })
                    .fontSize(fs(15))
                    .fontColor(this.c.textPrimary)
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .width('100%')
                    .onChange((v: string) => { this.editModel = v; })
                }
                if (this.creds.openaiCompatible.apiKey.editable) {
                  this.FieldLabel(t('settings.voice.credentials.apiKey'))
                  TextInput({ text: this.editApiKey, placeholder: this.apiKeyPlaceholder })
                    .fontSize(fs(15))
                    .fontColor(this.c.textPrimary)
                    .backgroundColor(this.c.surface)
                    .borderRadius(10)
                    .width('100%')
                    .type(InputType.Password)
                    .onChange((v: string) => { this.editApiKey = v; })
                }
              } else {
                this.FieldLabel(t('settings.voice.credentials.apiKey'))
                TextInput({ text: this.editApiKey, placeholder: this.apiKeyPlaceholder })
                  .fontSize(fs(15))
                  .fontColor(this.c.textPrimary)
                  .backgroundColor(this.c.surface)
                  .borderRadius(10)
                  .width('100%')
                  .type(InputType.Password)
                  .onChange((v: string) => { this.editApiKey = v; })
              }
              // 操作按钮：清除（已配置时）+ 保存
              Row({ space: 12 }) {
                if (this.editingConfigured) {
                  Button(t('settings.voice.credentials.clear'))
                    .fontSize(fs(15))
                    .fontColor(this.c.textPrimary)
                    .backgroundColor(this.c.surface)
                    .borderRadius(20)
                    .layoutWeight(1)
                    .enabled(!this.saving)
                    .onClick(() => { this.applyCredUpdate(true); })
                }
                Button(this.saving ? t('settings.voice.credentials.saving') : t('settings.voice.credentials.save'))
                  .fontSize(fs(15))
                  .fontColor('#FFFFFFFF')
                  .backgroundColor(this.c.primary)
                  .borderRadius(20)
                  .layoutWeight(1)
                  .enabled(!this.saving)
                  .onClick(() => { this.applyCredUpdate(false); })
              }
              .width('100%')
              .margin({ top: 8 })
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  @Builder FieldLabel(label: string) {
    Text(label)
      .fontSize(fs(13))
      .fontColor(this.c.textSecondary)
      .margin({ left: 4, bottom: 6, top: 6 })
      .width('100%')
  }
}
