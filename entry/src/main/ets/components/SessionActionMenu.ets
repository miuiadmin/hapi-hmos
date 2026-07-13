import { getHubClient } from '../api/HubClient';
import { getGeneratedImageCache } from '../services/GeneratedImageCache';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';
import { showToast } from '../utils/Toast';
import { t } from '../i18n/I18nService';

// 会话动作菜单（重命名 / 归档 / 删除）——列表长按（Index）与对话页标题栏 ⋯（ChatPage）复用，去重。
// 组件自持两 sheet（动作面板 + 重命名面板）+ 全部生命周期逻辑（确认弹窗 / API 调用 / 防重入）。
// 父只需：传目标快照（sessionId/title/active）+ open 信号（@Param 布尔）+ 成功回调（@Event）。
//   - open=true 开动作面板；面板被滑掉/点蒙层/选了某项 → onDisappear → onClose() 回写父（父置 open=false）。
//   - 重命名成功 → onRenamed(name)；归档成功 → onArchived()；删除成功 → onDeleted()。父决定后续：
//     列表 loadSessions / 对话页 设本地态 / pop 导航。
//   - 注：@Event 改父值立刻生效，同步回 @Param 在「渲染之前」完成（@Event 文档），故 onClose 后动作面板与
//     后续弹窗/重命名面板同帧切换，无可见闪烁。
// 上游行为逐字对照 hub 源码 + web SessionActionMenu/RenameSessionDialog/ConfirmDialog（无臆测）。
// 菜单按 active 二选一：活跃→归档，非活跃→删除，永不并存（Session 无 archived 字段：
//   归档=杀活跃 CLI + active=false；删除=硬删除不可恢复）。

@ComponentV2
export struct SessionActionMenu {
  // 目标会话快照（父持有；@Param 单向，随父态刷新）
  @Param sessionId: string = '';
  @Param title: string = '';
  @Param active: boolean = true;
  // 动作面板显隐（父控制开；onClose 回写关）
  @Param open: boolean = false;
  // 是否在面板顶部渲染「文件 / 终端」导航行（仅对话页 ⋯ 传 true；列表长按默认 false 不显）
  @Param showNavigation: boolean = false;

  // 成功回调（父决定后续动作）
  @Event onRenamed: (newName: string) => void = (newName: string) => {};
  @Event onArchived: () => void = () => {};
  @Event onDeleted: () => void = () => {};
  // 导航行回调（仅 showNavigation=true 时触发；父 push Files/Terminal 页）
  @Event onOpenFiles: () => void = () => {};
  @Event onOpenTerminal: () => void = () => {};
  // 动作面板关闭回写（滑掉/蒙层/选了重命名/归档/删除）
  @Event onClose: () => void = () => {};

  // 重命名面板（组件内部态；从动作面板内 transitions 进出，不暴露父）
  @Local showRename: boolean = false;
  @Local renameText: string = '';
  @Local isActing: boolean = false;                 // 请求进行中（防重入 + 保存按钮置灰）
  private renameInputController: TextInputController = new TextInputController();

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 动作面板被滑掉/点蒙层 → 回写父关闭
  private onActionDisappear(): void {
    this.onClose();
  }

  // 第二项文案：active→归档；非活跃→删除（永不并存，对照上游 SessionActionMenu）
  private destructiveLabel(): string {
    return this.active ? t('sessionMenu.archive') : t('sessionMenu.delete');
  }

  private onDestructiveTap(): void {
    if (this.active) {
      this.confirmArchive();
    } else {
      this.confirmDelete();
    }
  }

  // 切换到远程（仅 active 会话显）：多端/多窗口时让 CLI 把输入定向到本会话（对照上游
  // SessionChat.handleSwitchToRemote → switchSession）。移动端单窗口价值低，记为边缘入口。
  // 关面板 → POST /switch → toast（无本地态变更，不阻塞）。
  private async startSwitchRemote(): Promise<void> {
    this.onClose();
    if (this.sessionId === '') {
      return;
    }
    try {
      const ok = await getHubClient().switchSession(this.sessionId);
      showToast(ok ? t('sessionMenu.switchedRemote') : t('sessionMenu.switchRemoteFailed'));
    } catch (e) {
      showToast(t('sessionMenu.switchRemoteFailed'));
    }
  }

  // 重命名：关动作面板，预填当前标题，开重命名面板
  private startRename(): void {
    this.onClose();
    this.renameText = this.title;
    this.showRename = true;
  }

  private closeRename(): void {
    this.showRename = false;
    this.renameText = '';
  }

  // 确认重命名：空或未改不请求；成功 onRenamed(name) + 关面板；失败保留面板（toast 提示）
  private async confirmRename(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    const name = this.renameText.trim();
    if (name.length === 0 || name === this.title) {
      this.closeRename();
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().renameSession(this.sessionId, name);
      if (ok) {
        this.onRenamed(name);
        showToast(t('sessionMenu.renamed'));
        this.closeRename();
      } else {
        showToast(t('sessionMenu.renameFailed'));
      }
    } catch (e) {
      showToast(t('sessionMenu.renameFailed'));
    } finally {
      this.isActing = false;
    }
  }

  // 归档二次确认（危险操作，confirm 红字）
  private confirmArchive(): void {
    this.onClose();
    this.getUIContext().showAlertDialog({
      title: t('sessionMenu.archiveTitle'),
      message: t('sessionMenu.archiveConfirm', { name: this.title }),
      autoCancel: true,
      confirm: {
        value: t('sessionMenu.archive'),
        fontColor: this.c.error,
        action: () => { this.doArchive(); }
      }
    });
  }

