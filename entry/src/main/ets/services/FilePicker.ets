// 文件选取 + 读取 + base64 编码（附件上传前置；对照 chatcube AttachmentPicker，MIT）。
//   DocumentViewPicker 选文件 → fileIo 读字节 → util.Base64Helper 编码 → PickedFile。
//   本服务只负责「选 + 读」，不含上传（上传在 HubClient.uploadFile）；MIME 按扩展名猜，默认 octet-stream。
//   非 multipart：上游 uploadFile 收 JSON {filename, content: base64, mimeType}（已对照 web client.ts:298）。

import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

// 选取并读完的文件（base64Content 为整文件 base64，size 为字节数）
export class PickedFile {
  filename: string = '';
  mimeType: string = '';
  size: number = 0;
  base64Content: string = '';
}

// 常见扩展名 → MIME（其余落 application/octet-stream；图片常用项优先，覆盖 agent 常读的文本/图/表）。
const MIME_MAP: Record<string, string> = {
  txt: 'text/plain', md: 'text/markdown', json: 'application/json', csv: 'text/csv',
  html: 'text/html', xml: 'application/xml', yaml: 'text/yaml', yml: 'text/yaml',
  js: 'text/javascript', ts: 'text/typescript', py: 'text/x-python', java: 'text/x-java',
  c: 'text/x-c', h: 'text/x-c', cpp: 'text/x-c++', hpp: 'text/x-c++',
  go: 'text/x-go', rs: 'text/x-rust', rb: 'text/x-ruby', php: 'text/x-php',
  sh: 'application/x-sh', sql: 'application/sql',
  pdf: 'application/pdf', zip: 'application/zip', gz: 'application/gzip',
  png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif',
  webp: 'image/webp', svg: 'image/svg+xml', bmp: 'image/bmp',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  xls: 'application/vnd.ms-excel',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  doc: 'application/msword'
};

export function guessMime(filename: string): string {
  const lower: string = filename.toLowerCase();
  const dot: number = lower.lastIndexOf('.');
  if (dot < 0 || dot === lower.length - 1) { return 'application/octet-stream'; }
  const ext: string = lower.substring(dot + 1);
  const mime: string | undefined = MIME_MAP[ext];
  return mime !== undefined ? mime : 'application/octet-stream';
}

// 从 picker URI 取文件名（末段 + decodeURIComponent；取不到回落 'file'）
export function fileNameFromUri(uri: string): string {
  const slash: number = uri.lastIndexOf('/');
  const raw: string = slash >= 0 ? uri.substring(slash + 1) : uri;
  if (raw === '') { return 'file'; }
  try {
    const decoded: string = decodeURIComponent(raw);
    return decoded !== '' ? decoded : 'file';
  } catch (e) {
    return raw;
  }
}

// 从单个 URI 读字节 + base64 → PickedFile（单/多选取共用；读失败 → null）。
function readPickedFile(uri: string): PickedFile | null {
  const filename: string = fileNameFromUri(uri);
  try {
    const file: fileIo.File = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(file.fd);
    const ab: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, ab);
    fileIo.closeSync(file);
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    const u8: Uint8Array = new Uint8Array(ab);
    const base64Data: string = base64Helper.encodeToStringSync(u8);
    const out: PickedFile = new PickedFile();
    out.filename = filename;
    out.mimeType = guessMime(filename);
    out.size = stat.size;
    out.base64Content = base64Data;
    return out;
  } catch (e) {
    return null;
  }
}

// 打开 DocumentViewPicker 选单个文件并读完返回；用户取消/读失败 → null（调用方静默或 toast）。
export async function pickAndReadDocument(context: common.UIAbilityContext): Promise<PickedFile | null> {
  let uris: string[];
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const result: string[] = await documentPicker.select(options);
    if (result.length === 0) { return null; }
    uris = result;
  } catch (e) {
    return null;   // 用户取消或 picker 不可用
  }
  return readPickedFile(uris[0]);
}

// 多文件选取（对照上游多附件：一次选多个，每文件独立 upload）。maxSelectNumber 上限（默认 10）；
//   逐个读 base64，单文件读失败跳过不影响其余。用户取消/全失败 → 空数组（调用方静默）。
export async function pickAndReadDocuments(context: common.UIAbilityContext, maxNumber: number = 10): Promise<PickedFile[]> {
  let uris: string[];
  try {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = maxNumber;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const result: string[] = await documentPicker.select(options);
    if (result.length === 0) { return []; }
    uris = result;
  } catch (e) {
    return [];
  }
  const out: PickedFile[] = [];
  for (let i = 0; i < uris.length; i++) {
    const pf: PickedFile | null = readPickedFile(uris[i]);
    if (pf !== null) { out.push(pf); }
  }
  return out;
}
