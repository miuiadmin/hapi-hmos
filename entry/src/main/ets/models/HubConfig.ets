// Hapi Hub 连接配置
// 用户在登录页填写并持久化（对照 chatcube AccountService 的连接信息存储范式）

// 默认命名空间：hapi accessToken 无 ':' 后缀时用 'default'
export const DEFAULT_NAMESPACE: string = 'default';

// Hapi Hub 连接配置
export class HubConfig {
  hubUrl: string = '';                       // Hub 地址（含协议+端口），如 http://192.168.1.5:3006
  apiToken: string = '';                     // CLI_API_TOKEN（原始，无 :namespace 后缀）
  namespace: string = DEFAULT_NAMESPACE;     // 命名空间隔离（多用户）
}

// 预制服务器（厂内测试等：一键切换 Hub 地址 + token，免手填）。
//   切换 = LoginPage 预制芯片 onClick → 回填 hubUrl/apiToken → 复用 doLogin（authenticate→saveConnection→saveJwt）。
//   消费侧（HubClient/SSEClient）每次请求读 ConnectionService 单例，切服务器零改动。
export class ServerPreset {
  id: string;
  name: string;
  hubUrl: string;
  apiToken: string;

  constructor(id: string, name: string, hubUrl: string, apiToken: string) {
    this.id = id;
    this.name = name;
    this.hubUrl = hubUrl;
    this.apiToken = apiToken;
  }
}
