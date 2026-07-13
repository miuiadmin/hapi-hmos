import { getConnectionService } from '../services/ConnectionService';
import { getSSEClient } from '../api/SSEClient';
import { getPreferencesService } from '../services/PreferencesService';
import { AppStorageKeys, PreferenceKeys } from '../config/Keys';
import { window } from '@kit.ArkUI';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { fs, paletteOf, PaletteColors, getThemeState, ThemeService, ThemeMode, FontScaleMode } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';
import { t, I18nService, LanguageChoice } from '../i18n/I18nService';

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
