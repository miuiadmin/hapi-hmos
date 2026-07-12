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
