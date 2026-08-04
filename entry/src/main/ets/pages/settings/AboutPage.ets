// 关于子页（版本 / 检查更新(OTA) / 开源协议 / GitHub 源代码）—— 对照 berry3 设置子页骨架。
// 逻辑从旧 SettingsPage 迁移：loadVersionName / openGitHub / OTA 全套（getUpdateState 读取 + OtaSheet）。
// 只读信息行（版本/协议）用 SettingCard suffixType='none' + clickable:false（无按压态）。
// OtaCheckRow 单独自定义行（berry3 可点击行尺寸 + 按压态 + resolveRowRadius 咬合）；OtaSheet 阶段驱动。
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { fs, paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { t, kv } from '../../i18n/I18nService';
import { showToast } from '../../utils/Toast';
import { OtaController, getUpdateState, UpdateState } from '../../services/UpdateState';
import { UpdateInfo } from '../../services/SelfUpdateManager';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';
import { resolveRowRadius } from '../../components/settings/RowRadiusUtil';

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
  private get otaVersionName(): string {
    const i: UpdateInfo | null = this.ota.info;
    return i !== null ? i.versionName : '';
  }
  // 弹窗标题：安装中=「拉起安装器」/ 下载中=「下载中 X%」/ 否则=「发现新版本 vX」
  private get otaSheetTitle(): string {
    if (this.ota.installing) { return t('ota.installing'); }
    if (this.ota.phase === 'downloading') { return OtaController.downloadingText(this.ota.percent); }
    return t('ota.newVersion', kv('version', this.otaVersionName));
  }
  // 「版本号 · 大小」（prompting 态横幅）
  private get otaVersionMeta(): string {
    const i: UpdateInfo | null = this.ota.info;
    return i !== null ? `${i.versionName} · ${OtaController.formatSize(i.size)}` : '';
  }
  // 下载进度文本：「X% · 已下 / 总」
  private get otaProgressText(): string {
    const pct: string = `${this.ota.percent}%`;
    const received: number = this.ota.received;
    const total: number = this.ota.total;
    if (total > 0) {
      return `${pct} · ${OtaController.formatSize(received)} / ${OtaController.formatSize(total)}`;
    }
    return `${pct} · ${OtaController.formatSize(received)}`;
  }
  private get otaChangelog(): string[] {
    const i: UpdateInfo | null = this.ota.info;
    return i !== null ? i.changelog : [];
  }

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
      .bindSheet(this.ota.sheetOpen!!, this.OtaSheet(), {
        height: SheetSize.LARGE,
        detents: [SheetSize.LARGE],
        backgroundColor: this.c.bg,
        onDisappear: () => { this.closeOtaSheet(); }
      })
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

  // OTA 全宽按钮（primary=主色填充白字；secondary=bg 底主色字）
  @Builder OtaButton(label: string, primary: boolean, onTap: () => void) {
    Button(label)
      .width('100%')
      .height(48)
      .backgroundColor(primary ? this.c.primary : this.c.bg)
      .fontColor(primary ? '#FFFFFFFF' : this.c.textPrimary)
      .borderRadius(12)
      .onClick(() => { onTap(); })
  }

  // OTA 更新弹窗 sheet（阶段驱动：prompting 展示日志 / downloading 进度条 / failed 重试 / installing 拉起中）
  @Builder OtaSheet() {
    Column() {
      // 标题（随阶段变化）
      Text(this.otaSheetTitle)
        .fontSize(fs(17))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 24, bottom: 14 })

      if (this.ota.installing) {
        // 拉起安装器中
        Row() {
          LoadingProgress().width(24).height(24).color(this.c.primary)
          Text(t('ota.installing'))
            .fontSize(fs(14))
            .fontColor(this.c.textSecondary)
            .margin({ left: 10 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 28 })
        .alignItems(VerticalAlign.Center)
      } else if (this.ota.phase === 'downloading') {
        // 下载进度
        Column() {
          Progress({ value: this.ota.percent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .color(this.c.primary)
            .backgroundColor(this.c.border)
          Text(this.otaProgressText)
            .fontSize(fs(13))
            .fontColor(this.c.textTertiary)
            .width('100%')
            .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 28 })
        .alignItems(HorizontalAlign.Start)
      } else if (this.ota.phase === 'failed') {
        // 校验失败
        Text(this.ota.error.length > 0 ? this.ota.error : t('ota.downloadFailed'))
          .fontSize(fs(14))
          .fontColor(this.c.error)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 28 })
      } else {
        // prompting：版本 + 大小 + 更新日志（可滚动）
        Scroll() {
          Column() {
            Text(this.otaVersionMeta)
              .fontSize(fs(14))
              .fontColor(this.c.textSecondary)
              .width('100%')
            Text(t('ota.changelog'))
              .fontSize(fs(13))
              .fontColor(this.c.textTertiary)
              .width('100%')
              .margin({ top: 16, bottom: 8 })
            if (this.otaChangelog.length === 0) {
              Text('—')
                .fontSize(fs(14))
                .fontColor(this.c.textTertiary)
            } else {
              ForEach(this.otaChangelog, (item: string, idx: number) => {
                Row() {
                  Text('•')
                    .fontSize(fs(13))
                    .fontColor(this.c.textTertiary)
                    .margin({ right: 8 })
                  Text(item)
                    .fontSize(fs(14))
                    .fontColor(this.c.textSecondary)
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .margin({ bottom: 6 })
              }, (item: string, idx: number) => `${idx}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
        .padding({ left: 20, right: 20, bottom: 16 })
      }

      // 操作区（随阶段）
      if (this.ota.installing) {
        // 安装器接管中：无操作
      } else if (this.ota.phase === 'downloading') {
        this.OtaButton(t('ota.cancel'), false, (): void => { OtaController.cancelDownload(); })
      } else if (this.ota.phase === 'failed') {
        Row() {
          Button(t('ota.retry'))
            .layoutWeight(1)
            .height(46)
            .backgroundColor(this.c.primary)
            .fontColor('#FFFFFFFF')
            .borderRadius(12)
            .onClick(() => { OtaController.retry(); })
          Button(t('ota.close'))
            .layoutWeight(1)
            .height(46)
            .margin({ left: 12 })
            .backgroundColor(this.c.bg)
            .fontColor(this.c.textPrimary)
            .borderRadius(12)
            .onClick(() => { this.closeOtaSheet(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 28 })
      } else {
        // prompting：立即更新（主）+ 跳过此版本（次）
        Column() {
          this.OtaButton(t('ota.updateNow'), true, (): void => { OtaController.startDownload(); })
          Text(t('ota.skipVersion'))
            .fontSize(fs(14))
            .fontColor(this.c.textSecondary)
            .margin({ top: 14 })
            .onClick(() => { OtaController.skipVersion(); })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 28 })
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .backgroundColor(this.c.bg)
  }
}
