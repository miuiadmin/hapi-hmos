// TraceSection —— 子代理 children 嵌套追踪渲染（对照上游 TraceSection.tsx）
//
// 在「发起子代理的工具卡」详情 sheet 内，把 block.children（Reducer 递归 reduce 产出的子代理 block 时间线）
//   渲染为可折叠时间线。两种数据流复用同一组件（均产 ChatBlock.children，Flow A 由 Commit 1 接线）：
//     Flow A（Claude Task/Agent）：mode='trace'（左缩进 + 左边框；含 running/error/pending 时默认展）。
//     Flow B（Codex CodexAgent）：mode='session'（默认展；Flow B 接线时由 ToolCard 传 mode='session'）。
//
// 行渲染按 kind（对照 ChatPage 主时间线分支）：
//   tool-call   → 紧凑行（状态 glyph + presentation icon/title/subtitle）+ 点击开 dialog 详情 sheet；
//                 该 child 自身 children>0 → 递归 TraceSection（嵌套层级）。
//   agent-text  → MarkdownText（surface 容器）。
//   reasoning   → ReasoningBubble（自带折叠）。
//   cli-output  → CliOutputCard（自带详情 sheet）。
//   agent-event → 单行灰字（getEventPresentation，对照 ChatPage.eventLabel）。
//
// 复用 ToolGroupCard 折叠范式（chevron + @Builder 行渲染）+ ToolCardViews（dialog surface）。
// ArkUI V2 递归组件（自引用 struct）：ArkUI 支持；child.children>0 时递归挂载 TraceSection。

import { ChatBlock, ChatToolCall } from '../chat/ChatBlock';
import { ToolPresentation, getToolPresentation } from '../chat/Presentation';
import { EventPresentation, getEventPresentation } from '../chat/EventPresentation';
import { ToolInputView, ToolResultView } from './ToolCardViews';
import { MarkdownText } from './MarkdownText';
import { ReasoningBubble } from './ReasoningBubble';
import { CliOutputCard } from './CliOutputCard';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
struct TraceSection {
  @Param children: ChatBlock[] = [];
  // 'trace'（Claude Task/Agent：左缩进+左边框，活跃默认展）| 'session'（Codex CodexAgent：默认展）。
  @Param mode: string = 'trace';
  @Local open: boolean = false;
  @Local isDetailOpen: boolean = false;
  @Local detailTool: ChatToolCall = new ChatToolCall();

  aboutToAppear(): void {
    // session 默认展；trace 仅在含活跃（running/error/pending）子代理工具时默认展，否则收起降噪。
    this.open = this.mode === 'session' || this.hasActive;
  }

  private get c(): PaletteColors {
    return paletteOf(getThemeState().isDark);
  }

