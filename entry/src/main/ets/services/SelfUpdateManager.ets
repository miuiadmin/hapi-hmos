/**
 * SelfUpdateManager — Hapi 共存版在线自更新（OTA）
 *
 * 职责：
 * - 共存版守卫（bundleName 匹配 com.berry.hapi\d+，正式版 com.berry.hapi 无后缀永不触发）
 * - 启动静默检查（2h 节流）/ 设置页手动检查：GET 服务器 update.json → versionCode 对比 → 忽略过滤
 * - 流式下载 .app 安装包（http.requestInStream + cacheDir 落盘）+ 进度通知（downloadTemplate，三方禁实况窗）
 * - MD5（@ohos.file.hash）+ size 双校验
 * - 拉起系统/三方安装器安装（install / viewData want，靠 .app 扩展名路由；三方无 INSTALL_BUNDLE 权限）
 *
 * 移植自 berry3 `utils/SelfUpdateManager.ets`，按差异表改：
 *   - 守卫 regex: com.berry.browser\d+ → com.berry.hapi\d+
 *   - SELF_UPDATE_HOSTS: 仅 berry.flyme.chat（保留 readonly array 结构，便于将来加备机）
 *   - 路径: /berry/* → /hapi/*
 *   - 孤儿前缀: berry_update_ → hapi_update_
 *   - prefs 库: 'self_update' → 'hapi_self_update'（独立库，与主 prefs 隔离）
 *   - 版本比较: isNewerVersion(versionName) → versionCode 数字比较
 *   - 去除 ProxyResolver（浏览器特有，hapi 直连）
 *   - 通知文案: 硬编码 → Translate.t（纯逻辑侧 i18n）
 *
 * 架构约束：
 * - 纯逻辑、无 UI 状态（归属 services/）；页面经 UpdateState + 回调驱动
 * - prefs 独立库 'hapi_self_update'，键 last_check_ts / ignored_version / working_host
 *
 * 配置托管：服务器静态 update.json（下载服务器/scripts/dist.sh 生成，Caddy 静态托管，服务端零代码改动）。
 *   update.json 契约见 下载服务器/OTA接入文档.md §3（versionCode NUMBER 单调递增，客户端用它判更新）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http, connection } from '@kit.NetworkKit';
import { fileIo, fileUri, hash } from '@kit.CoreFileKit';
import { common, Want, wantAgent, wantConstant, bundleManager } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { t } from '../i18n/Translate';

const LOG_DOMAIN: number = 0x0000;
const TAG: string = 'SelfUpdate';

/** http 流式下载进度回调参数（receiveSize/totalSize，与 @ohos.net.http DataReceiveProgressInfo 同构） */
interface StreamProgressInfo {
  receiveSize: number;
  totalSize: number;
}

/**
 * 自更新可信主机【列表】（多 host 容错）。所有 host 同源同后端（Caddy 静态站），顺序=优先级。
 *
 * 主机级锚定：parseUpdateInfo 校验 update.json 的 url 必须 startsWith 列表内【任一】host + '/'，防篡改指向恶意域。
 *   列表全编译进 hap 二进制=新锚；攻击者即便能改 update.json 也只能指向列表内已知可信域，且下载内容仍 md5 校验。
 *
 * ⚠️ berry.flyme.chat 永久在列且必须排首位——对外域名永不变（换机器/IP/端口只改服务端 CF+Caddy）。
 *    列表【只能增不能删】：删=孤儿旧版 OTA 全死。
 *
 * 容错语义：fetchUpdateJson(取 update.json) / download(下 .app) 均【按列表顺序逐 host 试】，单个 host 网络层失败
 *   (超时/连接失败/HTTP!=200/size 截断)自动换下一个；md5 不符=致命(所有 host 同源同文件,试也没用)不重试。
 */
const SELF_UPDATE_HOSTS: readonly string[] = [
  'https://berry.flyme.chat:8443',     // 主（永久锚·首位）
  // 'https://<第二独立域>:8443',       // 备(预留)：第二套独立域名+后端就绪后填入=真根治(防 flyme.chat 整域 / CF 故障)
];
/** 静态 OTA 清单路径（纯静态下载站 Caddy file_server 托管 /opt/dist/hapi）。
 *  全新接入直接取规范路径 /hapi/update.json（无需兼容桥）。 */
const UPDATE_JSON_PATH: string = '/hapi/update.json';
/** 静态最新包路径（latest.app 符号链接→当前版本 .app，版本无关稳定 URL；实际下载优先用 update.json 的 url 字段，此为兜底）。 */
const OTA_LATEST_PATH: string = '/hapi/latest.app';
/** prefs 独立库名（与主 prefs 隔离，仿 berry 'self_update' 先例） */
const PREFS_NAME: string = 'hapi_self_update';
const K_LAST_CHECK_TS: string = 'last_check_ts';
const K_IGNORED_VERSION: string = 'ignored_version';
/** 上次成功连通的可信主机（prefs 持久化，下次 fetch/download 优先用它，减少首跳失败的重试） */
const K_WORKING_HOST: string = 'working_host';
/** 上次「自动弹更新 sheet」时刻（弹窗节流用，与 K_LAST_CHECK_TS 检查节流解耦；AUTO_PROMPT_THROTTLE_MS 据此判断） */
const K_LAST_PROMPTED_TS: string = 'last_prompted_ts';
// 自动检查节流（仅热恢复路径 force=false 用）：后台切回前台 ≥2h 才查。
// 冷启动路径 force=true 不节流（每次启动都查）。last_check_ts 成功 GET 后写入，节流据此判断。
const THROTTLE_MS: number = 2 * 60 * 60 * 1000;  // 2 小时
// 自动弹窗节流（仅 silent 自动检查路径用）：上次「自动弹更新 sheet」≥ 此间隔才再自动弹。
//   与 THROTTLE_MS【解耦】——检查(THROTTLE_MS)可更勤以刷新徽标，弹窗独立限频，避免每次进 app 都弹。
//   仅对 silent=true 自动检查生效；手动点「检查更新」(silent=false)不受此限、总是弹。
const AUTO_PROMPT_THROTTLE_MS: number = 2 * 60 * 60 * 1000;  // 2 小时
/** 自更新进度通知固定 id（单任务无需分配） */
const NOTIF_ID: number = 0x7001;
/** 进度通知节流间隔（避免每网络块一次 IPC 风暴） */
const NOTIF_THROTTLE_MS: number = 2000;

