import { url } from '@kit.ArkTS';
import { getHubClient } from '../api/HubClient';
import { getConnectionService } from './ConnectionService';
import { getJwtRefreshScheduler } from './JwtRefreshScheduler';
import { t } from '../i18n/I18nService';

// 配置导入（deep link）——「同一份代码、数据在设备」范式的输入通道。
//
// 链接格式：hapi://connect?server=<URL 编码的 Hub 地址>&token=<CLI_API_TOKEN>
//   例：hapi://connect?server=https%3A%2F%2Fhapi.example.nip.io%2F&token=5ae9…0b5e
//   由「你的服务器网页 / 备忘录」生成，点一下 → 拉起 App → 验证 token → 存进 preferences（持久化）。
//   token 不入源码、不入 HAP，仓库与构建产物对所有用户完全一致（取代旧 FactoryPresets 编译期常量）。
//
// scheme + host 须与 module.json5 EntryAbility skills 的 uris 一致。
//   解析用 @kit.ArkTS 的 url.URL.parseURL（标准库、自动 percent-decode，非 regex——ArkTS 严格模式友好）。
//   对照 berry3/ClashBox EntryAbility.onCreate 用 url.URL.parseURL 解析 clash://install-config?url= 的先例。

const SCHEME: string = 'hapi';
const HOST: string = 'connect';

// 解析结果
export interface ParsedConnect {
  server: string;
  token: string;
}

// 导入结果
export interface ImportResult {
  success: boolean;
  errorMessage: string;
}

export class DeepLinkImporter {
  private static instance: DeepLinkImporter | null = null;

  // 待处理的导入 URI：冷启动 onCreate 暂存 → 首屏（LoginPage.aboutToAppear 或 bootstrap 回调）消费。
  private pendingUri: string = '';

  private constructor() {}

  static getInstance(): DeepLinkImporter {
    if (DeepLinkImporter.instance === null) {
      DeepLinkImporter.instance = new DeepLinkImporter();
    }
    return DeepLinkImporter.instance;
  }

  // 是否为 connect 导入链接（onCreate/onNewWant 用此判定是否暂存/处理）
  isConnectLink(uri: string): boolean {
    const prefix: string = `${SCHEME}://${HOST}`;
    if (!uri.startsWith(prefix)) {
      return false;
    }
    // prefix 后须紧跟 ?、/ 或结尾，避免误匹配 hapi://connectXXX
    const next: string = uri.length > prefix.length ? uri.charAt(prefix.length) : '';
    return next === '' || next === '?' || next === '/';
  }

  // 暂存待处理 URI（EntryAbility.onCreate 调）
  setPending(uri: string): void {
    this.pendingUri = uri;
  }

  // 取出并清空待处理 URI（首屏 aboutToAppear / bootstrap 回调消费；幂等，取一次即空）
  consumePending(): string {
    const u: string = this.pendingUri;
    this.pendingUri = '';
    return u;
  }

  // 解析 hapi://connect?server=&token= → {server, token}；非 connect 链接或缺参返回 null
  parse(uri: string): ParsedConnect | null {
    if (!this.isConnectLink(uri)) {
      return null;
    }
    let parsed: url.URL;
    try {
      parsed = url.URL.parseURL(uri);
    } catch (_e) {
      return null;
    }
    const serverRaw: string | null = parsed.params.get('server');
    const tokenRaw: string | null = parsed.params.get('token');
    const server: string = serverRaw !== null ? serverRaw : '';
    const token: string = tokenRaw !== null ? tokenRaw : '';
    if (server === '' || token === '') {
      return null;
    }
    const result: ParsedConnect = { server: server, token: token };
    return result;
  }

  // 执行导入：authenticate（验证 token 换 JWT）→ 持久化连接 + JWT → arm 预刷定时器。
  //   与 LoginPage.doLogin 走同一条链路（导入 = 手动登录，单一真值源；故 LoginPage 也调本方法）。
  async apply(server: string, token: string): Promise<ImportResult> {
    const s: string = server.trim();
    const tk: string = token.trim();
    if (s === '' || tk === '') {
      return { success: false, errorMessage: t('deeplink.invalid') };
    }
    const result = await getHubClient().authenticate(tk, s);
    if (!result.success || result.jwt === '') {
      const msg: string = result.errorMessage !== '' ? result.errorMessage : t('login.error.authFailedGeneric');
      return { success: false, errorMessage: msg };
    }
    await getConnectionService().saveConnection(s, tk);
    await getConnectionService().saveJwt(result.jwt);
    getJwtRefreshScheduler().arm();
    return { success: true, errorMessage: '' };
  }
}

// 全局便捷访问
export function getDeepLinkImporter(): DeepLinkImporter {
  return DeepLinkImporter.getInstance();
}
