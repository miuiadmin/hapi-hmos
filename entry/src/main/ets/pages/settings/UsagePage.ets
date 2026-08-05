// 用量看板子页（v0.26.0 GET /api/usage/summary，仅 hub owner=namespace default）—— 对照 berry3 设置子页骨架。
// range 切换（7d/30d/all）→ 重拉；合计 + 按 agent + 按模型 三段分组白卡；非 owner 403 / 失败 → 错误态 + 重试。
import { paletteOf, PaletteColors, getThemeState } from '../../theme/ThemeService';
import { HdsNavDestination, HdsNavDestinationTitleMode, DividerShowType, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { getLayoutState } from '../../state/LayoutState';
import { hdsTitleBarStyle } from '../../components/HdsTitleBarStyle';
import { t, kv } from '../../i18n/I18nService';
import { getHubClient } from '../../api/HubClient';
import { UsageSummaryResponse, UsageSummaryBucket } from '../../models/Types';
import { SettingCard } from '../../components/settings/SettingCard';
import { SettingSectionTitle } from '../../components/settings/SettingSectionTitle';
import { rowPos } from '../../components/settings/RowRadiusUtil';

@Builder
export function UsagePageBuilder(name: string, param: Object) {
  UsagePage()
}

@ComponentV2
struct UsagePage {
  @Local range: string = '7d';                 // '7d' | '30d' | 'all'（hub：30d→30天, all→全部, 其余→7天）
  @Local data: UsageSummaryResponse | null = null;
  @Local loading: boolean = false;
  @Local errorMsg: string = '';                 // 非 owner 403 / 网络 / 解析错（来自 data.error 或本地兜底）
  private navPathStack: NavPathStack | null = null;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }
  private scroller: Scroller = new Scroller();
  private get titleBarStyle(): TitleBarStyleOptions { return hdsTitleBarStyle(this.c.bg); }

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    try {
      const r: UsageSummaryResponse = await getHubClient().getUsageSummary(this.range, '');
      this.data = r;
      if (r.error !== '') {
        this.errorMsg = r.error;
      }
    } catch (e) {
      this.data = null;
      this.errorMsg = t('settings.usage.loadError');
    } finally {
      this.loading = false;
    }
  }

  private selectRange(r: string): void {
    if (r !== this.range) {
      this.range = r;
      this.load();
    }
  }

  private rangeLabel(r: string): string {
    if (r === '30d') { return t('settings.usage.range30d'); }
    if (r === 'all') { return t('settings.usage.rangeAll'); }
    return t('settings.usage.range7d');
  }

  // 千分位整数（无 regex/Intl 依赖，ArkTS 严格安全）：从右每 3 位插逗号。
  private fmt(n: number): string {
    let s: string = n.toString();
    let neg: boolean = false;
    if (s.startsWith('-')) { neg = true; s = s.substring(1); }
    let out: string = '';
    let count: number = 0;
    for (let i = s.length - 1; i >= 0; i--) {
      out = s.charAt(i) + out;
      count++;
      if (count % 3 === 0 && i > 0) { out = ',' + out; }
    }
    return neg ? '-' + out : out;
  }

  // 合计是否全零（→ 显空态）。
  private isEmpty(): boolean {
    const d = this.data;
    if (d === null) { return true; }
    return d.totals.totalTokens === 0 && d.totals.requests === 0 && d.totals.sessions === 0
      && d.byAgent.length === 0 && d.byModel.length === 0;
  }

  build() {
    HdsNavDestination() {
      List({ space: 12, scroller: this.scroller }) {
        // 顶部安全区占位（ignoreLayoutSafeArea 后内容从 y=0；+56 titleBar +8）
        ListItem() { Row().height(getLayoutState().topAvoidHeight + 56 + 8) }.selectable(false)

        // —— range 切换（三段胶囊）——
        ListItem() { this.RangeSelector() }

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
        } else if (this.data !== null && this.isEmpty()) {
          ListItem() {
            Text(t('settings.usage.empty'))
              .fontSize(14).fontColor(this.c.textTertiary)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: 64, bottom: 64 })
          }.selectable(false)
        } else if (this.data !== null) {
          // —— 合计 ——
          ListItem() { SettingSectionTitle({ text: t('settings.usage.totals') }) }
          ListItemGroup() { this.TotalsItems() }
            .divider({
              strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
              startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
            })
            .backgroundColor(this.c.bg)
            .borderRadius($r('app.float.setting_card_radius'))
            .clip(true)

          // —— 按 agent ——
          if (this.data.byAgent.length > 0) {
            ListItem() { SettingSectionTitle({ text: t('settings.usage.byAgent') }) }
            ListItemGroup() {
              ForEach(this.data.byAgent, (b: UsageSummaryBucket, idx: number) => {
                ListItem() {
                  SettingCard({
                    primaryText: b.key, secondaryText: t('settings.usage.tokens', kv('n', this.fmt(b.totalTokens))),
                    suffixType: 'none', clickable: false,
                    rowPosition: rowPos(idx, this.data!.byAgent.length)
                  })
                }
              }, (b: UsageSummaryBucket) => b.key)
            }
              .divider({
                strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
                startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
              })
              .backgroundColor(this.c.bg)
              .borderRadius($r('app.float.setting_card_radius'))
              .clip(true)
          }

          // —— 按模型 ——
          if (this.data.byModel.length > 0) {
            ListItem() { SettingSectionTitle({ text: t('settings.usage.byModel') }) }
            ListItemGroup() {
              ForEach(this.data.byModel, (b: UsageSummaryBucket, idx: number) => {
                ListItem() {
                  SettingCard({
                    primaryText: b.key, secondaryText: t('settings.usage.tokens', kv('n', this.fmt(b.totalTokens))),
                    suffixType: 'none', clickable: false,
                    rowPosition: rowPos(idx, this.data!.byModel.length)
                  })
                }
              }, (b: UsageSummaryBucket) => b.key)
            }
              .divider({
                strokeWidth: $r('app.float.setting_divider_width'), color: this.c.border,
                startMargin: $r('app.float.setting_card_padding_h'), endMargin: $r('app.float.setting_card_padding_h')
              })
              .backgroundColor(this.c.bg)
              .borderRadius($r('app.float.setting_card_radius'))
              .clip(true)
          }
        }

        ListItem() { Row().height(24) }.selectable(false)
        // 底部安全区占位（手势导航条）
        ListItem() { Row().height(getLayoutState().bottomAvoidHeight) }.selectable(false)
      }
      .scrollBar(BarState.Off)
      .padding({ left: $r('sys.float.padding_level8'), right: $r('sys.float.padding_level8') })
    }
    .titleBar({
      content: { title: { mainTitle: t('settings.usage.title') }, divider: { showType: DividerShowType.OFF } },
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

  // range 三段胶囊（选中=primary 填充白字；未选=surface 次要字）。
  @Builder RangeSelector() {
    Row({ space: 0 }) {
      this.RangeCapsule('7d', this.range === '7d')
      this.RangeCapsule('30d', this.range === '30d')
      this.RangeCapsule('all', this.range === 'all')
    }
    .width('100%')
    .height(40)
    .borderRadius(12)
    .backgroundColor(this.c.surface)
  }

  @Builder RangeCapsule(r: string, selected: boolean) {
    Text(this.rangeLabel(r))
      .fontSize(14)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? this.c.bubbleUserText : this.c.textSecondary)
      .layoutWeight(1)
      .height(40)
      .textAlign(TextAlign.Center)
      .borderRadius(12)
      .backgroundColor(selected ? this.c.primary : Color.Transparent)
      .onClick(() => { this.selectRange(r); })
  }

  // 合计行组（会话 / 请求 / 总 tokens / 输入 / 输出 / 缓存读 / 缓存写）。
  @Builder TotalsItems() {
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.sessions'), secondaryText: this.fmt(this.data!.totals.sessions),
        suffixType: 'none', clickable: false, rowPosition: 'first'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.requests'), secondaryText: this.fmt(this.data!.totals.requests),
        suffixType: 'none', clickable: false, rowPosition: 'middle'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.total'),
        secondaryText: t('settings.usage.tokens', kv('n', this.fmt(this.data!.totals.totalTokens))),
        suffixType: 'none', clickable: false, rowPosition: 'middle'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.inputTokens'),
        secondaryText: t('settings.usage.tokens', kv('n', this.fmt(this.data!.totals.inputTokens))),
        suffixType: 'none', clickable: false, rowPosition: 'middle'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.outputTokens'),
        secondaryText: t('settings.usage.tokens', kv('n', this.fmt(this.data!.totals.outputTokens))),
        suffixType: 'none', clickable: false, rowPosition: 'middle'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.cacheRead'),
        secondaryText: t('settings.usage.tokens', kv('n', this.fmt(this.data!.totals.cacheReadTokens))),
        suffixType: 'none', clickable: false, rowPosition: 'middle'
      })
    }
    ListItem() {
      SettingCard({
        primaryText: t('settings.usage.cacheCreation'),
        secondaryText: t('settings.usage.tokens', kv('n', this.fmt(this.data!.totals.cacheCreationTokens))),
        suffixType: 'none', clickable: false, rowPosition: 'last'
      })
    }
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
        Text(t('settings.usage.retry'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.bubbleUserText)
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .borderRadius(20)
          .backgroundColor(this.c.primary)
          .onClick(() => { this.load(); })
      }
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
    .alignItems(HorizontalAlign.Center)
  }
}
