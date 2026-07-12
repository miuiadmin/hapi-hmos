import { http } from '@kit.NetworkKit';
import { getConnectionService } from '../services/ConnectionService';
import { AuthRequest, AuthUser } from '../models/Auth';
import { SessionSummary, parseSessionsResponse, Session, parseSessionDetail, RenameSessionRequest } from '../models/Types';
import { ChatMessage, MessagesPage, parseMessagesPageResponse, SendMessageRequest } from '../models/Message';
import { resolveBaseUrl as normalizeBaseUrl, ApproveOptions, buildApproveBody, buildDenyBody, categorizeAuthFailure } from './HubClientUtils';

// ApproveOptions 从 HubClientUtils（纯逻辑模块）再导出，保持外部 `import { ApproveOptions } from '../api/HubClient'` 不破。
export { ApproveOptions } from './HubClientUtils';

// Hapi Hub HTTP 客户端（对齐 web/src/api/client.ts）
// 鉴权：登录 POST /api/auth 用 CLI_API_TOKEN 换 JWT；后续 /api/* 用 Bearer <JWT>
// 用 @kit.NetworkKit 的 http，每请求新建并 finally destroy（HttpRequest destroy 后不可复用，对照 chatcube HttpService）
//
// 明文 HTTP：HarmonyOS 默认允许 cleartext（chatcube/berry3 未配 network_config 即可连 http），
//           Hub 默认明文监听可直连；若个别设备/版本禁用，再配 network_config.json 放行。
//
// hubUrl 参数：测试连接 / 登录时配置尚未持久化，调用方可传入填写的地址；
//             不传则用 ConnectionService.hubUrl（登录后已持久化的地址）。

// 通用 HTTP 响应
export interface HubHttpResponse {
  success: boolean;
  statusCode: number;
  data: string;
  errorMessage?: string;
}

// 登录结果
export interface AuthResult {
  success: boolean;
  jwt: string;
  user: AuthUser | null;
  errorMessage: string;
}

// token 用法
type TokenType = 'none' | 'token' | 'jwt';

// 空请求体（abort 等需 POST {} 的端点）
const EMPTY_BODY: Record<string, string> = {};

// 消息分页每页条数（对照 web PAGE_SIZE / hub route 默认 50，schema 上限 200）
const MESSAGES_PAGE_SIZE: number = 50;

export class HubClient {
  private static instance: HubClient | null = null;

  private constructor() {}

  static getInstance(): HubClient {
    if (HubClient.instance === null) {
      HubClient.instance = new HubClient();
    }
    return HubClient.instance;
  }

  // 解析 baseUrl：传入则用传入（测试/登录时未持久化），否则用 ConnectionService 的；去尾斜杠逻辑在 HubClientUtils
  private resolveBaseUrl(hubUrl?: string): string {
    const raw = hubUrl !== undefined && hubUrl !== '' ? hubUrl : getConnectionService().hubUrl;
    return normalizeBaseUrl(raw);
  }

  // 通用请求（含 JWT 自动刷新：jwt 类请求遇 401 → 用持久化的 apiToken 重新换 jwt → 重试一次）
  //   单飞去重（refreshPromise）：并发多请求同时 401 时只触发一次重新登录，共享结果，防雪崩。
  //   刷新失败（apiToken 也无效）→ 返回原 401，不循环重试。
  async request(method: http.RequestMethod, path: string, body?: object, tokenType: TokenType = 'jwt', hubUrl?: string): Promise<HubHttpResponse> {
    const first = await this.doRequest(method, path, body, tokenType, hubUrl);
    // 仅 jwt 类请求（持久化 hubUrl）+ 401 + 持有 apiToken 时才尝试刷新重试；
    // authenticate/health 用 'none'，不在此路径，故刷新内部调 authenticate 无递归。
    if (first.statusCode === 401 && tokenType === 'jwt' && getConnectionService().apiToken !== '') {
      const refreshed = await this.refreshJwt();
      if (refreshed) {
        return this.doRequest(method, path, body, tokenType, hubUrl);
      }
    }
    return first;
  }

