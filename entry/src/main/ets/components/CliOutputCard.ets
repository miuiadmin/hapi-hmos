// CliOutputCard —— 对照 web/src/components/CliOutputBlock.tsx
// CLI 命令输出块卡：header（终端图标 + 命令名 + 详情入口）+ 内嵌 CodeBlock（buildCliOutput，shellscript）。
//   点击 header → bindSheet 详情（全量不折叠、可纵向滚动）。
// 折叠阈值（对照上游 PREVIEW_*）：内嵌预览超 14 行或 1600 字符 → 折叠；详情态全量。
// V2 状态：@Param block（text/source 取自 block）；@Local isDetailOpen（bindSheet 双向）。

import { ChatBlock } from '../chat/ChatBlock';
import { buildCliOutput, extractCommandName } from '../chat/CliOutput';
import { CodeBlock } from './CodeBlock';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

const PREVIEW_LINE_THRESHOLD: number = 14;
const PREVIEW_CHAR_THRESHOLD: number = 1600;
const PREVIEW_MAX_HEIGHT: number = 220;   // 对照上游 collapsedHeight（CodeBlock maxHeight）

@ComponentV2
export struct CliOutputCard {
  @Param block: ChatBlock = new ChatBlock();
  @Local isDetailOpen: boolean = false;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 格式化后的输出串（buildCliOutput 已 i18n 化：标签经 t() 翻译）
  private get content(): string { return buildCliOutput(this.block.text); }

  // 命令名作卡片标题（对照 extractCommandName）；无则回落 terminal.commandName 文案
  private get title(): string {
    const name: string = extractCommandName(this.block.text);
    return name !== '' ? name : t('terminal.commandName');
  }

  // 内嵌预览折叠判定（对照 shouldCollapsePreview：超行/超字符阈值）
  private get collapsePreview(): boolean {
    if (this.content.length > PREVIEW_CHAR_THRESHOLD) { return true; }
    return this.content.split('\n').length > PREVIEW_LINE_THRESHOLD;
  }

  build() {
    Column() {
      // header（镜像 CliOutputBlock.tsx：终端图标 + 命令名 + 详情入口 ›）
      Row() {
        Text(t('terminal.icon'))
          .fontSize(fs(14))
          .fontColor(this.c.primary)
          .margin({ right: 6 })
        Text(this.title)
          .fontSize(fs(14))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('›')
          .fontSize(fs(18))
          .fontColor(this.c.textTertiary)
          .margin({ left: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 2, right: 2, bottom: 8 })
      .onClick((): void => { this.isDetailOpen = true; })

      // 内嵌预览（折叠态折叠到 PREVIEW_MAX_HEIGHT）
      CodeBlock({
        code: this.content,
        language: 'shellscript',
        title: t('terminal.output'),
        collapseLongContent: this.collapsePreview,
        maxHeight: PREVIEW_MAX_HEIGHT
      })
    }
    .width('100%')
    .padding(10)
    .borderRadius(20)
    .backgroundColor(this.c.surface)
    .border({ width: 0.5, color: this.c.border })
    .bindSheet(this.isDetailOpen!!, this.DetailSheet(), {
      height: SheetSize.LARGE,
      dragBar: true
    })
  }

  // 详情态：全量不折叠、纵向滚动（对照上游 DialogContent 的全量 CodeBlock）
  @Builder
  DetailSheet() {
    Column() {
      Text(this.title)
        .fontSize(fs(15))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.c.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      CodeBlock({
        code: this.content,
        language: 'shellscript',
        title: t('terminal.output'),
        collapseLongContent: false,
        scrollY: true
      })
        .padding({ left: 12, right: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.bg)
  }
}
