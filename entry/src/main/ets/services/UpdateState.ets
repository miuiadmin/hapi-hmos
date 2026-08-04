// OTA 自更新响应式状态 + UI 驱动控制器。
//
// 架构（镜像 services/DeviceNetworkService.ets 的「@ObservedV2 state + AppStorageV2.connect 共享单例」范式）：
//   - UpdateState{@Trace ...} 经 AppStorageV2 应用级共享；AboutPage 读 getUpdateState() 的 @Trace 字段
//     建立刷新依赖（弹窗阶段/进度/错误随下载回调即时重渲染）。
//   - OtaController：纯逻辑 SelfUpdateManager（重 IO/网络/校验）与 UI 状态之间的薄胶水层——
//     把 checkUpdate 结果 / 下载回调翻译成 UpdateState 突变 + 瞬时 toast。页面只调控制器方法，不直接碰 SelfUpdateManager。
//   - SelfUpdateManager 保持 context-free 于 UI（它已 init(ctx) 注入了 ability context）。

import { AppStorageV2 } from '@kit.ArkUI';
import {
  SelfUpdateManager,
  UpdateInfo,
  SelfUpdatePhase,
  CheckResult,
  DownloadCallbacks
} from './SelfUpdateManager';
import { t, kv } from '../i18n/Translate';
import { showToast } from '../utils/Toast';

/**
 * OTA 弹窗/进度响应式状态。AboutPage 经 getUpdateState() 读 @Trace 字段驱动 sheet 三态渲染。
 * 字段语义：
 *   sheetOpen    — 更新弹窗是否展开（checking 不开 sheet，只改行内 spinner）
 *   checking     — 手动检查进行中（行内 spinner + 禁用重复点）
 *   phase        — sheet 内阶段：prompting(展示日志) / downloading(下载中) / failed(失败重试)
 *   info         — 待安装更新（reason='update' 时设置；sheetOpen=true 时有效）
 *   percent/total/received — 下载进度（total<0 未知）
 *   downloading  — 下载进行中（区别于 phase：cancel 后 downloading=false 但 phase 待重置）
 *   error        — 失败原因（phase='failed' 时展示）
 *   installing   — 已触发拉起安装器（展示「下载完成，正在拉起安装器…」）
 */
@ObservedV2
export class UpdateState {
  @Trace sheetOpen: boolean = false;
  // 弹窗归属页（双挂载互斥）：'index'=主页自动检查触发 / 'about'=关于页手动触发 / ''=未开。
  //   sheetOpen=true 时仅 owner 对应页的 bindSheet 渲染，避免 Index（常驻 @Entry）与 AboutPage（pushed NavDestination）
  //   同时存活读同一 sheetOpen 而弹两张 sheet。
  @Trace sheetOwner: string = '';
  @Trace checking: boolean = false;
  @Trace hasUpdate: boolean = false;   // 静默检查发现新版（关于页「检查更新」行显示红点徽标；不自动弹窗，用户 tap 主动查看）
  @Trace phase: SelfUpdatePhase = 'prompting';
  @Trace info: UpdateInfo | null = null;
  @Trace percent: number = 0;
  @Trace total: number = -1;
  @Trace received: number = 0;
  @Trace downloading: boolean = false;
  @Trace error: string = '';
  @Trace installing: boolean = false;
}

let _state: UpdateState | null = null;

// 全局取值器：首次 AppStorageV2.connect 共享单例并缓存（对照 getDeviceNetworkState / getThemeState）
export function getUpdateState(): UpdateState {
  if (_state === null) {
    _state = AppStorageV2.connect(UpdateState, () => new UpdateState())!;
  }
  return _state;
}

/**
 * OTA UI 控制器：页面（AboutPage）←→ SelfUpdateManager 的胶水。
 * 所有方法静态、无状态（状态全在 getUpdateState() 共享单例 + SelfUpdateManager 单例）。
 */
export class OtaController {
  /** 当前包是否支持应用内自更新（共存版 com.berry.hapi88 = true；正式版 com.berry.hapi = false → 设置页隐藏检查更新行） */
  static isEligible(): boolean {
    return SelfUpdateManager.getInstance().isEligible();
  }

