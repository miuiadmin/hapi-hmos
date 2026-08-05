// 设置主页（入口列表，对照 berry3 SettingsPage）—— iOS 设置范式。
// 数据驱动：ALL_ITEMS 三分组（通用 / 连接 / 关于），每行莫兰迪彩色图标方块 + 标题 + chevron。
// 顶部 SettingSearchBar 受控过滤（标题/副标题模糊匹配，无结果显示空态）。
// 点击 pushPathByName 跳对应子页（router_map.json 注册）。
// 底部退出登录 SettingActionButton danger（镜像登录流程：断 SSE + 清连接 + loadContent(LoginPage)）。
// 颜色走 JS 调色板（paletteOf(isDark)）；图标方块色走莫兰迪 JS 色板（morandiSwatch）。
import { bundleManager } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { getLayoutState } from '../state/LayoutState';
import { hdsTitleBarStyle } from '../components/HdsTitleBarStyle';
import { t } from '../i18n/I18nService';
import { getConnectionService } from '../services/ConnectionService';
import { DEFAULT_NAMESPACE } from '../models/HubConfig';
import { getJwtRefreshScheduler } from '../services/JwtRefreshScheduler';
import { getSSEClient } from '../api/SSEClient';
import { AppStorageKeys } from '../config/Keys';
import { showToast } from '../utils/Toast';
import { SettingCard } from '../components/settings/SettingCard';
import { SettingSectionTitle } from '../components/settings/SettingSectionTitle';
import { SettingSearchBar } from '../components/settings/SettingSearchBar';
import { SettingActionButton } from '../components/settings/SettingActionButton';
import { rowPos } from '../components/settings/RowRadiusUtil';
import { MorandiKey, morandiSwatch } from '../components/settings/MorandiPalette';
import { ConfirmSheet, SheetButton } from '../components/settings/ConfirmSheet';
import { buildSheetOptions, SheetOverrides } from '../components/settings/SheetOptionsFactory';

// 入口项（具名 interface 标注，满足 ArkTS 严格模式对象字面量规则）
interface SettingsEntry {
  key: string;
  title: string;
  subtitle: string;
  symbol: Resource;
  morandi: MorandiKey;
  target: string;
}
// 入口分组
interface SettingsGroup {
  key: string;
  title: string;
  items: SettingsEntry[];
}

@ComponentV2
struct SettingsPage {
  @Local query: string = '';             // 搜索查询（受控，SettingSearchBar 唯一数据源）
  @Local isLoggingOut: boolean = false;
  @Local versionName: string = '';       // 关于副标题动态版本号（bundleManager 取）
  @Local showLogoutSheet: boolean = false;  // 退出登录确认 sheet 开关（单 sheet 挂 NavDestination）
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  // HDS 液态顶栏（全屏沉浸后回归 berry3 范式）：scroller 驱动滚动联动；titleBarStyle 随主题（c.bg）刷新。
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

  aboutToAppear(): void {
    this.loadVersionName();
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

  // 全部分组数据（symbol/morandi/target 驱动入口列表；$r 在组件上下文求值）。
  // ⚠️ ArkTS 严格模式：对象字面量须用具名 interface 标注的 const 承接（传参/返回裸字面量会失败）。
  private allGroups(): SettingsGroup[] {
    const display: SettingsEntry = {
      key: 'display', title: t('settings.display.title'), subtitle: '',
      symbol: $r('sys.symbol.paintpalette'), morandi: 'purple', target: 'DisplaySettingsPage'
    };
    const chat: SettingsEntry = {
      key: 'chat', title: t('settings.chat.title'), subtitle: '',
      symbol: $r('sys.symbol.message'), morandi: 'green', target: 'ChatSettingsPage'
    };
    const voice: SettingsEntry = {
      key: 'voice', title: t('settings.voice.title'), subtitle: '',
      symbol: $r('sys.symbol.mic'), morandi: 'orange', target: 'VoiceSettingsPage'
    };
    const connection: SettingsEntry = {
      key: 'connection', title: t('settings.connection.title'), subtitle: '',
      symbol: $r('sys.symbol.link'), morandi: 'blueDeep', target: 'ConnectionSettingsPage'
    };
    const about: SettingsEntry = {
      key: 'about', title: t('settings.about.title'), subtitle: this.versionName,
      symbol: $r('sys.symbol.info_circle'), morandi: 'teal', target: 'AboutPage'
    };
    const general: SettingsGroup = {
      key: 'general', title: t('settings.section.general'), items: [display, chat, voice]
    };
    const connGroup: SettingsGroup = {
      key: 'connection', title: t('settings.section.connection'), items: [connection]
    };
    // 用量看板入口仅 hub owner（namespace=default）可见（对照 hub /api/usage/summary 非 owner 返 403）。
    const aboutItems: SettingsEntry[] = [about];
    if (getConnectionService().namespace === DEFAULT_NAMESPACE) {
      const usage: SettingsEntry = {
        key: 'usage', title: t('settings.usage.title'), subtitle: '',
        symbol: $r('sys.symbol.hourglass'), morandi: 'yellow', target: 'UsagePage'
      };
      aboutItems.unshift(usage);
    }
    const aboutGroup: SettingsGroup = {
      key: 'about', title: t('settings.section.about'), items: aboutItems
    };
    const all: SettingsGroup[] = [general, connGroup, aboutGroup];
    return all;
  }

  // 按查询过滤：小写模糊匹配标题/副标题；剔除无命中项的空分组（查询空时返回全量）
  private filteredGroups(): SettingsGroup[] {
    const q: string = this.query.trim().toLowerCase();
    const groups: SettingsGroup[] = this.allGroups();
    if (q.length === 0) {
      return groups;
    }
    const result: SettingsGroup[] = [];
    for (const g of groups) {
      const kept: SettingsEntry[] = [];
      for (const it of g.items) {
        if (it.title.toLowerCase().indexOf(q) >= 0 || it.subtitle.toLowerCase().indexOf(q) >= 0) {
          kept.push(it);
        }
      }
      if (kept.length > 0) {
        const filtered: SettingsGroup = { key: g.key, title: g.title, items: kept };
        result.push(filtered);
      }
    }
    return result;
  }

  // 退出登录确认弹窗：改为 ConfirmSheet（对照 berry3 ConfirmSheet，替代系统 AlertDialog）
  private confirmLogout(): void {
    this.showLogoutSheet = true;
  }

  // LogoutSheet 按钮组（用具名 interface 标注的 const 承接：ArkTS 严格模式禁传参对象字面量）
  private logoutButtons(): SheetButton[] {
    const cancel: SheetButton = { text: t('common.cancel'), action: (): void => {} };
    const logout: SheetButton = {
      text: t('settings.logout'),
      role: 'danger',
      action: (): void => { this.doLogout(); }
    };
    const arr: SheetButton[] = [cancel, logout];
    return arr;
  }

  // LogoutSheet 的 bindSheet 视觉配置：白身(c.bg) + 毛玻璃 + MEDIUM/LARGE 档（message 可滚动）。
  private get logoutSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      onDisappear: () => { this.showLogoutSheet = false; }
    };
    return buildSheetOptions(this.c.bg, ov);
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
      // 取消 JWT 主动预刷定时器（已登出，无 jwt 可续）
      getJwtRefreshScheduler().cancel();
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

