// AskUserQuestionFooter —— 对照 web/src/components/ToolCard/AskUserQuestionFooter.tsx
// AskUserQuestion 工具的交互式答题 footer（permission.status==='pending' 时挂载；approved 后卸载）。
// 功能：多题翻页 / 单选·多选（multiSelect）/ 固定「其他」行 + 自填文本 / 校验 / 提交（复用 approve 端点只发 {answers}）。
//   提交后不乐观 patch agentState —— 坐等服务端 SESSION_UPDATED → permission.status pending→approved → footer 卸载、改由已答视图回显。
// ArkUI 控件取舍：选项行用自绘 Row + 字形（●/○ 单选、☑/☐ 多选），不用 Radio/Checkbox（ForEach 动态态更稳，且与 ChecklistList 风格一致）。
// V2：@Param tool/sessionId/disabled；@Local step/selectedByQuestion/otherSelectedByQuestion/otherTextByQuestion/fallbackText/submitting/error。

import { ChatToolCall } from '../chat/ChatBlock';
import {
  AskUserQuestionQuestion,
  AskUserQuestionOption,
  parseAskUserQuestionInput,
  computeAskUserAnswersForQuestion
} from '../chat/AskUserQuestion';
import { getHubClient, ApproveOptions } from '../api/HubClient';
import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
struct AskUserQuestionFooter {
  @Param tool: ChatToolCall = new ChatToolCall();
  @Param sessionId: string = '';
  @Param disabled: boolean = false;