  /**
   * 检查更新。
   * @param force true 忽略节流（手动 / 冷启动用）
   * @param silent true 静默（启动 / 回前台自动检查）：发现新版只置 hasUpdate 徽标，不弹 sheet / 不 toast；
   *               false（手动点「检查更新」）：发现新版直接弹 sheet，其余结果 toast 提示。
   */
  static async checkForUpdates(force: boolean, silent: boolean): Promise<void> {
    const mgr: SelfUpdateManager = SelfUpdateManager.getInstance();
    const state: UpdateState = getUpdateState();
    if (state.checking) {
      return;  // 防重复点
    }
    state.checking = true;
    let result: CheckResult;
    try {
      result = await mgr.checkUpdate(force);
    } catch (_e) {
      state.checking = false;
      if (!silent) {
        showToast(t('settings.about.checkFailed'));
      }
      return;
    }
    state.checking = false;
    switch (result.reason) {
      case 'update': {
        const info: UpdateInfo | null = result.info ?? null;
        state.info = info;
        state.hasUpdate = info !== null;
        // 弹 sheet 判定：
        //   手动检查(!silent)：总是弹。
        //   自动检查(silent)：受独立「弹窗节流」(shouldAutoPrompt, 2h)——上次自动弹 <2h 则只亮红点徽标、不弹 sheet。
        //     节流与 checkUpdate 内的「检查节流」(last_check_ts)解耦：检查可更勤以刷新徽标，弹窗独立 2h 一次。
        const pop: boolean = !silent || (info !== null && mgr.shouldAutoPrompt());
        if (pop) {
          // 弹过就记时刻（手动/自动皆然），启动 2h 自动弹窗冷却：用户刚看过，2h 内不主动再弹
          mgr.markAutoPrompted();
          state.phase = 'prompting';
          state.error = '';
          state.percent = 0;
          state.received = 0;
          state.total = info !== null ? info.size : -1;
          // 归属页：自动检查(silent，EntryAbility 启动/回前台)→'index' 主页弹；手动(!silent，AboutPage 行)→'about'。
          //   双挂载按 sheetOwner 互斥，避免 Index+AboutPage 同时弹两张。
          state.sheetOwner = silent ? 'index' : 'about';
          state.sheetOpen = true;
        }
        break;
      }
      case 'latest':
        state.hasUpdate = false;
        if (!silent) {
          showToast(t('settings.about.upToDate'));
        }
        break;
      case 'notEligible':
        if (!silent) {
          showToast(t('settings.about.notEligible'));
        }
        break;
      case 'network':
        if (!silent) {
          showToast(t('settings.about.noNetwork'));
        }
        break;
      case 'throttled':
        // 自动模式节流：静默
        break;
      case 'error':
      default:
        if (!silent) {
          showToast(t('settings.about.checkFailed'));
        }
        break;
    }
  }

  /** 启动下载当前 info 指向的更新（下载回调实时更新进度 / 完成拉起安装器 / 失败切 failed 态）。 */
  static startDownload(): void {
    const mgr: SelfUpdateManager = SelfUpdateManager.getInstance();
    const state: UpdateState = getUpdateState();
    if (state.info === null) {
      return;
    }
    const info: UpdateInfo = state.info;
    state.phase = 'downloading';
    state.downloading = true;
    state.installing = false;
    state.percent = 0;
    state.received = 0;
    state.total = info.size;
    state.error = '';
    // 回调提取为具名 const（DownloadCallbacks 接口上下文类型化，避 untyped-obj-literal）
    const cbs: DownloadCallbacks = {
      onProgress: (received: number, total: number): void => {
        const s: UpdateState = getUpdateState();
        s.received = received;
        s.total = total;
        s.percent = total > 0 ? Math.min(100, Math.round(received / total * 100)) : 0;
      },
      onVerifyDone: (ok: boolean, appPath?: string, error?: string): void => {
        const s: UpdateState = getUpdateState();
        s.downloading = false;
        if (ok && appPath !== undefined) {
          OtaController.install(appPath);
        } else {
          s.phase = 'failed';
          s.error = error !== undefined && error.length > 0 ? error : t('ota.downloadFailed');
        }
      },
      onCancel: (): void => {
        const s: UpdateState = getUpdateState();
        s.downloading = false;
        s.sheetOpen = false;
        s.phase = 'prompting';  // 复位，下次检查可重进
        s.percent = 0;
      }
    };
    const taskId: string = mgr.download(info, cbs);
    if (taskId.length === 0) {
      // 已有下载进行或未初始化：回退 UI 态
      state.downloading = false;
      state.phase = 'prompting';
    }
  }

  /** 取消下载（静默；onCancel 回调清 UI 态）。 */
  static cancelDownload(): void {
    SelfUpdateManager.getInstance().cancelDownload();
    // onCancel 回调会清状态（downloading=false / sheetOpen=false）
  }

  /** 失败重试（重新启动下载链）。 */
  static retry(): void {
    OtaController.startDownload();
  }

  /** 跳过当前版本（ignoreVersion，该 versionCode 不再弹；新版会重新提示）。 */
  static skipVersion(): void {
    const mgr: SelfUpdateManager = SelfUpdateManager.getInstance();
    const state: UpdateState = getUpdateState();
    if (state.info !== null) {
      mgr.ignoreVersion(state.info.versionCode);
    }
    state.sheetOpen = false;
    state.info = null;
    state.hasUpdate = false;
  }

  /** 拉起系统安装器安装已下载的 .app（下载校验通过后自动触发）。 */
  static async install(appPath: string): Promise<void> {
    const mgr: SelfUpdateManager = SelfUpdateManager.getInstance();
    const state: UpdateState = getUpdateState();
    state.installing = true;
    let ok: boolean = false;
    try {
      ok = await mgr.launchInstaller(appPath);
    } catch (_e) {
      ok = false;
    }
    state.installing = false;
    if (!ok) {
      showToast(t('ota.installFailed'));
    } else {
      // 安装器已成功拉起：清除「有更新」徽标（新版安装后下次启动 versionCode 升高，自然不再提示）
      state.hasUpdate = false;
    }
    // 安装器已拉起（或失败已 toast）：关闭 sheet，让系统安装器接管
    state.sheetOpen = false;
  }

  /** 格式化包大小（字节 → 「12.3 MB」），sheet 横幅展示用。 */
  static formatSize(bytes: number): string {
    const mb: number = bytes / (1024 * 1024);
    return `${mb.toFixed(1)} MB`;
  }

  /** 构造「下载中 X%」文案（供 sheet 标题/进度文本；带参插值）。 */
  static downloadingText(percent: number): string {
    return t('ota.downloading', kv('percent', percent));
  }
}
