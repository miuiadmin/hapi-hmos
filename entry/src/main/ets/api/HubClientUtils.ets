// HubClient 纯逻辑（无 ohos.* 依赖）—— 从 HubClient.ets 抽出，便于 LocalUnit 测试。
// 含：resolveBaseUrl（去尾斜杠）、ApproveOptions（审批请求体参数；从 HubClient 移入此处，避免 ohos 传染）、
//     buildApproveBody（仅序列化非空字段，对照 web approvePermission）、buildDenyBody、categorizeAuthFailure（登录失败归类）。

// 去掉 hubUrl 末尾的 '/'（对照原 HubClient.resolveBaseUrl / SSEClient.baseUrl）
export function resolveBaseUrl(raw: string): string {
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

// 审批权限请求的可选参数（对照 web approvePermission 的 options 分支）
//   普通工具：{ mode }（会话级放行可加 allowTools/decision）
//   答题工具（AskUserQuestion/request_user_input）：{ answers }（见 chat/AskUserQuestion|RequestUserInput）
export class ApproveOptions {
  mode: string = '';                                        // 'default'|'acceptEdits'|'bypassPermissions'|'plan'
  decision: string = '';                                     // 'approved'|'approved_for_session'|'denied'|'abort'
  allowTools: string[] = [];
  answers: Record<string, Object> | null = null;            // flat 或 nested（答题工具）
}

// 仅序列化非空字段（与 web 一致：string 非空→带；allowTools 非空数组→带；answers 非 null→带）
export function buildApproveBody(options?: ApproveOptions): Record<string, Object> {
  const body: Record<string, Object> = {};
  if (options !== undefined && options !== null) {
    if (options.mode !== '') {
      body['mode'] = options.mode;
    }
    if (options.decision !== '') {
      body['decision'] = options.decision;
    }
    if (options.allowTools.length > 0) {
      body['allowTools'] = options.allowTools;
    }
    if (options.answers !== null) {
      body['answers'] = options.answers;
    }
  }
  return body;
}

// 拒绝请求体：仅 decision 非空时带（对照原 HubClient.denyPermission）
export function buildDenyBody(decision?: string): Record<string, string> {
  const body: Record<string, string> = {};
  if (decision !== undefined && decision !== '') {
    body['decision'] = decision;
  }
  return body;
}

// spawn 请求体：对照上游 web NewSession 提交解析（index.tsx:341-358）条件化字段。
//   directory 恒发；agent 非空发；model/effort 仅非 'auto' 发（agent 用自身默认）；yolo 恒发；
//   sessionType 恒发（默认 'simple'）；worktreeName 仅 sessionType==='worktree' 且 trim 非空发。
//   上游 SpawnSessionRequestSchema 全 optional 无 default，省略 = 用 undefined（服务端按 agent 默认）。
export function buildSpawnBody(
  directory: string,
  agent: string,
  model: string,
  effort: string,
  yolo: boolean,
  sessionType: string,
  worktreeName: string
): Record<string, Object> {
  const body: Record<string, Object> = {};
  body['directory'] = directory;
  if (agent !== '') { body['agent'] = agent; }
  if (model !== 'auto' && model !== '') { body['model'] = model; }
  if (effort !== 'auto' && effort !== '') { body['effort'] = effort; }
  body['yolo'] = yolo;
  body['sessionType'] = sessionType !== '' ? sessionType : 'simple';
  if (sessionType === 'worktree') {
    const wt: string = worktreeName.trim();
    if (wt !== '') { body['worktreeName'] = wt; }
  }
  return body;
}

// 登录失败错误归类（对照原 HubClient.authenticate 的 !success 分支）
//   - 401 → 「Access Token 无效」
//   - data 非空 → 尝试解析 {error}，有则用之，否则落到默认「登录失败 (code)」
//   - data 空 + errorMessage 非空 → code 0 视为无法连通；否则透传 errorMessage
//   - 否则默认「登录失败 (code)」
// errorMessage 约定：调用方传 '' 表示「无网络层错误信息」（原代码用 undefined 判定，'' 等价）。
export function categorizeAuthFailure(statusCode: number, data: string, errorMessage: string): string {
  if (statusCode === 401) {
    return 'Access Token 无效';
  }
  if (data !== '') {
    try {
      const errBody = JSON.parse(data) as Record<string, string>;
      if (errBody['error'] !== undefined) {
        return errBody['error'];
      }
    } catch (e) {
      // 解析失败 → 落到默认文案
    }
    return `登录失败 (${statusCode})`;
  }
  if (errorMessage !== '') {
    if (statusCode === 0) {
      return '无法连接到 Hub，请检查地址';
    }
    return errorMessage;
  }
  return `登录失败 (${statusCode})`;
}
