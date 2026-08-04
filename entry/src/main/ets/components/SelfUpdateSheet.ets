// SelfUpdateSheet — OTA 自更新半屏弹窗内容组件（bindSheet 半模态）。
//
// 抽自 AboutPage 内联 OtaSheet（原 berry3 移植）：结构与各态布局 1:1 对齐 berry3
//   components/SelfUpdateSheet.ets —— SheetDialog 标题栏 + FIT_CONTENT 紧凑自适应
//   （根 layoutWeight(0)，不撑满不沉底）+ 三态（prompting/downloading/failed）+
//   installing（本项目独有：下载校验通过后拉起系统安装器期间）。
//
// 纯展示组件：@Param 驱动（父页从 getUpdateState() 传 @Trace 字段），@Event 回调交父页调 OtaController。
// 颜色走 this.c JS 调色板（CLAUDE.md 设置页规则：paletteOf(isDark)，非 sys.color）；字号走 fs()。
//
// FIT_CONTENT 避坑（berry3 避坑 29）：根 Column layoutWeight(0) 不撑满，内容自然高度；
//   prompting 长日志靠 changelogList 的 constraintSize maxHeight + Scroll 滚动（短日志贴合无空白）。

import { SheetDialog } from './settings/SheetDialog';
import { UpdateInfo, SelfUpdatePhase } from '../services/SelfUpdateManager';
import { OtaController } from '../services/UpdateState';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t, kv } from '../i18n/I18nService';

@ComponentV2
export struct SelfUpdateSheet {
  /** 远端更新信息（versionName/changelog/size）；prompting 态展示版本·大小 + 日志 */
  @Param info: UpdateInfo | null = null;
  /** 当前阶段：prompting=展示更新 / downloading=下载中 / failed=校验失败 */
  @Param phase: SelfUpdatePhase = 'prompting';
  /** 下载进度百分比（0~100） */
  @Param percent: number = 0;
  /** 已下载字节（进度文本展示） */
  @Param received: number = 0;
  /** 总字节（total<0 未知） */
  @Param total: number = -1;
  /** 已触发拉起安装器（展示 installing 态，本项目独有） */
  @Param installing: boolean = false;
  /** 失败原因（failed 态展示） */
  @Param error: string = '';

  /** 点「立即更新」→ 父页调 OtaController.startDownload */
  @Event onUpdate: () => void = () => {};
  /** 点「跳过此版本」→ 父页调 OtaController.skipVersion */
  @Event onIgnore: () => void = () => {};
  /** 点「取消」→ 父页调 OtaController.cancelDownload */
  @Event onCancel: () => void = () => {};
  /** 点「重试」→ 父页调 OtaController.retry */
  @Event onRetry: () => void = () => {};
  /** 关闭弹窗（✕ / 下滑 / failed 关闭） */
  @Event onClose: () => void = () => {};

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  /** 标题：恒为「发现新版本 vX」（对齐 berry3 —— 标题静态，下载进度/安装态只在正文，避免百分比与正文重复） */
  private get titleText(): string {
    const v: string = this.info !== null ? this.info.versionName : '';
    return t('ota.newVersion', kv('version', v));
  }

  /** 「版本号 · 大小」（prompting 态横幅） */
  private get versionMeta(): string {
    const i: UpdateInfo | null = this.info;
    return i !== null ? `${i.versionName} · ${OtaController.formatSize(i.size)}` : '';
  }

  /** 下载进度文本：「X% · 已下 / 总」（total<0 时省略总） */
  private get progressText(): string {
    const pct: string = `${this.percent}%`;
    if (this.total > 0) {
      return `${pct} · ${OtaController.formatSize(this.received)} / ${OtaController.formatSize(this.total)}`;
    }
    return `${pct} · ${OtaController.formatSize(this.received)}`;
  }

  private get changelog(): string[] {
    const i: UpdateInfo | null = this.info;
    return i !== null ? i.changelog : [];
  }

