// GeneratedImageCache 单测 —— 命中 / put / FIFO 上限 / re-put 新鲜 / clear（同步面）。
//   fetch() 的 in-flight 去重为异步，本项目 hypium LocalUnit 无 async 先例 → 留真机验证（loader 闭包可注入）。

import { describe, it, expect } from '@ohos/hypium';
import { GeneratedImageCache, GENERATED_IMAGE_CACHE_MAX } from '../main/ets/services/GeneratedImageCache';

export default function generatedImageCacheTest(): void {
  describe('GeneratedImageCache — 命中与 put', () => {
    it('未命中 → undefined', 0, () => {
      const c = new GeneratedImageCache();
      expect(c.get('s1:i1') === undefined).assertEqual(true);
    });
    it('put 后 get 命中', 0, () => {
      const c = new GeneratedImageCache();
      c.put('s1:i1', 'data:1');
      expect(c.get('s1:i1')).assertEqual('data:1');
    });
    it('不同 key 隔离（sessionId 作用域）', 0, () => {
      const c = new GeneratedImageCache();
      c.put('s1:i1', 'data:a');
      c.put('s2:i1', 'data:b');   // 同 imageId 不同 session
      expect(c.get('s1:i1')).assertEqual('data:a');
      expect(c.get('s2:i1')).assertEqual('data:b');
    });
  });

  describe('GeneratedImageCache — FIFO 上限淘汰', () => {
    it('超 MAX 淘汰最早插入（size 恒为 MAX）', 0, () => {
      const c = new GeneratedImageCache();
      const over: number = GENERATED_IMAGE_CACHE_MAX + 3;
      for (let i = 0; i < over; i++) {
        c.put(`s:k${i}`, `d${i}`);
      }
      expect(c.size()).assertEqual(GENERATED_IMAGE_CACHE_MAX);
      expect(c.get('s:k0') === undefined).assertEqual(true);   // 最早被淘汰
      expect(c.get(`s:k${over - 1}`)).assertEqual(`d${over - 1}`); // 最新仍在
    });
    it('re-put 已存在 key 移到末尾（避免被 FIFO 淘汰）', 0, () => {
      const c = new GeneratedImageCache();
      for (let i = 0; i < GENERATED_IMAGE_CACHE_MAX; i++) {   // 填满：k0..k(MAX-1)
        c.put(`s:k${i}`, `d${i}`);
      }
      c.put('s:k0', 'd0v2');   // re-insert k0 → 移末尾
      c.put('s:new', 'dnew');  // 触发淘汰：最旧 = k1
      expect(c.get('s:k0')).assertEqual('d0v2');              // k0 存活（刚移末尾）
      expect(c.get('s:k1') === undefined).assertEqual(true);  // k1 被淘汰
      expect(c.get('s:new')).assertEqual('dnew');
    });
  });

  describe('GeneratedImageCache — clear', () => {
    it('clear 清空 cache 与计数', 0, () => {
      const c = new GeneratedImageCache();
      c.put('s:a', '1');
      c.put('s:b', '2');
      expect(c.size()).assertEqual(2);
      c.clear();
      expect(c.size()).assertEqual(0);
      expect(c.get('s:a') === undefined).assertEqual(true);
    });
  });
}
