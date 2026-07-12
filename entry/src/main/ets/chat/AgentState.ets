// AgentState —— 对齐 shared/src/schemas.ts
//   AgentStateRequestSchema        { tool, arguments, createdAt|null }
//   AgentStateCompletedRequestSchema { ..., status, reason?, mode?, decision?, allowTools?, answers? }
//   AgentStateSchema               { controlledByUser|null, requests?, completedRequests? }
// 用途：承载会话的权限请求队列（pending=requests，已决=completedRequests），供 reducer 合并工具卡权限态。
// 纯数据类（无 ArkUI 依赖），由 parseAgentState 从原始 Record 安全解析。

import { pickStr } from '../models/Types';

// 待处理（pending）权限请求：agent 发起、等用户决定
export class AgentStateRequest {
  tool: string = '';                       // 工具名（如 'Bash'/'Edit'/'AskUserQuestion'）
  arguments: Object | null = null;         // z.unknown() → Object 透传（工具入参）
  createdAt: number = 0;                    // nullish → 0
}

// 已决权限请求：用户已批准/拒绝/取消
export class AgentStateCompletedRequest {
  tool: string = '';
  arguments: Object | null = null;
  createdAt: number = 0;
  completedAt: number = 0;
  status: string = '';                     // 'canceled' | 'denied' | 'approved'
  reason: string = '';                      // 拒绝/取消原因（可空）
  mode: string = '';                        // PermissionMode（可空）
  decision: string = '';                    // 'approved'|'approved_for_session'|'denied'|'abort'（可空）
  allowTools: string[] = [];                // 会话级放行工具列表（可空）
  // answers：两种格式并存，按工具名判形——
  //   AskUserQuestion  → Record<下标string, string[]>（扁平）
  //   request_user_input → Record<题id, { answers: string[] }>（嵌套）
  // 此处原样透传，由答题视图/提交逻辑按工具名解释。
  answers: Record<string, Object> | null = null;
}

export class AgentState {
  controlledByUser: boolean = false;
  requests: Record<string, AgentStateRequest> = {};
  completedRequests: Record<string, AgentStateCompletedRequest> = {};

  // 全空（无请求、无已决、非用户控制）→ reducer 可短路跳过权限合并
  get isEmpty(): boolean {
    return Object.keys(this.requests).length === 0
      && Object.keys(this.completedRequests).length === 0
      && !this.controlledByUser;
  }
}

// 从原始 Record 解析 AgentState（null/缺省 → 空 state，isEmpty=true）
export function parseAgentState(raw: Record<string, Object> | null): AgentState {
  const state: AgentState = new AgentState();
  if (raw === null) {
    return state;
  }
  if (raw['controlledByUser'] === true) {
    state.controlledByUser = true;
  }
  const reqs: Record<string, Object> | null = pickObjRecord(raw, 'requests');
  if (reqs !== null) {
    state.requests = parseRequests(reqs);
  }
  const done: Record<string, Object> | null = pickObjRecord(raw, 'completedRequests');
  if (done !== null) {
    state.completedRequests = parseCompletedRequests(done);
  }
  return state;
}

// 取 Record<string,Object> 字段（非对象 → null）
function pickObjRecord(r: Record<string, Object>, k: string): Record<string, Object> | null {
  const v = r[k];
  if (v !== null && v !== undefined && typeof v === 'object') {
    return v as Record<string, Object>;
  }
  return null;
}

function parseRequests(raw: Record<string, Object>): Record<string, AgentStateRequest> {
  const out: Record<string, AgentStateRequest> = {};
  const keys: string[] = Object.keys(raw);
  for (let i = 0; i < keys.length; i++) {
    const id: string = keys[i];
    const val: Object = raw[id];
    if (val !== null && val !== undefined && typeof val === 'object') {
      out[id] = parseRequest(val as Record<string, Object>);
    }
  }
  return out;
}

function parseRequest(rec: Record<string, Object>): AgentStateRequest {
  const r: AgentStateRequest = new AgentStateRequest();
  r.tool = pickStr(rec, 'tool');
  r.arguments = rec['arguments'] !== undefined ? rec['arguments'] : null;
  const ca: Object = rec['createdAt'];
  r.createdAt = typeof ca === 'number' ? ca : 0;
  return r;
}

function parseCompletedRequests(raw: Record<string, Object>): Record<string, AgentStateCompletedRequest> {
  const out: Record<string, AgentStateCompletedRequest> = {};
  const keys: string[] = Object.keys(raw);
  for (let i = 0; i < keys.length; i++) {
    const id: string = keys[i];
    const val: Object = raw[id];
    if (val !== null && val !== undefined && typeof val === 'object') {
      out[id] = parseCompletedRequest(val as Record<string, Object>);
    }
  }
  return out;
}

function parseCompletedRequest(rec: Record<string, Object>): AgentStateCompletedRequest {
  const r: AgentStateCompletedRequest = new AgentStateCompletedRequest();
  r.tool = pickStr(rec, 'tool');
  r.arguments = rec['arguments'] !== undefined ? rec['arguments'] : null;
  const ca: Object = rec['createdAt'];
  r.createdAt = typeof ca === 'number' ? ca : 0;
  const cma: Object = rec['completedAt'];
  r.completedAt = typeof cma === 'number' ? cma : 0;
  r.status = pickStr(rec, 'status');
  r.reason = pickStr(rec, 'reason');
  r.mode = pickStr(rec, 'mode');
  r.decision = pickStr(rec, 'decision');

  const at: Object = rec['allowTools'];
  if (at !== null && at !== undefined && Array.isArray(at)) {
    const arr: Object[] = at as Object[];
    const strs: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      const x: Object = arr[i];
      if (typeof x === 'string') {
        strs.push(x);
      }
    }
    r.allowTools = strs;
  }

  const ans: Object = rec['answers'];
  if (ans !== null && ans !== undefined && typeof ans === 'object') {
    r.answers = ans as Record<string, Object>;
  }
  return r;
}
