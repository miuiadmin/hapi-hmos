import { getPreferencesService } from './PreferencesService';
import { PreferenceKeys } from '../config/Keys';
import { DEFAULT_NAMESPACE } from '../models/HubConfig';

// 登录态管理：持久化（Preferences）做真值 + 内存缓存
// 对照 chatcube AccountService 范式
export class ConnectionService {
  private static instance: ConnectionService | null = null;

  hubUrl: string = '';
  apiToken: string = '';
  namespace: string = DEFAULT_NAMESPACE;
  jwt: string = '';            // 登录后换得（4h 过期，HubClient 自动重换）

  private constructor() {}

  static getInstance(): ConnectionService {
    if (ConnectionService.instance === null) {
      ConnectionService.instance = new ConnectionService();
    }
    return ConnectionService.instance;
  }

  // 启动时从 preferences 读回（EntryAbility.onWindowStageCreate 里 await）
  async initialize(): Promise<void> {
    const ps = getPreferencesService();
    this.hubUrl = await ps.getString(PreferenceKeys.HUB_URL);
    this.apiToken = await ps.getString(PreferenceKeys.API_TOKEN);
    this.namespace = await ps.getString(PreferenceKeys.NAMESPACE, DEFAULT_NAMESPACE);
    this.jwt = await ps.getString(PreferenceKeys.JWT);
  }

  // 是否已配置连接（hubUrl + apiToken 非空）。jwt 会过期，不作为登录态判据
  isLoggedIn(): boolean {
    return this.hubUrl !== '' && this.apiToken !== '';
  }

  // 保存连接配置（登录页提交时调用）
  async saveConnection(hubUrl: string, apiToken: string, namespace: string = DEFAULT_NAMESPACE): Promise<void> {
    this.hubUrl = hubUrl;
    this.apiToken = apiToken;
    this.namespace = namespace;
    const ps = getPreferencesService();
    await ps.putString(PreferenceKeys.HUB_URL, hubUrl);
    await ps.putString(PreferenceKeys.API_TOKEN, apiToken);
    await ps.putString(PreferenceKeys.NAMESPACE, namespace);
  }

  // 保存登录后换得的 JWT
  async saveJwt(jwt: string): Promise<void> {
    this.jwt = jwt;
    await getPreferencesService().putString(PreferenceKeys.JWT, jwt);
  }

  // 退出登录：清空所有连接信息
  async clear(): Promise<void> {
    this.hubUrl = '';
    this.apiToken = '';
    this.namespace = DEFAULT_NAMESPACE;
    this.jwt = '';
    const ps = getPreferencesService();
    await ps.delete(PreferenceKeys.HUB_URL);
    await ps.delete(PreferenceKeys.API_TOKEN);
    await ps.delete(PreferenceKeys.NAMESPACE);
    await ps.delete(PreferenceKeys.JWT);
  }
}

// 全局便捷访问
export function getConnectionService(): ConnectionService {
  return ConnectionService.getInstance();
}
