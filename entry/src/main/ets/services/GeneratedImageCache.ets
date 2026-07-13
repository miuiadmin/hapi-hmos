// 生成图片磁盘缓存 —— 重启持久化 + 免 base64 热路径。
//   Hub 二进制原样落盘，Image(裸沙箱路径) 直接渲染（对照 参考源码/chatcube IconDownloadCache，MIT 蓝本）。
//   与蓝本差异：Hub 已返回 PNG/JPEG 原始字节，直接写 ArrayBuffer，跳过 ImageKit 转码。
//
//   - key = sessionId:imageId（imageId 跨会话不保证唯一，会话作用域隔离）。
//   - 落盘文件名 = hashKey(key) + '.' + extensionForMime(mimeType)；重启后 rebuildIndex 扫目录重建 hash→path 索引。
//   - getCachedPath 同步命中查询（热路径零编码）；未命中走 loader 拉字节写盘。
//   - in-flight 去重：同 key 并发请求共享一个 Promise（try/finally 清，失败可重试）。
//   - clearSession：删本进程登记的该会话 hash 的盘文件 + 索引。hash 不可逆 → 跨重启删除的会话留孤儿（同 chatcube 零清理策略）。
//   纯函数（hash/扩展名/文件名等）在 GeneratedImageCacheUtils.ets（无 @kit，可单测）；本文件仅磁盘 IO + 编排。

import { fileIo } from '@kit.CoreFileKit';
import { Context } from '@kit.AbilityKit';
import { hashKey, extensionForMime, buildFileName, stripExtension } from './GeneratedImageCacheUtils';

const CACHE_DIR_NAME: string = 'generated_images';

export class GeneratedImageCache {
  private cacheDir: string = '';
  private isInitialized: boolean = false;
  private memoryIndex: Map<string, string> = new Map<string, string>();              // hash → 沙箱文件路径
  private sessionHashes: Map<string, Set<string>> = new Map<string, Set<string>>();   // sessionId → Set<hash>（进程内，clearSession 用）
  private pending: Map<string, Promise<string>> = new Map<string, Promise<string>>(); // key → 进行中的拉取

  async initialize(context: Context): Promise<void> {
    if (this.isInitialized) {
      return;
    }
    this.cacheDir = `${context.filesDir}/${CACHE_DIR_NAME}`;
    await this.ensureCacheDir();
    this.rebuildIndex();
    this.isInitialized = true;
  }

  // 确保缓存目录存在（accessSync 探测，不存在则 mkdirSync 递归）。失败仅 warn，不阻断。
  private async ensureCacheDir(): Promise<void> {
    try {
      fileIo.accessSync(this.cacheDir);
    } catch (_e) {
      try {
        fileIo.mkdirSync(this.cacheDir, true);
      } catch (error) {
        console.warn('GeneratedImageCache', `Failed to create cache directory: ${JSON.stringify(error)}`);
      }
    }
  }

  // 启动时扫缓存目录重建 hash→path 内存索引（hash 不可逆，仅恢复 hash 维度；key 维度在 fetch 命中时按需登记 sessionHashes）。
  private rebuildIndex(): void {
    try {
      const entries: string[] = fileIo.listFileSync(this.cacheDir);
      for (let i = 0; i < entries.length; i++) {
        const fileName: string = entries[i];
        const filePath: string = `${this.cacheDir}/${fileName}`;
        const hash: string = stripExtension(fileName);
        this.memoryIndex.set(hash, filePath);
      }
    } catch (_e) {
      // 目录为空或不存在，忽略
    }
  }

  // 同步命中查询；未初始化/未命中返回 ''
  getCachedPath(key: string): string {
    if (!this.isInitialized) {
      return '';
    }
    const cached: string | undefined = this.memoryIndex.get(hashKey(key));
    return cached !== undefined ? cached : '';
  }

  // 按 key 拉取：命中直返裸路径；未命中 loader 拉字节写盘 + 入索引；并发同 key 共享 in-flight。
  //   mimeType 决定扩展名；loader 失败重抛（不缓存、清 in-flight），调用方可重试。
  async fetch(key: string, mimeType: string, loader: () => Promise<ArrayBuffer>): Promise<string> {
    const hit: string = this.getCachedPath(key);
    if (hit !== '') {
      return hit;
    }
    const inflight: Promise<string> | undefined = this.pending.get(key);
    if (inflight !== undefined) {
      return inflight;   // 共享已发起的拉取，loader 不再被调
    }
    const p: Promise<string> = this.fetchToDisk(key, mimeType, loader);
    this.pending.set(key, p);
    try {
      return await p;
    } finally {
      this.pending.delete(key);   // 成功/失败均清，使失败可重试
    }
  }

  private async fetchToDisk(key: string, mimeType: string, loader: () => Promise<ArrayBuffer>): Promise<string> {
    const buffer: ArrayBuffer = await loader();
    const hash: string = hashKey(key);
    const ext: string = extensionForMime(mimeType);
    const filePath: string = `${this.cacheDir}/${buildFileName(hash, ext)}`;
    const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try {
      fileIo.writeSync(file.fd, buffer);
    } finally {
      fileIo.closeSync(file);
    }
    this.memoryIndex.set(hash, filePath);
    this.registerSessionHash(key, hash);
    return filePath;
  }

  // 登记本进程加载过的 key→hash 到 session 维度（clearSession 用；hash 不可逆故重启后无此映射）。
  private registerSessionHash(key: string, hash: string): void {
    const colon: number = key.indexOf(':');
    const sessionId: string = colon >= 0 ? key.substring(0, colon) : key;
    let set: Set<string> | undefined = this.sessionHashes.get(sessionId);
    if (set === undefined) {
      set = new Set<string>();
      this.sessionHashes.set(sessionId, set);
    }
    set.add(hash);
  }

  // 删该会话本进程登记的盘文件 + 索引（best-effort unlinkSync；未登记如重启后 no-op）。
  clearSession(sessionId: string): void {
    const hashes: Set<string> | undefined = this.sessionHashes.get(sessionId);
    if (hashes === undefined) {
      return;
    }
    for (const hash of hashes) {
      const path: string | undefined = this.memoryIndex.get(hash);
      this.memoryIndex.delete(hash);
      if (path !== undefined) {
        try {
          fileIo.unlinkSync(path);
        } catch (_e) {
          // best-effort：文件已删/不可达时忽略
        }
      }
    }
    this.sessionHashes.delete(sessionId);
  }

  clear(): void {
    this.memoryIndex.clear();
    this.sessionHashes.clear();
    this.pending.clear();
  }

  size(): number {
    return this.memoryIndex.size;
  }
}

const instance: GeneratedImageCache = new GeneratedImageCache();

export function getGeneratedImageCache(): GeneratedImageCache {
  return instance;
}
