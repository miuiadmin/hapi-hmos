// 语音设置子页（识别语言 / 声音）—— tap 开 sheet 选择器。
// 逻辑从旧 SettingsPage 迁移：voiceLangLabel / voiceIdLabel / openVoiceSheet / pickLang / pickVoice。
// 单分组（无 SectionTitle，顶部 List padding 留白）。VoicePickerSheet 走 berry3 弹窗设计系统：
//   SheetDialog 统一标题栏 + 白身(c.bg) + SettingCard(cardBackground) 灰卡浮白底选择器项。
import { paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t, getI18nState } from '../../i18n/I18nService';
import { VoiceSettingsService } from '../../services/VoiceSettingsService';
import { VOICE_LANGUAGES, VoiceLanguage, findLanguageByCode, getLanguageDisplayName } from '../../chat/VoiceLanguages';
import { VOICE_PRESETS, VoicePreset, getPresetDisplayName } from '../../chat/VoiceVoices';
import { SettingCard } from '../../components/settings/SettingCard';
import { SheetDialog } from '../../components/settings/SheetDialog';
import { buildSheetOptions, SheetOverrides } from '../../components/settings/SheetOptionsFactory';

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

  // VoicePickerSheet 的 bindSheet 视觉配置：白身(c.bg) + 毛玻璃 + 无把手 + LARGE 档。
  // 覆写参数用具名 interface 标注的 const 承接（ArkTS 严格模式禁传参对象字面量）。
  private get voiceSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.LARGE],
      onDisappear: () => { this.voiceSheetOpen = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
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
      .bindSheet(this.voiceSheetOpen!!, this.VoicePickerSheet(), this.voiceSheetOpts)
    }
    .title(t('settings.voice.title'))
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
}
