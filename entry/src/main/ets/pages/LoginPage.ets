import { getConnectionService } from '../services/ConnectionService';
import { getHubClient } from '../api/HubClient';
import { AppStorageKeys } from '../config/Keys';
import { window } from '@kit.ArkUI';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';

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
  }

  private isInputComplete(): boolean {
    return this.hubUrl.trim().length > 0 && this.apiToken.length > 0;
  }

  // 测试连接：GET /health，仅验证 Hub 地址可达（无需 token）
  private async testConnection(): Promise<void> {
    if (this.isTesting) { return; }
    if (this.hubUrl.trim() === '') {
      this.lastError = '请填写 Hub 地址';
      return;
    }
    this.isTesting = true;
    this.lastError = '';
    try {
      const ok = await getHubClient().health(this.hubUrl.trim());
      if (ok) {
        showToast('Hub 地址可达', 2000);
      } else {
        this.lastError = '无法连接到 Hub，请检查地址';
      }
    } catch (e) {
      this.lastError = '连接测试失败';
    } finally {
      this.isTesting = false;
    }
  }

  // 登录：用 token 换 JWT（POST /api/auth），成功持久化并切到主页
  private async doLogin(): Promise<void> {
    if (this.isSubmitting) { return; }
    if (!this.isInputComplete()) {
      this.lastError = '请填写 Hub 地址和 Access Token';
      return;
    }
    this.isSubmitting = true;
    this.lastError = '';
    try {
      const result = await getHubClient().authenticate(this.apiToken.trim(), this.hubUrl.trim());
      if (!result.success) {
        this.lastError = result.errorMessage !== '' ? result.errorMessage : '登录失败，请检查地址和 Token';
        return;
      }
      // 持久化配置 + JWT，然后切到会话列表页
      await getConnectionService().saveConnection(this.hubUrl.trim(), this.apiToken.trim());
      await getConnectionService().saveJwt(result.jwt);
      this.switchToMainContent();
    } catch (e) {
      this.lastError = '登录失败：' + (e instanceof Error ? e.message : '未知错误');
    } finally {
      this.isSubmitting = false;
    }
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
      Text('Hapi')
        .fontSize(fs(40))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.c.textPrimary)
        .margin({ top: 80 })
      Text('连接到你的 Hub')
        .fontSize(fs(16))
        .fontColor(this.c.textSecondary)
        .margin({ top: 8 })

      // 表单区
      Column() {
        this.InputRow('Hub 地址', this.hubUrl, 'http://192.168.1.5:3006', false,
          (text: string) => { this.hubUrl = text; this.lastError = '' })
        this.InputRow('Access Token', this.apiToken, 'CLI_API_TOKEN', true,
          (text: string) => { this.apiToken = text; this.lastError = '' })

        // 内联错误行（条件渲染，对照 OnboardingStepProvider）
        if (this.lastError !== '') {
          Text(this.lastError)
            .fontSize(fs(12))
            .fontColor(this.c.error)
            .width('100%')
            .margin({ top: 2, left: 4 })
        }

        // 帮助文本
        Text('启动 Hub：npx @twsxtd/hapi hub --relay。地址填 Hub 监听地址，Token 为 CLI_API_TOKEN。')
          .fontSize(fs(12))
          .fontColor(this.c.textTertiary)
          .margin({ top: 12 })
      }
      .width('100%')
      .margin({ top: 40, left: 24, right: 24 })

      // 按钮区（线框测试 + 实心登录，对照 chatcube WebDAVSyncPage 双按钮）
      Row({ space: 12 }) {
        Button(this.isTesting ? '测试中…' : '测试连接')
          .layoutWeight(1)
          .height(44)
          .fontSize(fs(15))
          .backgroundColor(this.c.surface)
          .fontColor(this.c.primary)
          .borderRadius(10)
          .enabled(!this.isTesting && !this.isSubmitting)
          .onClick(() => this.testConnection())

        Button(this.isSubmitting ? '登录中…' : '登录')
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
