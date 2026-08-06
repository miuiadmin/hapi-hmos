import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
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
import { PinInProgressService } from '../services/PinInProgressService';
import { getSessionSeenService } from '../services/SessionAttention';
import { TerminalFontSizeService } from '../services/TerminalFontSizeService';
import { SyncStateService } from '../services/SyncStateService';
import { HapticService } from '../services/HapticService';
import { DeviceNetworkService } from '../services/DeviceNetworkService';
import { getJwtRefreshScheduler } from '../services/JwtRefreshScheduler';
import { SelfUpdateManager } from '../services/SelfUpdateManager';
import { OtaController } from '../services/UpdateState';
import { getLayoutState, setMainWindow, applyStatusBarColor } from '../state/LayoutState';
import { decodeJwtExpMs } from '../utils/JwtUtils';
import { shouldResync } from '../chat/SyncResync';
import { getDeepLinkImporter, ParsedConnect, ImportResult } from '../services/DeepLinkImporter';
import { showToast } from '../utils/Toast';
import { t } from '../i18n/I18nService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

// px→vp 转换（照搬 berry3 EntryAbility:38）。全局 px2vp 已废弃（非 UIContext 感知，多屏/DPI 不准），
//   改用 display densityPixels 手算。失败回退原 px 值。
function pxToVp(px: number): number {
  try {
    return px / display.getDefaultDisplaySync().densityPixels;
  } catch (_e) {
    return px;
  }
}

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
    // 冷启动经 deep link（hapi://connect?…）拉起：暂存 URI，待首屏消费（LoginPage.aboutToAppear 或 bootstrap 回调）
    const uri: string = want.uri ?? '';
    if (uri !== '' && getDeepLinkImporter().isConnectLink(uri)) {
      getDeepLinkImporter().setPending(uri);
    }
  }

  // 暖启动经 deep link 拉起（App 已在运行）：直接处理导入
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    const uri: string = want.uri ?? '';
    if (uri !== '' && getDeepLinkImporter().isConnectLink(uri)) {
      this.applyImport(uri);
    }
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
    // JWT 主动预刷（对照上游 web useAuth 的 scheduler + focus/visibility 续期）：
    //   注入 onFire 回调 → arm（按 jwt 的 exp 排一次预刷定时器）。
    //   onFire 经 refreshAndArm 调 getHubClient().refreshJwt()（Scheduler 不 import HubClient，避 import 环）。
    //   未登录时 jwt='' → arm 内部 cancel（无操作）；登录后 LoginPage.doLogin 再 arm 一次。
    const jwtSched = getJwtRefreshScheduler();
    jwtSched.onFire = (): void => { this.refreshAndArm(); };
    jwtSched.arm();
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
    // 置顶进行中会话开关须在 loadContent 前从持久化读回（Index sessionRows 首帧即用正确分区，避默认关闪一下）
    await PinInProgressService.init();
    // 会话「已看」时间戳须在 loadContent 前从持久化读回（Index 列表首帧即用正确未读态，否则重启后全会话误显未读）
    await getSessionSeenService().hydrate();
    // 终端字号须在 loadContent 前从持久化读回（TerminalPage boot 即用，避默认 13 闪一下）
    await TerminalFontSizeService.init();
    // 触感反馈开关须在 loadContent 前从持久化读回（各交互 tap 即用正确 enabled，避默认开闪一下）
    await HapticService.init();
    // 设备网络探测须在 loadContent 前注册（hasDefaultNet 初始探测 + netAvailable/netUnavailable 监听），
    //   ConnectionBanner 首帧即用正确在线态（避乐观默认在线→离线闪烁）
    await DeviceNetworkService.init();
    // 生成图片磁盘缓存须在 loadContent 前初始化（扫目录重建索引），首屏命中即直读盘免 base64
    await getGeneratedImageCache().initialize(this.context);
    // OTA 自更新：注入 ability context + 初始化独立 prefs（共存版守卫 / 检查 / 下载 / 安装均依赖；幂等）
    SelfUpdateManager.getInstance().init(this.context);
    // 窗口全屏沉浸 + 安全区高度采集（ChatPage HDS 沉浸光感前提）：
    //   setWindowLayoutFullScreen 让窗口布局延伸到状态栏/导航条区域（官方：此后 NavDestination 默认
    //   expandSafeArea 仍把内部内容避让在安全区内 → 其他页面不回归；仅显式 ignoreLayoutSafeArea 的
    //   ChatPage 沉浸到状态栏）。采集 topAvoidHeight 供 ChatPage List 首项占位。照搬 berry EntryAbility:340-370。
    //   放 ThemeService.init 之后（用 isDark 设状态栏图标色）。
    try {
      const win = await windowStage.getMainWindow();
      setMainWindow(win);
      win.setWindowLayoutFullScreen(true);
      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const layout = getLayoutState();
      layout.topAvoidHeight = pxToVp(sysArea.topRect.height);
      layout.bottomAvoidHeight = pxToVp(navArea.bottomRect.height);
      // 全屏后状态栏图标色不再自动随 setColorMode → 显式设初始值（明暗切换由 ThemeService 重设）
      applyStatusBarColor(getThemeState().isDark);
      // 折叠屏展开/旋转 → 安全区高度变化，同步更新（ChatPage 占位随之刷新）。
      //   回调参类型由 on('avoidAreaChange',…) 签名推断（无显式导出名 AvoidAreaInfo，照搬 berry EntryAbility:373 不标注）
      win.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          const h = pxToVp(data.area.topRect.height);
          if (h > 0 && layout.topAvoidHeight !== h) {
            layout.topAvoidHeight = h;
          }
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          const h = pxToVp(data.area.bottomRect.height);
          if (layout.bottomAvoidHeight !== h) {
            layout.bottomAvoidHeight = h;
          }
        }
      });
    } catch (e) {
      // 窗口配置失败不阻塞首屏（非沉浸态降级可用）
    }
    // 按登录态选首屏
    const pagePath: string = getConnectionService().isLoggedIn() ? 'pages/Index' : 'pages/LoginPage';
    windowStage.loadContent(pagePath, (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'Loaded ' + pagePath);
      // 冷启动经 deep link 拉起且首屏未消费（如已登录重导入、或 LoginPage 尚未消费的竞态兜底）：在此处理
      const pending: string = getDeepLinkImporter().consumePending();
      if (pending !== '') {
        this.applyImport(pending);
      }
      // 冷启动静默检查更新（force=true 不节流；silent 不弹窗，发现新版只置「检查更新」行徽标；
      //   fire-and-forget 不阻塞首屏；仅共存版 com.berry.hapi88 会真正发请求）
      OtaController.checkForUpdates(true, true);
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
    // JWT 回前台续期（对照上游 web focus/visibility minTtlMs:60_000）：距过期 <60s 主动刷新，
    //   避免回前台后首个请求撞过期 401。后台期间可能错过定时器，故回前台补检一次。
    const jwt: string = getConnectionService().jwt;
    const expMs: number = decodeJwtExpMs(jwt);
    if (jwt !== '' && expMs > 0 && expMs - Date.now() < 60_000) {
      this.refreshAndArm();
    }
    // 回前台静默检查更新（force=false 走 2h 节流；silent 不弹窗；仅共存版会真正发请求）
    OtaController.checkForUpdates(false, true);
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

  // JWT 预刷定时器到期回调（由 JwtRefreshScheduler.onFire 触发）：
  //   刷新成功 → arm 下一轮预刷；刷新失败但 token 尚未过期 → 15s 后重试；已过期则停（下次请求 401 被动刷新）。
  //   refreshJwt() 单飞：与 SSEClient 的 401 被动刷新 / onForeground 续期并发调用共享同一次在途刷新。
  private async refreshAndArm(): Promise<void> {
    try {
      const ok = await getHubClient().refreshJwt();
      if (ok) {
        getJwtRefreshScheduler().arm();
      } else {
        getJwtRefreshScheduler().retryIfStillValid();
      }
    } catch (e) {
      getJwtRefreshScheduler().retryIfStillValid();
    }
  }

  // deep link 导入处理：解析 → apply（验证 token + 持久化）→ 成功切到主页；失败 toast，未登录落登录页。
  //   冷启动重导入（bootstrap 回调兜底）与暖启动（onNewWant）共用此入口。
  private async applyImport(uri: string): Promise<void> {
    const parsed: ParsedConnect | null = getDeepLinkImporter().parse(uri);
    if (parsed === null) {
      showToast(t('deeplink.invalid'));
      return;
    }
    showToast(t('deeplink.importing'));
    const r: ImportResult = await getDeepLinkImporter().apply(parsed.server, parsed.token);
    if (r.success) {
      showToast(t('deeplink.imported'));
      const stage = AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE);
      if (stage !== undefined) {
        stage.loadContent('pages/Index');
      }
    } else {
      showToast(r.errorMessage);
      // 导入失败且当前未登录 → 落到登录页让用户手动重试
      if (!getConnectionService().isLoggedIn()) {
        const stage = AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE);
        if (stage !== undefined) {
          stage.loadContent('pages/LoginPage');
        }
      }
    }
  }
}
