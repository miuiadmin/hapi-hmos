// ToolCardViews —— 对照 web/src/components/ToolCard/views/（_all.tsx 派发 + _results.tsx 结果视图）
// ArkUI 无动态组件引用 → 用 if-chain 按工具名派发。两个派发组件：
//   ToolInputView：输入视图（inline 卡片体 / dialog 详情 sheet 的「输入」段）
//   ToolResultView：结果视图（仅 dialog 详情 sheet 的「结果」段）
// inline 卡片体仅对 showInline 工具（TodoWrite/update_plan/ExitPlanMode，即 presentation.minimal=false）挂载；
// 其余工具（Edit/Bash/Read 等 minimal=true）卡片体为空，富内容只在 sheet。
// 降级：无 Shiki 语法高亮（CodeBlock 等宽纯文本）；Markdown 复用 MarkdownText。

import { ChatToolCall } from '../chat/ChatBlock';
import { getInputStrAny, hasInputStr, extractResultText, extractStdoutStderr, extractCodexBashDisplay, parseCodexBashOutput, CodexBashDisplay, CodexBashParsedOutput, looksLikeJson, looksLikeHtml, commandStr, codexPatchFiles, basenameOfPath, extractNotebookEditFields, NotebookEditFields, formatNotebookCellMeta } from '../chat/ToolInputUtils';
import { extractTodoChecklist, extractUpdatePlanChecklist } from '../chat/Checklist';
import { parseUnifiedDiff, CodexDiffParsed } from '../chat/CodexDiff';
import { getCodexAgentFieldRows, getCodexAgentPrompt, getCodexAgentActivity, getCodexAgentTargets, parseCodexSpawnAgentResult, parseCodexWaitAgentResult, parseCodexCloseAgentResult, CodexSpawnAgentResult, CodexWaitAgentResult, CodexAgentStatus, AgentFieldRow } from '../chat/CodexAgents';
import { isAskUserQuestionToolName, hasStructuredAnswers } from '../chat/AskUserQuestion';
import { CodeBlock } from './CodeBlock';
import { DiffView } from './DiffView';
import { ChecklistList } from './ChecklistList';
import { MarkdownText } from './MarkdownText';
import { AskUserQuestionView } from './AskUserQuestionView';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

const MAX_COMPACT_EDITS: number = 3;

// Codex 子代理集群 6 工具名（CodexAgent + 5 蛇形）
const CODEX_AGENT_TOOLS: string[] = ['CodexAgent', 'spawn_agent', 'send_input', 'resume_agent', 'wait_agent', 'close_agent'];

function isCodexAgentToolName(name: string): boolean {
  for (let i = 0; i < CODEX_AGENT_TOOLS.length; i++) {
    if (CODEX_AGENT_TOOLS[i] === name) {
      return true;
    }
  }
  return false;
}

// a 非空取 a，否则取 b（'' 哨兵）
function firstNonEmpty2(a: string, b: string): string {
  return a !== '' ? a : b;
}

// wait_agent 状态计数（state→count，保序）—— @Builder 内禁命令式循环，故前置纯函数
class AgentStateCount {
  state: string = '';
  count: number = 0;
}