/** 共存版 bundleName 守卫正则：com.berry.hapi + 数字后缀（88 包 = com.berry.hapi88）。
 *  正式包 com.berry.hapi 无后缀 → 不匹配 → 永不触发。hapi 代码库正则字面量先例：ChatSurfaceColors/GitParsers/CliOutput。 */
const ELIGIBLE_BUNDLE_REGEX: RegExp = /^com\.berry\.hapi\d+$/;

/** 服务器 update.json 数据模型（契约见 下载服务器/OTA接入文档.md §3） */
export interface UpdateInfo {
  versionName: string;
  versionCode: number;
  bundleName: string;   // 升级目标包名（服务端 update.json 带），checkUpdate 校验「=== 当前包 bundleName」防装错包
  url: string;
  md5: string;
  size: number;
  changelog: string[];
}

/** 检查结果分类 */
export type CheckReason = 'update' | 'latest' | 'notEligible' | 'throttled' | 'network' | 'error';

/**
 * 自更新弹窗阶段（联合字面量类型，编译期防拼写错误）。
 * prompting=展示更新日志 / downloading=下载中 / failed=校验失败。
 */
export type SelfUpdatePhase = 'prompting' | 'downloading' | 'failed';

/** checkUpdate 返回值：reason 决定页面 UI（自动模式仅 act on 'update'） */
export interface CheckResult {
  reason: CheckReason;
  info?: UpdateInfo;
}

/** 下载进度回调参数（received/total，total<0 表示未知） */
export interface DownloadCallbacks {
  onProgress: (received: number, total: number) => void;
  /** 校验完成：ok=true 时 appPath 有效；ok=false 时 error 给出原因 */
  onVerifyDone: (ok: boolean, appPath?: string, error?: string) => void;
  /** 用户取消下载：页面只关 sheet 不切 failed 态；缺省回退 onVerifyDone(false) */
  onCancel?: () => void;
}

/** 单次下载尝试结果分类（多 host 容错链 runDownloadChain 用） */
type DownloadAttemptKind = 'ok' | 'retriable' | 'fatal' | 'canceled';
interface DownloadAttemptResult {
  kind: DownloadAttemptKind;
  /** retriable/fatal 时给原因（hilog + 失败通知用） */
  error?: string;
}

/**
 * SelfUpdateManager 单例。
 * 使用前须 init(context) 注入 UIAbilityContext（prefs/cacheDir/bundleName/startAbility 依赖）。
 */
export class SelfUpdateManager {
  private static instance: SelfUpdateManager | null = null;
  private ctx: common.UIAbilityContext | null = null;
  private prefs: preferences.Preferences | null = null;
  /** 当前下载的 http 请求句柄（供 cancelDownload 调 destroy） */
  private currentRequest: http.HttpRequest | null = null;
  /** 当前下载任务 id（非空表示下载中） */
  private currentTaskId: string = '';
  /** 当前下载落盘路径（cancel 时删半成品） */
  private currentAppPath: string = '';
  /** 已校验待安装 app 路径（cleanOrphanApps 跳过，防误删刚校验未点安装的 app） */
  private verifiedAppPath: string = '';
  /** 当前下载回调（cancel 时主动通知页面） */
  private currentCallbacks: DownloadCallbacks | null = null;
  /** downloadTemplate 是否支持（首次 publish 失败后降级纯文本，缓存避免双重 publish） */
  private templateSupported: boolean = true;
  /** 后台长时任务是否已申请（DATA_TRANSFER，防切后台下载中断） */
  private isBackgroundRunning: boolean = false;
  /** 后台保活启动 promise（stop await 它等启动落地，消除 start/stop 异步竞态） */
  private bgPromise: Promise<void> | null = null;
  /** 上次进度通知 publish 时间戳（NOTIF_THROTTLE_MS 节流，避免 IPC 风暴） */
  private lastNotifTs: number = 0;
  /** checkUpdate 并发保护：fetchUpdateJson 进行中时，新的 checkUpdate 直接返回（防热恢复连续 onForeground 并发 GET） */
  private isChecking: boolean = false;
  /** 上次成功连通的可信主机（init 从 prefs 读，fetch/download 成功后更新；download 优先从它起跳减少首跳失败） */
  private workingHost: string = '';

  private constructor() {}

  static getInstance(): SelfUpdateManager {
    if (SelfUpdateManager.instance === null) {
      SelfUpdateManager.instance = new SelfUpdateManager();
    }
    return SelfUpdateManager.instance;
  }

  /** 注入上下文 + 初始化 prefs（幂等，EntryAbility 启动时调一次） */
  init(ctx: common.UIAbilityContext): void {
    this.ctx = ctx;
    if (this.prefs === null) {
      try {
        this.prefs = preferences.getPreferencesSync(ctx, { name: PREFS_NAME });
      } catch (e) {
        hilog.error(LOG_DOMAIN, TAG, 'init prefs 失败: %{public}s', String(e));
      }
    }
    // 多 host 容错：读上次成功连通的 host，download 优先从它起跳（减少首跳 30s 超时的无谓重试）
    if (this.prefs !== null) {
      try {
        const saved: string = this.prefs.getSync(K_WORKING_HOST, '') as string;
        this.workingHost = SelfUpdateManager.isTrustedHost(saved) ? saved : '';
      } catch (_e) {
        this.workingHost = '';
      }
    }
    // 清理上次下载未安装就退出 App 残留的孤儿 hap（cacheDir 系统可清，但显式回收更及时）
    this.cleanOrphanApps();
  }