  /** prompting：版本·大小 + 更新日志（可滚动，限高 400 防超长撑爆 FIT_CONTENT） */
  @Builder changelogList() {
    Scroll() {
      Column() {
        Text(this.versionMeta)
          .fontSize(fs(14))
          .fontColor(this.c.textSecondary)
          .width('100%')
        Text(t('ota.changelog'))
          .fontSize(fs(13))
          .fontColor(this.c.textTertiary)
          .width('100%')
          .margin({ top: 16, bottom: 8 })
        if (this.changelog.length === 0) {
          Text(t('ota.noChangelog'))
            .fontSize(fs(14))
            .fontColor(this.c.textTertiary)
        } else {
          ForEach(this.changelog, (item: string, idx: number) => {
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
    // ⚠️ FIT_CONTENT 自适应：constraintSize 限 changelog 区最大高度。短日志（2~3 条）Scroll 高度=内容
    //   （sheet 收缩无空白）；长日志超 400vp 则固定 400vp 内部滚动。ScrollAttribute 无 maxHeight，用 constraintSize。
    .width('100%')
    .constraintSize({ maxHeight: 400 })
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }

  /** 胶囊按钮（layoutWeight(1) 撑满父 Row；primary=主色填充白字 / normal=灰底主字）。对照 berry3 胶囊按钮。 */
  @Builder actionButton(label: string, primary: boolean, onTap: () => void) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Text(label)
        .fontSize(fs(14))
        .fontColor(primary ? this.c.bubbleUserText : this.c.textPrimary)
    }
    .layoutWeight(1)
    .height(48)
    .backgroundColor(primary ? this.c.primary : this.c.surfaceSelected)
    .onClick(() => { onTap(); })
  }

  /** prompting 底部：立即更新（主）+ 跳过此版本（次）并排双胶囊 —— 对齐 berry3 promptActions */
  @Builder promptActions() {
    Row({ space: 12 }) {
      this.actionButton(t('ota.updateNow'), true, () => { this.onUpdate(); })
      this.actionButton(t('ota.skipVersion'), false, () => { this.onIgnore(); })
    }
    .width('100%')
    .margin({ top: 16 })
  }

  /** downloading：进度条 + 百分比/已下 + 提示 + 取消 —— 对齐 berry3 downloadingContent */
  @Builder downloadingContent() {
    Column({ space: 16 }) {
      Progress({ value: this.percent, total: 100, type: ProgressType.Linear })
        .width('100%')
        .color(this.c.primary)
        .backgroundColor(this.c.border)
      Row() {
        Text(this.progressText)
          .fontSize(fs(13))
          .fontColor(this.c.textTertiary)
        Blank()
        Text(t('ota.downloadHint'))
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Text(t('ota.cancel'))
          .fontSize(fs(14))
          .fontColor(this.c.textPrimary)
      }
      .width('100%')
      .height(48)
      .backgroundColor(this.c.surfaceSelected)
      .onClick(() => { this.onCancel(); })
    }
    .width('100%')
  }

  /** failed：⚠️图标 + 标题 + 原因 + 提示 + 重试/关闭双按钮 —— 对齐 berry3 failedContent */
  @Builder failedContent() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(40)
        .fontColor([this.c.error])
      Text(t('ota.verifyFailed'))
        .fontSize(fs(16))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(fs(13))
          .fontColor(this.c.textSecondary)
          .textAlign(TextAlign.Center)
      }
      Text(t('ota.failedHint'))
        .fontSize(fs(13))
        .fontColor(this.c.textTertiary)
        .textAlign(TextAlign.Center)

      Row({ space: 12 }) {
        this.actionButton(t('ota.retry'), true, () => { this.onRetry(); })
        this.actionButton(t('ota.close'), false, () => { this.onClose(); })
      }
      .width('100%')
    }
    .width('100%')
  }

  /** installing（本项目独有）：Loading + 文案，无按钮（系统安装器接管期间） */
  @Builder installingContent() {
    Row() {
      LoadingProgress().width(24).height(24).color(this.c.primary)
      Text(t('ota.installing'))
        .fontSize(fs(14))
        .fontColor(this.c.textSecondary)
        .margin({ left: 10 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    // 三态 + installing 统一 FIT_CONTENT：根 Column layoutWeight(0) 不撑满，sheet 高度=内容自然高度。
    Column() {
      SheetDialog({
        title: this.titleText,
        showCloseButton: true,
        onClose: () => { this.onClose(); }
      })
      Column() {
        if (this.installing) {
          this.installingContent()
        } else if (this.phase === 'downloading') {
          this.downloadingContent()
        } else if (this.phase === 'failed') {
          this.failedContent()
        } else {
          this.changelogList()
          this.promptActions()
        }
      }
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
    }
    .width('100%')
    .layoutWeight(0)
  }
}
