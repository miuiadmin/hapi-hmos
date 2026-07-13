// AskUserQuestionView —— 对照 web/src/components/ToolCard/views/AskUserQuestionView.tsx
// AskUserQuestion 已答态只读回显：approved 后 permission.answers 回填 → 渲染题目 + 高亮选中 label + Other 自定义回答。
// answers 兼容两种格式（flat Record<string,string[]> / nested Record<string,{answers:string[]>}）→ 统一扁平化。
// ToolCard 在 permission.status!=='pending'（approved/denied/canceled）时挂此视图作内联卡片体。
// V2：@Param tool；纯展示，无 @Local。

import { ChatToolCall } from '../chat/ChatBlock';
import {
  AskUserQuestionQuestion,
  AskUserQuestionOption,
  parseAskUserQuestionInput
} from '../chat/AskUserQuestion';
import { MarkdownText } from './MarkdownText';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

@ComponentV2
struct AskUserQuestionView {
  @Param tool: ChatToolCall = new ChatToolCall();

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private get questions(): AskUserQuestionQuestion[] {
    return parseAskUserQuestionInput(this.tool.input);
  }

  // 扁平化 answers：flat 直收；nested {answers:[]} 取内层；null → null
  private get normalizedAnswers(): Record<string, string[]> | null {
    const p = this.tool.permission;
    if (p === null || p.answers === null) {
      return null;
    }
    const raw: Record<string, Object> = p.answers;
    const result: Record<string, string[]> = {};
    const keys: string[] = Object.keys(raw);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const v: Object = raw[k];
      if (Array.isArray(v)) {
        result[k] = toStringArray(v as Object[]);
      } else if (v !== null && v !== undefined && typeof v === 'object') {
        const rec: Record<string, Object> = v as Record<string, Object>;
        const inner: Object = rec['answers'];
        if (Array.isArray(inner)) {
          result[k] = toStringArray(inner as Object[]);
        }
      }
    }
    return result;
  }

  private get hasAnswers(): boolean {
    const a: Record<string, string[]> | null = this.normalizedAnswers;
    return a !== null && Object.keys(a).length > 0;
  }

  private questionAnswers(idx: number): string[] {
    const a: Record<string, string[]> | null = this.normalizedAnswers;
    if (a === null) {
      return [];
    }
    const v: string[] | undefined = a[String(idx)];
    return v !== undefined ? v : [];
  }

  private isOptionSelected(qIdx: number, label: string): boolean {
    const arr: string[] = this.questionAnswers(qIdx);
    const t: string = label.trim();
    for (let i = 0; i < arr.length; i++) {
      if (arr[i].trim() === t) {
        return true;
      }
    }
    return false;
  }

  // 非选项 label 的作答（Other 自定义回答）
  private otherAnswers(q: AskUserQuestionQuestion, qIdx: number): string[] {
    const arr: string[] = this.questionAnswers(qIdx);
    const labels: Set<string> = new Set<string>();
    for (let i = 0; i < q.options.length; i++) {
      labels.add(q.options[i].label.trim());
    }
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const t: string = arr[i].trim();
      if (t.length > 0 && !labels.has(t)) {
        out.push(arr[i]);
      }
    }
    return out;
  }

  build() {
    Column({ space: 10 }) {
      if (this.questions.length === 0) {
        // 无题目但有作答（fallback 路径）：直接列出自定义回答
        if (this.hasAnswers) {
          ForEach(this.questionAnswers(0), (answer: string, idx: number) => {
            this.AnswerRow(answer, true)
          }, (answer: string, idx: number) => `free-${idx}`)
        }
      } else {
        ForEach(this.questions, (q: AskUserQuestionQuestion, qIdx: number) => {
          Column({ space: 6 }) {
            if (q.header !== '') {
              Text(q.header)
                .fontSize(fs(11))
                .fontColor(this.c.textSecondary)
            }
            if (q.question !== '') {
              MarkdownText({ content: q.question })
            }
            if (q.options.length > 0) {
              ForEach(q.options, (opt: AskUserQuestionOption, optIdx: number) => {
                this.AnswerRow(opt.label, this.isOptionSelected(qIdx, opt.label))
              }, (opt: AskUserQuestionOption, optIdx: number) => `q${qIdx}:opt${optIdx}`)
            }
            // Other 自定义回答
            if (this.hasAnswers) {
              ForEach(this.otherAnswers(q, qIdx), (answer: string, oi: number) => {
                Column({ space: 2 }) {
                  this.AnswerRow(answer, true)
                  Text('（自定义回答）')
                    .fontSize(fs(10))
                    .fontColor(this.c.textSecondary)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }, (answer: string, oi: number) => `q${qIdx}:other${oi}`)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }, (q: AskUserQuestionQuestion, qIdx: number) => `q${qIdx}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AnswerRow(label: string, selected: boolean) {
    Row({ space: 8 }) {
      Text(selected ? '☑' : '☐')
        .fontSize(fs(15))
        .fontColor(selected ? this.c.success : this.c.textSecondary)
      Text(label)
        .fontSize(fs(13))
        .fontColor(this.c.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(selected ? this.c.surfaceSelected : Color.Transparent)
  }
}

function toStringArray(arr: Object[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    if (typeof arr[i] === 'string') {
      out.push(arr[i] as string);
    }
  }
  return out;
}

export { AskUserQuestionView };