function aggregateAgentStateCounts(statuses: CodexAgentStatus[]): AgentStateCount[] {
  const map: Record<string, number> = {};
  const order: string[] = [];
  for (let i = 0; i < statuses.length; i++) {
    const s: string = statuses[i].state;
    if (map[s] === undefined) {
      map[s] = 1;
      order.push(s);
    } else {
      map[s] = map[s] + 1;
    }
  }
  const out: AgentStateCount[] = [];
  for (let i = 0; i < order.length; i++) {
    const c: AgentStateCount = new AgentStateCount();
    c.state = order[i];
    c.count = map[order[i]];
    out.push(c);
  }
  return out;
}

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
    return commandStr(this.input);
  }

  private codexPatchFileList(): string[] {
    return codexPatchFiles(this.input);
  }

  private notebookEditFields(): NotebookEditFields {
    return extractNotebookEditFields(this.input);
  }

  private notebookEditMeta(): string {
    const f: NotebookEditFields = this.notebookEditFields();
    return formatNotebookCellMeta(f.cellType, f.cellId);
  }

  private planText(): string {
    return getInputStrAny(this.input, ['plan']);
  }

  private codexDiffUnified(): string {
    return getInputStrAny(this.input, ['unified_diff']);
  }

  private codexDiffParsed(): CodexDiffParsed {
    return parseUnifiedDiff(this.codexDiffUnified());
  }

  private jsonInput(): string {
    try {
      return this.input !== null ? JSON.stringify(this.input, null, 2) : t('tool.inputEmpty');
    } catch (e) {
      return t('tool.cannotSerialize');
    }
  }

  private codexAgentRows(): AgentFieldRow[] {
    return getCodexAgentFieldRows(this.tool.name, this.input);
  }

  private codexAgentPrompt(): string {
    return getCodexAgentPrompt(this.input);
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
        ChecklistList({ items: extractTodoChecklist(this.input, this.tool.result), emptyLabel: t('tool.todoEmpty') })
      } else if (this.tool.name === 'update_plan') {
        ChecklistList({ items: extractUpdatePlanChecklist(this.input, this.tool.result), emptyLabel: t('tool.planEmpty') })
      } else if (this.tool.name === 'ExitPlanMode' || this.tool.name === 'exit_plan_mode') {
        this.PlanInput()
      } else if (this.tool.name === 'Bash' || this.tool.name === 'shell_command' || this.tool.name === 'run_shell_command' || this.tool.name === 'CodexBash') {
        this.BashInput()
      } else if (this.tool.name === 'CodexDiff') {
        this.CodexDiffInput()
      } else if (this.tool.name === 'CodexPatch') {
        this.CodexPatchInput()
      } else if (this.tool.name === 'NotebookEdit') {
        this.NotebookEditInput()
      } else if (isCodexAgentToolName(this.tool.name)) {
        this.CodexAgentInput()
      } else if (isAskUserQuestionToolName(this.tool.name)) {
        AskUserQuestionView({ tool: this.tool })
      } else {
        CodeBlock({ code: this.jsonInput(), language: 'json', title: t('tool.input'), collapseLongContent: this.isInline })
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
        Text(t('tool.moreEdits', { n: this.multiEdits().length - MAX_COMPACT_EDITS }))
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
        CodeBlock({ code: this.writeContent(), language: 'text', title: t('tool.draft'), collapseLongContent: false })
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
      CodeBlock({ code: this.bashCommand(), language: 'bash', title: t('tool.command'), collapseLongContent: this.isInline })
    }
  }

  // CodexDiff：input.unified_diff 统一 diff 串 → 复用 DiffView 染色（对照 web CodexDiffView.tsx:57-72）。
  //   inline 不传 filePath（无文件头）；dialog 传 fileName + comfortable。空 diff → 回退 JSON。
  @Builder
  CodexDiffInput() {
    if (this.codexDiffUnified() !== '') {
      DiffView({
        oldString: this.codexDiffParsed().oldText,
        newString: this.codexDiffParsed().newText,
        filePath: this.isInline ? '' : this.codexDiffParsed().fileName,
        size: this.isInline ? 'compact' : 'comfortable'
      })
    } else {
      CodeBlock({ code: this.jsonInput(), language: 'json', title: t('tool.input'), collapseLongContent: this.isInline })
    }
  }

  // CodexPatch（apply_patch）：input.changes 是文件→改动映射，body 仅列文件名 basename（对照 web CodexPatchView，
  //   不展开 diff 内容）。空 changes → 回退 JSON。
  @Builder
  CodexPatchInput() {
    if (this.codexPatchFileList().length > 0) {
      Column({ space: 2 }) {
        ForEach(this.codexPatchFileList(), (file: string, idx: number) => {
          Text(basenameOfPath(file))
            .fontSize(fs(12))
            .fontColor(this.c.codeText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }, (file: string, idx: number) => `patch-${idx}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      CodeBlock({ code: this.jsonInput(), language: 'json', title: t('tool.input'), collapseLongContent: this.isInline })
    }
  }

  // NotebookEdit（Claude Jupyter）：cell 编辑 body（端口增强——上游无 body view，仅 JSON dump）。
  //   cell 元信息行（cellType · #cellId）+ new_source：markdown cell→MarkdownText 渲染预览，code cell→CodeBlock 显源。
  //   delete（无 new_source）仅显元信息行；全空 → 回退 JSON。
  @Builder
  NotebookEditInput() {
    if (this.notebookEditFields().newSource !== '') {
      Column({ space: 6 }) {
        if (this.notebookEditMeta() !== '') {
          Text(this.notebookEditMeta())
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        if (this.notebookEditFields().cellType === 'markdown') {
          MarkdownText({ content: this.notebookEditFields().newSource })
        } else {
          CodeBlock({ code: this.notebookEditFields().newSource, language: 'text', title: t('tool.source'), collapseLongContent: this.isInline })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.notebookEditMeta() !== '') {
      Text(this.notebookEditMeta())
        .fontSize(fs(12))
        .fontColor(this.c.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    } else {
      CodeBlock({ code: this.jsonInput(), language: 'json', title: t('tool.input'), collapseLongContent: this.isInline })
    }
  }

  // CodexAgent / spawn_agent / send_input / resume_agent / wait_agent / close_agent（对照 web CodexAgentView）。
  //   Prompt 块仅 dialog；字段 pill 行总显（label 本地化）；不重复内联结果摘要（subtitle 已含，端口增强避冗余）；空 → JSON 回退。
  @Builder
  CodexAgentInput() {
    Column({ space: 6 }) {
      if (!this.isInline) {
        if (this.codexAgentPrompt() !== '') {
          Column() {
            Text(t('agent.promptLabel'))
              .fontSize(fs(11))
              .fontColor(this.c.textTertiary)
              .margin({ bottom: 4 })
            Text(this.codexAgentPrompt())
              .fontSize(fs(12))
              .fontColor(this.c.textPrimary)
              .width('100%')
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.surface)
          .borderRadius(12)
          .alignItems(HorizontalAlign.Start)
        }
      }
      if (this.codexAgentRows().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.codexAgentRows(), (row: AgentFieldRow, idx: number) => {
            Row({ space: 4 }) {
              Text(row.label + ':')
                .fontSize(fs(11))
                .fontColor(this.c.textPrimary)
              Text(row.value)
                .fontSize(fs(11))
                .fontColor(this.c.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: '75%' })
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor(this.c.surfaceSelected)
            .borderRadius(10)
            .margin({ right: 4, bottom: 4 })
          }, (row: AgentFieldRow, idx: number) => `agent-field-${idx}-${row.label}`)
        }
        .width('100%')
      } else {
        CodeBlock({ code: this.jsonInput(), language: 'json', title: t('tool.input'), collapseLongContent: this.isInline })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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

  // —— CodexBash 对象结果（extractCodexBashDisplay）——
  private codexBashDisplay(): CodexBashDisplay | null {
    return extractCodexBashDisplay(this.tool.result);
  }
  private codexBashExitLabel(): string {
    const d: CodexBashDisplay | null = this.codexBashDisplay();
    if (d === null) {
      return '';
    }
    if (d.hasExitCode) {
      return `exit ${d.exitCode.toString()}`;
    }
    return d.status !== '' ? d.status : t('tool.completed');
  }
  private codexBashStdout(): string {
    const d: CodexBashDisplay | null = this.codexBashDisplay();
    return d === null ? '' : d.stdout.trimEnd();
  }
  private codexBashStderr(): string {
    const d: CodexBashDisplay | null = this.codexBashDisplay();
    return d === null ? '' : d.stderr.trimEnd();
  }
  private codexBashDisplayEmptyLabel(): string {
    const d: CodexBashDisplay | null = this.codexBashDisplay();
    if (d === null) {
      return t('tool.noOutput');
    }
    return (d.hasExitCode && d.exitCode === 0) || d.status === 'completed' ? t('tool.completed') : t('tool.noOutput');
  }

  // —— CodexBash 字符串结果（parseCodexBashOutput；仅对字符串 result）——
  private codexBashParsed(): CodexBashParsedOutput | null {
    const r: Object | null = this.tool.result;
    if (r === null || typeof r !== 'string') {
      return null;
    }
    return parseCodexBashOutput(r as string);
  }
  private codexBashParsedExitLabel(): string {
    const p: CodexBashParsedOutput | null = this.codexBashParsed();
    if (p === null || !p.hasExitCode) {
      return '';
    }
    return `exit ${p.exitCode.toString()}`;
  }
  private codexBashWallTime(): string {
    const p: CodexBashParsedOutput | null = this.codexBashParsed();
    return p === null ? '' : p.wallTime;
  }
  private codexBashParsedOutputText(): string {
    const p: CodexBashParsedOutput | null = this.codexBashParsed();
    return p === null ? '' : p.output.trim();
  }

  // —— Skill 结果（@Builder 内禁局部变量 → 前置纯 getter）——
  private skillErrorText(): string {
    const txt: string = this.resultText().trim();
    return txt !== '' ? txt : t('tool.skillFailed');
  }
  private skillLoadedLabel(): string {
    const skill: string = getInputStrAny(this.tool.input, ['skill']);
    return skill !== '' ? t('tool.skillLoaded', { name: skill }) : t('tool.skillLoadedShort');
  }

  // —— CodexDiff 结果解析（parseUnifiedDiff 恒返回非空；old/new 均空 = 非 diff 文本 → 回退 CodeBlock）——
  private codexDiffParsed(): CodexDiffParsed {
    return parseUnifiedDiff(this.resultText());
  }

  private placeholderForState(): string {
    if (this.tool.state === 'pending') {
      return t('tool.statePending');
    }
    if (this.tool.state === 'running') {
      return t('tool.stateRunning');
    }
    return t('tool.noOutput');
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

  private codexAgentActivityText(): string {
    return getCodexAgentActivity(this.tool.input);
  }

  private codexAgentTargetsList(): string[] {
    return getCodexAgentTargets(this.tool.input);
  }

  private spawnParsed(): CodexSpawnAgentResult | null {
    return parseCodexSpawnAgentResult(this.tool.result);
  }

  private waitParsed(): CodexWaitAgentResult | null {
    return parseCodexWaitAgentResult(this.tool.result);
  }

  private closeParsed(): CodexAgentStatus | null {
    return parseCodexCloseAgentResult(this.tool.result);
  }

  private waitStateCounts(): AgentStateCount[] {
    const parsed: CodexWaitAgentResult | null = parseCodexWaitAgentResult(this.tool.result);
    return parsed === null ? [] : aggregateAgentStateCounts(parsed.statuses);
  }

  private waitStatuses(): CodexAgentStatus[] {
    const parsed: CodexWaitAgentResult | null = parseCodexWaitAgentResult(this.tool.result);
    return parsed === null ? [] : parsed.statuses;
  }

  private waitTimedOut(): boolean {
    const parsed: CodexWaitAgentResult | null = parseCodexWaitAgentResult(this.tool.result);
    return parsed !== null && parsed.timedOut;
  }

  private spawnNickname(): string {
    const parsed: CodexSpawnAgentResult | null = parseCodexSpawnAgentResult(this.tool.result);
    return parsed === null ? '' : parsed.nickname;
  }

  private spawnAgentId(): string {
    const parsed: CodexSpawnAgentResult | null = parseCodexSpawnAgentResult(this.tool.result);
    return parsed === null ? '' : parsed.agentId;
  }

  private closeState(): string {
    const parsed: CodexAgentStatus | null = parseCodexCloseAgentResult(this.tool.result);
    return parsed === null ? '' : parsed.state;
  }

  private closeText(): string {
    const parsed: CodexAgentStatus | null = parseCodexCloseAgentResult(this.tool.result);
    return parsed === null ? '' : parsed.text;
  }

  build() {
    Column() {
      if (isAskUserQuestionToolName(this.tool.name)) {
        // answers 已结构化作答 → 结果段不渲（避与已答输入视图双显）；无作答 → 回退 Markdown 结果
        if (!hasStructuredAnswers(this.tool)) {
          this.MarkdownResult()
        }
      } else if (this.tool.name === 'Bash' || this.tool.name === 'shell_command' || this.tool.name === 'run_shell_command' || this.tool.name === 'CodexBash') {
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
      } else if (this.tool.name === 'Skill') {
        this.SkillResult()
      } else if (this.tool.name === 'CodexDiff') {
        this.CodexDiffResult()
      } else if (isCodexAgentToolName(this.tool.name)) {
        this.AgentResult()
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
    } else if (this.tool.name === 'CodexBash' && this.codexBashDisplay() !== null) {
      this.CodexBashObjectResult()
    } else if (this.tool.name === 'CodexBash' && this.codexBashParsed() !== null) {
      this.CodexBashStringResult()
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
      CodeBlock({ code: this.resultText(), language: 'text', title: t('tool.output'), collapseLongContent: this.isInline })
    } else {
      this.Pill(t('tool.noOutput'))
    }
  }

  // CodexBash 对象结果（对照上游 CodexBashResultView + extractCodexBashDisplay）：
  //   exit/status meta pill + stdout/stderr CodeBlock；空输出 → Done/no-output pill。
  @Builder
  CodexBashObjectResult() {
    Column({ space: 6 }) {
      this.Pill(this.codexBashExitLabel())
      if (this.codexBashStdout() !== '') {
        CodeBlock({ code: this.codexBashStdout(), language: 'text', title: 'stdout', collapseLongContent: this.isInline })
      }
      if (this.codexBashStderr() !== '') {
        CodeBlock({ code: this.codexBashStderr(), language: 'text', title: 'stderr', collapseLongContent: this.isInline })
      }
      if (this.codexBashStdout() === '' && this.codexBashStderr() === '') {
        this.Pill(this.codexBashDisplayEmptyLabel())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // CodexBash 字符串结果（对照上游 GenericResultView 字符串分支 + parseCodexBashOutput）：
  //   exit pill + wallTime pill + output CodeBlock。
  @Builder
  CodexBashStringResult() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        if (this.codexBashParsedExitLabel() !== '') {
          this.Pill(this.codexBashParsedExitLabel())
        }
        if (this.codexBashWallTime() !== '') {
          this.Pill(this.codexBashWallTime())
        }
      }
      if (this.codexBashParsedOutputText() !== '') {
        CodeBlock({ code: this.codexBashParsedOutputText(), language: 'text', title: t('tool.output'), collapseLongContent: this.isInline })
      } else {
        this.Pill(t('tool.noOutput'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ReadResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      CodeBlock({ code: this.resultText(), language: 'text', title: this.readPath() !== '' ? this.readPath() : t('tool.fileContent'), collapseLongContent: this.isInline })
    } else {
      this.Pill(t('tool.noOutput'))
    }
  }

  @Builder
  MutationResult() {
    if (this.tool.result === null) {
      this.Pill(this.tool.state === 'completed' ? t('tool.completed') : this.placeholderForState())
    } else if (this.resultText().trim() !== '') {
      if (this.tool.state === 'error') {
        // error：红字 + 近似等宽（对照上游 MutationResultView error：text-red-600 + code 模式；
        //   CodeBlock 不支持自定义字色 → 用 Text + Courier New 近似 mono）
        Text(this.resultText())
          .fontSize(fs(13))
          .fontColor(this.c.error)
          .fontFamily('Courier New')
          .width('100%')
      } else {
        CodeBlock({ code: this.resultText(), language: 'text', title: t('tool.result'), collapseLongContent: this.isInline })
      }
    } else {
      this.Pill(this.tool.state === 'completed' ? t('tool.completed') : t('tool.noOutput'))
    }
  }

  // Skill 结果（对照上游 SkillResultView）：null+completed→「技能已加载」；error→红字（空则「技能加载失败」）；
  //   成功→「已加载「{name}」」/「技能已加载」pill。
  @Builder
  SkillResult() {
    if (this.tool.result === null) {
      this.Pill(this.tool.state === 'completed' ? t('tool.skillLoadedShort') : this.placeholderForState())
    } else if (this.tool.state === 'error') {
      Text(this.skillErrorText())
        .fontSize(fs(13))
        .fontColor(this.c.error)
        .width('100%')
    } else {
      this.Pill(this.skillLoadedLabel())
    }
  }

  // CodexDiff 结果（对照上游 CodexDiffResultView）。端口无 Shiki diff 语法高亮 → 路径 A：parseUnifiedDiff
  //   成功（解析出 +/- 行内容）则 DiffView 行级染色（复用 input 侧已验证管线），否则回退 CodeBlock 纯文本。
  @Builder
  CodexDiffResult() {
    if (this.tool.result === null) {
      this.Pill(this.tool.state === 'completed' ? t('tool.completed') : this.placeholderForState())
    } else if (this.resultText() !== '') {
      if (this.codexDiffParsed().oldText !== '' || this.codexDiffParsed().newText !== '') {
        DiffView({
          oldString: this.codexDiffParsed().oldText,
          newString: this.codexDiffParsed().newText,
          filePath: this.codexDiffParsed().fileName
        })
      } else {
        CodeBlock({ code: this.resultText(), language: 'text', title: t('tool.output'), collapseLongContent: this.isInline })
      }
    } else {
      this.Pill(t('tool.completed'))
    }
  }

  @Builder
  MarkdownResult() {
    if (this.tool.result === null) {
      this.Pill(this.placeholderForState())
    } else if (this.resultText() !== '') {
      MarkdownText({ content: this.resultText() })
    } else {
      this.Pill(t('tool.noOutput'))
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
      this.Pill(t('tool.noOutput'))
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
      this.Pill(t('tool.noOutput'))
    }
  }

  // label+value pill（Name/ID 等，对照上游 AgentIdPill）
  @Builder
  LabelPill(label: string, value: string) {
    Row({ space: 4 }) {
      Text(label + ':')
        .fontSize(fs(11))
        .fontColor(this.c.textPrimary)
      Text(value)
        .fontSize(fs(11))
        .fontColor(this.c.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '70%' })
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .backgroundColor(this.c.surfaceSelected)
    .borderRadius(10)
    .margin({ right: 4, bottom: 4 })
  }

  // 子代理集群结果（对照 web CodexAgentResultView）：此视图本就详情-sheet-only。
  @Builder
  AgentResult() {
    if (this.tool.result === null) {
      this.Pill(firstNonEmpty2(this.codexAgentActivityText(), this.placeholderForState()))
    } else if (this.tool.state === 'error') {
      Text(this.resultText().trim() !== '' ? this.resultText() : t('agent.toolFailed'))
        .fontSize(fs(13))
        .fontColor(this.c.error)
        .width('100%')
    } else if (this.tool.name === 'spawn_agent') {
      this.SpawnAgentResult()
    } else if (this.tool.name === 'wait_agent') {
      this.WaitAgentResult()
    } else if (this.tool.name === 'close_agent') {
      this.CloseAgentResult()
    } else {
      if (this.resultText() !== '') {
        MarkdownText({ content: this.resultText() })
      } else {
        this.Pill(this.placeholderForState())
      }
    }
  }

  @Builder
  NAgentsPill(count: number) {
    this.Pill(count === 1 ? t('agent.nAgent', { n: count }) : t('agent.nAgents', { n: count }))
  }

  @Builder
  SpawnAgentResult() {
    if (this.spawnParsed() !== null) {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.Pill(t('agent.launchedShort'))
        if (this.spawnNickname() !== '') {
          this.LabelPill(t('agent.name'), this.spawnNickname())
        }
        if (this.spawnAgentId() !== '') {
          this.LabelPill(t('agent.id'), this.spawnAgentId())
        }
      }
      .width('100%')
    } else if (this.resultText() !== '') {
      MarkdownText({ content: this.resultText() })
    } else {
      this.Pill(this.placeholderForState())
    }
  }

  @Builder
  WaitAgentResult() {
    if (this.waitParsed() !== null) {
      if (this.waitStatuses().length === 0) {
        this.Pill(this.waitTimedOut() ? t('agent.timedOut') : t('agent.noStatus'))
      } else {
        Column({ space: 8 }) {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.waitTimedOut()) {
              this.Pill(t('agent.timedOut'))
            }
            this.NAgentsPill(this.waitStatuses().length)
            ForEach(this.waitStateCounts(), (sc: AgentStateCount, idx: number) => {
              this.Pill(`${sc.count} ${sc.state}`)
            }, (sc: AgentStateCount, idx: number) => `wstate-${idx}-${sc.state}`)
          }
          .width('100%')
          Column({ space: 6 }) {
            ForEach(this.waitStatuses(), (status: CodexAgentStatus, idx: number) => {
              Column() {
                Row({ space: 6 }) {
                  this.Pill(status.state)
                  Text(status.agentId)
                    .fontSize(fs(11))
                    .fontColor(this.c.textSecondary)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                if (status.text !== '') {
                  MarkdownText({ content: status.text })
                    .margin({ top: 4 })
                }
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.c.surface)
              .borderRadius(12)
              .alignItems(HorizontalAlign.Start)
            }, (status: CodexAgentStatus, idx: number) => `wagent-${idx}-${status.agentId}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    } else if (this.resultText() !== '') {
      MarkdownText({ content: this.resultText() })
    } else {
      this.Pill(this.placeholderForState())
    }
  }

  @Builder
  CloseAgentResult() {
    if (this.closeParsed() !== null) {
      Column({ space: 6 }) {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.Pill(t('agent.closed'))
          if (this.codexAgentTargetsList().length > 0) {
            this.LabelPill(t('agent.id'), this.codexAgentTargetsList()[0])
          }
          this.Pill(this.closeState())
        }
        .width('100%')
        if (this.closeText() !== '') {
          MarkdownText({ content: this.closeText() })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.resultText() !== '') {
      MarkdownText({ content: this.resultText() })
    } else {
      this.Pill(this.placeholderForState())
    }
  }
}

export { ToolInputView, ToolResultView };
