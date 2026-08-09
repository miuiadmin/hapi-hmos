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
  // v0.27.2 #1353 新增三字段（agent 自由格式工具输入的一部分，非 Pi 专属）：
  placeholder: string = '';   // 自定义占位文案（'' = 未提供；上游 placeholder?）
  prefill: string = '';        // 预填答案（'' = 未提供；上游 prefill?）
  inputType: string = '';      // '' = 普通文本题；'editor' = 编辑器题型（恒视为已答 + 不 trim 首尾空格）
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
    // 三可选字段：placeholder/prefill 不 trim（上游保留原文）；inputType 仅认 'editor'。
    q.placeholder = typeof rec['placeholder'] === 'string' ? rec['placeholder'] as string : '';
    q.prefill = typeof rec['prefill'] === 'string' ? rec['prefill'] as string : '';
    q.inputType = rec['inputType'] === 'editor' ? 'editor' : '';
    questions.push(q);
  }
  return questions;
}

// 格式化作答态 → 嵌套 answers（赋给 ApproveOptions.answers；body 最终 = { answers: { [id]: { answers: [...] } } }）。
//   selected 非空 → 入数组；userNote：editor 题型保留首尾空格且空也发，其余 trim 非空才发 "user_note: <text>"。
//   questions 传入以判定 editor 题型（对照上游 formatRequestUserInputAnswers 的 questionById）。
export function buildRequestUserInputAnswers(
  stateByQuestion: Record<string, RequestUserInputAnswerState>,
  questions: RequestUserInputQuestion[]
): Record<string, Object> {
  // editor 题 id 集合（查表 O(1)）
  const editorIds: Set<string> = new Set<string>();
  for (let i = 0; i < questions.length; i++) {
    if (questions[i].inputType === 'editor') {
      editorIds.add(questions[i].id);
    }
  }
  const answers: Record<string, Object> = {};
  const keys: string[] = Object.keys(stateByQuestion);
  for (let i = 0; i < keys.length; i++) {
    const id: string = keys[i];
    const st: RequestUserInputAnswerState = stateByQuestion[id];
    const isEditor: boolean = editorIds.has(id);
    const arr: string[] = [];
    if (st.selected !== '') {
      arr.push(st.selected);
    }
    // editor：保留原文（不 trim）+ 空也发；其余：trim 非空才发（对照上游 isEditor ? userNote : userNote.trim()）。
    const note: string = isEditor ? st.userNote : st.userNote.trim();
    if (isEditor || note.length > 0) {
      arr.push(`user_note: ${note}`);
    }
    const inner: Record<string, string[]> = { 'answers': arr };
    answers[id] = inner;
  }
  return answers;
}

// 备注前缀（与 buildRequestUserInputAnswers 的 `user_note: <text>` 编码一致）。
const NOTE_PREFIX: string = 'user_note: ';

// 从 answers 数组里挑出 string（过滤非 string 项）。
function pickStrings(arr: Object[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    if (typeof arr[i] === 'string') {
      out.push(arr[i] as string);
    }
  }
  return out;
}

// 精确选项匹配（对照上游 exactOption）：question 的某选项 label 与 item 完全相等。
function findOptionByLabelExact(q: RequestUserInputQuestion | undefined, label: string): RequestUserInputOption | null {
  if (q === undefined) { return null; }
  for (let i = 0; i < q.options.length; i++) {
    if (q.options[i].label === label) { return q.options[i]; }
  }
  return null;
}

// 归一化匹配（对照上游 normalizedOptions）：trim 后唯一命中才算（避免多义）。
function findOptionByLabelNormalized(q: RequestUserInputQuestion | undefined, label: string): RequestUserInputOption | null {
  if (q === undefined) { return null; }
  const trimmed: string = label.trim();
  let match: RequestUserInputOption | null = null;
  let count: number = 0;
  for (let i = 0; i < q.options.length; i++) {
    if (q.options[i].label.trim() === trimmed) {
      match = q.options[i];
      count++;
    }
  }
  return count === 1 ? match : null;
}

// 读回解析（对照上游 requestUserInput.ts parseRequestUserInputAnswers）。
//   入参可为外层 { answers: { [id]: { answers: [...] } } }（body 提交格式）或扁平 { [id]: string[] | {answers:[]} }。
//   questions 传入以做精确/归一化选项匹配 + editor 题型判定（editor 的 userNote 不 trim，对照上游）。
//   逐条：精确选项→归一化选项→`user_note: ` 前缀（editor 不 trim）→否则首个入 selected（trim）。null → '' 归一。
//   非 object 入参 → null。
export function parseRequestUserInputAnswers(
  answers: Object,
  questions: RequestUserInputQuestion[]
): Record<string, RequestUserInputAnswerState> | null {
  if (!isPlainObject(answers)) {
    return null;
  }
  const outer: Record<string, Object> = answers as Record<string, Object>;
  const wrapped: Object = outer['answers'];
  const answersObj: Record<string, Object> = isPlainObject(wrapped) ? wrapped as Record<string, Object> : outer;

  // id → question 查表（对照上游 questionById）
  const questionById: Map<string, RequestUserInputQuestion> = new Map<string, RequestUserInputQuestion>();
  for (let i = 0; i < questions.length; i++) {
    questionById.set(questions[i].id, questions[i]);
  }

  const parsed: Record<string, RequestUserInputAnswerState> = {};
  const keys: string[] = Object.keys(answersObj);
  for (let i = 0; i < keys.length; i++) {
    const id: string = keys[i];
    const value: Object = answersObj[id];
    const question: RequestUserInputQuestion | undefined = questionById.get(id);
    const isEditor: boolean = question !== undefined && question.inputType === 'editor';

    let answerArray: string[] = [];
    if (isPlainObject(value)) {
      const innerArr: Object = (value as Record<string, Object>)['answers'];
      if (Array.isArray(innerArr)) {
        answerArray = pickStrings(innerArr as Object[]);
      }
    } else if (Array.isArray(value)) {
      answerArray = pickStrings(value as Object[]);
    }

    let selected: string = '';
    let userNote: string = '';
    for (let j = 0; j < answerArray.length; j++) {
      const item: string = answerArray[j];
      const exactOpt: RequestUserInputOption | null = findOptionByLabelExact(question, item);
      if (exactOpt !== null) {
        if (selected === '') { selected = exactOpt.label; }
        continue;
      }
      const normOpt: RequestUserInputOption | null = findOptionByLabelNormalized(question, item);
      if (normOpt !== null) {
        if (selected === '') { selected = normOpt.label; }
        continue;
      }
      if (item.startsWith(NOTE_PREFIX)) {
        const note: string = item.substring(NOTE_PREFIX.length);
        userNote = isEditor ? note : note.trim();
      } else if (selected === '') {
        selected = item.trim();
      }
    }

    const st: RequestUserInputAnswerState = new RequestUserInputAnswerState();
    st.selected = selected;
    st.userNote = userNote;
    parsed[id] = st;
  }
  return parsed;
}
