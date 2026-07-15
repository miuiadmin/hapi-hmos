// RequestUserInputView —— 对照 web/src/components/ToolCard/views/RequestUserInputView.tsx
// request_user_input 已答态只读回显：approve 后 permission.answers 回填（或 history tool.result）→
//   渲染题目 + ●/○ 单选高亮 + 备注（纯文本题翠绿、选项题带 Note: 标签）。
// 与 AskUserQuestionView 差异：单选 ●/○（非多选 ☑/☐）、每题恒可带备注盒、无 header。
// answers 源：permission.answers 优先（live），回退 tool.result（history 可能是 JSON 串，剥壳后同形）。
// V2：@Param tool；纯展示，无 @Local。

import { ChatToolCall } from '../chat/ChatBlock';
import {
  RequestUserInputQuestion,
  RequestUserInputOption,
  RequestUserInputAnswerState,
  parseRequestUserInputInput,
  parseRequestUserInputAnswers
} from '../chat/RequestUserInput';
import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
struct RequestUserInputView {
  @Param tool: ChatToolCall = new ChatToolCall();

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get questions(): RequestUserInputQuestion[] {
    return parseRequestUserInputInput(this.tool.input);
  }

  // 答案源：permission.answers 优先（live），回退 tool.result（history）
  private get parsedAnswers(): Record<string, RequestUserInputAnswerState> | null {
    const p = this.tool.permission;
    let source: Object | null = null;
    if (p !== null && p.answers !== null) {
      source = p.answers;
    } else {
      source = parseResultAsAnswers(this.tool.result);
    }
    if (source === null) {
      return null;
    }
    return parseRequestUserInputAnswers(source);
  }

  private get hasAnswers(): boolean {
    const a: Record<string, RequestUserInputAnswerState> | null = this.parsedAnswers;
    return a !== null && Object.keys(a).length > 0;
  }

  private answerFor(qId: string): RequestUserInputAnswerState | null {
    const a: Record<string, RequestUserInputAnswerState> | null = this.parsedAnswers;
    if (a === null) {
      return null;
    }
    const v: Object | undefined = a[qId];
    return v !== undefined ? v as RequestUserInputAnswerState : null;
  }

  private isSelected(qId: string, label: string): boolean {
    const ans: RequestUserInputAnswerState | null = this.answerFor(qId);
    return ans !== null && ans.selected === label;
  }

  private noteTextOf(qId: string): string {
    const ans: RequestUserInputAnswerState | null = this.answerFor(qId);
    return ans !== null ? ans.userNote : '';
  }

  build() {
    Column({ space: 10 }) {
      ForEach(this.questions, (q: RequestUserInputQuestion, qIdx: number) => {
        Column({ space: 8 }) {
          if (q.question !== '') {
            MarkdownText({ content: q.question })
          }
          if (q.options.length === 0) {
            // 纯文本题：备注即答案（翠绿 ●）
            if (this.noteTextOf(q.id) !== '') {
              this.PureTextNoteBox(this.noteTextOf(q.id))
            }
          } else {
            // 有选项：●/○ 单选列表
            ForEach(q.options, (opt: RequestUserInputOption, optIdx: number) => {
              this.OptionRow(opt.label, opt.description, this.isSelected(q.id, opt.label))
            }, (opt: RequestUserInputOption, optIdx: number) => `q${qIdx}:opt${optIdx}`)
            // 补充备注（带 Note: 标签）
            if (this.noteTextOf(q.id) !== '') {
              this.OptionNoteBox(this.noteTextOf(q.id))
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (q: RequestUserInputQuestion, qIdx: number) => `q${qIdx}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  OptionRow(label: string, description: string, selected: boolean) {
    Row({ space: 8 }) {
      Text(selected ? '●' : '○')
        .fontSize(fs(15))
        .fontColor(selected ? this.c.success : this.c.textSecondary)
      Column({ space: 2 }) {
        Text(label)
          .fontSize(fs(13))
          .fontColor(selected ? this.c.success : this.c.textPrimary)
        if (description !== '') {
          Text(description)
            .fontSize(fs(11))
            .fontColor(this.c.textSecondary)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(selected ? this.c.surfaceSelected : Color.Transparent)
  }

  // 纯文本题答案盒（翠绿 ● + 文本）
  @Builder
  PureTextNoteBox(note: string) {
    Row({ space: 8 }) {
      Text('●')
        .fontSize(fs(13))
        .fontColor(this.c.success)
      Text(note)
        .fontSize(fs(13))
        .fontColor(this.c.success)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(this.c.surfaceSelected)
  }

  // 选项题补充备注盒（📝 + Note: 标签 + 文本）
  @Builder
  OptionNoteBox(note: string) {
    Row({ space: 8 }) {
      Text('📝')
        .fontSize(fs(12))
      Column({ space: 2 }) {
        Text(t('requestInput.answeredNote'))
          .fontSize(fs(10))
          .fontColor(this.c.textSecondary)
        Text(note)
          .fontSize(fs(13))
          .fontColor(this.c.textPrimary)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(this.c.bg)
  }
}

// tool.result（history）可能是 JSON 串 → 剥壳为对象；非串原样返回；null/解析失败 → null。
function parseResultAsAnswers(result: Object | null): Object | null {
  if (result === null) {
    return null;
  }
  if (typeof result === 'string') {
    try {
      return JSON.parse(result as string);
    } catch (e) {
      return null;
    }
  }
  return result;
}

export { RequestUserInputView };