  @Local step: number = 0;
  @Local selectedByQuestion: number[][] = [];
  @Local otherSelectedByQuestion: boolean[] = [];
  @Local otherTextByQuestion: string[] = [];
  @Local fallbackText: string = '';
  @Local submitting: boolean = false;
  @Local done: boolean = false;          // approve 成功后置位，等 SSE 翻转卸载前防重复提交
  @Local error: string = '';

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    this.resetState();
  }

  // 初始化各题状态（每个 footer 实例对应一张 pending 卡，实例新建即初始化，无需 tool.id 变化重置）
  private resetState(): void {
    const n: number = this.questions.length;
    const sel: number[][] = [];
    const othSel: boolean[] = [];
    const othTxt: string[] = [];
    for (let i = 0; i < n; i++) {
      sel.push([]);
      othSel.push(false);
      othTxt.push('');
    }
    this.selectedByQuestion = sel;
    this.otherSelectedByQuestion = othSel;
    this.otherTextByQuestion = othTxt;
    this.fallbackText = '';
    this.step = 0;
    this.submitting = false;
    this.done = false;
    this.error = '';
  }

  private get questions(): AskUserQuestionQuestion[] {
    return parseAskUserQuestionInput(this.tool.input);
  }

  private get total(): number {
    return Math.max(1, this.questions.length);
  }

  private get clampedStep(): number {
    return Math.min(Math.max(this.step, 0), this.total - 1);
  }

  private get current(): AskUserQuestionQuestion {
    // 非空：仅在 questions 非空时访问（build 路径已用 this.questions.length === 0 守卫）
    return this.questions[this.clampedStep];
  }

  private get isMulti(): boolean {
    return this.questions.length > 0 && this.current.multiSelect;
  }

  private currentSelected(): number[] {
    const idx: number = this.clampedStep;
    return idx >= 0 && idx < this.selectedByQuestion.length ? this.selectedByQuestion[idx] : [];
  }

  private currentOtherSelected(): boolean {
    const idx: number = this.clampedStep;
    return idx >= 0 && idx < this.otherSelectedByQuestion.length ? this.otherSelectedByQuestion[idx] : false;
  }

  private currentOtherText(): string {
    const idx: number = this.clampedStep;
    return idx >= 0 && idx < this.otherTextByQuestion.length ? this.otherTextByQuestion[idx] : '';
  }

  private isOptionSelected(optIdx: number): boolean {
    const sel: number[] = this.currentSelected();
    for (let i = 0; i < sel.length; i++) {
      if (sel[i] === optIdx) {
        return true;
      }
    }
    return false;
  }

  // 计算第 idx 题答案（校验/提交共用）；questions 空走 fallback 文本
  private validateQuestion(idx: number): string[] | null {
    const qs: AskUserQuestionQuestion[] = this.questions;
    if (qs.length === 0) {
      const t: string = this.fallbackText.trim();
      return t.length > 0 ? [t] : null;
    }
    if (idx < 0 || idx >= qs.length) {
      return null;
    }
    const sel: number[] = idx < this.selectedByQuestion.length ? this.selectedByQuestion[idx] : [];
    const othSel: boolean = idx < this.otherSelectedByQuestion.length ? this.otherSelectedByQuestion[idx] : false;
    const othTxt: string = idx < this.otherTextByQuestion.length ? this.otherTextByQuestion[idx] : '';
    const answers: string[] = computeAskUserAnswersForQuestion(qs[idx], sel, othSel, othTxt);
    return answers.length > 0 ? answers : null;
  }

  // ===== 交互 =====
  private toggleOption(optIdx: number): void {
    if (this.questions.length === 0) {
      return;
    }
    const q: AskUserQuestionQuestion = this.current;
    const qIdx: number = this.clampedStep;
    const sel: number[][] = this.selectedByQuestion.slice();
    const cur: number[] = qIdx < sel.length ? sel[qIdx].slice() : [];
    if (q.multiSelect) {
      let pos: number = -1;
      for (let i = 0; i < cur.length; i++) {
        if (cur[i] === optIdx) {
          pos = i;
          break;
        }
      }
      if (pos >= 0) {
        cur.splice(pos, 1);
      } else {
        cur.push(optIdx);
        cur.sort((a: number, b: number): number => a - b);
      }
    } else {
      cur.splice(0, cur.length);
      cur.push(optIdx);
    }
    sel[qIdx] = cur;
    this.selectedByQuestion = sel;

    // 单选时清除 Other 选择
    if (!q.multiSelect) {
      const oth: boolean[] = this.otherSelectedByQuestion.slice();
      oth[qIdx] = false;
      this.otherSelectedByQuestion = oth;
    }
  }

  private toggleOther(): void {
    if (this.questions.length === 0) {
      return;
    }
    const qIdx: number = this.clampedStep;
    const q: AskUserQuestionQuestion = this.current;
    if (!q.multiSelect) {
      // 单选：选 Other 即清空 option 选择
      const sel: number[][] = this.selectedByQuestion.slice();
      sel[qIdx] = [];
      this.selectedByQuestion = sel;
      const oth: boolean[] = this.otherSelectedByQuestion.slice();
      oth[qIdx] = true;
      this.otherSelectedByQuestion = oth;
      return;
    }
    const oth: boolean[] = this.otherSelectedByQuestion.slice();
    oth[qIdx] = !oth[qIdx];
    this.otherSelectedByQuestion = oth;
  }

  private updateOtherText(value: string): void {
    const qIdx: number = this.clampedStep;
    const txt: string[] = this.otherTextByQuestion.slice();
    txt[qIdx] = value;
    this.otherTextByQuestion = txt;
    // 有非空文本即视为选中 Other（多选叠加）
    if (value.trim().length > 0) {
      const oth: boolean[] = this.otherSelectedByQuestion.slice();
      oth[qIdx] = true;
      this.otherSelectedByQuestion = oth;
    }
  }

  private prev(): void {
    this.error = '';
    this.step = Math.max(this.clampedStep - 1, 0);
  }

  private next(): void {
    if (this.questions.length === 0) {
      return;
    }
    const a: string[] | null = this.validateQuestion(this.clampedStep);
    if (a === null) {
      this.error = t('askUser.selectOptionRequired');
      return;
    }
    this.error = '';
    this.step = Math.min(this.clampedStep + 1, this.questions.length - 1);
  }

  private async submit(): Promise<void> {
    if (this.submitting || this.done) {
      return;
    }
    const answers: Record<string, Object> = {};
    const qs: AskUserQuestionQuestion[] = this.questions;
    if (qs.length === 0) {
      const a0: string[] | null = this.validateQuestion(0);
      if (a0 === null) {
        this.error = t('askUser.selectOptionRequired');
        return;
      }
      answers['0'] = a0;
    } else {
      for (let i = 0; i < qs.length; i++) {
        const a: string[] | null = this.validateQuestion(i);
        if (a === null) {
          this.error = t('askUser.selectOptionRequired');
          this.step = i;
          return;
        }
        answers[String(i)] = a;
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
      opts.answers = answers;
      const ok: boolean = await getHubClient().approvePermission(this.sessionId, p.id, opts);
      if (!ok) {
        this.error = t('askUser.submitFailed');
      } else {
        this.done = true;
      }
    } catch (e) {
      this.error = e instanceof Error ? e.message : t('askUser.submitFailed');
    } finally {
      this.submitting = false;
    }
  }

  private optionGlyph(selected: boolean): string {
    return this.isMulti ? (selected ? '☑' : '☐') : (selected ? '●' : '○');
  }

  build() {
    Column() {
      // 头：问题 badge + 进度
      Row() {
        Text(t('askUser.questionLabel'))
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

      if (this.questions.length === 0) {
        // 兜底纯文本（questions 解析为空）
        Text(t('askUser.enterAnswer'))
          .fontSize(fs(13))
          .fontColor(this.c.textSecondary)
          .width('100%')
          .margin({ top: 8 })
        TextArea({ text: this.fallbackText, placeholder: t('askUser.placeholder') })
          .fontSize(fs(13))
          .fontColor(this.c.textPrimary)
          .placeholderColor(this.c.textTertiary)
          .constraintSize({ minHeight: 72 })
          .width('100%')
          .margin({ top: 6 })
          .borderRadius(10)
          .border({ width: 1, color: this.c.border })
          .padding(8)
          .enabled(!this.submitting && !this.disabled)
          .onChange((v: string) => { this.fallbackText = v; })
      } else {
        this.QuestionBody()
      }

      // 导航
      Row() {
        if (this.total > 1) {
          this.NavButton(t('askUser.prev'), this.c.textSecondary, false, this.clampedStep === 0 || this.submitting || this.done, 'prev')
        }
        Blank()
        if (this.total > 1 && this.clampedStep < this.total - 1) {
          this.NavButton(t('askUser.next'), this.c.textPrimary, false, this.submitting || this.done, 'next')
        } else {
          this.NavButton(this.done ? t('askUser.submitted') : (this.submitting ? t('askUser.submitting') : t('askUser.submit')), this.c.success, this.submitting, this.submitting || this.done, 'submit')
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
        if (this.current.header !== '') {
          Text(this.current.header)
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.c.surfaceSelected)
            .borderRadius(8)
        }
        if (this.current.question !== '') {
          MarkdownText({ content: this.current.question })
        }

        // 选项
        ForEach(this.current.options, (opt: AskUserQuestionOption, optIdx: number) => {
          Row({ space: 8 }) {
            Text(this.optionGlyph(this.isOptionSelected(optIdx)))
              .fontSize(fs(15))
              .fontColor(this.isOptionSelected(optIdx) ? this.c.success : this.c.textSecondary)
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
          .backgroundColor(this.isOptionSelected(optIdx) ? this.c.surfaceSelected : this.c.bg)
          .onClick(() => {
            if (!this.submitting && !this.disabled) {
              this.toggleOption(optIdx);
            }
          })
        }, (opt: AskUserQuestionOption, optIdx: number) => `q${this.clampedStep}:opt${optIdx}`)

        // 「其他」行
        Row({ space: 8 }) {
          Text(this.optionGlyph(this.currentOtherSelected()))
            .fontSize(fs(15))
            .fontColor(this.currentOtherSelected() ? this.c.success : this.c.textSecondary)
          Column() {
            Text(t('askUser.other'))
              .fontSize(fs(13))
              .fontColor(this.c.textPrimary)
            Text(t('askUser.otherDescription'))
              .fontSize(fs(11))
              .fontColor(this.c.textSecondary)
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.currentOtherSelected() ? this.c.surfaceSelected : this.c.bg)
        .onClick(() => {
          if (!this.submitting && !this.disabled) {
            this.toggleOther();
          }
        })

        // Other 自填文本框
        if (this.currentOtherSelected()) {
          TextArea({ text: this.currentOtherText(), placeholder: t('askUser.otherPlaceholder') })
            .fontSize(fs(13))
            .fontColor(this.c.textPrimary)
            .placeholderColor(this.c.textTertiary)
            .constraintSize({ minHeight: 72 })
            .width('100%')
            .borderRadius(10)
            .border({ width: 1, color: this.c.border })
            .padding(8)
            .enabled(!this.submitting && !this.disabled)
            .onChange((v: string) => { this.updateOtherText(v); })
        }
      }
    }
    .width('100%')
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  // 导航按钮（kind 派发，避免向 @Builder 传回调）
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

export { AskUserQuestionFooter };
