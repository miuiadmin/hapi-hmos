// RequestUserInput —— 对照 web/src/components/ToolCard/requestUserInput.ts
// request_user_input（Codex 路径）工具的解析 + 类型 + 答案格式化（纯逻辑，无 ArkUI 依赖）。
// 工具名固定 'request_user_input'。
//
// 与 AskUserQuestion 的差异：无 header、无 multiSelect（仅单选，点选即覆盖）；每题恒带 Note 文本框。
// answers 提交格式（嵌套）：Record<题id, { answers: string[] }>，selected 的 label 入数组，
//   Note 以 "user_note: <text>" 前缀追加。note 编码对齐上游 formatRequestUserInputAnswers。

export class RequestUserInputOption {
  label: string = '';
  description: string = '';        // '' = null
}

export class RequestUserInputQuestion {
  id: string = '';
  question: string = '';
  options: RequestUserInputOption[] = [];
}

// 单题作答态（footer 内部）
export class RequestUserInputAnswerState {
  selected: string = '';           // '' = null（未选）
  userNote: string = '';
}

export function isRequestUserInputToolName(toolName: string): boolean {
  return toolName === 'request_user_input';
}

function isPlainObject(v: Object): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v);
}

// 解析 input → questions。规则（对齐上游 parseRequestUserInputInput）：
//   - 非 questions 数组 → []
//   - 每题 trim id/question；无 id 的题整题丢弃
//   - 每选项 trim label，空 label 丢弃；description 非 string → ''
export function parseRequestUserInputInput(input: Record<string, Object> | null): RequestUserInputQuestion[] {
  if (input === null) {
    return [];
  }
  const rawQuestions: Object = input['questions'];
  if (!Array.isArray(rawQuestions)) {
    return [];
  }
  const questions: RequestUserInputQuestion[] = [];
  const arr: Object[] = rawQuestions as Object[];
  for (let i = 0; i < arr.length; i++) {
    const raw: Object = arr[i];
    if (!isPlainObject(raw)) {
      continue;
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const id: string = typeof rec['id'] === 'string' ? (rec['id'] as string).trim() : '';
    if (id === '') {
      continue;
    }
    const question: string = typeof rec['question'] === 'string' ? (rec['question'] as string).trim() : '';

    const rawOptions: Object = rec['options'];
    const rawOptArr: Object[] = Array.isArray(rawOptions) ? rawOptions as Object[] : [];
    const options: RequestUserInputOption[] = [];
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
      const opt: RequestUserInputOption = new RequestUserInputOption();
      opt.label = label;
      opt.description = typeof optRec['description'] === 'string' ? (optRec['description'] as string).trim() : '';
      options.push(opt);
    }

    const q: RequestUserInputQuestion = new RequestUserInputQuestion();
    q.id = id;
    q.question = question;
    q.options = options;
    questions.push(q);
  }
  return questions;
}

// 格式化作答态 → 嵌套 answers（赋给 ApproveOptions.answers；body 最终 = { answers: { [id]: { answers: [...] } } }）。
//   selected 非空 → 入数组；userNote trim 非空 → "user_note: <text>" 追加。
export function buildRequestUserInputAnswers(stateByQuestion: Record<string, RequestUserInputAnswerState>): Record<string, Object> {
  const answers: Record<string, Object> = {};
  const keys: string[] = Object.keys(stateByQuestion);
  for (let i = 0; i < keys.length; i++) {
    const id: string = keys[i];
    const st: RequestUserInputAnswerState = stateByQuestion[id];
    const arr: string[] = [];
    if (st.selected !== '') {
      arr.push(st.selected);
    }
    const note: string = st.userNote.trim();
    if (note.length > 0) {
      arr.push(`user_note: ${note}`);
    }
    const inner: Record<string, string[]> = { 'answers': arr };
    answers[id] = inner;
  }
  return answers;
}
