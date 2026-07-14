import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { getPreferencesService } from '../services/PreferencesService';
import { getConnectionService } from '../services/ConnectionService';
import { getGeneratedImageCache } from '../services/GeneratedImageCache';
import { getSSEClient } from '../api/SSEClient';
import { getHubClient } from '../api/HubClient';
import { AppStorageKeys } from '../config/Keys';
import { ThemeService, getThemeState } from '../theme/ThemeService';
import { I18nService } from '../i18n/I18nService';
import { ChatSurfaceColorsService } from '../services/ChatSurfaceColorsService';
import { TerminalToolDisplayService } from '../services/TerminalToolDisplayService';
import { VoiceSettingsService } from '../services/VoiceSettingsService';
import { SessionPreviewLimitService } from '../services/SessionPreviewLimitService';
import { TerminalFontSizeService } from '../services/TerminalFontSizeService';
import { SessionListStatusModeService } from '../services/SessionListStatusModeService';
import { SyncStateService } from '../services/SyncStateService';
import { HapticService } from '../services/HapticService';
import { DeviceNetworkService } from '../services/DeviceNetworkService';
import { shouldResync } from '../chat/SyncResync';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

// 应用入口 Ability（Stage 模型）
// 启动流程：onWindowStageCreate → bootstrap 里 await 初始化（Preferences + 登录态），
// 再按登录态选首屏（对照 chatcube EntryAbility 登录态 loadContent 范式）。
// 注意：onWindowStageCreate 保持 void 签名以匹配 UIAbility 基类，
//       async 初始化放私有 bootstrap（内部 await 保证「先初始化、后 loadContent」的顺序）。
export default class EntryAbility extends UIAbility {
  // 上次切到后台的时刻（ms）。onBackground 记录；onForeground 用 shouldResync 门控是否触发重同步。
  //   纯实例字段（UIAbility 非 V2 组件，不用 @Local）；Date.now() 由 Ability 调用方取，shouldResync 纯函数不取（可测）。
  private lastHideAt: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    // 存 windowStage，供登录成功后做窗口级跳转（LoginPage → Index）
    AppStorage.setOrCreate<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE, windowStage);
    // fire-and-forget：bootstrap 内部 await 保证初始化完成后才 loadContent
    this.bootstrap(windowStage);
  }

  private async bootstrap(windowStage: window.WindowStage): Promise<void> {
    // 初始化必须在 loadContent 之前完成，否则 isLoggedIn 读不到已存配置
    await getPreferencesService().initialize(this.context);
    await getConnectionService().initialize();
    // 主题须在 loadContent 前应用，避免首屏默认色→切换闪烁（chatcube 教训）
    await ThemeService.init(this.context);
    // 气泡配色须在 loadContent 前从持久化读回 + 按当前 isDark resolve（ToolCard/ChatPage 首帧即用，避默认色闪一下）
    await ChatSurfaceColorsService.init(getThemeState().isDark);
    // 语言须在 loadContent 前解析，首屏即用持久化/系统语言（避首帧中文→切英文闪烁，同主题）
    await I18nService.init(this.context);
    // 终端工具卡片显示模式须在 loadContent 前从持久化读回（ToolCard 首帧即用正确模式，避默认 compact 闪一下）
    await TerminalToolDisplayService.init();
    // 语音语言/声音须在 loadContent 前从持久化读回（VoicePage boot 即用，避默认声闪一下）
    await VoiceSettingsService.init();
    // 会话列表每组预览行数须在 loadContent 前从持久化读回（Index sessionRows 首帧即用，避默认 8 闪一下）
    await SessionPreviewLimitService.init();
    // 终端字号须在 loadContent 前从持久化读回（TerminalPage boot 即用，避默认 13 闪一下）
    await TerminalFontSizeService.init();
    // 会话列表状态模式须在 loadContent 前从持久化读回（Index SessionItem 首帧即用，避默认 standard 闪一下）
    await SessionListStatusModeService.init();
    // 触感反馈开关须在 loadContent 前从持久化读回（各交互 tap 即用正确 enabled，避默认开闪一下）
    await HapticService.init();
    // 设备网络探测须在 loadContent 前注册（hasDefaultNet 初始探测 + netAvailable/netUnavailable 监听），
    //   ConnectionBanner 首帧即用正确在线态（避乐观默认在线→离线闪烁）
    await DeviceNetworkService.init();
    // 生成图片磁盘缓存须在 loadContent 前初始化（扫目录重建索引），首屏命中即直读盘免 base64
    await getGeneratedImageCache().initialize(this.context);
    // 按登录态选首屏
    const pagePath: string = getConnectionService().isLoggedIn() ? 'pages/Index' : 'pages/LoginPage';
    windowStage.loadContent(pagePath, (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Loaded ' + pagePath);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  // 系统配置变化（含明暗模式）：仅「跟随系统」时同步 isDark；显式模式不受影响
  onConfigurationUpdate(newConfig: Configuration): void {
    const dark: boolean = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    ThemeService.applySystemColorMode(dark);
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    // 前台重同步门控（对照上游 SyncingBanner 离开 30s 触发）：离开 >30s 才 beginSync，
    //   避免短时切出（通知中心/分屏）误触；resyncSeq++ 触发页面 @Monitor reload。
    if (shouldResync(Date.now(), this.lastHideAt)) {
      SyncStateService.beginSync();
    }
    this.reportVisibility('visible');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
    // 记录切后台时刻，供下次 onForeground 的 shouldResync 门控
    this.lastHideAt = Date.now();
    this.reportVisibility('hidden');
  }

  // 上报应用可见性（对照 web useVisibilityReporter：visibility='visible'/'hidden'）。
  //   仅 SSE 已连（subscriptionId 非空）才发；未连/重连中静默跳过，避免无谓请求与坏订阅上报。
  private reportVisibility(visibility: string): void {
    const sid: string = getSSEClient().getSubscriptionId();
    if (sid === '') {
      return;
    }
    getHubClient().setVisibility(sid, visibility).catch((): void => {});
  }
}
