// ToolCardViews —— 对照 web/src/components/ToolCard/views/（_all.tsx 派发 + _results.tsx 结果视图）
// ArkUI 无动态组件引用 → 用 if-chain 按工具名派发。两个派发组件：
//   ToolInputView：输入视图（inline 卡片体 / dialog 详情 sheet 的「输入」段）
//   ToolResultView：结果视图（仅 dialog 详情 sheet 的「结果」段）
// inline 卡片体仅对 showInline 工具（TodoWrite/update_plan/ExitPlanMode，即 presentation.minimal=false）挂载；
// 其余工具（Edit/Bash/Read 等 minimal=true）卡片体为空，富内容只在 sheet。
// 降级：无 Shiki 语法高亮（CodeBlock 等宽纯文本）；Markdown 复用 MarkdownText。

import { ChatToolCall } from '../chat/ChatBlock';
import { getInputStrAny, hasInputStr, extractResultText, extractStdoutStderr, looksLikeJson, looksLikeHtml } from '../chat/ToolInputUtils';
import { extractTodoChecklist, extractUpdatePlanChecklist } from '../chat/Checklist';
import { CodeBlock } from './CodeBlock';
import { DiffView } from './DiffView';
import { ChecklistList } from './ChecklistList';
import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

const MAX_COMPACT_EDITS: number = 3;

class EditPair {
  oldStr: string = '';
  newStr: string = '';
}

function extractMultiEdits(input: Record<string, Object> | null): EditPair[] {
  const out: EditPair[] = [];
  if (input === null) {
    return out;
  }
  const edits: Object = input['edits'];
  if (!Array.isArray(edits)) {
    return out;
  }
  const arr: Object[] = edits as Object[];
  for (let i = 0; i < arr.length; i++) {
    const e: Object = arr[i];
    if (e === null || e === undefined || typeof e !== 'object' || Array.isArray(e)) {
      continue;
    }
    const rec: Record<string, Object> = e as Record<string, Object>;
    const o: Object = rec['old_string'];
    const n: Object = rec['new_string'];
    const oldS: string = typeof o === 'string' ? o : '';
    const newS: string = typeof n === 'string' ? n : '';
    if (oldS !== '' || newS !== '') {
      const p: EditPair = new EditPair();
      p.oldStr = oldS;
      p.newStr = newS;
      out.push(p);
    }
  }
  return out;
}

// ===== 输入视图派发 =====
@ComponentV2
struct ToolInputView {
  @Param tool: ChatToolCall = new ChatToolCall();
  @Param surface: string = 'inline';   // 'inline' | 'dialog'

