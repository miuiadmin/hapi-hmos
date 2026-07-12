// AskUserQuestion —— 对照 web/src/components/ToolCard/askUserQuestion.ts
// AskUserQuestion 工具的解析 + 类型 + 答案计算（纯逻辑，无 ArkUI 依赖）。
// 工具名：'AskUserQuestion'（Claude 路径）或 'ask_user_question'（CLI 透传）。
//
// answers 提交格式（扁平）：Record<题下标字符串, string[]> —— 值是选中 option 的 label（trim），
//   AskUserQuestion 的 Other 自填文本原样进数组末尾。回显高亮也按 trim label 比较。

export class AskUserQuestionOption {
  label: string = '';
  description: string = '';        // '' = null
}

export class AskUserQuestionQuestion {
  header: string = '';             // '' = null
  question: string = '';
  options: AskUserQuestionOption[] = [];
  multiSelect: boolean = false;
}

// 工具名判别（footer/已答视图据此挂载）
export function isAskUserQuestionToolName(toolName: string): boolean {
  return toolName === 'AskUserQuestion' || toolName === 'ask_user_question';
}

// 非数组对象判定（对照上游 isObject：排除 null/数组/基本类型）
function isPlainObject(v: Object): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v);
}

// 解析 input → questions。规则（对齐上游 parseAskUserQuestionInput）：
//   - 非 questions 数组 → []
//   - 每题 trim question/header；multiSelect 非 boolean → false
//   - 每选项 trim label，空 label 丢弃；description 非 string → ''（表 null）
//   - 无 question 且无有效选项的题整题丢弃
export function parseAskUserQuestionInput(input: Record<string, Object> | null): AskUserQuestionQuestion[] {
  if (input === null) {
    return [];
  }
  const rawQuestions: Object = input['questions'];
  if (!Array.isArray(rawQuestions)) {
    return [];
  }
  const questions: AskUserQuestionQuestion[] = [];
  const arr: Object[] = rawQuestions as Object[];
  for (let i = 0; i < arr.length; i++) {
    const raw: Object = arr[i];
    if (!isPlainObject(raw)) {
      continue;
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const question: string = typeof rec['question'] === 'string' ? (rec['question'] as string).trim() : '';
    const header: string = typeof rec['header'] === 'string' ? (rec['header'] as string).trim() : '';
    const multiSelect: boolean = typeof rec['multiSelect'] === 'boolean' ? rec['multiSelect'] as boolean : false;

    const rawOptions: Object = rec['options'];
    const rawOptArr: Object[] = Array.isArray(rawOptions) ? rawOptions as Object[] : [];
    const options: AskUserQuestionOption[] = [];
    for (let j = 0; j < rawOptArr.length; j++) {
      const optRaw: Object = rawOptArr[j];
      if (!isPlainObject(optRaw)) {
        continue;
      }
      const optRec: Record<string, Object> = optRaw as Record<string, Object>;
      const label: string = typeof optRec['label'] === 'string' ? (optRec['label'] as string).trim() : '';
      if (label === '') {
        continue;
      }
      const opt: AskUserQuestionOption = new AskUserQuestionOption();
      opt.label = label;
      opt.description = typeof optRec['description'] === 'string' ? (optRec['description'] as string).trim() : '';
      options.push(opt);
    }

    if (question === '' && options.length === 0) {
      continue;
    }

    const q: AskUserQuestionQuestion = new AskUserQuestionQuestion();
    q.header = header;
    q.question = question;
    q.options = options;
    q.multiSelect = multiSelect;
    questions.push(q);
  }
  return questions;
}

// 计算单题的答案字符串数组（footer 校验/提交共用）。
//   selectedOptionIndices → 对应 option 的 label（trim，非空才入）；Other 自填文本（trim 非空）追加末尾。
export function computeAskUserAnswersForQuestion(
  question: AskUserQuestionQuestion,
  selectedOptionIndices: number[],
  otherSelected: boolean,
  otherText: string
): string[] {
  const answers: string[] = [];
  for (let i = 0; i < selectedOptionIndices.length; i++) {
    const idx: number = selectedOptionIndices[i];
    if (idx < 0 || idx >= question.options.length) {
      continue;
    }
    const label: string = question.options[idx].label.trim();
    if (label.length > 0) {
      answers.push(label);
    }
  }
  const other: string = otherText.trim();
  if (otherSelected && other.length > 0) {
    answers.push(other);
  }
  return answers;
}
