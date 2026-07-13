import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { getPreferencesService } from '../services/PreferencesService';
import { getConnectionService } from '../services/ConnectionService';
import { getSSEClient } from '../api/SSEClient';
import { getHubClient } from '../api/HubClient';
import { AppStorageKeys } from '../config/Keys';
import { ThemeService } from '../theme/ThemeService';
import { I18nService } from '../i18n/I18nService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

// 应用入口 Ability（Stage 模型）
// 启动流程：onWindowStageCreate → bootstrap 里 await 初始化（Preferences + 登录态），
// 再按登录态选首屏（对照 chatcube EntryAbility 登录态 loadContent 范式）。
// 注意：onWindowStageCreate 保持 void 签名以匹配 UIAbility 基类，
//       async 初始化放私有 bootstrap（内部 await 保证「先初始化、后 loadContent」的顺序）。
export default class EntryAbility extends UIAbility {
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
    // 语言须在 loadContent 前解析，首屏即用持久化/系统语言（避首帧中文→切英文闪烁，同主题）
    await I18nService.init(this.context);
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
    this.reportVisibility('visible');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
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