  // 实际发一次 HTTP（request 的内层，不含刷新逻辑；每请求新建并 finally destroy）
  private async doRequest(method: http.RequestMethod, path: string, body?: object, tokenType: TokenType = 'jwt', hubUrl?: string): Promise<HubHttpResponse> {
    const url = `${this.resolveBaseUrl(hubUrl)}${path}`;
    const httpRequest = http.createHttp();
    try {
      const header: Record<string, string> = { 'Content-Type': 'application/json' };
      if (tokenType === 'token') {
        header['Authorization'] = `Bearer ${getConnectionService().apiToken}`;
      } else if (tokenType === 'jwt') {
        const jwt = getConnectionService().jwt;
        if (jwt !== '') {
          header['Authorization'] = `Bearer ${jwt}`;
        }
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: 15000,
        readTimeout: 15000
      };
      if (body !== undefined) {
        options.extraData = JSON.stringify(body);
      }

      const response = await httpRequest.request(url, options);
      const result: HubHttpResponse = {
        success: response.responseCode >= 200 && response.responseCode < 300,
        statusCode: response.responseCode,
        data: response.result as string
      };
      if (!result.success) {
        result.errorMessage = `HTTP ${response.responseCode}`;
      }
      return result;
    } catch (error) {
      return {
        success: false,
        statusCode: 0,
        data: '',
        errorMessage: `请求失败: ${JSON.stringify(error)}`
      };
    } finally {
      httpRequest.destroy();
    }
  }

  // 刷新 JWT：用持久化的 CLI_API_TOKEN 重新 POST /api/auth 换新 jwt 并持久化。
  //   公开方法——request() 内部 401 重试用它；SSEClient 流 401 时也调它自愈。
  //   单飞（refreshPromise）：并发调用共享同一次在途刷新，finally 清空，防 N 个 401 同时重新登录。
  private refreshPromise: Promise<boolean> | null = null;

  async refreshJwt(): Promise<boolean> {
    if (this.refreshPromise !== null) {
      return this.refreshPromise;
    }
    const conn = getConnectionService();
    if (conn.apiToken === '') {
      return false;   // 无 apiToken 无法重换，交由调用方按 401/失败处理
    }
    const p = this.doRefresh();
    this.refreshPromise = p;
    try {
      return await p;
    } finally {
      this.refreshPromise = null;
    }
  }

  private async doRefresh(): Promise<boolean> {
    const conn = getConnectionService();
    // authenticate 内部走 tokenType='none'（不触发刷新，无递归）；用持久化 hubUrl。
    const result = await this.authenticate(conn.apiToken);
    if (result.success && result.jwt !== '') {
      await conn.saveJwt(result.jwt);
      return true;
    }
    return false;
  }

  // 登录：用 CLI_API_TOKEN 换 JWT（POST /api/auth）
  // hubUrl 可选：登录页测试时传入填写的地址。401 → token 无效；400 → 请求体格式错
  async authenticate(apiToken: string, hubUrl?: string): Promise<AuthResult> {
    const req: AuthRequest = new AuthRequest();
    req.accessToken = apiToken;
    const resp = await this.request(http.RequestMethod.POST, '/api/auth', req, 'none', hubUrl);
    if (!resp.success) {
      const msg = categorizeAuthFailure(resp.statusCode, resp.data,
        resp.errorMessage !== undefined ? resp.errorMessage : '');
      return { success: false, jwt: '', user: null, errorMessage: msg };
    }

    const raw = JSON.parse(resp.data) as Record<string, Object>;
    const jwt = raw['token'] as string;
    const rawUser = raw['user'] as Record<string, Object>;
    const user = new AuthUser();
    user.id = rawUser['id'] as number;
    user.firstName = rawUser['firstName'] as string;
    return { success: true, jwt: jwt, user: user, errorMessage: '' };
  }

  // 健康检查（GET /health，无需鉴权）—— 用于测 Hub 地址连通性
  async health(hubUrl?: string): Promise<boolean> {
    try {
      const resp = await this.request(http.RequestMethod.GET, '/health', undefined, 'none', hubUrl);
      return resp.success;
    } catch (e) {
      return false;
    }
  }

