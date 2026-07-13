import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { getConnectionService } from '../services/ConnectionService';
import { AuthRequest, AuthUser } from '../models/Auth';
import { SessionSummary, parseSessionsResponse, Session, parseSessionDetail, RenameSessionRequest, Machine, DirEntry, ListDirectoryRequest, parseMachinesResponse, parseListDirectoryResponse, parseSpawnResponse, parseResumeSessionResponse, parseSlashCommandsResponse, ServerSlashCommand, parseSkillsResponse, SkillItem, FileSearchItem, parseFileSearchResponse, CommandResponse, parseCommandResponse, FileReadResponse, parseFileReadResponse, SessionDirEntry, parseSessionDirectoryResponse, AttachmentMetadata, UploadFileResult, parseUploadFileResponse } from '../models/Types';
import { ChatMessage, MessagesPage, parseMessagesPageResponse, CancelMessageResult, parseCancelMessageResponse } from '../models/Message';
import { resolveBaseUrl as normalizeBaseUrl, ApproveOptions, buildApproveBody, buildDenyBody, buildSpawnBody, categorizeAuthFailure } from './HubClientUtils';
import { t } from '../i18n/I18nService';

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

// 生成图片拉取结果（对照 web getGeneratedImageBlob：二进制 → base64 data URI）
export interface GeneratedImageResult {
  success: boolean;
  dataUri: string;   // 成功：data:${mime};base64,...；失败：''
  error: string;     // 失败：错误文案；成功：''
}

