// 附件选择内联面板（输入栏「+」展开后露出；对照 chatcube components/AttachmentPicker.ets，MIT）。
//   三项：拍照(cameraPicker) / 照片(PhotoViewPicker) / 上传文件(DocumentViewPicker)，均为系统 picker、免权限。
//   本组件只负责「选 + 读」，上传在 ChatPage.uploadPickedFiles（与原 📎 路径同一条）。
//   MIT License © LongLiveY96/chatcube（搬运自上游，保留版权）。

import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { pickAndReadPhotos, pickAndReadCameraPhoto, pickAndReadDocuments, PickedFile } from '../services/FilePicker';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { t } from '../i18n/I18nService';

@ComponentV2
export struct AttachmentPickerPanel {
  // 选完一组附件回调（ChatPage 走 uploadFile 入 pendingAttachments）；用户取消不触发。
  @Event onSelect: (picked: PickedFile[]) => void = (_picked: PickedFile[]): void => {};
  // 选完（有结果）或面板应关闭时回调（ChatPage 收起内联面板）。
  @Event onClose: () => void = (): void => {};
  @Local isBusy: boolean = false;   // 某一项正在调 picker（防重入；选完即复位）

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  private ctx(): common.UIAbilityContext | null {
    const host = this.getUIContext().getHostContext();
    if (host === undefined || host === null) { return null; }
    return host as common.UIAbilityContext;
  }

  build() {
    Row() {
      this.OptionButton($r('sys.symbol.camera'), t('composer.attach.camera'), (): Promise<void> => { return this.openCamera(); })
      this.OptionButton($r('sys.symbol.shutter_photo'), t('composer.attach.photo'), (): Promise<void> => { return this.openPhoto(); })
      this.OptionButton($r('sys.symbol.paperclip'), t('composer.attach.file'), (): Promise<void> => { return this.openFile(); })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .padding({ left: 16, right: 16, top: 16, bottom: 12 })
    .backgroundColor(this.c.surface)
  }

  @Builder
  OptionButton(icon: Resource, label: string, action: () => Promise<void>) {
    Column() {
      Column() {
        SymbolGlyph(icon)
          .fontSize(fs(24))
          .fontColor([this.c.textPrimary])
      }
      .width(64)
      .height(64)
      .borderRadius(16)
      .backgroundColor(this.c.bg)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(label)
        .fontSize(fs(13))
        .fontColor(this.c.textSecondary)
        .margin({ top: 8 })
    }
    .onClick(() => {
      if (this.isBusy) { return; }
      action();
    })
  }

  // 拍照：cameraPicker.pick → 单图 PickedFile → onSelect + onClose。
  private async openCamera(): Promise<void> {
    if (this.isBusy) { return; }
    const ctx = this.ctx();
    if (ctx === null) { return; }
    this.isBusy = true;
    try {
      const picked: PickedFile | null = await pickAndReadCameraPhoto(ctx);
      if (picked !== null) {
        this.onSelect([picked]);
        this.onClose();
      }
    } catch (e) {
      // 静默：用户取消或相机不可用
    } finally {
      this.isBusy = false;
    }
  }

  // 照片：PhotoViewPicker 多选 → PickedFile[] → onSelect + onClose。
  private async openPhoto(): Promise<void> {
    if (this.isBusy) { return; }
    const ctx = this.ctx();
    if (ctx === null) { return; }
    this.isBusy = true;
    try {
      const picked: PickedFile[] = await pickAndReadPhotos(ctx, 5);
      if (picked.length > 0) {
        this.onSelect(picked);
        this.onClose();
      }
    } catch (e) {
      // 静默：用户取消
    } finally {
      this.isBusy = false;
    }
  }

  // 上传文件：DocumentViewPicker 多选 → PickedFile[] → onSelect + onClose。
  private async openFile(): Promise<void> {
    if (this.isBusy) { return; }
    const ctx = this.ctx();
    if (ctx === null) { return; }
    this.isBusy = true;
    try {
      const picked: PickedFile[] = await pickAndReadDocuments(ctx, 10);
      if (picked.length > 0) {
        this.onSelect(picked);
        this.onClose();
      }
    } catch (e) {
      // 静默：用户取消
    } finally {
      this.isBusy = false;
    }
  }
}
