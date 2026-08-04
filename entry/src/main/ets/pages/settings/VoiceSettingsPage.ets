// 语音设置子页（识别语言 / 声音）—— tap 开 sheet 选择器。
// 逻辑从旧 SettingsPage 迁移：voiceLangLabel / voiceIdLabel / openVoiceSheet / pickLang / pickVoice。
// 单分组（无 SectionTitle，顶部 List padding 留白），VoicePickerSheet 内部保留 PickerOptionRow 自定义行。
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t, getI18nState } from '../../i18n/I18nService';
import { VoiceSettingsService } from '../../services/VoiceSettingsService';
import { VOICE_LANGUAGES, VoiceLanguage, findLanguageByCode, getLanguageDisplayName } from '../../chat/VoiceLanguages';
import { VOICE_PRESETS, VoicePreset, getPresetDisplayName } from '../../chat/VoiceVoices';
import { SettingCard } from '../../components/settings/SettingCard';

@Builder
export function VoiceSettingsPageBuilder(name: string, param: Object) {
  VoiceSettingsPage()
}

@ComponentV2
struct VoiceSettingsPage {
  @Local voiceSheetOpen: boolean = false;
  @Local voiceSheetMode: 'lang' | 'voice' = 'lang';
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

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

  build() {
    NavDestination() {
      List({ space: 12 }) {
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

        ListItem() { Row().height(24) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({
        top: 12, bottom: 0,
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
      .bindSheet(this.voiceSheetOpen!!, this.VoicePickerSheet(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.LARGE],
        backgroundColor: this.c.bg,
        onDisappear: () => { this.voiceSheetOpen = false; }
      })
    }
    .title(t('settings.voice.title'))
    .backgroundColor(this.c.surface)
    .onReady((context: NavDestinationContext) => { this.navPathStack = context.pathStack; })
    .onBackPressed(() => { this.navPathStack?.pop(); return true; })
  }

  // 语音设置选择器 sheet（语言/声音两态；Scroll 承载长列表）
  @Builder VoicePickerSheet() {
    Column() {
      Row() {
        Text(this.voiceSheetMode === 'lang' ? t('settings.voice.language') : t('settings.voice.voice'))
          .fontSize(fs(16))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(fs(18))
          .fontColor([this.c.textSecondary])
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
              this.PickerOptionRow(getPresetDisplayName(v.id, getI18nState().locale),
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

  // 选择器选项行（label + 当前选中 ✓）
  @Builder PickerOptionRow(label: string, selected: boolean, onSelect: () => void) {
    Row() {
      Text(label)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      if (selected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(fs(16))
          .fontColor([this.c.primary])
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onSelect(); })
  }
}
