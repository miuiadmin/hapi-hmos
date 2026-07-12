import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { getConnectionService } from '../services/ConnectionService';
import { SyncEvent, parseSyncEvent } from '../models/SyncEvent';
import { SSEFrameParser, buildEventsUrl } from './SSEClientUtils';
import { getHubClient } from './HubClient';

// Hapi Hub SSE 客户端（对齐 web/src/hooks/useSSE.ts）
// 鸿蒙无 EventSource，用 @ohos.net.http 的 requestInStream + on('dataReceive') 流式接收
// （对照 chatcube HttpService.streamPost 范式：expectDataType=ARRAY_BUFFER 才会逐块回调）。
// 鉴权：token 作 query param（/api/events?token=<jwt>，对齐 web buildEventsUrl）。
// 解析：ArrayBuffer → TextDecoder → 行缓冲按 \n\n 分帧 → 剥 data:/event:/id: → JSON.parse → SyncEvent。
// 重连：手动指数退避（对齐 hapi useSSE），重连前 off()+destroy() 旧实例防句柄泄漏/OOM。
//
// 多监听者：单例 + 单条全局连接（不带 sessionId，visibility=visible 收所有可见会话事件），
//           列表页 / 对话页各自 addListener 并按 sessionId 过滤（根因修复：单回调会被后入页面覆盖）。

// 监听者（页面注册：onEvent 必填，onStateChange 可选）
export interface SSEListener {
  onEvent: (event: SyncEvent) => void;
  onStateChange?: (state: SSEConnectionState) => void;
}

// 监听者条目（id 用于注销）
class ListenerEntry {
  id: number = 0;
  listener: SSEListener;
  constructor(listener: SSEListener, id: number) {
    this.listener = listener;
    this.id = id;
  }
}

// SSE 订阅范围（对齐 hapi SSESubscription；对话页/列表页均用全局订阅，不设 sessionId）
export class SSESubscription {
  all: boolean = false;
  sessionId: string = '';
  machineId: string = '';
}

// 连接状态
export type SSEConnectionState = 'idle' | 'connecting' | 'open' | 'reconnecting' | 'closed';

// 重连参数（对齐 hapi useSSE 常量）
const RECONNECT_BASE_DELAY_MS: number = 1000;
const RECONNECT_MAX_DELAY_MS: number = 30000;
const RECONNECT_JITTER_MS: number = 500;
const READ_TIMEOUT_MS: number = 600000;     // SSE 长连接，readTimeout 设大

export class SSEClient {
  private static instance: SSEClient | null = null;

  private httpRequest: http.HttpRequest | null = null;
  private decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  // SSE 帧解析（纯逻辑抽到 SSEClientUtils.SSEFrameParser，便于单测）
  private parser: SSEFrameParser = new SSEFrameParser();

  // 连接状态
  private state: SSEConnectionState = 'idle';
  private reconnectAttempt: number = 0;
  private reconnecting: boolean = false;
  private reconnectTimerId: number = -1;

  // 订阅
  private subscription: SSESubscription = new SSESubscription();

  // 多监听者
  private listeners: ListenerEntry[] = [];
  private nextListenerId: number = 1;

  private constructor() {}

  static getInstance(): SSEClient {
    if (SSEClient.instance === null) {
      SSEClient.instance = new SSEClient();
    }
    return SSEClient.instance;
  }

  // 当前连接状态（供 UI 横幅等在挂载时读当前态，而非只靠 onStateChange 转换）
  getState(): SSEConnectionState {
    return this.state;
  }

  // 注册监听者，返回 id（用于注销）
  addListener(listener: SSEListener): number {
    const id = this.nextListenerId;
    this.nextListenerId = this.nextListenerId + 1;
    this.listeners.push(new ListenerEntry(listener, id));
    return id;
  }

  // 注销监听者
  removeListener(id: number): void {
    this.listeners = this.listeners.filter((e: ListenerEntry): boolean => e.id !== id);
  }

  // 建连（需已登录：hubUrl + jwt 非空）
  connect(subscription?: SSESubscription): void {
    const conn = getConnectionService();
    if (conn.hubUrl === '' || conn.jwt === '') {
      this.setState('closed');
      return;
    }
    this.subscription = subscription ?? new SSESubscription();
    this.reconnectAttempt = 0;
    this.openStream();
  }