  // 主题（读 @Trace isDark 建立刷新依赖）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get isInline(): boolean {
    return this.surface === 'inline';
  }

  private get input(): Record<string, Object> | null {
    return this.tool.input;
  }

  private get hasEditStrings(): boolean {
    return hasInputStr(this.input, 'old_string') && hasInputStr(this.input, 'new_string');
  }

  private editOld(): string {
    return getInputStrAny(this.input, ['old_string']);
  }

  private editNew(): string {
    return getInputStrAny(this.input, ['new_string']);
  }

  private multiEdits(): EditPair[] {
    return extractMultiEdits(this.input);
  }

  private writeContent(): string {
    const c: Object = this.input !== null ? this.input['content'] : null;
    if (typeof c === 'string') {
      return c;
    }
    const t: Object = this.input !== null ? this.input['text'] : null;
    return typeof t === 'string' ? t : '';
  }

  private writePath(): string {
    return getInputStrAny(this.input, ['file_path', 'path']);
  }

  private bashCommand(): string {
    const cmd: Object = this.input !== null ? this.input['command'] : null;
    if (typeof cmd === 'string') {
      return cmd;
    }
    if (Array.isArray(cmd)) {
      const arr: Object[] = cmd as Object[];
      const parts: string[] = [];
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          parts.push(arr[i] as string);
        }
      }
      return parts.join(' ');
    }
    return getInputStrAny(this.input, ['cmd']);
  }

  private planText(): string {
    return getInputStrAny(this.input, ['plan']);
  }

  private jsonInput(): string {
    try {
      return this.input !== null ? JSON.stringify(this.input, null, 2) : '(无)';
    } catch (e) {
      return '(无法序列化)';
    }
  }

  build() {
    Column() {
      if (this.tool.name === 'Edit') {
        if (this.hasEditStrings) {
          DiffView({ oldString: this.editOld(), newString: this.editNew(), size: this.isInline ? 'compact' : 'comfortable' })
        }
      } else if (this.tool.name === 'MultiEdit') {
        this.MultiEditInput()
      } else if (this.tool.name === 'Write') {
        this.WriteInput()
      } else if (this.tool.name === 'TodoWrite') {
        ChecklistList({ items: extractTodoChecklist(this.input, this.tool.result), emptyLabel: '(无待办)' })
      } else if (this.tool.name === 'update_plan') {
        ChecklistList({ items: extractUpdatePlanChecklist(this.input, this.tool.result), emptyLabel: '(无步骤)' })
      } else if (this.tool.name === 'ExitPlanMode' || this.tool.name === 'exit_plan_mode') {
        this.PlanInput()
      } else if (this.tool.name === 'Bash' || this.tool.name === 'shell_command' || this.tool.name === 'run_shell_command') {
        this.BashInput()
      } else {
        CodeBlock({ code: this.jsonInput(), language: 'json', title: '输入', collapseLongContent: this.isInline })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MultiEditInput() {
    Column({ space: 8 }) {
      ForEach(this.multiEdits(), (ep: EditPair, idx: number) => {
        DiffView({ oldString: ep.oldStr, newString: ep.newStr })
      }, (ep: EditPair, idx: number) => `edit-${idx}`)
      if (this.isInline && this.multiEdits().length > MAX_COMPACT_EDITS) {
        Text(`（还有 ${this.multiEdits().length - MAX_COMPACT_EDITS} 处编辑）`)
          .fontSize(fs(11))
          .fontColor(this.c.textSecondary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  WriteInput() {
    if (this.isInline) {
      // inline：把整段内容当新增 diff（对照上游 WriteView inline 分支）
      DiffView({ oldString: '', newString: this.writeContent() })
    } else {
      Column({ space: 6 }) {
        if (this.writePath() !== '') {
          Text(this.writePath())
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        CodeBlock({ code: this.writeContent(), language: 'text', title: '草稿', collapseLongContent: false })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  PlanInput() {
    if (this.planText() !== '') {
      MarkdownText({ content: this.planText() })
    }
  }

  @Builder
  BashInput() {
    if (this.bashCommand() !== '') {
      CodeBlock({ code: this.bashCommand(), language: 'bash', title: '命令', collapseLongContent: this.isInline })
    }
  }
}

// ===== 结果视图派发 =====
@ComponentV2
struct ToolResultView {
  @Param tool: ChatToolCall = new ChatToolCall();
  @Param surface: string = 'dialog';

  // 主题（读 @Trace isDark 建立刷新依赖）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get isInline(): boolean {
    return this.surface === 'inline';
  }

  private resultText(): string {
    return extractResultText(this.tool.result);
  }

  private bashStdout(): string {
    const stdio = extractStdoutStderr(this.tool.result);
    return stdio !== null ? stdio.stdout : '';
  }

  private bashStderr(): string {
    const stdio = extractStdoutStderr(this.tool.result);
    return stdio !== null ? stdio.stderr : '';
  }

  private placeholderForState(): string {
    if (this.tool.state === 'pending') {
      return '(等待批准)';
    }
    if (this.tool.state === 'running') {
      return '(运行中)';
    }
    return '(无输出)';
  }

  private readPath(): string {
    return getInputStrAny(this.tool.input, ['file_path', 'path', 'name']);
  }

  private jsonResult(): string {
    const r: Object | null = this.tool.result;
    if (r === null || r === undefined) {
      return '';
    }
    try {
      return JSON.stringify(r, null, 2);
    } catch (e) {
      return '';
    }
  }

  build() {
    Column() {
      if (this.tool.name === 'Bash' || this.tool.name === 'shell_command' || this.tool.name === 'run_shell_command') {
        this.BashResult()
      } else if (this.tool.name === 'Read' || this.tool.name === 'NotebookRead') {
        this.ReadResult()
      } else if (this.tool.name === 'Edit' || this.tool.name === 'MultiEdit' || this.tool.name === 'Write' || this.tool.name === 'NotebookEdit') {
        this.MutationResult()
      } else if (this.tool.name === 'TodoWrite') {
        ChecklistList({ items: extractTodoChecklist(this.tool.input, this.tool.result), emptyLabel: this.placeholderForState() })
      } else if (this.tool.name === 'Task' || this.tool.name === 'WebFetch' || this.tool.name === 'WebSearch'
        || this.tool.name === 'ExitPlanMode' || this.tool.name === 'exit_plan_mode') {
        this.MarkdownResult()
      } else if (this.tool.name === 'Glob' || this.tool.name === 'Grep' || this.tool.name === 'LS') {
        this.LineListResult()
      } else {
        this.GenericResult()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Pill(text: string) {
    Text(text)
      .fontSize(fs(11))
      .fontColor(this.c.textSecondary)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(this.c.surfaceSelected)
      .borderRadius(10)
  }

  @Builder
  BashResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.bashStdout() !== '' || this.bashStderr() !== '') {
      Column({ space: 6 }) {
        if (this.bashStdout() !== '') {
          CodeBlock({ code: this.bashStdout(), language: 'text', title: 'stdout', collapseLongContent: this.isInline })
        }
        if (this.bashStderr() !== '') {
          CodeBlock({ code: this.bashStderr(), language: 'text', title: 'stderr', collapseLongContent: this.isInline })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.resultText() !== '') {
      CodeBlock({ code: this.resultText(), language: 'text', title: '输出', collapseLongContent: this.isInline })
    } else {
      this.Pill('(无输出)')
    }
  }

  @Builder
  ReadResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      CodeBlock({ code: this.resultText(), language: 'text', title: this.readPath() !== '' ? this.readPath() : '文件内容', collapseLongContent: this.isInline })
    } else {
      this.Pill('(无输出)')
    }
  }

  @Builder
  MutationResult() {
    if (this.tool.result === null) {
      this.Pill(this.tool.state === 'completed' ? '完成' : this.placeholderForState())
    } else if (this.resultText().trim() !== '') {
      CodeBlock({ code: this.resultText(), language: 'text', title: '结果', collapseLongContent: this.isInline })
    } else {
      this.Pill(this.tool.state === 'completed' ? '完成' : '(无输出)')
    }
  }

  @Builder
  MarkdownResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      MarkdownText({ content: this.resultText() })
    } else {
      this.Pill('(无输出)')
    }
  }

  @Builder
  LineListResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      Column({ space: 2 }) {
        ForEach(this.splitResultLines(), (line: string, idx: number) => {
          Text(line)
            .fontSize(fs(12))
            .fontColor(this.c.codeText)
            .width('100%')
        }, (line: string, idx: number) => `line-${idx}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      this.Pill('(无输出)')
    }
  }

  private splitResultLines(): string[] {
    const raw: string = this.resultText();
    const all: string[] = raw.split('\n');
    const out: string[] = [];
    for (let i = 0; i < all.length; i++) {
      const t: string = all[i].trim();
      if (t.length > 0) {
        out.push(t);
      }
    }
    return out;
  }

  @Builder
  GenericResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      if (looksLikeJson(this.resultText()) || looksLikeHtml(this.resultText())) {
        CodeBlock({ code: this.resultText(), language: looksLikeJson(this.resultText()) ? 'json' : 'html', collapseLongContent: this.isInline })
      } else {
        MarkdownText({ content: this.resultText() })
      }
    } else if (this.jsonResult() !== '') {
      CodeBlock({ code: this.jsonResult(), language: 'json', title: 'JSON', collapseLongContent: this.isInline })
    } else {
      this.Pill('(无输出)')
    }
  }
}

export { ToolInputView, ToolResultView };
