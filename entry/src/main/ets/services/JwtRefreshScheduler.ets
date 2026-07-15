// JWT 主动预刷调度器（对照上游 web useAuth.ts 的 scheduler + focus/visibility 续期）。
//   单例（getJwtRefreshScheduler），避环：本类只 import {ConnectionService, JwtUtils}，**不 import HubClient**。
//   刷新动作经 EntryAbility 注入的 onFire 回调触发（getHubClient().refreshJwt()），从而切断
//   HubClient↔ConnectionService 的 import 环。
//
//   arm()：读当前 jwt → decodeJwtExpMs → 计 exp-60s-now 的延迟 → schedule；jwt 空 / exp≤0 → cancel。
//   schedule(ms)：清旧定时器 + 设新定时器（到期置 timerId=-1 并触发 onFire）。
//   cancel()：清定时器、置 -1。
//   与 SSEClient 的 401 被动刷新无竞争：双方最终都走 HubClient.refreshJwt() 的单飞，去重共享结果。

import { getConnectionService } from './ConnectionService';
import { decodeJwtExpMs } from '../utils/JwtUtils';

// 预留 60s 提前量（对照上游 60_000）：到期前 1 分钟触发刷新，避免请求途中过期。
const REFRESH_LEAD_MS: number = 60_000;
// 刷新失败但 token 尚未过期时的退避重试间隔（对照上游 15_000）。
const RETRY_MS: number = 15_000;

class JwtRefreshScheduler {
  private static instance: JwtRefreshScheduler | null = null;

  private constructor() {}

  static getInstance(): JwtRefreshScheduler {
    if (JwtRefreshScheduler.instance === null) {
      JwtRefreshScheduler.instance = new JwtRefreshScheduler();
    }
    return JwtRefreshScheduler.instance;
  }

  private timerId: number = -1;
  // 由 EntryAbility 注入：到期触发时调用 getHubClient().refreshJwt() 并按结果续期。
  onFire: () => void = (): void => {};

  // 进会话 / 登录成功后调用：按当前 jwt 的 exp 排一次预刷。
  arm(): void {
    const jwt: string = getConnectionService().jwt;
    const expMs: number = decodeJwtExpMs(jwt);
    if (jwt === '' || expMs <= 0) {
      this.cancel();
      return;
    }
    const delayMs: number = expMs - REFRESH_LEAD_MS - Date.now();
    this.schedule(delayMs);
  }

  // 退避重试：刷新失败但 token 仍有效时，15s 后再试（由 EntryAbility.retryIfStillValid 调用）。
  retryIfStillValid(): void {
    const jwt: string = getConnectionService().jwt;
    const expMs: number = decodeJwtExpMs(jwt);
    if (jwt !== '' && expMs > 0 && Date.now() < expMs) {
      this.schedule(RETRY_MS);
    }
  }

  schedule(delayMs: number): void {
    this.cancel();
    const safe: number = delayMs < 0 ? 0 : delayMs;
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      this.onFire();
    }, safe);
  }

  cancel(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}

// 全局便捷访问（对照 getConnectionService/getHubClient 的 getInstance 懒单例范式）。
export function getJwtRefreshScheduler(): JwtRefreshScheduler {
  return JwtRefreshScheduler.getInstance();
}
