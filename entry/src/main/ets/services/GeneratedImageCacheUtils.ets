// 生成图片磁盘缓存 —— 纯逻辑工具层（无 @kit，可 LocalUnit 测）。
//   磁盘 IO 在 GeneratedImageCache.ets（带 @kit.CoreFileKit，LocalUnit 闭包不可加载）；
//   本文件抽出不依赖文件系统的纯函数，对照 KvStore(纯)/Translate(纯) 拆层范式。
//
//   落盘文件名 = hashKey(key) + '.' + extensionForMime(mimeType)；
//   key = sessionId:imageId（imageId 跨会话不保证唯一，会话作用域隔离）。
//   hashKey 为 chatcube IconDownloadCache.hashUrl 原样移植（djb2 变体 → 8 位 hex）。

// 拼 key：sessionId + ':' + imageId
export function buildImageCacheKey(sessionId: string, imageId: string): string {
  return sessionId + ':' + imageId;
}

// djb2 变体字符串哈希 → 8 位零填充小写 hex（对照 参考源码/chatcube/.../services/IconDownloadCache.ets:163-173 hashUrl）。
//   hash = hash*31 + ch（用位移 (hash<<5)-hash 实现 *31）；hash & hash 强转 int32；>>>0 转无符号。
export function hashKey(key: string): string {
  let hash: number = 0;
  for (let i = 0; i < key.length; i++) {
    const ch: number = key.charCodeAt(i);
    hash = ((hash << 5) - hash) + ch;
    hash = hash & hash;
  }
  const unsigned: number = hash >>> 0;
  return unsigned.toString(16).padStart(8, '0');
}

// mimeType → 文件扩展名（小写归一）。
//   图片：png/jpg/gif/webp/bmp/svg，未知 image/* → png（Image 按文件头嗅探，扩展名错也不影响渲染）。
//   音频：mp3/wav/m4a/ogg/aac/flac，未知 audio/* → mp3（否则音频被存成 .png，磁盘与播放器都错）。
//   视频：mp4/mov/webm/mkv，未知 video/* → mp4。
//   其余 → bin。
export function extensionForMime(mimeType: string): string {
  const m: string = mimeType.toLowerCase();
  // 图片
  if (m === 'image/png') { return 'png'; }
  if (m === 'image/jpeg' || m === 'image/jpg') { return 'jpg'; }
  if (m === 'image/gif') { return 'gif'; }
  if (m === 'image/webp') { return 'webp'; }
  if (m === 'image/bmp') { return 'bmp'; }
  if (m === 'image/svg+xml') { return 'svg'; }
  // 音频
  if (m === 'audio/mpeg' || m === 'audio/mp3' || m === 'audio/mp4a') { return 'mp3'; }
  if (m === 'audio/wav' || m === 'audio/wave' || m === 'audio/x-wav') { return 'wav'; }
  if (m === 'audio/mp4' || m === 'audio/m4a' || m === 'audio/x-m4a') { return 'm4a'; }
  if (m === 'audio/ogg' || m === 'audio/ogg; codecs=opus') { return 'ogg'; }
  if (m === 'audio/aac' || m === 'audio/aacp') { return 'aac'; }
  if (m === 'audio/flac' || m === 'audio/x-flac') { return 'flac'; }
  if (m.startsWith('audio/')) { return 'mp3'; }
  // 视频
  if (m === 'video/mp4' || m === 'video/x-m4v') { return 'mp4'; }
  if (m === 'video/quicktime') { return 'mov'; }
  if (m === 'video/webm') { return 'webm'; }
  if (m === 'video/x-matroska') { return 'mkv'; }
  if (m.startsWith('video/')) { return 'mp4'; }
  // 图片兜底（未知 image/*）+ 通用二进制
  if (m.startsWith('image/')) { return 'png'; }
  return 'bin';
}

// 组文件名：<hash>.<ext>
export function buildFileName(hash: string, ext: string): string {
  return hash + '.' + ext;
}

// 剥扩展名还原 hash（rebuildIndex 用）：取最后一个 '.' 前的部分。
//   hash 本身是 8 位 hex 无点，故文件名中首个 '.' 即扩展名分隔；无点/隐藏文件原样返回。
export function stripExtension(fileName: string): string {
  const dot: number = fileName.lastIndexOf('.');
  if (dot <= 0) {
    return fileName;
  }
  return fileName.substring(0, dot);
}

// 取 key 的 session 部分（首个 ':' 前；无 ':' 原样）。clearSession 索引维护用。
export function sessionOfKey(key: string): string {
  const colon: number = key.indexOf(':');
  return colon >= 0 ? key.substring(0, colon) : key;
}
