// 关于子页（版本 / 检查更新(OTA) / 开源协议 / GitHub 源代码）—— 对照 berry3 设置子页骨架。
// 逻辑从旧 SettingsPage 迁移：loadVersionName / openGitHub / OTA 全套（getUpdateState 读取 + OtaSheet）。
// 只读信息行（版本/协议）用 SettingCard suffixType='none' + clickable:false（无按压态）。
// OtaCheckRow 单独自定义行（berry3 可点击行尺寸 + 按压态 + resolveRowRadius 咬合）；OtaSheet 阶段驱动。
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t } from '../../i18n/I18nService';
import { showToast } from '../../utils/Toast';
import { OtaController, getUpdateState, UpdateState } from '../../services/UpdateState';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';
import { resolveRowRadius } from '../../components/settings/RowRadiusUtil';
import { buildSheetOptions, SheetOverrides } from '../../components/settings/SheetOptionsFactory';
import { SelfUpdateSheet } from '../../components/SelfUpdateSheet';

@Builder
export function AboutPageBuilder(name: string, param: Object) {
  AboutPage()
}

@ComponentV2
struct AboutPage {
  @Local versionName: string = '';
  @Local otaEligible: boolean = false;
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // —— OTA 自更新状态（读 getUpdateState() 的 @Trace 字段建立刷新依赖；弹窗阶段/进度/错误随下载回调即时重渲染）——
  private get ota(): UpdateState { return getUpdateState(); }

  aboutToAppear(): void {
    this.loadVersionName();
    // 共存版（com.berry.hapi88）才显示「检查更新」行；正式版无后缀 → 隐藏
    this.otaEligible = OtaController.isEligible();
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

  // OTA sheet 关闭（用户下滑/系统关闭）：下载中视为取消（静默收尾），否则仅关 sheet
  private closeOtaSheet(): void {
    const s: UpdateState = getUpdateState();
    if (s.downloading) {
      OtaController.cancelDownload();   // onCancel 回调会清 sheetOpen
    } else {
      s.sheetOpen = false;
    }
  }

  // OtaSheet 的 bindSheet 视觉配置：灰身(c.surface) + 毛玻璃 + 无把手 + FIT_CONTENT 首档（贴合内容，可下拉到 LARGE）。
  private get otaSheetOpts(): SheetOptions {
    const ov: SheetOverrides = {
      onDisappear: () => { this.closeOtaSheet(); }
    };
    return buildSheetOptions(this.c.surface, ov);
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

  build() {
    NavDestination() {
      List({ space: 12 }) {
        // ── 关于 ──
        ListItem() {
          SettingSectionTitle({ text: t('settings.section.about') })
        }
        ListItemGroup() {
          ListItem() {
            SettingCard({
              primaryText: t('settings.about.version'), secondaryText: this.versionName,
              suffixType: 'none', clickable: false, rowPosition: 'first'
            })
          }
          // 检查更新行（共存版才渲染）：custom row，berry3 可点击行尺寸 + 按压态 + middle 咬合圆角
          if (this.otaEligible) {
            ListItem() { this.OtaCheckRow() }
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.about.license'), secondaryText: t('settings.about.licenseValue'),
              suffixType: 'none', clickable: false, rowPosition: 'middle'
            })
          }
          ListItem() {
            SettingCard({
              primaryText: t('settings.about.sourceCode'), suffixText: t('settings.about.sourceCodeValue'),
              suffixType: 'textAndArrow', rowPosition: 'last',
              onItemClick: () => { this.openGitHub(); }
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
      .bindSheet(this.ota.sheetOpen && this.ota.sheetOwner === 'about', this.OtaSheet(), this.otaSheetOpts)
    }
    .title(t('settings.about.title'))
    .backgroundColor(this.c.surface)
    .onReady((context: NavDestinationContext) => { this.navPathStack = context.pathStack; })
    .onBackPressed(() => { this.navPathStack?.pop(); return true; })
  }

  // 「检查更新」行（共存版才渲染）：checking→spinner，有更新→红点，否则 chevron；tap 触发手动检查
  // 尺寸对齐 SettingCard（padding_h/v + minHeight56 + 咬合圆角 middle + 按压灰底 surfaceSelected）
  @Builder OtaCheckRow() {
    Row() {
      Text(t('settings.about.checkUpdate'))
        .fontSize(fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
      if (this.ota.checking) {
        LoadingProgress().width(20).height(20).color(this.c.textTertiary)
      } else {
        if (this.ota.hasUpdate) {
          Circle({ width: 8, height: 8 }).fill(this.c.error).margin({ right: 8 })
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([this.c.textTertiary])
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({
      left: $r('app.float.setting_card_padding_h'), right: $r('app.float.setting_card_padding_h'),
      top: $r('app.float.setting_card_padding_v'), bottom: $r('app.float.setting_card_padding_v')
    })
    .alignItems(VerticalAlign.Center)
    .borderRadius(resolveRowRadius('middle'))
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({
      pressed: { .backgroundColor(this.c.surfaceSelected) },
      normal: { .backgroundColor(Color.Transparent) }
    })
    .onClick(() => { OtaController.checkForUpdates(true, false); })
  }

  // OTA 更新弹窗 sheet —— 挂独立组件 SelfUpdateSheet（抽自原内联 OtaSheet，各态布局对齐 berry3：
  //   FIT_CONTENT 紧凑半窗 + SheetDialog 标题栏 + 三态 + installing）。
  //   @Param 由 getUpdateState() 的 @Trace 字段驱动（单页挂载，@Trace→@Param 链可靠）；
  //   @Event 回调接 OtaController / closeOtaSheet。
  @Builder OtaSheet() {
    SelfUpdateSheet({
      info: this.ota.info,
      phase: this.ota.phase,
      percent: this.ota.percent,
      received: this.ota.received,
      total: this.ota.total,
      installing: this.ota.installing,
      error: this.ota.error,
      onUpdate: (): void => { OtaController.startDownload(); },
      onIgnore: (): void => { OtaController.skipVersion(); },
      onCancel: (): void => { OtaController.cancelDownload(); },
      onRetry: (): void => { OtaController.retry(); },
      onClose: (): void => { this.closeOtaSheet(); }
    })
  }
}