  /**
   * 清理 cacheDir 下 hapi_update_*.app 孤儿文件（兼容历史 .hap 残留一并清）。
   * 场景：上次下载完成未点安装就退出 / 下载中断，重启后残留占空间。
   * 仅在无活跃下载时清理（currentTaskId 空）；init 早于用户点更新，不冲突。
   * 跨会话页面状态已丢，孤儿理应清（用户重新触发下载即可）。
   */
  private cleanOrphanApps(): void {
    if (this.ctx === null || this.currentTaskId.length > 0) {
      return;  // 无上下文或有活跃下载，不动
    }
    try {
      const entries: string[] = fileIo.listFileSync(this.ctx.cacheDir);
      for (const name of entries) {
        if (name.startsWith('hapi_update_') && (name.endsWith('.app') || name.endsWith('.hap'))) {
          const fullPath: string = `${this.ctx.cacheDir}/${name}`;
          // 跳过已校验待安装的 hap（用户刚下载完未点安装，切页回来 init 不应误删）
          if (this.verifiedAppPath.length > 0 && fullPath === this.verifiedAppPath) {
            continue;
          }
          try {
            fileIo.unlinkSync(fullPath);
            hilog.info(LOG_DOMAIN, TAG, '清理孤儿 app/hap: %{public}s', name);
          } catch (_e) {
            // 单个文件删除失败不阻塞其余清理
          }
        }
      }
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, '清理孤儿 hap 失败: %{public}s', String(e));
    }
  }

  private ensureReady(): boolean {
    return this.ctx !== null && this.prefs !== null;
  }

  /**
   * 共存版守卫：bundleName 匹配 com.berry.hapi\d+（有数字后缀）。
   * 正式包 com.berry.hapi 无后缀 → false → 永不触发自更新。
   * isDebugBuild() 区分不了正式版/共存版，唯一可靠信号是 bundleName。
   */
  isEligible(ctx?: common.UIAbilityContext): boolean {
    const c: common.UIAbilityContext | null = ctx ?? this.ctx;
    if (c === null) {
      return false;
    }
    try {
      return ELIGIBLE_BUNDLE_REGEX.test(c.abilityInfo.bundleName);
    } catch (_e) {
      return false;
    }
  }

  // ========== 检查更新 ==========

  /**
   * 检查更新。
   * @param force true 忽略节流（手动触发）
   * @returns CheckResult；reason='update' 时 info 有效
   *
   * 时序：守卫→节流→网络→GET update.json→包名校验→versionCode 对比→忽略过滤。
   * last_check_ts 仅在成功 GET 后更新（网络失败不更新，下次启动可重试）。
   */
  async checkUpdate(force: boolean): Promise<CheckResult> {
    if (!this.ensureReady() || this.prefs === null) {
      return { reason: 'error' };
    }
    // ① 共存版守卫
    if (!this.isEligible()) {
      return { reason: 'notEligible' };
    }
    // ② 节流（仅自动模式）
    if (!force) {
      const lastTs: number = this.prefs.getSync(K_LAST_CHECK_TS, 0) as number;
      if (lastTs > 0 && (Date.now() - lastTs) < THROTTLE_MS) {
        return { reason: 'throttled' };
      }
    }
    // ③ 网络预检
    if (!this.isNetworkAvailable()) {
      return { reason: 'network' };
    }
    // ④ GET update.json + 解析
    // 并发保护：GET 进行中时新的 checkUpdate 直接返回（防热恢复连续 onForeground 在上次 GET 完成前再发请求；
    //   ArkTS 单线程同步无竞态，但 await fetchUpdateJson 让出执行权后可被重入）
    if (this.isChecking) {
      return { reason: 'throttled' };
    }
    this.isChecking = true;
    let info: UpdateInfo | null = null;
    try {
      info = await this.fetchUpdateJson();
    } finally {
      this.isChecking = false;
    }
    if (info === null) {
      return { reason: 'error' };
    }
    // ④.5 包名校验：服务端推的 bundleName 必须 === 当前包 bundleName。
    //   isEligible(①) 只判「当前包有数字后缀」，这里判「下载包 specifically 是我这个包」——
    //   防 88 包收到非 88 包更新（服务端推错 / 归档混入 / 将来多后缀并存）。不匹配即拒绝，且不计入节流。
    const myBundle: string = this.ctx?.abilityInfo.bundleName ?? '';
    if (info.bundleName !== myBundle) {
      hilog.warn(LOG_DOMAIN, TAG, 'OTA 包名不匹配，拒绝更新: 服务端=%{public}s 当前=%{public}s',
        info.bundleName, myBundle);
      return { reason: 'notEligible' };
    }
    // 成功 GET，更新节流时间戳（网络失败不更新，保证下次可重试）
    try {
      this.prefs?.putSync(K_LAST_CHECK_TS, Date.now());
      this.prefs?.flush();
    } catch (_e) {
      // 节流时间戳写失败不影响本次判断
    }
    // ⑤ versionCode 对比（安全F2：读不到本地版本返回 error 而非 fallback 误更新）。
    //   versionCode 是 NUMBER 单调递增整数，客户端用它判更新（OTA接入文档 §3/§5），不用 versionName。
    const localCode: number | null = await this.getLocalVersionCode();
    if (localCode === null) {
      return { reason: 'error' };
    }
    if (info.versionCode <= localCode) {
      return { reason: 'latest' };
    }
    // ⑥ 忽略过滤：用户忽略过该版本Code则视为「无更新」（新版本Code不匹配会重新提示）
    const ignored: number = this.prefs.getSync(K_IGNORED_VERSION, 0) as number;
    if (ignored > 0 && ignored === info.versionCode) {
      return { reason: 'latest' };
    }
    hilog.info(LOG_DOMAIN, TAG, '发现新版本: %{public}s(versionCode=%{public}d → %{public}d)',
      info.versionName, localCode, info.versionCode);
    return { reason: 'update', info };
  }

  /**
   * 安全F2：取本地 versionCode，失败返回 null（不 fallback）。
   * OTA 读不到本地版本应返回 error 而非误触发更新，故独立实现不 fallback。
   * getBundleInfoForSelf 查自身包信息免权限（SettingsPage/AboutPage 已在用 getBundleInfoForSelfSync）。
   */
  private async getLocalVersionCode(): Promise<number | null> {
    try {
      const info = await bundleManager.getBundleInfoForSelf(0x00000001);
      return info.versionCode;
    } catch (e) {
      hilog.error(LOG_DOMAIN, TAG, 'getLocalVersionCode 失败: %{public}s', String(e));
      return null;
    }
  }

  /**
   * GET update.json 并解析为 UpdateInfo（多 host 容错：按 SELF_UPDATE_HOSTS 顺序逐 host 试，
   * 首个 200 + 解析成功即返回并记住该 host；全失败返回 null）。
   */
  private async fetchUpdateJson(): Promise<UpdateInfo | null> {
    for (const host of SELF_UPDATE_HOSTS) {
      const info = await this.tryFetchJsonAt(host + UPDATE_JSON_PATH);
      if (info !== null) {
        this.rememberWorkingHost(host);  // 记住这次通的 host，download 优先用它
        return info;
      }
    }
    hilog.warn(LOG_DOMAIN, TAG, '所有可信主机取 update.json 均失败');
    return null;
  }

  /** 单 host 取 update.json（成功返回 UpdateInfo，失败/异常返回 null；httpRequest 必 destroy） */
  private async tryFetchJsonAt(url: string): Promise<UpdateInfo | null> {
    let httpRequest: http.HttpRequest | null = null;
    try {
      httpRequest = http.createHttp();
      // header 用「空{} + 索引赋值」构造（ArkTS 严格模式唯一 Record 构造法）
      const header: Record<string, string> = {};
      header['Cache-Control'] = 'no-cache';   // 版本检测对时效敏感，防中间层/CDN 缓存旧 update.json
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: 15000,
        readTimeout: 30000
      };
      const response = await httpRequest.request(url, options);
      if (response.responseCode !== 200 || !response.result) {
        hilog.warn(LOG_DOMAIN, TAG, 'GET update.json 失败(%{public}s): HTTP %{public}d', url, response.responseCode);
        return null;
      }
      const raw: string = typeof response.result === 'string'
        ? response.result
        : String(response.result);
      return SelfUpdateManager.parseUpdateInfo(raw);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, 'GET update.json 异常(%{public}s): %{public}s', url, String(e));
      return null;
    } finally {
      if (httpRequest) {
        httpRequest.destroy();
      }
    }
  }

  /** 解析 + 字段校验 update.json（ArkTS 安全：cast 后逐字段 typeof 校验） */
  private static parseUpdateInfo(raw: string): UpdateInfo | null {
    let parsed: UpdateInfo;
    try {
      parsed = JSON.parse(raw) as UpdateInfo;
    } catch (_e) {
      hilog.warn(LOG_DOMAIN, TAG, 'update.json 解析失败');
      return null;
    }
    if (typeof parsed.versionName !== 'string' || parsed.versionName.length === 0) return null;
    if (typeof parsed.versionCode !== 'number' || parsed.versionCode <= 0) return null;
    // 安全F1（多 host）：下载 url 必须锚定可信主机【列表】内任一 host（防 update.json 的 url 字段被篡改指向恶意域）。
    //   列表全编译进 hap 二进制=新锚；攻击者即便能改 update.json 也只能指向列表内已知可信域，且下载内容仍 md5 校验。
    if (typeof parsed.url !== 'string' || !SelfUpdateManager.isUrlTrusted(parsed.url)) return null;
    // bundleName 校验：服务端必须带升级目标包名，客户端据此判「是否适合当前包」（防 88 包装非 88 包）
    if (typeof parsed.bundleName !== 'string' || parsed.bundleName.length === 0) return null;
    if (typeof parsed.md5 !== 'string' || parsed.md5.length === 0) return null;
    if (typeof parsed.size !== 'number' || parsed.size <= 0) return null;
    if (!Array.isArray(parsed.changelog)) return null;
    // 构造干净对象，归一化类型（过滤 null/非字符串脏数据，避免显示成 "null"）
    const changelog: string[] = (parsed.changelog as string[])
      .filter((s: Object) => s !== null && s !== undefined)
      .map((s: Object) => String(s));
    const info: UpdateInfo = {
      versionName: parsed.versionName,
      versionCode: parsed.versionCode,
      bundleName: parsed.bundleName,
      url: parsed.url,
      md5: parsed.md5,
      size: parsed.size,
      changelog: changelog
    };
    return info;
  }

  /** 安全F1 辅助：url 是否锚定可信主机列表内任一 host（含 '/' 边界，防 https://a.com 冒充 https://a.com.evil） */
  private static isUrlTrusted(url: string): boolean {
    for (const h of SELF_UPDATE_HOSTS) {
      if (url.startsWith(h + '/')) {
        return true;
      }
    }
    return false;
  }

  /** host 是否为可信主机列表内成员（prefs 读出的 workingHost 防御性校验用） */
  private static isTrustedHost(host: string): boolean {
    for (const h of SELF_UPDATE_HOSTS) {
      if (h === host) {
        return true;
      }
    }
    return false;
  }

  /**
   * 从已校验受信的 url 提取 path 部分（去 host），供 download 跨 host 重建下载 URL（host + 同 path）。
   * 调用前 parseUpdateInfo 已保证 url 锚定列表内某 host（含 '/'），故此处理论必命中；异常兜底返回 OTA_LATEST_PATH。
   */
  private static urlToTrustedPath(url: string): string {
    for (const h of SELF_UPDATE_HOSTS) {
      if (url.startsWith(h + '/')) {
        return url.substring(h.length);  // 含前导 '/'，形如 '/hapi/latest.app'
      }
    }
    return OTA_LATEST_PATH;
  }

  /** 记住成功连通的 host（下次 fetch/download 优先用）+ 持久化到 prefs */
  private rememberWorkingHost(host: string): void {
    this.workingHost = host;
    if (this.prefs !== null) {
      try {
        this.prefs.putSync(K_WORKING_HOST, host);
        this.prefs.flush();
      } catch (_e) {
        // 持久化失败不影响本次（内存 workingHost 仍生效）
      }
    }
  }

  /** 排序可信主机：preferred(上次通的)排首位，其余按 SELF_UPDATE_HOSTS 原序补齐（去重） */
  private orderHosts(preferred: string): string[] {
    const list: string[] = [];
    if (preferred.length > 0 && SelfUpdateManager.isTrustedHost(preferred)) {
      list.push(preferred);
    }
    for (const h of SELF_UPDATE_HOSTS) {
      if (h !== preferred) {
        list.push(h);
      }
    }
    return list;
  }

  // ========== 下载 + 校验 ==========

  /**
   * 流式下载 .app 安装包 + MD5/size 校验（多 host 容错：网络层失败自动换下一个可信 host 重流）。
   * @param info checkUpdate 返回的 UpdateInfo
   * @param callbacks onProgress(received,total) / onVerifyDone(ok,appPath?,error?)
   * @returns taskId（非空；空串表示已在下载中或未初始化）
   *
   * 结构：download() 仅做 setup + 启动 runDownloadChain；runDownloadChain 逐 host 跑 streamOnce，
   *   retriable 换下一个 / fatal(md5不符)·ok 终结；streamOnce=单 host 流式尝试，resolve 结果不调 finishDownload。
   * cancel 由 cancelDownload 直接 finishDownload 清 currentTaskId，编排链每次 await 后查 taskId 守卫自然停。
   */
  download(info: UpdateInfo, callbacks: DownloadCallbacks): string {
    if (!this.ensureReady() || this.ctx === null) {
      return '';
    }
    if (this.currentTaskId.length > 0) {
      hilog.warn(LOG_DOMAIN, TAG, '已有下载在进行，拒绝重复触发');
      return '';
    }
    const appPath: string = `${this.ctx.cacheDir}/hapi_update_${info.versionName}.app`;
    const taskId: string = `su_${Date.now()}`;
    this.currentTaskId = taskId;
    this.currentAppPath = appPath;
    this.currentCallbacks = callbacks;
    this.lastNotifTs = 0;
    // 申请 DATA_TRANSFER 长时任务，防切后台下载被系统回收（整个下载链只申请一次，finishDownload 停）
    this.startBackgroundKeepAlive();

    // 多 host 容错：下载 path 从已校验的 info.url 提取（同源同 path），主机按 orderHosts 排序逐个试
    const dlPath: string = SelfUpdateManager.urlToTrustedPath(info.url);
    const orderedHosts: string[] = this.orderHosts(this.workingHost);
    this.runDownloadChain(orderedHosts, 0, dlPath, info, appPath, taskId, callbacks);
    return taskId;
  }

  /**
   * 多 host 下载编排：逐 host 跑 streamOnce，网络层失败(retriable)换下一个，md5 不符(fatal)/成功(ok)终结。
   * cancel 由 cancelDownload 直接 finishDownload 清 currentTaskId，本编排每次 await 后查 taskId 守卫自然停。
   */
  private async runDownloadChain(hosts: string[], idx: number, dlPath: string, info: UpdateInfo,
    appPath: string, taskId: string, callbacks: DownloadCallbacks): Promise<void> {
    // cancel 后 currentTaskId 已清，迟到此处直接停（cancel 路径已 finishDownload）
    if (this.currentTaskId !== taskId) {
      return;
    }
    if (idx >= hosts.length) {
      this.finishDownload(taskId, false, appPath, '所有可信主机下载均失败', callbacks);
      return;
    }
    const url: string = hosts[idx] + dlPath;
    const result: DownloadAttemptResult = await this.streamOnce(url, info, appPath, taskId, callbacks);
    // 流期间被 cancel：currentTaskId 已变，停（cancel 路径已 finishDownload）
    if (this.currentTaskId !== taskId) {
      return;
    }
    switch (result.kind) {
      case 'ok':
        this.rememberWorkingHost(hosts[idx]);
        this.publishCompleteNotification();
        this.finishDownload(taskId, true, appPath, undefined, callbacks);
        break;
      case 'retriable':
        hilog.warn(LOG_DOMAIN, TAG, '下载失败(可重试,换下一个可信主机): %{public}s → %{public}s', url, result.error ?? '');
        this.runDownloadChain(hosts, idx + 1, dlPath, info, appPath, taskId, callbacks);
        break;
      case 'fatal':
        this.finishDownload(taskId, false, appPath, result.error ?? '下载校验失败', callbacks);
        break;
      case 'canceled':
      default:
        // cancel 路径已收尾，此处不重复处理
        break;
    }
  }

  /**
   * 单次流式下载尝试（一个 host）。成功 resolve {ok}；网络层失败 resolve {retriable}；
   * md5 不符 resolve {fatal}；cancel(taskId 守卫命中) resolve {canceled}。
   * streamOnce 自身【不调 finishDownload】——终结收尾统一交 runDownloadChain / cancelDownload。
   *
   * streamCodeReady：requestInStream 的 Promise 仅 resolve 状态码，但 dataEnd 可能先于 then 触发，
   *   用同步闸门等状态码就绪后再判 200/失败。
   */
  private streamOnce(url: string, info: UpdateInfo, appPath: string, taskId: string,
    callbacks: DownloadCallbacks): Promise<DownloadAttemptResult> {
    return new Promise<DownloadAttemptResult>((resolve: (r: DownloadAttemptResult) => void) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      this.currentRequest = httpRequest;
      let fd: number = -1;                          // 文件句柄，-1 = 未开（首块到达才开）
      let finished: boolean = false;                // 防重入：dataEnd / catch 两路互斥（单次尝试内，settle 置位）
      let receivedBytes: number = 0;                // 已写字节（dataEnd 时与 info.size 校验）

      // 终结辅助：关 fd + destroy 请求 + resolve（finished 防重入），单次尝试内幂等
      const settle = (r: DownloadAttemptResult): void => {
        if (finished) { return; }
        finished = true;
        if (fd >= 0) {
          try { fileIo.closeSync(fd); } catch (_e) {}
          fd = -1;
        }
        // ⚠️ destroy 收敛到 settle：HTTP 句柄在任何终结路径(dataEnd/catch)必达，防泄漏
        try { httpRequest.destroy(); } catch (_e) {}
        resolve(r);
      };

      // streamCodeReady 闸门（见方法注释）；参数名用 res 避免遮蔽外层 resolve
      let resolveStreamCode: (code: number) => void = () => {};
      const streamCodeReady: Promise<number> = new Promise<number>((res: (c: number) => void) => {
        resolveStreamCode = res;
      });

      // 响应头：取 Content-Length（进度 total 依据）
      httpRequest.on('headersReceive', (header: Object) => {
        if (finished) return;
        try {
          const headerMap = header as Record<string, string>;
          const cl: string = headerMap['content-length'] || headerMap['Content-Length'] || '';
          if (cl.length > 0) {
            callbacks.onProgress(0, parseInt(cl, 10));
          }
        } catch (_e) {
          // 响应头格式异常忽略，total 由 dataReceiveProgress 兜底
        }
      });

      // 数据块到达：增量写盘（首块开 fd，TRUNC 覆盖上次失败尝试的半成品）
      httpRequest.on('dataReceive', (chunk: ArrayBuffer) => {
        if (finished) return;
        try {
          if (fd < 0) {
            const opened = fileIo.openSync(appPath,
              fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
            fd = opened.fd;
          }
          fileIo.writeSync(fd, chunk);
          receivedBytes += chunk.byteLength;
        } catch (e) {
          // 写盘异常交由 dataEnd 校验时捕获
          hilog.warn(LOG_DOMAIN, TAG, '写盘异常: %{public}s', String(e));
        }
      });

      // 进度：回调 onProgress + 更新通知栏
      httpRequest.on('dataReceiveProgress', (data: StreamProgressInfo) => {
        if (finished) return;
        const total: number = data.totalSize >= 0 ? data.totalSize : -1;
        callbacks.onProgress(data.receiveSize, total);
        this.publishProgressNotification(total > 0 ? Math.min(100, Math.round(data.receiveSize / total * 100)) : 0);
      });

      // 流结束：状态码就绪后判 200/失败 → 校验 → settle
      httpRequest.on('dataEnd', () => {
        if (finished) return;
        // dataEnd 后等状态码，加 5s 超时兜底——requestInStream 理论可能不 resolve（异常网络栈：
        //   流已结束 dataEnd 触发，但状态码 Promise 迟迟不 settle）。不兜底则 streamCodeReady 永挂 →
        //   校验不执行 → 编排链卡死。超时返回 -1（!=200 走 retriable）。
        let toHandle: number = -1;
        const codeRace: Promise<number> = Promise.race<number>([
          streamCodeReady,
          new Promise<number>((r: (c: number) => void) => { toHandle = setTimeout(() => { r(-1); }, 5000); })
        ]);
        codeRace.then(async (statusCode: number) => {
          // 进 then 即清超时 timer（成功/超时两路都进，统一清）
          if (toHandle >= 0) { clearTimeout(toHandle); toHandle = -1; }
          // cancel 后 currentTaskId 已清，迟到此处 settle canceled，不重复收尾（cancel 路径已 finishDownload）
          if (this.currentTaskId !== taskId) { settle({ kind: 'canceled' }); return; }
          if (statusCode !== 200) {
            settle({ kind: 'retriable', error: `HTTP ${statusCode}` });
            return;
          }
          // size 校验：截断(网络层)→retriable 换 host 再试（同源正确文件在别处可下全）
          if (receivedBytes !== info.size) {
            settle({ kind: 'retriable', error: `大小不符（${receivedBytes}/${info.size}）` });
            return;
          }
          try {
            // ⚠️ hash.hash 返回大写 hex，toLowerCase 归一化后与 info.md5（脚本 md5sum 产小写）对比
            const md5: string = (await hash.hash(appPath, 'md5')).toLowerCase();
            if (md5 !== info.md5.toLowerCase()) {
              // md5 不符=致命：所有可信 host 同源同后端同文件，换 host 也是同样错字节，不浪费带宽重试
              settle({ kind: 'fatal', error: 'MD5 校验失败' });
            } else {
              hilog.info(LOG_DOMAIN, TAG, '下载校验通过: %{public}s', info.versionName);
              settle({ kind: 'ok' });
            }
          } catch (e) {
            // md5 计算异常：归 retriable（本地瞬时 IO 异常，换 host 重流可能恢复）
            settle({ kind: 'retriable', error: `MD5 计算异常: ${String(e)}` });
          }
        });
      });

      // 发起流式请求（hapi 直连，无 proxy）
      const streamOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: 30000,
        readTimeout: 300000    // 5min：.app 安装包较大，弱网放宽
      };
      httpRequest.requestInStream(url, streamOptions).then((code: number) => {
        resolveStreamCode(code);
      }).catch((err: Error) => {
        // 取消时 destroy 会触发此 catch，必须 settle 关 fd——fd 是闭包局部变量，cancelDownload
        //   访问不到，若不在此 settle 则 fd 永久泄漏 + 孤儿 inode 占空间直到 App 重启。
        //   finished 已防 dataEnd 路径双重；cancel 由 taskId 守卫判定(currentTaskId 已清→canceled)。
        if (finished) { return; }
        if (this.currentTaskId !== taskId) {
          settle({ kind: 'canceled' });
          return;
        }
        settle({ kind: 'retriable', error: String(err) });
      });
    });
  }

  /**
   * 统一收尾：清状态 + 删失败文件 + 通知 UI。
   * taskId 守卫保证幂等——dataEnd/catch/cancel 三路可能交错（如 dataEnd 卡在 await hash 时用户取消），
   *   迟到的调用 currentTaskId 已清 → return，杜绝「取消后被成功覆盖」式重复 onVerifyDone。
   * silent=true 时不弹「下载失败」通知（用户主动取消应静默，只 cancelProgressNotification）。
   */
  private finishDownload(taskId: string, ok: boolean, appPath: string, error: string | undefined,
    callbacks: DownloadCallbacks, silent: boolean = false): void {
    // 幂等守卫——已收尾的迟到调用直接吞
    if (this.currentTaskId !== taskId) {
      return;
    }
    this.currentTaskId = '';
    this.currentRequest = null;
    this.currentCallbacks = null;
    this.currentAppPath = '';
    // 下载结束停后台保活（无论成败）
    this.stopBackgroundKeepAlive();
    if (!ok) {
      // 失败/取消：删半成品文件 + 取消进度通知
      this.cancelProgressNotification();
      // 用户取消(silent)不弹「下载失败」通知，避免误导
      if (!silent) {
        this.publishFailedNotification();
      }
      try { fileIo.unlinkSync(appPath); } catch (_e) {}
      hilog.warn(LOG_DOMAIN, TAG, '下载结束(失败/取消): %{public}s', error ?? '');
    } else {
      // 记录已校验路径，cleanOrphanApps 跳过防误删（用户点安装前 app 保留）
      this.verifiedAppPath = appPath;
    }
    // 取消(silent)且提供 onCancel → 只走 onCancel（页面关 sheet 不切 failed，避免闪现「校验失败」）；
    //   真失败走 onVerifyDone(false) 切 failed 态展示重试；成功走 onVerifyDone(true)。
    if (!ok && silent && callbacks.onCancel) {
      callbacks.onCancel();
    } else {
      callbacks.onVerifyDone(ok, ok ? appPath : undefined, ok ? undefined : error);
    }
  }

  /**
   * 取消当前下载（用户点「取消」/ 离开页面）。
   * destroy 请求 + silent 收尾通知页面。cancel 静默依赖 destroy 异步触发 catch（关 fd）+
   *   finishDownload 的 taskId 守卫去重（迟到 catch 路径 currentTaskId 已清→return，不重复回调）。
   */
  cancelDownload(): void {
    if (this.currentTaskId.length === 0) {
      return;
    }
    const taskId: string = this.currentTaskId;
    const appPath: string = this.currentAppPath;
    const callbacks: DownloadCallbacks | null = this.currentCallbacks;
    if (this.currentRequest) {
      try { this.currentRequest.destroy(); } catch (_e) {}
    }
    // 主动收尾（silent=true：用户取消不弹「下载失败」通知，只 cancelProgressNotification）
    if (callbacks) {
      this.finishDownload(taskId, false, appPath, '用户取消', callbacks, true);
    }
  }

  /** 是否下载中（页面回前台判断是否需恢复进度 UI） */
  isDownloading(): boolean {
    return this.currentTaskId.length > 0;
  }

  /**
   * 申请 DATA_TRANSFER 长时任务，防切后台下载被系统回收。
   * module.json5 已声明 backgroundModes + KEEP_BACKGROUND_RUNNING。
   * 失败仅 log（不影响下载，仅后台保活降级）。
   */
  async startBackgroundKeepAlive(): Promise<void> {
    // 乐观置 isBackgroundRunning=true（调用即置，不等 await），防 stop 在 start 的 await 完成
    //   前早退（标志仍 false→空操作）→ 随后 start 置 true → 永卡。bgPromise 存启动 promise 供 stop await。
    if (this.isBackgroundRunning || this.ctx === null) {
      return;
    }
    this.isBackgroundRunning = true;
    this.bgPromise = this.doStartBackgroundRunning();
  }

  /** 实际启动后台保活（失败回退乐观标志），由 startBackgroundKeepAlive 存入 bgPromise */
  private async doStartBackgroundRunning(): Promise<void> {
    if (this.ctx === null) {
      return;
    }
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [{ bundleName: this.ctx.abilityInfo.bundleName, abilityName: this.ctx.abilityInfo.name }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(
        this.ctx,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );
      hilog.info(LOG_DOMAIN, TAG, '后台保活已启动');
    } catch (e) {
      // 启动失败回退乐观标志（stop 后续判 !isBackgroundRunning 直接 return，不误 stop）
      this.isBackgroundRunning = false;
      hilog.error(LOG_DOMAIN, TAG, '启动后台保活失败(切后台下载可能中断): %{public}s', String(e));
    }
  }

  /** 停后台保活（下载完成/失败/取消时调用） */
  async stopBackgroundKeepAlive(): Promise<void> {
    // 无条件 stop——先 await bgPromise 等启动落地（若 start 的 await 未完成），再 stop，
    //   消除"stop 早退 → start 迟置 → 永卡"窗口。ctx 空直接 return。
    if (this.ctx === null) {
      return;
    }
    if (this.bgPromise !== null) {
      try { await this.bgPromise; } catch (_e) {}
      this.bgPromise = null;
    }
    if (!this.isBackgroundRunning) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.ctx);
      this.isBackgroundRunning = false;
      hilog.info(LOG_DOMAIN, TAG, '后台保活已停止');
    } catch (e) {
      hilog.error(LOG_DOMAIN, TAG, '停止后台保活失败: %{public}s', String(e));
    }
  }

  // ========== 拉起安装器 ==========

  /**
   * 拉起系统/三方安装器安装 .app（三方无 INSTALL_BUNDLE 权限，靠隐式 want 委托安装器）。
   * 多 want 串行 + reject 回退：install 为主，reject 时回退 viewData（按 .app 扩展名路由）；全失败返回 false。
   */
  async launchInstaller(appPath: string): Promise<boolean> {
    // 用户已点安装，清除已校验保护（下次 cleanOrphanApps 可清残留）
    this.verifiedAppPath = '';
    if (this.ctx === null) {
      return false;
    }
    try {
      const uri: string = fileUri.getUriFromPath(appPath);
      // 不带 type，靠 uri 的 .app 扩展名让系统路由到注册了 .app 的安装器（复刻文件管理器点 .app → hokit 的真实路径）。
      //   多 want 串行 + reject 回退：install 为主（安装语义）；viewData 兜底（复刻"打开"，按 .app 扩展名匹安装器）。
      //   两 want 均 reject → return false。
      const wants: Want[] = [
        { action: 'ohos.want.action.install', uri: uri,
          flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION },
        { action: 'ohos.want.action.viewData', uri: uri,
          flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION }
      ];
      for (let i = 0; i < wants.length; i++) {
        try {
          await this.ctx.startAbility(wants[i]);
          hilog.info(LOG_DOMAIN, TAG, '已拉起安装器(want[%{public}d]): %{public}s', i, appPath);
          return true;
        } catch (e) {
          // 该 want 无匹配 ability（reject）→ 继续试下一个 want
          hilog.warn(LOG_DOMAIN, TAG, 'want[%{public}d] 拉起失败，试下一个: %{public}s', i, String(e));
        }
      }
      hilog.warn(LOG_DOMAIN, TAG, '所有拉起 want 均失败: %{public}s', appPath);
      return false;
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, '拉起安装器异常（uri 构建/意外）: %{public}s', String(e));
      return false;
    }
  }

  // ========== 忽略 / prefs ==========

  /** 忽略指定版本Code（同版本Code不再弹，新版本Code不匹配会重新提示） */
  ignoreVersion(versionCode: number): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(K_IGNORED_VERSION, versionCode);
      this.prefs.flush();
      hilog.info(LOG_DOMAIN, TAG, '已忽略版本Code: %{public}d', versionCode);
    } catch (e) {
      hilog.warn(LOG_DOMAIN, TAG, '写 ignored_version 失败: %{public}s', String(e));
    }
  }

  /** 读取已忽略版本Code（调试/校验用） */
  getIgnoredVersion(): number {
    if (this.prefs === null) {
      return 0;
    }
    return this.prefs.getSync(K_IGNORED_VERSION, 0) as number;
  }

  /**
   * 自动弹窗是否已过节流期：距上次「自动弹 sheet」≥ AUTO_PROMPT_THROTTLE_MS（或从未弹过）才允许自动弹。
   * 仅 OtaController.checkForUpdates 的 silent 自动检查路径调；手动检查(silent=false)不走节流、总是弹。
   * prefs 读失败 → 返回 true（不因 IO 异常吞掉更新提示）。
   */
  shouldAutoPrompt(): boolean {
    if (this.prefs === null) {
      return true;
    }
    try {
      const last: number = this.prefs.getSync(K_LAST_PROMPTED_TS, 0) as number;
      return last <= 0 || (Date.now() - last) >= AUTO_PROMPT_THROTTLE_MS;
    } catch (_e) {
      return true;
    }
  }

  /** 记录「已弹更新 sheet」时刻，启动 2h 自动弹窗冷却。弹 sheet 时（手动/自动皆然）调。 */
  markAutoPrompted(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(K_LAST_PROMPTED_TS, Date.now());
      this.prefs.flush();
    } catch (_e) {
      // 写失败不影响本次弹窗（最坏下次重复弹一次，可接受）
    }
  }

  // ========== 通知（downloadTemplate，三方禁实况窗） ==========

  private isNetworkAvailable(): boolean {
    try {
      return connection.hasDefaultNetSync();
    } catch (_e) {
      return false;
    }
  }

  /** 发布/更新进度通知（downloadTemplate 进度条模板，progressMaxValue 必填=100） */
  private publishProgressNotification(percent: number): void {
    // 节流——dataReceiveProgress 每网络块触发一次，50MB 包会产生数千次 IPC 风暴。2s 内不重复 publish（应用内进度条不受影响）。
    const now: number = Date.now();
    if (this.lastNotifTs > 0 && now - this.lastNotifTs < NOTIF_THROTTLE_MS) {
      return;
    }
    this.lastNotifTs = now;
    if (!this.templateSupported) {
      this.publishFallbackNotification(percent);
      return;
    }
    const title: string = t('ota.notif.title');
    const request: notificationManager.NotificationRequest = {
      id: NOTIF_ID,
      updateOnly: true,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: t('ota.notif.downloading'), additionalText: `${percent}%` }
      },
      template: {
        name: 'downloadTemplate',
        // data 四字段缺一不可：title/fileName/progressValue/progressMaxValue
        data: {
          title: title,
          fileName: t('ota.notif.fileName'),
          progressValue: percent,
          progressMaxValue: 100
        }
      }
    };
    notificationManager.publish(request).catch((e: Error) => {
      // 模板不支持：置标志后续直接降级，并补发一次纯文本（本次进度不丢）
      this.templateSupported = false;
      hilog.warn(LOG_DOMAIN, TAG, '进度条模板通知失败，降级纯文本: %{public}s', String(e));
      this.publishFallbackNotification(percent);
    });
  }

  /** 降级纯文本进度通知（设备不支持 downloadTemplate 时；每次覆盖 publish，无 updateOnly 漏显示） */
  private publishFallbackNotification(percent: number): void {
    const request: notificationManager.NotificationRequest = {
      id: NOTIF_ID,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: t('ota.notif.title'), text: t('ota.notif.downloading'), additionalText: `${percent}%` }
      }
    };
    notificationManager.publish(request).catch(() => {});
  }

  /** 下载完成通知（先 cancel 进度通知避免 slot/模板冲突） */
  private publishCompleteNotification(): void {
    notificationManager.cancel(NOTIF_ID).catch(() => {});
    const request: notificationManager.NotificationRequest = {
      id: NOTIF_ID,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: t('ota.notif.title'), text: t('ota.notif.complete'), additionalText: '' }
      }
    };
    notificationManager.publish(request).catch(() => {});
  }

  /** 下载失败通知 */
  private publishFailedNotification(): void {
    notificationManager.cancel(NOTIF_ID).catch(() => {});
    const request: notificationManager.NotificationRequest = {
      id: NOTIF_ID,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: t('ota.notif.title'), text: t('ota.notif.failed'), additionalText: '' }
      }
    };
    notificationManager.publish(request).catch(() => {});
  }

  /** 取消进度通知（取消下载时） */
  private cancelProgressNotification(): void {
    notificationManager.cancel(NOTIF_ID).catch(() => {});
  }
}
