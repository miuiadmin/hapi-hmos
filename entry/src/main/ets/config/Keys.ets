// 持久化 key（Preferences）集中管理（对照 chatcube PreferenceKeys 范式）
export class PreferenceKeys {
  static readonly HUB_URL: string = 'hapi_hub_url';
  static readonly API_TOKEN: string = 'hapi_api_token';
  static readonly NAMESPACE: string = 'hapi_namespace';
  static readonly JWT: string = 'hapi_jwt';           // 登录后换得的 JWT
  static readonly THEME_MODE: string = 'hapi_theme_mode';   // 主题模式 light/dark/system
  static readonly FONT_SCALE: string = 'hapi_font_scale';   // 全局字号缩放（'small'|'default'|'large'）
  static readonly ENTER_TO_SEND: string = 'hapi_enter_to_send';   // 回车发送消息（bool，默认关：Enter=换行）
  static readonly TERMINAL_TOOL_DISPLAY_MODE: string = 'hapi_terminal_tool_display_mode';   // 终端工具卡片显示模式（'compact'|'detailed'，默认 compact：仅 header）
  static readonly LANGUAGE: string = 'hapi_lang';   // 语言选择（'system'|'zh-CN'|'en'，默认 system 跟随系统）
  static readonly RECENT_SKILLS: string = 'hapi_recent_skills';   // $ 技能最近使用 map（JSON name→timestamp，上限 200）
  static readonly VOICE_LANG: string = 'hapi_voice_lang';   // 语音识别语言（locale 码，如 'zh-CN'；''=自动检测）
  static readonly VOICE_ID: string = 'hapi_voice_id';   // 语音声音（ElevenLabs voice id；''=Hub 默认 agent）
  static readonly TOOL_GROUP_BG: string = 'hapi_tool_group_bg';   // 工具组气泡配色偏好串（'default'|'preset:soft-x'|'custom:#hex'）
  static readonly USER_MESSAGE_BG: string = 'hapi_user_message_bg';   // 用户消息气泡配色偏好串
  static readonly SESSION_PREVIEW_LIMIT: string = 'hapi_session_preview_limit';   // 会话列表每组预览行数（整数，默认 8）
  static readonly TERMINAL_FONT_SIZE: string = 'hapi_terminal_font_size';   // 终端字号（离散 9/11/13/15/17，默认 13）
  static readonly SESSION_LIST_STATUS_MODE: string = 'hapi_session_list_status_mode';   // 会话列表状态模式（'standard'|'detailed'，默认 standard）
  static readonly HAPTICS_ENABLED: string = 'hapi_haptics_enabled';   // 触感反馈开关（'on'|'off'，默认 on：移动端发送/删除/长按/错误短震动）

  // per-session 输入草稿 key（hapi_draft_<sessionId>）：草稿随会话存，切换/重进恢复，发送即清。
  static draftKey(sessionId: string): string {
    return `hapi_draft_${sessionId}`;
  }
}

// AppStorage key（跨页面运行时状态）
export class AppStorageKeys {
  static readonly MAIN_WINDOW_STAGE: string = 'main_window_stage';   // 窗口级导航用（登录成功后再 loadContent）
}
