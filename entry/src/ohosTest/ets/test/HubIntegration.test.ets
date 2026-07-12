// HubIntegration 集成测试（ohosTest / ARunit）—— 需真实 Hub，且设备/模拟器能访问到。
//
// 运行手册（改顶部两个常量即可）：
//   1) 起本地 Hub（已知 token）：
//        CLI_API_TOKEN=testhubtoken0123456789abcdef npx -y @twsxtd/hapi@0.21.0 hub --no-relay --port 3006
//   2) HUB_URL 改成「设备/模拟器能访问到 Hub 的」地址：
//        - 模拟器：先试 http://10.0.2.2:3006，不通则用宿主机 LAN IP；
//        - 真机：宿主机 LAN IP（如 http://192.168.x.x:3006）。
//   3) HUB_TOKEN 填上面 CLI_API_TOKEN（可加 :namespace 后缀，如 ...:dev）。
//   4) DevEco 跑 ARunit。**未起 Hub 时本套件自动跳过（标 pass + 不连累其它用例）**。
//
// 实测契约（2026-07-12 对 @twsxtd/hapi 0.21.0 抓取，裸 Hub 无 CLI agent）：
//   GET  /health                       → 200 {status:'ok',protocolVersion:1}（无鉴权）
//   POST /api/auth {accessToken}       → 200 {token,user:{id,firstName:'Web User'}}
//                                         坏 token → 401 {error:'Invalid access token'}
//                                         坏体    → 400 {error:'Invalid body'}
//   GET  /api/sessions   (Bearer jwt)  → 200 {sessions:[]}（engine 启动即存在，**非 agent 绑定**）
//   GET  /api/sessions/:id             → 404 {error:'Session not found'}（需 agent 建会话）
//   POST /api/sessions/:id/messages    → 404（需 active 会话；happy path 需 agent，未纳入）
//   GET  /api/events?token=<jwt>       → 连上立即吐 data:{"type":"connection-changed",...}；坏 jwt → 401 {error:'Invalid token'}
//
// 故覆盖：health(正/负) / authenticate(好/坏) / fetchSessions(空数组) / SSE 连上收 connection-changed / sendMessage(无会话→false 负向)。
// sendMessage/SSE 的 agent 相关 happy path 属更重 harness（需起 CLI agent），未纳入。

import { describe, it, expect } from '@ohos/hypium';
import { getHubClient } from '../../../main/ets/api/HubClient';
import { getSSEClient, SSEConnectionState } from '../../../main/ets/api/SSEClient';
import { getConnectionService } from '../../../main/ets/services/ConnectionService';

// ===== 用户按需修改 =====
const HUB_URL: string = 'http://10.0.2.2:3006';              // 模拟器默认；真机改宿主机 LAN IP
const HUB_TOKEN: string = 'testhubtoken0123456789abcdef';   // 起 Hub 时的 CLI_API_TOKEN（可加 :ns）
// =======================

// 懒探测：首个需 Hub 的用例探一次，缓存结果；后续用例复用。未起 Hub → 各用例早退（标 pass）。
let hubReachable: boolean = false;
let probed: boolean = false;
async function hubUp(): Promise<boolean> {
  if (!probed) {
    hubReachable = await getHubClient().health(HUB_URL);
    probed = true;
  }
  return hubReachable;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => { setTimeout(resolve, ms); });
}