  // tool-call 子块数（N calls 主口径；0 回退 children 总数）。
  private get callCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.children.length; i++) {
      if (this.children[i].kind === 'tool-call') {
        n++;
      }
    }
    return n;
  }

  private get headerCount(): number {
    const c: number = this.callCount;
    return c > 0 ? c : this.children.length;
  }

  // 各 agent-text 子块 usage（input+output）求和（token chip；0=无/不显）。
  private get totalTokens(): number {
    let n: number = 0;
    for (let i = 0; i < this.children.length; i++) {
      const ch: ChatBlock = this.children[i];
      if (ch.kind === 'agent-text' && ch.usage !== null) {
        n += ch.usage.inputTokens + ch.usage.outputTokens;
      }
    }
    return n;
  }

  // 各子块 durationMs（>=0）求和（秒 chip；0=无/不显）。
  private get totalDurationMs(): number {
    let n: number = 0;
    for (let i = 0; i < this.children.length; i++) {
      const d: number = this.children[i].durationMs;
      if (d >= 0) {
        n += d;
      }
    }
    return n;
  }

  private get hasActive(): boolean {
    for (let i = 0; i < this.children.length; i++) {
      const ch: ChatBlock = this.children[i];
      if (ch.kind === 'tool-call' && ch.tool !== null) {
        const s: string = ch.tool.state;
        if (s === 'running' || s === 'pending' || s === 'error') {
          return true;
        }
      }
    }
    return false;
  }

  // 头部摘要：Trace · N calls · Xk tok · Ys（仅 >0 的 chip 才拼，对照上游 TraceSection header）。
  private get headerLabel(): string {
    let label: string = t('tool.trace');
    const parts: string[] = [];
    const cnt: number = this.headerCount;
    if (cnt > 0) {
      parts.push(t('tool.traceCalls', { n: cnt }));
    }
    const tok: number = this.totalTokens;
    if (tok > 0) {
      parts.push(t('tool.traceTokens', { n: Math.floor(tok / 1000) }));
    }
    const dur: number = this.totalDurationMs;
    if (dur > 0) {
      parts.push(t('tool.traceDuration', { n: Math.floor(dur / 1000) }));
    }
    if (parts.length > 0) {
      label += '  ·  ' + parts.join('  ·  ');
    }
    return label;
  }

  private childStateGlyph(ch: ChatBlock): string {
    if (ch.tool === null) {
      return '●';
    }
    const s: string = ch.tool.state;
    if (s === 'pending') { return '🔒'; }
    if (s === 'completed') { return '✓'; }
    if (s === 'error') { return '✕'; }
    return '●';   // running
  }

  private childStateColor(ch: ChatBlock): string {
    if (ch.tool === null) {
      return this.c.textTertiary;
    }
    const s: string = ch.tool.state;
    if (s === 'completed') { return this.c.success; }
    if (s === 'error') { return this.c.error; }
    if (s === 'pending') { return this.c.warning; }
    return this.c.primary;   // running
  }

  private presentationOf(ch: ChatBlock): ToolPresentation {
    const fallback: ToolPresentation = new ToolPresentation();
    if (ch.tool === null) {
      return fallback;
    }
    return getToolPresentation(ch.tool);
  }

  // 递归 TraceSection 的 mode：子代理工具名为 CodexAgent → session（Flow B）；其余 → trace。
  private childNestedMode(ch: ChatBlock): string {
    if (ch.tool !== null && ch.tool.name === 'CodexAgent') {
      return 'session';
    }
    return 'trace';
  }

  // agent-event 子行单行文本（icon + text，对照 ChatPage.eventLabel）。
  private eventLine(ch: ChatBlock): string {
    if (ch.event === null) {
      return '';
    }
    const p: EventPresentation = getEventPresentation(ch.event);
    return p.icon !== '' ? p.icon + ' ' + p.text : p.text;
  }

  private openDetail(ch: ChatBlock): void {
    if (ch.tool === null) {
      return;
    }
    this.detailTool = ch.tool;
    this.isDetailOpen = true;
  }

  @Builder
  Header() {
    Row({ space: 6 }) {
      Text(this.open ? '▾' : '▸')
        .fontSize(fs(11)).fontColor(this.c.textTertiary)
      Text(this.headerLabel)
        .fontSize(fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.textSecondary)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%').alignItems(VerticalAlign.Center)
  }

  @Builder
  ToolCallRowInner(ch: ChatBlock) {
    Row({ space: 8 }) {
      Text(this.childStateGlyph(ch)).fontSize(fs(13)).fontColor(this.childStateColor(ch))
      Text(this.presentationOf(ch).icon).fontSize(fs(13))
      Column({ space: 2 }) {
        Text(this.presentationOf(ch).title)
          .fontSize(fs(13)).fontColor(this.c.textPrimary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.presentationOf(ch).subtitle !== '') {
          Text(this.presentationOf(ch).subtitle)
            .fontSize(fs(11)).fontColor(this.c.textTertiary).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10).backgroundColor(this.c.surface)
    .border({ width: 0.5, color: this.c.border })
    .onClick(() => { this.openDetail(ch); })
  }

  @Builder
  TraceRow(ch: ChatBlock) {
    if (ch.kind === 'tool-call') {
      Column({ space: 6 }) {
        this.ToolCallRowInner(ch)
        if (ch.children.length > 0) {
          TraceSection({ children: ch.children, mode: this.childNestedMode(ch) })
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    } else if (ch.kind === 'agent-text') {
      if (ch.text !== '') {
        Column() {
          MarkdownText({ content: ch.text })
        }
        .width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(10).backgroundColor(this.c.surface)
      }
    } else if (ch.kind === 'reasoning') {
      if (ch.text !== '') {
        ReasoningBubble({ text: ch.text })
      }
    } else if (ch.kind === 'cli-output') {
      CliOutputCard({ block: ch })
    } else if (ch.kind === 'agent-event') {
      if (ch.event !== null) {
        Text(this.eventLine(ch))
          .fontSize(fs(11)).fontColor(this.c.textTertiary).fontStyle(FontStyle.Italic)
          .width('100%')
      }
    }
  }

  @Builder
  ChildDetailSheet() {
    Scroll() {
      Column() {
        Text(t('tool.input'))
          .fontSize(fs(11)).fontColor(this.c.textTertiary).width('100%').margin({ bottom: 6 })
        ToolInputView({ tool: this.detailTool, surface: 'dialog' })

        Text(t('tool.result'))
          .fontSize(fs(11)).fontColor(this.c.textTertiary).width('100%').margin({ top: 16, bottom: 6 })
        ToolResultView({ tool: this.detailTool, surface: 'dialog' })
      }
      .width('100%').padding(16).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').align(Alignment.Top)
    .scrollBar(BarState.Auto)
  }

  build() {
    Column() {
      Row() {
        this.Header()
      }
      .width('100%').padding({ top: 6, bottom: 6 })
      .onClick(() => { this.open = !this.open; })

      if (this.open) {
        if (this.mode === 'session') {
          // Codex agent-run：默认展，固定高度内滚（Flow B 接线时启用）。
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.children, (ch: ChatBlock) => {
                this.TraceRow(ch)
              }, (ch: ChatBlock) => ch.id)
            }
            .width('100%').padding({ left: 4, right: 4, bottom: 6 }).alignItems(HorizontalAlign.Start)
          }
          .width('100%').height(300).align(Alignment.Top)
          .scrollBar(BarState.Auto)
          .border({ width: 0.5, color: this.c.border }).borderRadius(10)
          .backgroundColor(this.c.bg)
        } else {
          // Claude sidechain：左缩进 + 左边框（嵌套层级可视）。
          Column({ space: 8 }) {
            ForEach(this.children, (ch: ChatBlock) => {
              this.TraceRow(ch)
            }, (ch: ChatBlock) => ch.id)
          }
          .width('100%').padding({ left: 12, top: 4, bottom: 4 }).alignItems(HorizontalAlign.Start)
          .border({ width: { left: 1.5 }, color: this.c.border })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .bindSheet(this.isDetailOpen!!, this.ChildDetailSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      blurStyle: BlurStyle.Thick,
      title: { title: getToolPresentation(this.detailTool).title },
    })
  }
}

export { TraceSection };
