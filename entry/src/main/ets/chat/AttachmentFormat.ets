import { AttachmentMetadata } from '../models/Types';

// 附件格式化（对照 web/src/lib/fileAttachments.ts + web/src/chat/normalizeUser.ts + MessageAttachments.tsx）
//   零 @kit 纯层：isImageMimeType / formatFileSize / parseAttachmentsFromContent。
//   附件仅是 user 消息概念（agent 产图走 generated-image 块、改文件走 tool-call），故只在 user 气泡内渲染。

// 图片 MIME 判断（对照 fileAttachments.ts:22-24：startsWith('image/')）
export function isImageMimeType(mimeType: string): boolean {
  return mimeType.startsWith('image/');
}

// 文件大小可读串（对照 MessageAttachments.tsx:6-10：B/KB/MB 三档，1024 进制，1 位小数）
//   上游无 GB 档，此处对齐；模板串接（无 replace-fn）。
export function formatFileSize(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  const MB: number = 1024 * 1024;
  if (bytes < MB) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  return `${(bytes / MB).toFixed(1)} MB`;
}

// 从 content.attachments 数组解析附件（对照 normalizeUser.ts:5-28 parseAttachments）
//   容错：非数组/空 → 空数组；逐项须 id/filename/mimeType(string)/size(number)/path(string) 四必填；
//   缺任一必填字段 → 跳过（不 push）。previewUrl 可选（string，否则空串）。
export function parseAttachmentsFromContent(raw: Object | null): AttachmentMetadata[] {
  const out: AttachmentMetadata[] = [];
  if (raw === null || raw === undefined || !Array.isArray(raw)) {
    return out;
  }
  const arr: Object[] = raw as Object[];
  for (let i = 0; i < arr.length; i++) {
    const entry: Object = arr[i];
    if (entry === null || entry === undefined || typeof entry !== 'object') {
      continue;
    }
    const rec: Record<string, Object> = entry as Record<string, Object>;
    const idVal: Object = rec['id'];
    const filenameVal: Object = rec['filename'];
    const mimeTypeVal: Object = rec['mimeType'];
    const sizeVal: Object = rec['size'];
    const pathVal: Object = rec['path'];
    if (typeof idVal !== 'string') { continue; }
    if (typeof filenameVal !== 'string') { continue; }
    if (typeof mimeTypeVal !== 'string') { continue; }
    if (typeof sizeVal !== 'number') { continue; }
    if (typeof pathVal !== 'string') { continue; }
    const meta: AttachmentMetadata = new AttachmentMetadata();
    meta.id = idVal;
    meta.filename = filenameVal;
    meta.mimeType = mimeTypeVal;
    meta.size = sizeVal;
    meta.path = pathVal;
    const previewVal: Object = rec['previewUrl'];
    meta.previewUrl = typeof previewVal === 'string' ? previewVal : '';
    out.push(meta);
  }
  return out;
}