  // 删除二次确认（硬删除不可恢复，confirm 红字）
  private confirmDelete(): void {
    this.onClose();
    this.getUIContext().showAlertDialog({
      title: t('sessionMenu.deleteTitle'),
      message: t('sessionMenu.deleteConfirm', { name: this.title }),
      autoCancel: true,
      confirm: {
        value: t('sessionMenu.delete'),
        fontColor: this.c.error,
        action: () => { this.doDelete(); }
      }
    });
  }

  // 执行归档：成功 onArchived()（父决定后续）；失败 toast
  private async doArchive(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().archiveSession(this.sessionId);
      if (ok) {
        this.onArchived();
        showToast(t('sessionMenu.archived'));
      } else {
        showToast(t('sessionMenu.archiveFailed'));
      }
    } catch (e) {
      showToast(t('sessionMenu.archiveFailed'));
    } finally {
      this.isActing = false;
    }
  }

  // 执行删除：成功 onDeleted()（父决定后续：列表 loadSessions / 对话页 pop）；失败 toast
  private async doDelete(): Promise<void> {
    if (this.isActing || this.sessionId === '') {
      return;
    }
    this.isActing = true;
    try {
      const ok = await getHubClient().deleteSession(this.sessionId);
      if (ok) {
        // 删该会话本进程登记的生成图片盘文件 + 索引（hash 不可逆→跨重启孤儿留观察；一处覆盖列表删/对话页删）
        getGeneratedImageCache().clearSession(this.sessionId);
        this.onDeleted();
        showToast(t('sessionMenu.deleted'));
      } else {
        showToast(t('sessionMenu.deleteFailed'));
      }
    } catch (e) {
      showToast(t('sessionMenu.deleteFailed'));
    } finally {
      this.isActing = false;
    }
  }

  // 动作面板（重命名 / 归档或删除，对照上游 SessionActionMenu）
  @Builder
  private ActionMenuSheet() {
    Column() {
      Text(this.title)
        .fontSize(fs(13))
        .fontColor(this.c.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

      // 导航行（仅对话页 showNavigation=true；终端行 inactive 置灰——非活跃会话无可用 CLI）
      if (this.showNavigation) {
        Row() {
          Text(t('sessionMenu.files')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.onClose(); this.onOpenFiles(); })

        Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

        Row() {
          Text(t('sessionMenu.terminal')).fontSize(fs(16))
            .fontColor(this.active ? this.c.textPrimary : this.c.textTertiary).layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .opacity(this.active ? 1 : 0.5)
        .onClick(() => { if (this.active) { this.onClose(); this.onOpenTerminal(); } })

        Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })
      }

      Row() {
        Text(t('sessionMenu.rename')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.startRename(); })

      if (this.active) {
        Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

        Row() {
          Text(t('sessionMenu.switchRemote')).fontSize(fs(16)).fontColor(this.c.textPrimary).layoutWeight(1)
        }
        .width('100%')
        .height(52)
        .padding({ left: 20, right: 20 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.startSwitchRemote(); })
      }

      Divider().color(this.c.border).strokeWidth(0.5).margin({ left: 20, right: 20 })

      Row() {
        Text(this.destructiveLabel()).fontSize(fs(16)).fontColor(this.c.error).layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.onDestructiveTap(); })
    }
    .width('100%')
    .backgroundColor(this.c.bg)
    .padding({ bottom: 20 })
  }

  // 重命名面板：TextInput 预填 + 保存/取消；空或未改不请求，回车提交，失败保留面板（对照上游 RenameSessionDialog）
  @Builder
  private RenameSheet() {
    Column() {
      TextInput({ text: this.renameText, placeholder: t('sessionMenu.sessionNamePlaceholder'), controller: this.renameInputController })
        .fontSize(fs(16))
        .fontColor(this.c.textPrimary)
        .placeholderColor(this.c.textTertiary)
        .backgroundColor(this.c.surface)
        .borderRadius(12)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .maxLength(255)
        .defaultFocus(true)
        .onChange((v: string) => { this.renameText = v; })
        .onSubmit(() => { this.confirmRename(); })

      Row({ space: 10 }) {
        Button(t('common.cancel'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.surface)
          .fontColor(this.c.textPrimary)
          .borderRadius(12)
          .onClick(() => { this.closeRename(); })
        Button(this.isActing ? t('sessionMenu.saving') : t('sessionMenu.save'))
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.c.primary)
          .fontColor(this.c.bubbleUserText)
          .borderRadius(12)
          .enabled(!this.isActing && this.renameText.trim().length > 0)
          .onClick(() => { this.confirmRename(); })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
    .backgroundColor(this.c.bg)
  }

  build() {
    // 零尺寸常驻容器：仅承载两 sheet。动作面板挂外层 Column / 重命名面板挂内层 Column，
    // 双节点规避同节点 bindSheet 叠加疑问（延续 Index 两节点模式）。bindSheet 为模态覆盖，锚点尺寸无关。
    Column() {
      Column() {}
        .bindSheet(this.showRename, this.RenameSheet(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: true,
          showClose: true,
          title: { title: t('sessionMenu.renameSheetTitle') },
          onDisappear: (): void => { this.closeRename(); }
        })
    }
    .width(0)
    .height(0)
    .bindSheet(this.open, this.ActionMenuSheet(), {
      detents: [SheetSize.FIT_CONTENT],
      dragBar: true,
      showClose: false,
      onDisappear: (): void => { this.onActionDisappear(); }
    })
  }
}