// 二进制响应（doRequestBinary 内部用；成功 errorMessage=''，失败 buffer 为空）
interface BinaryResult {
  statusCode: number;
  buffer: ArrayBuffer;
  errorMessage: string;
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
        errorMessage: t('api.requestFailed', { detail: JSON.stringify(error) })
      };
    } finally {
      httpRequest.destroy();
    }
  }

  // 二进制请求（同 doRequest，但响应按 ARRAY_BUFFER 读，对照 chatcube IconDownloadCache.ets:113 expectDataType）。
  //   仅生成图片拉取用：GET 二进制 → ArrayBuffer → 调用方 base64 编码。不含刷新逻辑（由 fetchGeneratedImage 包）。
  private async doRequestBinary(method: http.RequestMethod, path: string, tokenType: TokenType, hubUrl?: string): Promise<BinaryResult> {
    const url = `${this.resolveBaseUrl(hubUrl)}${path}`;
    const httpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {};
      if (tokenType === 'jwt') {
        const jwt = getConnectionService().jwt;
        if (jwt !== '') {
          header['Authorization'] = `Bearer ${jwt}`;
        }
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 30000   // 图片最大 25MB，读超时放宽到 30s
      };
      const response = await httpRequest.request(url, options);
      const ok: boolean = response.responseCode >= 200 && response.responseCode < 300;
      return {
        statusCode: response.responseCode,
        buffer: response.result as ArrayBuffer,
        errorMessage: ok ? '' : `HTTP ${response.responseCode}`
      };
    } catch (error) {
      return { statusCode: 0, buffer: new ArrayBuffer(0), errorMessage: t('api.requestFailed', { detail: JSON.stringify(error) }) };
    } finally {
      httpRequest.destroy();
    }
  }

  // 拉生成图片二进制 → base64 data URI（对照 web client.ts:255-278 getGeneratedImageBlob）。
  //   GET /api/sessions/:id/generated-images/:imageId，Bearer jwt + 401 刷 token 重试一次。
  //   mimeType 取报文元数据（block.mimeType），缺省回退 image/png（ArkUI Image 按数据头自识别）。
  async fetchGeneratedImage(sessionId: string, imageId: string, mimeType: string): Promise<GeneratedImageResult> {
    const path = `/api/sessions/${encodeURIComponent(sessionId)}/generated-images/${encodeURIComponent(imageId)}`;
    const first = await this.doRequestBinary(http.RequestMethod.GET, path, 'jwt');
    if (first.statusCode === 401 && getConnectionService().apiToken !== '') {
      const refreshed = await this.refreshJwt();
      if (refreshed) {
        return this.buildImageResult(await this.doRequestBinary(http.RequestMethod.GET, path, 'jwt'), mimeType);
      }
    }
    return this.buildImageResult(first, mimeType);
  }

  // 二进制响应 → data URI（成功）/ 错误结果（失败/空体）。base64 编码同 FilePicker（util.Base64Helper）。
  private buildImageResult(r: BinaryResult, mimeType: string): GeneratedImageResult {
    if (r.errorMessage !== '') {
      return { success: false, dataUri: '', error: r.errorMessage };
    }
    if (r.buffer.byteLength === 0) {
      return { success: false, dataUri: '', error: t('api.emptyImage') };
    }
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    const b64: string = base64Helper.encodeToStringSync(new Uint8Array(r.buffer));
    const mime: string = mimeType !== '' ? mimeType : 'image/png';
    return { success: true, dataUri: `data:${mime};base64,${b64}`, error: '' };
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
  // 列机器（GET /api/machines → { machines }，对照 web getMachines）——新建会话选 machine 用
  async getMachines(): Promise<Machine[]> {
    const resp = await this.request(http.RequestMethod.GET, '/api/machines', undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.loadMachinesFailed', { code: resp.statusCode }));
    }
    return parseMachinesResponse(resp.data);
  }

  // 浏览远端目录（POST /api/machines/:id/list-directory body { path } → { entries }，对照 web listMachineDirectory）
  //   新建会话「选择文件夹」树浏览用；entry 无绝对 path，UI 拼 currentPath + '/' + name 进入子目录。
  async listMachineDirectory(machineId: string, path: string): Promise<DirEntry[]> {
    const body = new ListDirectoryRequest();
    body.path = path;
    const resp = await this.request(http.RequestMethod.POST,
      `/api/machines/${machineId}/list-directory`, body, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.browseDirFailed', { code: resp.statusCode }));
    }
    return parseListDirectoryResponse(resp.data);
  }

  // 新建会话：spawn agent（POST /api/machines/:id/spawn → { type, sessionId }，对照 web spawnSession）
  //   在指定 machine 的 directory 上启动 agent 产生新 session。body 由 buildSpawnBody 条件化：
  //   model/effort 'auto' 省略、yolo 恒发、sessionType 恒发（默认 simple）、worktreeName 仅 worktree 时发。
  //   成功返回 sessionId；HTTP 失败或业务 error 抛 Error。
  async spawnSession(
    machineId: string,
    directory: string,
    agent: string,
    model: string = 'auto',
    effort: string = 'auto',
    yolo: boolean = false,
    sessionType: string = 'simple',
    worktreeName: string = ''
  ): Promise<string> {
    const body: Record<string, Object> = buildSpawnBody(directory, agent, model, effort, yolo, sessionType, worktreeName);
    const resp = await this.request(http.RequestMethod.POST,
      `/api/machines/${machineId}/spawn`, body, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.spawnFailed', { code: resp.statusCode }));
    }
    return parseSpawnResponse(resp.data);   // 业务 error（type:'error'）在此抛
  }

  async fetchSessions(): Promise<SessionSummary[]> {
    const resp = await this.request(http.RequestMethod.GET, '/api/sessions', undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.loadSessionsFailed', { code: resp.statusCode }));
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
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.loadMessagesFailed', { code: resp.statusCode }));
    }
    return parseMessagesPageResponse(resp.data);
  }

  // 拉取会话消息（首屏便捷：仅返回 messages，丢弃分页元数据）
  async fetchMessages(sessionId: string): Promise<ChatMessage[]> {
    const page = await this.fetchMessagesPage(sessionId);
    return page.messages;
  }

  // 发送用户消息（POST /api/sessions/:id/messages body { text, localId, scheduledAt? } → { ok:true }）
  // 真实消息靠 SSE message-received 回推（用 localId 匹配并替换乐观行）。
  // scheduledAt：>0 = 定时发送（epoch-ms，上游 refine 须 >0、≤7 天、带 localId、禁附件）；0/省略 = 即时。
  //   注意 body 用 Record 手建：scheduledAt===0 时**不发该键**——上游 refine scheduledAt==null 放行，
  //   若序列化 0 会撞 positive 校验 → 400（SendMessageRequest 类仅作类型文档，不直接序列化）。
  // 发送消息（POST /api/sessions/:id/messages，对照 web sendMessage）。
  //   attachments 与 scheduledAt 互斥（上游 refine：scheduledAt + attachments 同时给会 400），故 attachments 非空时不带 scheduledAt。
  async sendMessage(sessionId: string, text: string, localId: string,
    scheduledAt: number = 0, attachments: AttachmentMetadata[] = []): Promise<boolean> {
    const body: Record<string, Object> = { text: text, localId: localId };
    if (attachments.length > 0) {
      body['attachments'] = attachments as Object;
    } else if (scheduledAt > 0) {
      body['scheduledAt'] = scheduledAt;
    }
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/messages`, body, 'jwt');
    return resp.success;
  }

  // 取消排队消息（DELETE /api/sessions/:id/messages/:messageId → CancelMessageResponse，对照 web cancelMessage）
  //   响应 cancelled | invoked 竞态分支：cancelled=已取消；invoked=CLI 已消费（竞态失败，invokedMessage 为权威行）。
  //   网络层失败（statusCode 0）→ 返回 cancelled=false 的空结果，UI 据此提示「取消失败」而非误判已取消。
  async cancelMessage(sessionId: string, messageId: string): Promise<CancelMessageResult> {
    const resp = await this.request(http.RequestMethod.DELETE,
      `/api/sessions/${sessionId}/messages/${messageId}`, undefined, 'jwt');
    if (resp.statusCode === 0) {
      return new CancelMessageResult();   // 网络错误：保守判未取消
    }
    return parseCancelMessageResponse(resp.data);
  }

  // 中止会话运行（POST /api/sessions/:id/abort，对照 web abortSession）——「停止生成」
  async abortSession(sessionId: string): Promise<boolean> {
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/abort`, EMPTY_BODY, 'jwt');
    return resp.success;
  }

  // 恢复会话（POST /api/sessions/:id/resume[ body { permissionMode }] → { sessionId }，对照 web resumeSession client.ts:312）
  //   语义：非活跃会话重新拉起 CLI runner。发送前隐式调用（对齐上游 useSendMessage.resolveSessionId：
  //   session 非 active 时先 resume 拿【可能新的】sessionId 再发，否则 POST messages 撞 requireActive）。
  //   permissionMode 非空才随 body 发（保持当前权限模式）；成功返回 sessionId，HTTP/业务失败抛 Error。
  async resumeSession(sessionId: string, permissionMode: string = ''): Promise<string> {
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/resume`,
      permissionMode !== '' ? { permissionMode } as Record<string, Object> : EMPTY_BODY, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.resumeFailed', { code: resp.statusCode }));
    }
    return parseResumeSessionResponse(resp.data);
  }

  // 切换到远程会话（POST /api/sessions/:id/switch body {} → { ok:true }，对照 web switchSession client.ts:359）
  //   语义：多端/多窗口时让 CLI 把输入定向到本会话（「切换到远程」）。单窗口移动端价值低，保留入口供边缘场景。
  async switchSession(sessionId: string): Promise<boolean> {
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/switch`, EMPTY_BODY, 'jwt');
    return resp.success;
  }

  // 拉服务端斜杠命令（GET /api/sessions/:id/slash-commands → { success, commands? }，对照 web getSlashCommands:516）
  //   用户/项目/插件命令（source != 'builtin'）。失败返 [] 静默回落内置（离线/jwt 失效不阻塞输入，不抛）。
  async getSlashCommands(sessionId: string): Promise<ServerSlashCommand[]> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}/slash-commands`, undefined, 'jwt');
    if (!resp.success) {
      return [];
    }
    return parseSlashCommandsResponse(resp.data);
  }

  // 拉技能（GET /api/sessions/:id/skills → { success, skills? }，对照 web getSkills:522）
  //   $ 技能联想数据源。失败返 [] 静默（不阻塞输入，不抛）。
  async getSkills(sessionId: string): Promise<SkillItem[]> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}/skills`, undefined, 'jwt');
    if (!resp.success) {
      return [];
    }
    return parseSkillsResponse(resp.data);
  }

  // 上报可见性（POST /api/visibility body { subscriptionId, visibility }，对照 web setVisibility:189）
  //   subscriptionId 来自 SSE connection-changed；visibility = 'visible'(前台)/'hidden'(后台)。
  //   Hub 据此决定是否推送 TOAST。subscriptionId 空（未连/重连中）早退 false，不发无谓请求。
  async setVisibility(subscriptionId: string, visibility: string): Promise<boolean> {
    if (subscriptionId === '') {
      return false;
    }
    const body: Record<string, Object> = {
      subscriptionId: subscriptionId,
      visibility: visibility
    };
    const resp = await this.request(http.RequestMethod.POST, '/api/visibility', body, 'jwt');
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
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.loadSessionsFailed', { code: resp.statusCode }));
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

  // —— 会话内即时配置（对照 web client.ts:366-399，均 POST，body {key:value}）——
  //   5 端点：permission-mode（全 flavor）/ collaboration-mode（仅 codex）/ model（全）/ effort（claude）/ model-reasoning-effort（codex）。
  //   model/effort/reasoning 上游 schema .min(1).nullable()：空串非法，''(=默认/auto) 须发 null 复位 → body 用 string|null 联合类型。
  //   permission/collaboration mode 必填非空（'default' 即字面默认模式，非「复位」）。

  // 权限模式（POST /sessions/:id/permission-mode {mode}）
  async setPermissionMode(sessionId: string, mode: string): Promise<boolean> {
    const body: Record<string, string> = { mode: mode };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/permission-mode`, body, 'jwt');
    return resp.success;
  }

  // 协作模式（POST /sessions/:id/collaboration-mode {mode}，仅 codex）
  async setCollaborationMode(sessionId: string, mode: string): Promise<boolean> {
    const body: Record<string, string> = { mode: mode };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/collaboration-mode`, body, 'jwt');
    return resp.success;
  }

  // 模型（POST /sessions/:id/model {model}；'' → null 复位为 agent 默认）
  async setModel(sessionId: string, model: string): Promise<boolean> {
    const body: Record<string, string | null> = { model: model !== '' ? model : null };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/model`, body, 'jwt');
    return resp.success;
  }

  // 努力度（POST /sessions/:id/effort {effort}，claude；'' → null 复位 auto）
  async setEffort(sessionId: string, effort: string): Promise<boolean> {
    const body: Record<string, string | null> = { effort: effort !== '' ? effort : null };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/effort`, body, 'jwt');
    return resp.success;
  }

  // 推理努力（POST /sessions/:id/model-reasoning-effort {modelReasoningEffort}，codex；'' → null 复位）
  async setModelReasoningEffort(sessionId: string, effort: string): Promise<boolean> {
    const body: Record<string, string | null> = { modelReasoningEffort: effort !== '' ? effort : null };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/model-reasoning-effort`, body, 'jwt');
    return resp.success;
  }

  // —— Files 浏览（对照 web client.ts:224-296，均 GET /sessions/:id/...）——
  //   git-* 返 CommandResponse（业务 success 在 payload，不抛——非 git 仓库返 success=false+error，UI 据此显空态）。
  //   files/directory 返数组（HTTP 失败抛 Error，同 getMachines 模式）。
  //   readSessionFile 返 FileReadResponse（content 为 base64；不抛，业务 success 在 payload）。
  //   query/path 用 encodeURIComponent 编码（等价 web URLSearchParams）。

  // git status（GET /sessions/:id/git-status → CommandResponse，stdout=porcelain v2 --branch）
  async getGitStatus(sessionId: string): Promise<CommandResponse> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}/git-status`, undefined, 'jwt');
    return parseCommandResponse(resp.data);
  }

  // git diff numstat（GET /sessions/:id/git-diff-numstat?staged=bool → CommandResponse，stdout=added\tdeleted\tpath）
  async getGitDiffNumstat(sessionId: string, staged: boolean): Promise<CommandResponse> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}/git-diff-numstat?staged=${staged}`, undefined, 'jwt');
    return parseCommandResponse(resp.data);
  }

  // 单文件 diff（GET /sessions/:id/git-diff-file?path=&staged= → CommandResponse，stdout=统一 diff）
  async getGitDiffFile(sessionId: string, path: string, staged?: boolean): Promise<CommandResponse> {
    let p = `/api/sessions/${sessionId}/git-diff-file?path=${encodeURIComponent(path)}`;
    if (staged !== undefined) { p = `${p}&staged=${staged}`; }
    const resp = await this.request(http.RequestMethod.GET, p, undefined, 'jwt');
    return parseCommandResponse(resp.data);
  }

  // 文件名搜索（GET /sessions/:id/files[?query=&limit=] → FileSearchItem[]）
  async searchSessionFiles(sessionId: string, query: string, limit: number = 0): Promise<FileSearchItem[]> {
    let p = `/api/sessions/${sessionId}/files`;
    const params: string[] = [];
    if (query !== '') { params.push(`query=${encodeURIComponent(query)}`); }
    if (limit > 0) { params.push(`limit=${limit}`); }
    if (params.length > 0) { p = `${p}?${params.join('&')}`; }
    const resp = await this.request(http.RequestMethod.GET, p, undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.searchFilesFailed', { code: resp.statusCode }));
    }
    return parseFileSearchResponse(resp.data);
  }

  // 读文件内容（GET /sessions/:id/file?path= → FileReadResponse，content=base64）
  async readSessionFile(sessionId: string, path: string): Promise<FileReadResponse> {
    const resp = await this.request(http.RequestMethod.GET,
      `/api/sessions/${sessionId}/file?path=${encodeURIComponent(path)}`, undefined, 'jwt');
    return parseFileReadResponse(resp.data);
  }

  // 会话工作区目录浏览（GET /sessions/:id/directory[?path=] → SessionDirEntry[]）
  async listSessionDirectory(sessionId: string, path?: string): Promise<SessionDirEntry[]> {
    let p = `/api/sessions/${sessionId}/directory`;
    if (path !== undefined && path !== '') { p = `${p}?path=${encodeURIComponent(path)}`; }
    const resp = await this.request(http.RequestMethod.GET, p, undefined, 'jwt');
    if (!resp.success) {
      throw new Error(resp.errorMessage !== undefined ? resp.errorMessage : t('api.browseDirFailed', { code: resp.statusCode }));
    }
    return parseSessionDirectoryResponse(resp.data);
  }

  // —— 附件上传（对照 web client.ts:298 uploadFile / :306 deleteUploadFile）——
  //   上传为 JSON {filename, content: base64, mimeType}（非 multipart）；成功返服务端 path（回填 AttachmentMetadata.path）。
  //   请求体较大（整文件 base64），走既有 request（Content-Type application/json + JWT）。

  async uploadFile(sessionId: string, filename: string, content: string, mimeType: string): Promise<UploadFileResult> {
    const body: Record<string, Object> = {
      filename: filename,
      content: content,
      mimeType: mimeType
    };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/upload`, body, 'jwt');
    const result: UploadFileResult = parseUploadFileResponse(resp.data);
    // HTTP 层失败也合成 success=false（parse 只认 JSON 体）
    if (!resp.success && result.success) { result.success = false; }
    return result;
  }

  // 删除已上传附件（POST /sessions/:id/upload/delete body {path}，对照 deleteUploadFile）。
  //   用于附件 chip 的 ✕：移除待发附件时同步清服务端临时文件，避免残留。
  async deleteUploadFile(sessionId: string, path: string): Promise<boolean> {
    const body: Record<string, Object> = { path: path };
    const resp = await this.request(http.RequestMethod.POST,
      `/api/sessions/${sessionId}/upload/delete`, body, 'jwt');
    return resp.success;
  }
}

// 全局便捷访问
export function getHubClient(): HubClient {
  return HubClient.getInstance();
}
