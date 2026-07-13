// 持久化 key（Preferences）集中管理（对照 chatcube PreferenceKeys 范式）
export class PreferenceKeys {
  static readonly HUB_URL: string = 'hapi_hub_url';
  static readonly API_TOKEN: string = 'hapi_api_token';
  static readonly NAMESPACE: string = 'hapi_namespace';
  static readonly JWT: string = 'hapi_jwt';           // 登录后换得的 JWT
  static readonly THEME_MODE: string = 'hapi_theme_mode';   // 主题模式 light/dark/system
  static readonly FONT_SCALE: string = 'hapi_font_scale';   // 全局字号缩放（'small'|'default'|'large'）
  static readonly ENTER_TO_SEND: string = 'hapi_enter_to_send';   // 回车发送消息（bool，默认关：Enter=换行）
  static readonly LANGUAGE: string = 'hapi_lang';   // 语言选择（'system'|'zh-CN'|'en'，默认 system 跟随系统）
  static readonly RECENT_SKILLS: string = 'hapi_recent_skills';   // $ 技能最近使用 map（JSON name→timestamp，上限 200）

  // per-session 输入草稿 key（hapi_draft_<sessionId>）：草稿随会话存，切换/重进恢复，发送即清。
  static draftKey(sessionId: string): string {
    return `hapi_draft_${sessionId}`;
  }
}

// AppStorage key（跨页面运行时状态）
export class AppStorageKeys {
  static readonly MAIN_WINDOW_STAGE: string = 'main_window_stage';   // 窗口级导航用（登录成功后再 loadContent）
}
