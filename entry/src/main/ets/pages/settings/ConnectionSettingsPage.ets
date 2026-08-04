// 连接信息子页（Hub URL / 命名空间 / 访问令牌）—— 对照 berry3 设置子页骨架。
// 逻辑从旧 SettingsPage 迁移：aboutToAppear 读 ConnectionService + maskToken（语义不变）。
// 只读信息行用 SettingCard suffixType='none'（primaryText=标签 + secondaryText=值，竖排）。
import { paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t } from '../../i18n/I18nService';
import { getConnectionService } from '../../services/ConnectionService';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';
import { SettingFooter } from '../../components/settings/SettingFooter';
import { HdsNavDestination, HdsNavDestinationTitleMode, TitleBarStyleOptions, DividerShowType } from '@kit.UIDesignKit';
import { getLayoutState } from '../../state/LayoutState';
import { hdsTitleBarStyle } from '../../components/HdsTitleBarStyle';

@Builder
export function ConnectionSettingsPageBuilder(name: string, param: Object) {
  ConnectionSettingsPage()
}

@ComponentV2
struct ConnectionSettingsPage {
  @Local hubUrl: string = '';
  @Local namespace: string = '';
  @Local tokenMask: string = '';
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  // HDS 液态 titleBar：scroller 联动滚动磨砂 + style 随主题（c.bg）刷新（对照 ChatPage/berry3 设置页范式）
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

  aboutToAppear(): void {
    const conn = getConnectionService();
    this.hubUrl = conn.hubUrl;
    this.namespace = conn.namespace;
    this.tokenMask = this.maskToken(conn.apiToken);
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

  build() {
    HdsNavDestination() {
      List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（HdsNavDestination ignoreLayoutSafeArea 后内容从 y=0 起；+56 titleBar 高 +8 间距）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)
        // ── 连接信息 ──
        ListItem() {
          SettingSectionTitle({ text: t('settings.section.connection') })
        }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.hubUrl'), secondaryText: this.hubUrl,
              suffixType: 'none', clickable: false, rowPosition: 'first'
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.namespace'), secondaryText: this.namespace,
              suffixType: 'none', clickable: false, rowPosition: 'middle'
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.accessToken'), secondaryText: this.tokenMask,
              suffixType: 'none', clickable: false, rowPosition: 'last'
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

        // 说明
        ListItem() {
          SettingFooter({ text: t('settings.connectionHint') })
        }

        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: t('settings.connection.title') },
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
}