export default function hubIntegrationTest(): void {
  describe('HubIntegration — health', () => {
    it('health returns true when the hub is up', 0, async () => {
      if (!(await hubUp())) { return; }   // 未起 Hub → 跳过
      expect(await getHubClient().health(HUB_URL)).assertTrue();
    });

    it('health returns false for an unreachable host', 0, async () => {
      // 负向：始终可测（端口拒绝连接 → health 捕获异常返回 false）
      expect(await getHubClient().health('http://127.0.0.1:1')).assertFalse();
    });
  });

  describe('HubIntegration — authenticate', () => {
    it('authenticates with a valid token and returns a jwt + Web User', 0, async () => {
      if (!(await hubUp())) { return; }
      const r = await getHubClient().authenticate(HUB_TOKEN, HUB_URL);
      expect(r.success).assertTrue();
      expect(r.jwt.length > 0).assertTrue();
      expect(r.user !== null).assertTrue();
      if (r.user !== null) {
        expect(r.user.firstName).assertEqual('Web User');
      }
    });

    it('rejects a wrong token with 401 / "Access Token 无效"', 0, async () => {
      if (!(await hubUp())) { return; }
      const r = await getHubClient().authenticate('wrongtoken1234567890abcdef', HUB_URL);
      expect(r.success).assertFalse();
      expect(r.errorMessage).assertEqual('Access Token 无效');
    });
  });

  describe('HubIntegration — sessions & messages', () => {
    it('fetchSessions returns an array (empty on a bare hub)', 0, async () => {
      if (!(await hubUp())) { return; }
      const conn = getConnectionService();
      conn.hubUrl = HUB_URL;
      const auth = await getHubClient().authenticate(HUB_TOKEN, HUB_URL);
      expect(auth.success).assertTrue();
      conn.jwt = auth.jwt;   // fetchSessions 用 ConnectionService.jwt
      const sessions = await getHubClient().fetchSessions();
      expect(sessions.length >= 0).assertTrue();   // 全链路（HTTP→parseSessionsResponse）未抛错；裸 Hub 为 0
      conn.jwt = '';
    });

    it('sendMessage to a nonexistent session returns false', 0, async () => {
      if (!(await hubUp())) { return; }
      // happy path 需 agent 建会话；此处只验「无会话 → false」（404 → request.success=false）
      const ok = await getHubClient().sendMessage('no-such-session', 'hi', 'local-1');
      expect(ok).assertFalse();
    });
  });

  describe('HubIntegration — SSE', () => {
    it('receives connection-changed on connect (state becomes open)', 0, async () => {
      if (!(await hubUp())) { return; }
      const conn = getConnectionService();
      conn.hubUrl = HUB_URL;
      const auth = await getHubClient().authenticate(HUB_TOKEN, HUB_URL);
      expect(auth.success).assertTrue();
      conn.jwt = auth.jwt;

      const sse = getSSEClient();
      let gotOpen: boolean = false;
      let gotEvent: boolean = false;
      const id = sse.addListener({
        onEvent: () => { gotEvent = true; },
        onStateChange: (s: SSEConnectionState) => { if (s === 'open') { gotOpen = true; } }
      });
      sse.connect();
      // Hub 连上立即吐 connection-changed；等最多 ~6s
      for (let i = 0; i < 60; i++) {
        if (gotOpen || gotEvent) { break; }
        await sleep(100);
      }
      sse.removeListener(id);
      sse.disconnect();
      conn.jwt = '';   // 复位，避免影响其它套件
      expect(gotOpen || gotEvent).assertTrue();
    });
  });

  // JWT 自动刷新（自愈）：REST 401 → refreshJwt(apiToken) → saveJwt → 重试；SSE 流 401 → handleAuthFailure → 刷新重连。
  // 覆盖：REST 自愈成功 / 刷新失败不循环 / SSE 流 401 自愈收到 connection-changed。
  describe('HubIntegration — JWT 自动刷新（自愈）', () => {
    // REST：把 jwt 改成坏值 → 发 jwt 请求 → 命中 401 → 自动用 apiToken 重换 → 重试成功。
    // 裸 Hub 无会话：fetchSessions 不抛错（返回 []）即证明刷新+重试链路通了（坏 jwt 本会 401 抛错）。
    it('REST: corrupt jwt → fetchSessions self-heals (refresh + retry)', 0, async () => {
      if (!(await hubUp())) { return; }
      const conn = getConnectionService();
      conn.hubUrl = HUB_URL;
      conn.apiToken = HUB_TOKEN;
      const auth = await getHubClient().authenticate(HUB_TOKEN, HUB_URL);
      expect(auth.success).assertTrue();
      conn.jwt = auth.jwt;

      conn.jwt = 'corrupted.invalid.jwt';   // 坏 jwt：Hub 必 401 → request() 触发 refreshJwt → 重试
      const sessions = await getHubClient().fetchSessions();   // 不抛错 = 自愈成功
      expect(sessions.length >= 0).assertTrue();
      expect(conn.jwt !== 'corrupted.invalid.jwt').assertTrue();   // jwt 已被刷新
      expect(conn.jwt.length > 0).assertTrue();

      conn.jwt = '';      // 复位
      conn.apiToken = '';
    });

    // 刷新失败收敛：apiToken 也无效时刷新必失败 → 不无限重试，请求照常失败（fetchSessions 抛错）。
    it('REST: refresh failure does not loop (bad apiToken → request still fails)', 0, async () => {
      if (!(await hubUp())) { return; }
      const conn = getConnectionService();
      conn.hubUrl = HUB_URL;
      conn.apiToken = 'badtoken-not-valid-1234567890';   // 坏 apiToken → 重换必 401
      conn.jwt = 'corrupted.invalid.jwt';

      let threw = false;
      try {
        await getHubClient().fetchSessions();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();   // 刷新失败 → 原 401 → 抛错，不挂死

      conn.apiToken = '';   // 复位
      conn.jwt = '';
    });

    // SSE：坏 jwt 建流 → Hub 401 → handleAuthFailure 刷新 → 重连自愈 → 收 connection-changed。
    // connection-changed 只可能由真实连上的流发出（401 错误体 parseSyncEvent 为 null）→ gotEvent 即自愈成功。
    it('SSE: corrupt jwt → stream 401 → refresh → reconnect emits connection-changed', 0, async () => {
      if (!(await hubUp())) { return; }
      const conn = getConnectionService();
      conn.hubUrl = HUB_URL;
      conn.apiToken = HUB_TOKEN;
      const auth = await getHubClient().authenticate(HUB_TOKEN, HUB_URL);
      expect(auth.success).assertTrue();
      conn.jwt = 'corrupted.invalid.jwt';   // 故意坏 jwt 建 SSE → 触发流 401 → 自愈

      const sse = getSSEClient();
      let gotEvent = false;
      const id = sse.addListener({
        onEvent: () => { gotEvent = true; }
      });
      sse.connect();
      // 自愈时序：坏 jwt 401(~100ms) → refreshJwt(~100ms) → 首次重连退避(1~1.5s) → 建流吐 connection-changed。给 ~10s。
      for (let i = 0; i < 100; i++) {
        if (gotEvent) { break; }
        await sleep(100);
      }
      sse.removeListener(id);
      sse.disconnect();
      expect(gotEvent).assertTrue();
      expect(conn.jwt !== 'corrupted.invalid.jwt').assertTrue();   // jwt 已刷新

      conn.jwt = '';      // 复位
      conn.apiToken = '';
    });
  });
}