  // 主动断开（不再重连）
  disconnect(): void {
    this.setState('closed');
    if (this.reconnectTimerId !== -1) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = -1;
    }
    this.reconnecting = false;
    this.cleanupRequest();
  }

  private setState(s: SSEConnectionState): void {
    this.state = s;
    for (let i = 0; i < this.listeners.length; i++) {
      const cb = this.listeners[i].listener.onStateChange;
      if (cb !== undefined) {
        cb(s);
      }
    }
  }

  private get baseUrl(): string {
    const url = getConnectionService().hubUrl;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // 构造 /api/events?token=...&visibility=visible&...（拼装逻辑抽到 SSEClientUtils.buildEventsUrl）
  private buildEventsUrl(): string {
    return buildEventsUrl(this.baseUrl, getConnectionService().jwt,
      this.subscription.all, this.subscription.sessionId, this.subscription.machineId);
  }

  // 建立一次 SSE 流连接
  private openStream(): void {
    this.cleanupRequest();
    this.parser.reset();   // 清帧缓冲（lastEventId 保留供断点续传）
    this.setState(this.reconnectAttempt > 0 ? 'reconnecting' : 'connecting');

    const httpRequest = http.createHttp();
    this.httpRequest = httpRequest;

    // 首次收到数据 = 连接已建立（等价 EventSource.onopen）
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (this.state !== 'open') {
        this.reconnectAttempt = 0;
        this.setState('open');
      }
      // stream:true 维持多字节字符跨块状态
      const text = this.decoder.decodeToString(new Uint8Array(data), { stream: true });
      const events = this.parser.feed(text);
      for (let i = 0; i < events.length; i++) {
        const event = parseSyncEvent(events[i]);
        if (event !== null) {
          this.dispatchToListeners(event);
        }
      }
    });

    const header: Record<string, string> = {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache'
    };
    if (this.parser.lastEventId !== '') {
      header['Last-Event-ID'] = this.parser.lastEventId;   // 断点续传
    }
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,   // 必须：否则一次性返回不逐块回调
      connectTimeout: 15000,
      readTimeout: READ_TIMEOUT_MS
    };

    // requestInStream 的 then 在流结束时 resolve（SSE 正常应持续，结束即断开 → 重连）
    httpRequest.requestInStream(this.buildEventsUrl(), options)
      .then((code: number) => {
        if (code === 401 || code === 403) {
          // 鉴权失败：jwt 多半已过期 → 刷新一次再重连自愈；刷新失败（apiToken 也无效）才停止
          this.handleAuthFailure();
        } else {
          this.scheduleReconnect(`stream ended ${code}`);
        }
      })
      .catch((err: Error) => {
        this.scheduleReconnect(`error: ${err.message}`);
      });
  }

  // 流鉴权失败（401/403）：jwt 过期则刷新后重连自愈（对照 REST request 的 401 刷新 + 单飞）。
  //   刷新成功 → scheduleReconnect（重读已更新的 ConnectionService.jwt 重建流）；
  //   刷新失败 / 异常 → setState('closed')，避免用坏凭据无限重连。
  private handleAuthFailure(): void {
    getHubClient().refreshJwt().then((ok: boolean) => {
      if (ok) {
        this.scheduleReconnect('token refreshed after 401');
      } else {
        this.setState('closed');
      }
    }).catch(() => {
      this.setState('closed');
    });
  }

  // 把已解析的 SSE 事件派发给所有监听者
  private dispatchToListeners(event: SyncEvent): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].listener.onEvent(event);
    }
  }

  // 指数退避重连（对齐 hapi useSSE scheduleReconnect）
  private scheduleReconnect(reason: string): void {
    if (this.state === 'closed') {
      return;
    }
    if (this.reconnecting) {
      return;
    }
    this.reconnecting = true;
    this.cleanupRequest();

    const attempt: number = this.reconnectAttempt;
    const delay: number = Math.min(RECONNECT_MAX_DELAY_MS, RECONNECT_BASE_DELAY_MS * Math.pow(2, attempt));
    const jitter: number = Math.floor(Math.random() * (RECONNECT_JITTER_MS + 1));
    this.reconnectAttempt = attempt + 1;
    this.setState('reconnecting');

    this.reconnectTimerId = setTimeout(() => {
      this.reconnecting = false;
      this.reconnectTimerId = -1;
      if (this.state === 'closed') {
        return;
      }
      this.openStream();
    }, delay + jitter);
  }

  // 清理 HTTP 实例（off 监听 + destroy，防句柄泄漏/OOM，对照 chatcube cleanupHttpRequest）
  private cleanupRequest(): void {
    if (this.httpRequest !== null) {
      try {
        this.httpRequest.off('dataReceive');
      } catch (e) {
        // 忽略 off 异常
      }
      try {
        this.httpRequest.destroy();
      } catch (e) {
        // 忽略
      }
      this.httpRequest = null;
    }
  }
}

// 全局便捷访问
export function getSSEClient(): SSEClient {
  return SSEClient.getInstance();
}
