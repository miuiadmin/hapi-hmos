// 生成图片内存缓存（消除会话重入 / 组件回收 / 列表项复用导致的重复全量拉取 + 同步 base64 重编码）。
//   纯内存（无 @kit）：磁盘缓存按既定「大图留后续」暂不实现（参考源码/chatcube IconDownloadCache 为磁盘版蓝本）。
//   - key = sessionId:imageId（imageId 跨会话不保证唯一，会话作用域隔离）。
//   - 命中 → 同步返回 dataUri；未命中走 loader 拉取，成功入缓存。
//   - in-flight 去重：同 key 并发请求共享一个 Promise（复用 chatcube IconDownloadCache pendingDownloads 范式，
//     参考源码/chatcube/.../services/IconDownloadCache.ets:21,96-104）。
//   - FIFO 上限：超 GENERATED_IMAGE_CACHE_MAX 淘汰最早插入项；re-put 已存在 key 移到末尾保持新鲜。
//     与「组件 @Local 各持 dataUri」相比，命中后多组件共享同一字符串引用 → 实际降内存。
//   HubClient 保持 Context-free：本缓存不触文件系统，loader 由调用方注入（GeneratedImageCard 传 fetchGeneratedImage）。

export const GENERATED_IMAGE_CACHE_MAX: number = 32;

export class GeneratedImageCache {
  private cache: Map<string, string> = new Map<string, string>();                        // key → dataUri
  private pending: Map<string, Promise<string>> = new Map<string, Promise<string>>();    // key → 进行中的拉取

  // 同步命中查询；未命中返回 undefined
  get(key: string): string | undefined {
    return this.cache.get(key);
  }

  // 按 key 拉取：命中直返；未命中 loader 拉取 + 成功入缓存；并发同 key 共享 in-flight。
  //   loader 失败则重抛（不入缓存、清 in-flight），调用方可重试。
  async fetch(key: string, loader: () => Promise<string>): Promise<string> {
    const hit: string | undefined = this.cache.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const inflight: Promise<string> | undefined = this.pending.get(key);
    if (inflight !== undefined) {
      return inflight;   // 共享已发起的拉取，loader 不再被调
    }
    const p: Promise<string> = loader();
    this.pending.set(key, p);
    try {
      const uri: string = await p;
      this.put(key, uri);
      return uri;
    } finally {
      this.pending.delete(key);   // 成功/失败均清，使失败可重试
    }
  }

  // 入缓存（已存在则 re-insert 移到末尾；超上限 FIFO 淘汰）
  put(key: string, dataUri: string): void {
    if (this.cache.has(key)) {
      this.cache.delete(key);
    }
    this.cache.set(key, dataUri);
    this.evict();
  }

  clear(): void {
    this.cache.clear();
    this.pending.clear();
  }

  size(): number {
    return this.cache.size;
  }

  // FIFO 淘汰：Map 迭代按插入序 → 首个即最旧
  private evict(): void {
    while (this.cache.size > GENERATED_IMAGE_CACHE_MAX) {
      let oldest: string | null = null;
      for (const k of this.cache.keys()) {
        oldest = k;
        break;
      }
      if (oldest === null) {
        break;
      }
      this.cache.delete(oldest);
    }
  }
}

const instance: GeneratedImageCache = new GeneratedImageCache();

export function getGeneratedImageCache(): GeneratedImageCache {
  return instance;
}
