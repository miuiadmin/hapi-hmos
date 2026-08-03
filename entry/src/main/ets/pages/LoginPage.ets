import { getConnectionService } from '../services/ConnectionService';
import { getDeepLinkImporter, ParsedConnect } from '../services/DeepLinkImporter';
import { getHubClient } from '../api/HubClient';
import { AppStorageKeys } from '../config/Keys';
import { ServerPreset } from '../models/HubConfig';
import { FACTORY_PRESETS } from '../config/FactoryPresets.local';
import { t, kv } from '../i18n/I18nService';
import { window } from '@kit.ArkUI';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';

// 厂内测试预制服务器数据源见 config/FactoryPresets.local（芯片 onClick 回填并直接登录）。
//   ⚠️ 其内 token 机密：公开仓库版本为空数组；本机用 `git update-index --skip-worktree` 后填真值，不入库/不外传。

// 登录页：填 Hub 地址 + CLI_API_TOKEN，「测试连接」「登录」
// UI 写法/样式对照 chatcube（WebDAVSyncPage 表单 + OnboardingStepProvider 内联错误），V2 状态管理
// 语义：登录 = POST /api/auth 用 token 换 JWT（对照 web/src/api/client.ts），成功持久化配置并切到会话列表页
// 颜色经统一主题（theme/ThemeService）—— 读 getThemeState().isDark 取调色板，切换/跟随系统即时响应。

@Entry
@ComponentV2
struct LoginPage {
  // 表单字段
  @Local hubUrl: string = '';
  @Local apiToken: string = '';
  @Local lastError: string = '';           // 内联错误（空串 = 隐藏）
  // 按钮 loading 态（每个异步动作一个独立标志，防重入 + try/finally 复位）
  @Local isTesting: boolean = false;
  @Local isSubmitting: boolean = false;

  // 主题（读 @Trace isDark 建立刷新依赖；切换即时重渲染）
  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  aboutToAppear(): void {
    // 回填已存的 Hub 地址，方便重连；token 不回填（安全）
    this.hubUrl = getConnectionService().hubUrl;
    // 冷启动经 deep link 拉起：消费待导入链接 → 验证后登录（与手动登录走同一条 apply 链路）
    const pending: string = getDeepLinkImporter().consumePending();
    if (pending !== '') {
      this.handleDeepLink(pending);
    }
  }

  private isInputComplete(): boolean {
    return this.hubUrl.trim().length > 0 && this.apiToken.length > 0;
  }

  // 测试连接：GET /health，仅验证 Hub 地址可达（无需 token）
  private async testConnection(): Promise<void> {
    if (this.isTesting) { return; }
    if (this.hubUrl.trim() === '') {
      this.lastError = t('login.error.hubUrlRequired');
      return;
    }
    this.isTesting = true;
    this.lastError = '';
    try {
      const ok = await getHubClient().health(this.hubUrl.trim());
      if (ok) {
        showToast(t('login.hubReachable'), 2000);
      } else {
        this.lastError = t('login.error.cannotConnect');
      }
    } catch (e) {
      this.lastError = t('login.error.testFailed');
    } finally {
      this.isTesting = false;
    }
  }

  // 登录：用 token 换 JWT（POST /api/auth），成功持久化并切到主页
  //   鉴权 + 持久化 + arm 预刷抽到 DeepLinkImporter.apply，与 deep link 导入共用同一条链路。
  private async doLogin(): Promise<void> {
    if (this.isSubmitting) { return; }
    if (!this.isInputComplete()) {
      this.lastError = t('login.error.fillAll');
      return;
    }
    this.isSubmitting = true;
    this.lastError = '';
    try {
      const r = await getDeepLinkImporter().apply(this.hubUrl.trim(), this.apiToken.trim());
      if (!r.success) {
        this.lastError = r.errorMessage;
        return;
      }
      this.switchToMainContent();
    } catch (e) {
      this.lastError = t('login.error.failedWithReason', kv('reason', e instanceof Error ? e.message : t('login.error.unknown')));
    } finally {
      this.isSubmitting = false;
    }
  }