  build() {
    HdsNavDestination() {
      List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（HdsNavDestination ignoreLayoutSafeArea 后内容从 y=0 起；+56 titleBar 高 +8 间距）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)
        // 顶部搜索框（受控）
        ListItem() {
          SettingSearchBar({
            query: this.query,
            placeholder: t('settings.searchPlaceholder'),
            onQueryChange: (v: string) => { this.query = v; }
          })
        }.selectable(false)

        if (this.filteredGroups().length === 0) {
          // 无匹配空态
          ListItem() {
            Column() {
              Text(t('settings.searchNoResult'))
                .fontSize(fs(14))
                .fontColor(this.c.textTertiary)
            }
            .width('100%')
            .padding({ top: 48, bottom: 48 })
            .alignItems(HorizontalAlign.Center)
          }.selectable(false)
        } else {
          ForEach(this.filteredGroups(), (group: SettingsGroup) => {
            // 分组小标题
            ListItem() {
              SettingSectionTitle({ text: group.title })
            }.selectable(false)
            // 分组白卡（连续圆角咬合）
            ListItemGroup() {
              ForEach(group.items, (item: SettingsEntry, idx: number) => {
                ListItem() {
                  SettingCard({
                    primaryText: item.title, secondaryText: item.subtitle,
                    suffixType: 'arrow',
                    iconSymbol: item.symbol,
                    iconBgColor: morandiSwatch(item.morandi, getThemeState().isDark),
                    rowPosition: rowPos(idx, group.items.length),
                    onItemClick: () => {
                      if (this.navPathStack !== null) {
                        this.navPathStack.pushPathByName(item.target, null);
                      }
                    }
                  })
                }
              }, (item: SettingsEntry) => item.key)
            }
            .divider({
              strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
              startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
            })
            .backgroundColor(this.c.bg)
            .borderRadius($r('app.float.setting_card_radius'))
            .clip(true)
          }, (group: SettingsGroup) => group.key)
        }

        // 底部退出登录（危险操作）
        ListItem() {
          SettingActionButton({
            label: this.isLoggingOut ? t('settings.loggingOut') : t('settings.logout'),
            style: 'danger',
            isEnabled: !this.isLoggingOut,
            onPress: () => { this.confirmLogout(); }
          })
        }
        .selectable(false)
        .padding({ top: 8 })

        ListItem() { Row().height(16) }.selectable(false)
        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .padding({
        left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8')
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: t('settings.title') },
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
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack;
    })
    // 退出登录确认 sheet（单 sheet 直接挂 NavDestination，无多 sheet 锚点冲突）
    .bindSheet(this.showLogoutSheet, this.LogoutSheet(), this.logoutSheetOpts)
  }

  // 退出登录确认半屏 sheet（ConfirmSheet：标题 + message + 取消/退出登录双胶囊）
  @Builder LogoutSheet() {
    ConfirmSheet({
      title: t('settings.logout'),
      message: t('settings.logoutConfirm'),
      buttons: this.logoutButtons(),
      onClose: () => { this.showLogoutSheet = false; }
    })
  }
}

// 系统路由表 buildFunction（router_map.json 引用）
@Builder
export function SettingsPageBuilder(name: string, param: Object) {
  SettingsPage()
}
