import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { t } from '../i18n/I18nService';

// 系统分享服务：纯文本 → 系统分享面板（@kit.ShareKit systemShare）。
// 对照 chatcube services/ShareService.ets 的 shareText（MIT），裁掉其图片/Markdown/HTML/截图导出，
// 仅保留纯文本分享（消息长按「分享」用）。
//
// 关键 import（chatcube 实证，编译必需）：
//   - systemShare ∈ @kit.ShareKit
//   - uniformTypeDescriptor(as utd) ∈ @kit.ArkData（UniformDataType.PLAIN_TEXT）
//   - common ∈ @kit.AbilityKit（UIAbilityContext）
//
// context 由调用方传入（组件 getHostContext() as common.UIAbilityContext），免去 init 生命周期。
// 纯文本走系统分享面板（非静默分享），无需额外权限声明（chatcube 未声明即可用）。

export interface ShareResult {
  success: boolean;
  errorMessage: string;
}

export class ShareService {
  // 分享纯文本：拉起系统分享面板。success=true 表示面板已成功弹出并关闭（用户是否真分享不可知）。
  async shareText(context: common.UIAbilityContext, content: string, title: string = t('share.defaultTitle')): Promise<ShareResult> {
    if (content === '') {
      return { success: false, errorMessage: t('share.emptyContent') };
    }
    try {
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: content,
        title: title
      });
      const controller = new systemShare.ShareController(shareData);
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
      return { success: true, errorMessage: '' };
    } catch (error) {
      return { success: false, errorMessage: t('share.failed', { detail: JSON.stringify(error) }) };
    }
  }
}

// 全局便捷访问（与其他 *Service 单例一致）
export function getShareService(): ShareService {
  return ShareServiceHolder.instance;
}

class ShareServiceHolder {
  static instance: ShareService = new ShareService();
}