  // deep link 导入：解析链接 → apply（与 doLogin 同链路）。token 不回填表单（安全），仅地址回填 + 状态指示。
  private async handleDeepLink(uri: string): Promise<void> {
    const parsed: ParsedConnect | null = getDeepLinkImporter().parse(uri);
    if (parsed === null) {
      return;   // 非 connect 链接，忽略
    }
    this.hubUrl = parsed.server;
    this.isSubmitting = true;
    this.lastError = '';
    try {
      const r = await getDeepLinkImporter().apply(parsed.server, parsed.token);
      if (!r.success) {
        this.lastError = r.errorMessage;
        return;
      }
      this.switchToMainContent();
    } catch (e) {
      this.lastError = t('login.error.failedWithReason', kv('reason', e instanceof Error ? e.message : t('login.error.unknown')));
    } finally {
      this.isSubmitting = false;
    }
  }

  // 预制服务器一键登录：回填表单 + 直接走 doLogin（厂测免手填）。
  private applyPreset(p: ServerPreset): void {
    this.hubUrl = p.hubUrl;
    this.apiToken = p.apiToken;
    this.lastError = '';
    this.doLogin();
  }

  // 预制服务器芯片行（横向排列，点即登录）。
  @Builder
  private PresetChips() {
    Row({ space: 8 }) {
      ForEach(FACTORY_PRESETS, (p: ServerPreset): void => {
        Text(p.name)
          .fontSize(fs(13))
          .fontColor(this.c.primary)
          .backgroundColor(this.c.surface)
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .onClick(() => { this.applyPreset(p); })
      }, (p: ServerPreset): string => p.id)
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
  }

  private switchToMainContent(): void {
    const stage = AppStorage.get<window.WindowStage>(AppStorageKeys.MAIN_WINDOW_STAGE);
    if (stage !== undefined) {
      stage.loadContent('pages/Index');
    }
  }

  // 复用输入行（标签 + TextInput），密码框 isPassword=true（对照 chatcube WebDAVSyncPage.InputRow）
  @Builder
  private InputRow(label: string, value: string, placeholder: string | Resource, isPassword: boolean,
    onChange: (text: string) => void) {
    Column() {
      Text(label)
        .fontSize(fs(13))
        .fontColor(this.c.textSecondary)
        .margin({ bottom: 6, left: 4 })
      TextInput({ text: value, placeholder: placeholder })
        .type(isPassword ? InputType.Password : InputType.Normal)
        .fontSize(fs(15))
        .fontColor(this.c.textPrimary)
        .height(48)
        .backgroundColor(this.c.surface)
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
        .onChange(onChange)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 12 })
  }

  build() {
    Column() {
      // 标题区
      Text(t('app.name'))
        .fontSize(fs(40))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c.textPrimary)
        .margin({ top: 80 })
      Text(t('login.subtitle'))
        .fontSize(fs(16))
        .fontColor(this.c.textSecondary)
        .margin({ top: 8 })

      // 表单区
      Column() {
        this.InputRow(t('login.hubUrl'), this.hubUrl, 'http://192.168.1.5:3006', false,
          (text: string) => { this.hubUrl = text; this.lastError = '' })
        this.InputRow(t('login.accessToken'), this.apiToken, 'CLI_API_TOKEN', true,
          (text: string) => { this.apiToken = text; this.lastError = '' })

        // 预制服务器（厂测一键登录）
        this.PresetChips()

        // 内联错误行（条件渲染，对照 OnboardingStepProvider）
        if (this.lastError !== '') {
          Text(this.lastError)
            .fontSize(fs(12))
            .fontColor(this.c.error)
            .width('100%')
            .margin({ top: 2, left: 4 })
        }

        // 帮助文本
        Text(t('login.helpText'))
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
          .margin({ top: 12 })
      }
      .width('100%')
      .margin({ top: 40, left: 24, right: 24 })

      // 按钮区（线框测试 + 实心登录，对照 chatcube WebDAVSyncPage 双按钮）
      Row({ space: 12 }) {
        Button(this.isTesting ? t('login.testing') : t('login.testConnection'))
          .layoutWeight(1)
          .height(44)
          .fontSize(fs(15))
          .backgroundColor(this.c.surface)
          .fontColor(this.c.primary)
          .borderRadius(10)
          .enabled(!this.isTesting && !this.isSubmitting)
          .onClick(() => this.testConnection())

        Button(this.isSubmitting ? t('login.submitting') : t('login.submit'))
          .layoutWeight(1)
          .height(44)
          .fontSize(fs(15))
          .backgroundColor(this.c.primary)
          .fontColor(this.c.bubbleUserText)
          .borderRadius(10)
          .enabled(!this.isTesting && !this.isSubmitting && this.isInputComplete())
          .onClick(() => this.doLogin())
      }
      .width('100%')
      .margin({ top: 24, left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.c.bg)
    .alignItems(HorizontalAlign.Center)
  }
}
