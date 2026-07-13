// RequestUserInputFooter —— 对照 web/src/components/ToolCard/RequestUserInputFooter.tsx
// request_user_input 工具的交互式答题 footer（permission.status==='pending' 时挂载）。
// 与 AskUserQuestionFooter 差异：仅单选（点选即覆盖）/ 无 header / 无 Other / 每题恒带「备注」文本框。
//   answers 嵌套格式（buildRequestUserInputAnswers）→ ApproveOptions.answers → body={answers:{[id]:{answers:[...]}}}。
// V2：@Param tool/sessionId/disabled；@Local step/stateByQuestion(Record<id,AnswerState>)/submitting/error。

import { ChatToolCall } from '../chat/ChatBlock';
import {
  RequestUserInputQuestion,
  RequestUserInputOption,
  RequestUserInputAnswerState,
  parseRequestUserInputInput,
  buildRequestUserInputAnswers
} from '../chat/RequestUserInput';
import { getHubClient, ApproveOptions } from '../api/HubClient';
import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

@ComponentV2
struct RequestUserInputFooter {
  @Param tool: ChatToolCall = new ChatToolCall();
  @Param sessionId: string = '';
  @Param disabled: boolean = false;

  @Local step: number = 0;
  @Local stateByQuestion: Record<string, RequestUserInputAnswerState> = {};
  @Local submitting: boolean = false;
  @Local done: boolean = false;          // approve 成功后置位，等 SSE 翻转卸载前防重复提交
  @Local error: string = '';

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    this.resetState();
  }

  private resetState(): void {
    const init: Record<string, RequestUserInputAnswerState> = {};
    const qs: RequestUserInputQuestion[] = this.questions;
    for (let i = 0; i < qs.length; i++) {
      const s: RequestUserInputAnswerState = new RequestUserInputAnswerState();
      s.selected = '';
      s.userNote = '';
      init[qs[i].id] = s;
    }
    this.stateByQuestion = init;
    this.step = 0;
    this.submitting = false;
    this.done = false;
    this.error = '';
  }

  private get questions(): RequestUserInputQuestion[] {
    return parseRequestUserInputInput(this.tool.input);
  }

  private get total(): number {
    return Math.max(1, this.questions.length);
  }

  private get clampedStep(): number {
    return Math.min(Math.max(this.step, 0), this.total - 1);
  }

  private get current(): RequestUserInputQuestion {
    // 非空：仅在 questions 非空时访问（build 路径已用 this.questions.length > 0 守卫）
    return this.questions[this.clampedStep];
  }

  private get currentState(): RequestUserInputAnswerState | null {
    if (this.questions.length === 0) {
      return null;
    }
    const q: RequestUserInputQuestion = this.current;
    const s: Object | undefined = this.stateByQuestion[q.id];
    return s !== undefined ? s as RequestUserInputAnswerState : null;
  }

  private get isPureText(): boolean {
    return this.questions.length > 0 && this.current.options.length === 0;
  }

  private isSelected(label: string): boolean {
    const s: RequestUserInputAnswerState | null = this.currentState;
    return s !== null && s.selected === label;
  }

  // 校验单题：有选项 → 选了或填了备注即过；纯文本题 → 必须填备注
  private validateQuestion(q: RequestUserInputQuestion): boolean {
    const s: Object | undefined = this.stateByQuestion[q.id];
    if (s === undefined) {
      return false;
    }
    const st: RequestUserInputAnswerState = s as RequestUserInputAnswerState;
    if (q.options.length > 0) {
      return st.selected !== '' || st.userNote.trim().length > 0;
    }
    return st.userNote.trim().length > 0;
  }

  // 改单题字段（克隆整个 record 后改，V2 靠引用变化刷新）
  private setStateField(qId: string, field: string, value: string): void {
    const next: Record<string, RequestUserInputAnswerState> = {};
    const keys: string[] = Object.keys(this.stateByQuestion);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const src: RequestUserInputAnswerState = this.stateByQuestion[k];
      const c: RequestUserInputAnswerState = new RequestUserInputAnswerState();
      c.selected = src.selected;
      c.userNote = src.userNote;
      next[k] = c;
    }
    if (next[qId] === undefined) {
      next[qId] = new RequestUserInputAnswerState();
    }
    if (field === 'selected') {
      next[qId].selected = value;
    } else {
      next[qId].userNote = value;
    }
    this.stateByQuestion = next;
  }

  private selectOption(label: string): void {
    if (this.questions.length === 0) {
      return;
    }
    this.setStateField(this.current.id, 'selected', label);
  }

  private updateNote(value: string): void {
    if (this.questions.length === 0) {
      return;
    }
    this.setStateField(this.current.id, 'note', value);
  }

  private prev(): void {
    this.error = '';
    this.step = Math.max(this.clampedStep - 1, 0);
  }

  private next(): void {
    if (this.questions.length === 0) {
      return;
    }
    const q: RequestUserInputQuestion = this.current;
    if (!this.validateQuestion(q)) {
      this.error = '请选择一个选项或填写备注';
      return;
    }
    this.error = '';
    this.step = Math.min(this.clampedStep + 1, this.questions.length - 1);
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.done) {
      return;
    }
    const qs: RequestUserInputQuestion[] = this.questions;
    for (let i = 0; i < qs.length; i++) {
      if (!this.validateQuestion(qs[i])) {
        this.error = '请选择一个选项或填写备注';
        this.step = i;
        return;
      }
    }
    this.error = '';
    this.submitting = true;
    const p = this.tool.permission;
    if (p === null) {
      this.submitting = false;
      return;
    }
    try {
      const opts: ApproveOptions = new ApproveOptions();
      opts.answers = buildRequestUserInputAnswers(this.stateByQuestion);
      const ok: boolean = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      if (!ok) {
        this.error = '提交失败';
      } else {
        this.done = true;
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : '提交失败';
    } finally {
      this.submitting = false;
    }
  }

  private get currentNote(): string {
    const s: RequestUserInputAnswerState | null = this.currentState;
    return s !== null ? s.userNote : '';
  }

  build() {
    Column() {
      // 头：问题 badge + 进度
      Row() {
        Text('问题')
          .fontSize(fs(11))
          .fontColor(this.c.textSecondary)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.c.surfaceSelected)
          .borderRadius(8)
        Text(`[${this.clampedStep + 1}/${this.total}]`)
          .fontSize(fs(11))
          .fontColor(this.c.textSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.error !== '') {
        Text(this.error)
          .fontSize(fs(11))
          .fontColor(this.c.error)
          .width('100%')
          .margin({ top: 6 })
      }

      this.QuestionBody()

      // 导航
      Row() {
        if (this.total > 1) {
          this.NavButton('上一步', this.c.textSecondary, false, this.clampedStep === 0 || this.submitting || this.done, 'prev')
        }
        Blank()
        if (this.total > 1 && this.clampedStep < this.total - 1) {
          this.NavButton('下一步', this.c.textPrimary, false, this.submitting || this.done, 'next')
        } else {
          this.NavButton(this.done ? '已提交' : (this.submitting ? '提交中…' : '提交'), this.c.success, this.submitting, this.submitting || this.done, 'submit')
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 10 })
      .padding({ top: 8 })
      .border({ width: { top: 1 }, color: this.c.border })
    }
    .width('100%')
    .padding(12)
    .margin({ top: 8 })
    .borderRadius(12)
    .backgroundColor(this.c.bg)
    .border({ width: 1, color: this.c.border })
  }

  @Builder
  QuestionBody() {
    Column({ space: 8 }) {
      if (this.questions.length > 0) {
        if (this.current.question !== '') {
          MarkdownText({ content: this.current.question })
        }

        if (this.isPureText) {
          // 纯文本题：仅备注输入框
          Text('请输入回答')
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
          TextArea({ text: this.currentNote, placeholder: '请输入…' })
            .fontSize(fs(13))
            .fontColor(this.c.textPrimary)
            .placeholderColor(this.c.textTertiary)
            .constraintSize({ minHeight: 72 })
            .width('100%')
            .borderRadius(10)
            .border({ width: 1, color: this.c.border })
            .padding(8)
            .enabled(!this.submitting && !this.disabled)
            .onChange((v: string) => { this.updateNote(v); })
        } else {
          // 有选项：单选列表
          ForEach(this.current.options, (opt: RequestUserInputOption, optIdx: number) => {
            Row({ space: 8 }) {
              Text(this.isSelected(opt.label) ? '●' : '○')
                .fontSize(fs(15))
                .fontColor(this.isSelected(opt.label) ? this.c.success : this.c.textSecondary)
              Column() {
                Text(opt.label)
                  .fontSize(fs(13))
                  .fontColor(this.c.textPrimary)
                if (opt.description !== '') {
                  Text(opt.description)
                    .fontSize(fs(11))
                    .fontColor(this.c.textSecondary)
                    .margin({ top: 2 })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(10)
            .backgroundColor(this.isSelected(opt.label) ? this.c.surfaceSelected : this.c.bg)
            .onClick(() => {
              if (!this.submitting && !this.disabled) {
                this.selectOption(opt.label);
              }
            })
          }, (opt: RequestUserInputOption, optIdx: number) => `q${this.clampedStep}:opt${optIdx}`)

          // 备注（有选项题也恒带）
          Text('备注')
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
          TextArea({ text: this.currentNote, placeholder: '可选：补充说明…' })
            .fontSize(fs(13))
            .fontColor(this.c.textPrimary)
            .placeholderColor(this.c.textTertiary)
            .constraintSize({ minHeight: 56 })
            .width('100%')
            .borderRadius(10)
            .border({ width: 1, color: this.c.border })
            .padding(8)
            .enabled(!this.submitting && !this.disabled)
            .onChange((v: string) => { this.updateNote(v); })
        }
      }
    }
    .width('100%')
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NavButton(label: string, color: string, loading: boolean, disabled: boolean, kind: string) {
    Row() {
      Text(label)
        .fontSize(fs(13))
        .fontColor(disabled ? this.c.textTertiary : color)
      if (loading) {
        LoadingProgress()
          .width(12)
          .height(12)
          .color(color)
          .margin({ left: 4 })
      }
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(this.c.bg)
    .border({ width: 1, color: this.c.border })
    .opacity(disabled ? 0.5 : 1)
    .onClick(() => {
      if (disabled) {
        return;
      }
      if (kind === 'prev') {
        this.prev();
      } else if (kind === 'next') {
        this.next();
      } else {
        this.submit();
      }
    })
  }
}

export { RequestUserInputFooter };
