// SSE 纯逻辑（无 ohos.* 依赖）—— 从 SSEClient.ets 抽出，便于 LocalUnit 测试。
// 1) SSEFrameParser：SSE 帧状态机（buffer/currentData/currentEvent/lastEventId），
//    对照 WHATWG Server-Sent Events 规范 + 原 SSEClient.feedChunk/handleLine/dispatchEvent。
// 2) buildEventsUrl：拼 /api/events?token=...&visibility=visible&...（对照原 SSEClient.buildEventsUrl）。

// SSE 帧解析器（纯逻辑：只吃文本、吐完整事件的 data 负载）
// 语义：
// - 按 \n 切行；空行 = 事件边界（派发当前累积的 data，并复位 data/event）。
// - 以 ':' 开头的行是注释（心跳常用），忽略。
// - "field: value" 形式；冒号后若有恰好一个前导空格则剥离一个（SSE 规范）。
// - 多个 data: 行用 \n 拼接成一个事件的 data 负载。
// - event:/id: 字段被解析（id 写入 lastEventId 供 Last-Event-ID 断点续传；event 暂存不用）。
// - 空事件（data 为空）不派发（对照原 dispatchEvent 早退）。
// - lastEventId 跨 reset()/重连保留（断点续传需要）；reset() 只清缓冲与当前事件。
export class SSEFrameParser {
  private buffer: string = '';
  private currentData: string = '';
  private currentEvent: string = '';
  lastEventId: string = '';

  // 喂入一段文本，返回本次新解析出的完整事件的 data 负载（已多行 \n 合并）；无完整事件返回空数组。
  feed(text: string): string[] {
    const events: string[] = [];
    this.buffer += text;
    let idx: number = this.buffer.indexOf('\n');
    while (idx >= 0) {
      const line: string = this.buffer.substring(0, idx);
      this.buffer = this.buffer.substring(idx + 1);
      this.handleLine(line, events);
      idx = this.buffer.indexOf('\n');
    }
    return events;
  }

  // 复位解析缓冲（重连前调用）；lastEventId 不清（断点续传）
  reset(): void {
    this.buffer = '';
    this.currentData = '';
    this.currentEvent = '';
  }

  private handleLine(line: string, events: string[]): void {
    let l: string = line;
    if (l.endsWith('\r')) {
      l = l.substring(0, l.length - 1);
    }
    if (l === '') {
      if (this.currentData !== '') {
        events.push(this.currentData);
      }
      this.currentData = '';
      this.currentEvent = '';
      return;
    }
    if (l.startsWith(':')) {
      return; // 注释行
    }
    const colon: number = l.indexOf(':');
    const field: string = colon > 0 ? l.substring(0, colon) : l;
    let value: string = colon > 0 ? l.substring(colon + 1) : '';
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field === 'data') {
      this.currentData += (this.currentData !== '' ? '\n' : '') + value;
    } else if (field === 'event') {
      this.currentEvent = value;
    } else if (field === 'id') {
      this.lastEventId = value;
    }
  }
}

// 拼 /api/events?... URL（对照原 SSEClient.buildEventsUrl；纯函数，参数显式传入便于测试）
// token 为空则不带（未登录场景）；visibility=visible 恒带；all/sessionId/machineId 按需带。
export function buildEventsUrl(baseUrl: string, token: string, all: boolean,
  sessionId: string, machineId: string): string {
  const params: string[] = [];
  if (token !== '') {
    params.push(`token=${encodeURIComponent(token)}`);
  }
  params.push('visibility=visible');
  if (all) {
    params.push('all=true');
  }
  if (sessionId !== '') {
    params.push(`sessionId=${encodeURIComponent(sessionId)}`);
  }
  if (machineId !== '') {
    params.push(`machineId=${encodeURIComponent(machineId)}`);
  }
  return `${baseUrl}/api/events?${params.join('&')}`;
}