  // 拉取会话列表（GET /api/sessions → { sessions: SessionSummary[] }，对照 web client.getSessions）
  // 失败抛 Error（UI 层 try/catch 显示错误态）
  async fetchSessions(): Promise<SessionSummary[]> {
    const resp = await this.request(http.RequestMethod.GET, '/api/sessions', undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : `加载会话失败 (${resp.statusCode})`);
    }
    return parseSessionsResponse(resp.data);
  }

  // 拉取会话消息（分页）：GET /api/sessions/:id/messages?limit=50[&beforeAt=&beforeSeq=]
  //   对照 web getMessages：beforeAt/beforeSeq 成对，取自上一页响应 page.nextBefore*（服务端给出，禁止本地重算）。
  //   首屏不传游标取最新页；加载更旧传上一页最旧位置游标。返回带 page 元数据（hasMore / 下一页游标）。失败抛 Error。
  async fetchMessagesPage(sessionId: string, beforeAt?: number, beforeSeq?: number): Promise<MessagesPage> {
    let path = `/api/sessions/${sessionId}/messages?limit=${MESSAGES_PAGE_SIZE}`;
    if (beforeAt !== undefined && beforeSeq !== undefined && beforeAt > 0 && beforeSeq > 0) {
      path = `${path}&beforeAt=${beforeAt}&beforeSeq=${beforeSeq}`;
    }
    const resp = await this.request(http.RequestMethod.GET, path, undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : `加载消息失败 (${resp.statusCode})`);
    }
    return parseMessagesPageResponse(resp.data);
  }

  // 拉取会话消息（首屏便捷：仅返回 messages，丢弃分页元数据）
  async fetchMessages(sessionId: string): Promise<ChatMessage[]> {
    const page = await this.fetchMessagesPage(sessionId);
    return page.messages;
  }

  // 发送用户消息（POST /api/sessions/:id/messages body { text, localId } → { ok:true }）
  // 真实消息靠 SSE message-received 回推（用 localId 匹配并替换乐观行）
  async sendMessage(sessionId: string, text: string, localId: string): Promise<boolean> {
    const body = new SendMessageRequest();
    body.text = text;
    body.localId = localId;
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/messages`, body, 'jwt');
    return resp.success;
  }

  // 中止会话运行（POST /api/sessions/:id/abort，对照 web abortSession）——「停止生成」
  async abortSession(sessionId: string): Promise<boolean> {
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/abort`, EMPTY_BODY, 'jwt');
    return resp.success;
  }

  // 重命名会话（PATCH /api/sessions/:id body { name } → { ok:true }，对照 web renameSession）
  //   name 上游校验 1–255；成功后 SSE session-updated（全 Session）回推，列表兜底刷新。
  //   注：HarmonyOS http.RequestMethod 枚举不含 PATCH（对照 berry3 WebDAVClient 处理 MKCOL/PROPFIND 的先例），
  //   以 'PATCH' as http.RequestMethod 强转；底层 HTTP 实现接受任意方法字符串（berry3 已验证）。
  async renameSession(sessionId: string, name: string): Promise<boolean> {
    const body = new RenameSessionRequest();
    body.name = name;
    const resp = await this.request('PATCH' as http.RequestMethod,
      `/api/sessions/${sessionId}`, body, 'jwt');
    return resp.success;
  }

  // 归档会话（POST /api/sessions/:id/archive body {} → { ok:true }，对照 web archiveSession）
  //   语义：杀活跃 CLI 进程 + active=false（非「归档夹」；Session 无 archived 字段）。
  //   前置 active===true，否则 409 { error: 'Session is inactive' }。
  async archiveSession(sessionId: string): Promise<boolean> {
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/archive`, EMPTY_BODY, 'jwt');
    return resp.success;
  }

  // 删除会话（DELETE /api/sessions/:id → { ok:true }，对照 web deleteSession）
  //   语义：硬删除（行 + 消息全删，不可恢复，无 undo）。前置 active===false，否则
  //   409 { error: 'Cannot delete active session. Archive it first.' }。
  async deleteSession(sessionId: string): Promise<boolean> {
    const resp = await this.request(http.RequestMethod.DELETE,
      `/api/sessions/${sessionId}`, undefined, 'jwt');
    return resp.success;
  }

  // 拉取会话详情（GET /api/sessions/:id → { session: {...} }，对照 web getSession）
  // 主要为取 agentState（权限请求队列，agentStateRaw 由调用方 parseAgentState 解析）；失败抛 Error
  async fetchSession(sessionId: string): Promise<Session> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}`, undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : `加载会话失败 (${resp.statusCode})`);
    }
    return parseSessionDetail(resp.data);
  }

  // 审批权限请求（POST /api/sessions/:id/permissions/:requestId/approve，对照 web approvePermission）
  // options：普通工具 { mode }；答题工具 { answers }；会话级放行可加 allowTools/decision。
  // 仅序列化非空字段（与 web 一致：string mode→{mode}，对象→原样）。
  async approvePermission(sessionId: string, requestId: string, options?: ApproveOptions): Promise<boolean> {
    const body: Record<string, Object> = buildApproveBody(options);
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/permissions/${requestId}/approve`, body, 'jwt');
    return resp.success;
  }

  // 拒绝权限请求（POST /api/sessions/:id/permissions/:requestId/deny，对照 web denyPermission）
  async denyPermission(sessionId: string, requestId: string, decision?: string): Promise<boolean> {
    const body: Record<string, string> = buildDenyBody(decision);
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/permissions/${requestId}/deny`, body, 'jwt');
    return resp.success;
  }
}

// 全局便捷访问
export function getHubClient(): HubClient {
  return HubClient.getInstance();
}
