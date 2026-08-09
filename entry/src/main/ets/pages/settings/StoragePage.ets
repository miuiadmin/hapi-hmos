// 存储用量看板子页（v0.27.2 GET /api/storage/sqlite，仅 hub owner=namespace default）—— 对照上游
//   web/src/routes/settings/storage.tsx + 镜像本项目 UsagePage 骨架。甜甜圈饼图（database/wal/shm）+
//   总量 + 路径 + 刷新。非 owner 403 / 失败 → 错误态 + 重试。
import { paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { getLayoutState } from '../../state/LayoutState';
import { hdsTitleBarStyle } from '../../components/HdsTitleBarStyle';
import { t } from '../../i18n/I18nService';
import { getHubClient } from '../../api/HubClient';
import { SqliteStorageUsageResult } from '../../models/Types';
import { StorageUsagePie } from '../../components/settings/StorageUsagePie';

@Builder
export function StoragePageBuilder(name: string, param: Object) {
  StoragePage()
}

@ComponentV2
struct StoragePage {
  @Local data: SqliteStorageUsageResult | null = null;
  @Local loading: boolean = false;
  @Local refreshing: boolean = false;
  @Local errorMsg: string = '';
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

  aboutToAppear(): void {
    this.load(false);
  }

  private async load(isRefresh: boolean): Promise<void> {
    if (isRefresh) { this.refreshing = true; } else { this.loading = true; }
    this.errorMsg = '';
    try {
      const r: SqliteStorageUsageResult = await getHubClient().getSqliteStorageUsage();
      this.data = r;
      if (r.error !== '') { this.errorMsg = r.error; }
    } catch (e) {
      this.data = null;
      this.errorMsg = t('settings.storage.error');
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  build() {
    HdsNavDestination() {
      List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（ignoreLayoutSafeArea 后内容从 y=0；+56 titleBar +8）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)

        // 说明
        ListItem() {
          Text(t('settings.storage.description'))
            .fontSize(13).fontColor(this.c.textSecondary)
            .width('100%').padding({ left: 4, right: 4 })
        }.selectable(false)

        if (this.loading && this.data === null) {
          ListItem() {
            Column() {
              LoadingProgress().width(32).height(32).color(this.c.textTertiary)
            }
            .width('100%')
            .padding({ top: 64, bottom: 64 })
            .alignItems(HorizontalAlign.Center)
          }.selectable(false)
        } else if (this.errorMsg !== '') {
          ListItem() { this.ErrorState() }.selectable(false)
        } else if (this.data !== null) {
          ListItem() {
            StorageUsagePie({
              databaseBytes: this.data.databaseBytes,
              walBytes: this.data.walBytes,
              shmBytes: this.data.shmBytes,
              totalBytes: this.data.totalBytes,
              path: this.data.path
            })
          }.selectable(false)
        }

        // 刷新按钮
        ListItem() {
          Row() {
            Text(this.refreshing ? t('settings.storage.refreshing') : t('settings.storage.refresh'))
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.bubbleUserText)
              .padding({ left: 24, right: 24, top: 10, bottom: 10 })
              .borderRadius(20)
              .backgroundColor(this.c.primary)
              .opacity(this.refreshing ? 0.5 : 1)
              .onClick(() => { this.load(true); })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8 })
        }.selectable(false)

        ListItem() { Row().height(24) }.selectable(false)
        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({ left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8') })
    }
    .titleBar({
      content: { title: { mainTitle: t('settings.storage.title') }, divider: { showType: DividerShowType.OFF } },
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

  // 错误态：非 owner（403 文案）或加载失败 → 提示 + 重试胶囊。
  @Builder ErrorState() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(36)
        .fontColor([this.c.warning])
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor(this.c.textSecondary)
        .textAlign(TextAlign.Center)
        .width('100%')
      Row() {
        Text(t('settings.storage.retry'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.bubbleUserText)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor(this.c.primary)
          .onClick(() => { this.load(false); })
      }
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
    .alignItems(HorizontalAlign.Center)
  }
}
