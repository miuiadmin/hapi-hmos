// 显示设置子页（主题 / 字号 / 语言）—— 对照 berry3 设置子页骨架（List + ListItemGroup + SettingCard）。
// 逻辑从旧 SettingsPage 迁移：selectTheme / selectFontScale / selectLanguage（语义不变，UI 用 SettingCard）。
// 单选用 SettingCard suffixType='check' 成员行（iOS 设置单选范式，选中显示 checkmark）。
import { common } from '@kit.AbilityKit';
import { paletteOf, PaletteColors, getThemeState, ThemeService, ThemeMode, FontScaleMode } from '../../theme/ThemeService';
import { t, I18nService, LanguageChoice } from '../../i18n/I18nService';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';

@Builder
export function DisplaySettingsPageBuilder(name: string, param: Object) {
  DisplaySettingsPage()
}

@ComponentV2
struct DisplaySettingsPage {
  @Local langChoice: LanguageChoice = 'system';
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private get mode(): ThemeMode { return getThemeState().mode; }
  private get fontScaleMode(): FontScaleMode { return ThemeService.currentFontScaleMode; }

  aboutToAppear(): void {
    this.langChoice = I18nService.currentChoice;
  }

  // 切主题：取宿主 UIAbilityContext 调 ThemeService.setMode（同步更新 state + setColorMode + 持久化）
  private selectTheme(mode: ThemeMode): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined || ctx === null) {
      return;
    }
    ThemeService.setMode(mode, ctx as common.UIAbilityContext);
  }

  // 切字号：setFontScale 仅更 state.fontScale @Trace + 持久化
  private selectFontScale(scaleMode: FontScaleMode): void {
    ThemeService.setFontScale(scaleMode);
  }

  // 切语言：setChoice 改 locale @Trace（全局 t() 重渲染）+ 持久化；本地 langChoice 同步高亮
  private selectLanguage(choice: LanguageChoice): void {
    this.langChoice = choice;
    I18nService.setChoice(choice);
  }

  build() {
    NavDestination() {
      List({ space: 12 }) {
        // ── 主题 ──
        ListItem() {
          SettingSectionTitle({ text: t('settings.section.theme') })
        }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.theme.light'), suffixType: 'check',
              isChecked: this.mode === 'light', rowPosition: 'first',
              onItemClick: () => { this.selectTheme('light'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.theme.dark'), suffixType: 'check',
              isChecked: this.mode === 'dark', rowPosition: 'middle',
              onItemClick: () => { this.selectTheme('dark'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.theme.system'), suffixType: 'check',
              isChecked: this.mode === 'system', rowPosition: 'last',
              onItemClick: () => { this.selectTheme('system'); }
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

        // ── 字号 ──
        ListItem() {
          SettingSectionTitle({ text: t('settings.section.fontSize') })
        }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.fontSize.small'), suffixType: 'check',
              isChecked: this.fontScaleMode === 'small', rowPosition: 'first',
              onItemClick: () => { this.selectFontScale('small'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.fontSize.default'), suffixType: 'check',
              isChecked: this.fontScaleMode === 'default', rowPosition: 'middle',
              onItemClick: () => { this.selectFontScale('default'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.fontSize.large'), suffixType: 'check',
              isChecked: this.fontScaleMode === 'large', rowPosition: 'last',
              onItemClick: () => { this.selectFontScale('large'); }
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

        // ── 语言 ──
        ListItem() {
          SettingSectionTitle({ text: t('settings.section.language') })
        }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.language.system'), suffixType: 'check',
              isChecked: this.langChoice === 'system', rowPosition: 'first',
              onItemClick: () => { this.selectLanguage('system'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.language.zhCN'), suffixType: 'check',
              isChecked: this.langChoice === 'zh-CN', rowPosition: 'middle',
              onItemClick: () => { this.selectLanguage('zh-CN'); }
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.language.en'), suffixType: 'check',
              isChecked: this.langChoice === 'en', rowPosition: 'last',
              onItemClick: () => { this.selectLanguage('en'); }
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
        top: 4, bottom: 0,
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
    }
    .title(t('settings.display.title'))
    .backgroundColor(this.c.surface)
    .onReady((context: NavDestinationContext) => { this.navPathStack = context.pathStack; })
    .onBackPressed(() => { this.navPathStack?.pop(); return true; })
  }
}
