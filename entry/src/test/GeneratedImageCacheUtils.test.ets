// GeneratedImageCacheUtils 单测 —— 磁盘缓存纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 Translate.test / KvStore 范式：同步断言（assertEqual / === ）。
//   磁盘 IO（带 @kit.CoreFileKit 的 GeneratedImageCache）留真机验证，不入 LocalUnit。
// hashKey 为 chatcube IconDownloadCache.hashUrl 原样移植（djb2 变体）；用确定输入断言以钉住算法。

import { describe, it, expect } from '@ohos/hypium';
import {
  buildImageCacheKey,
  hashKey,
  extensionForMime,
  buildFileName,
  stripExtension,
  sessionOfKey
} from '../main/ets/services/GeneratedImageCacheUtils';

export default function generatedImageCacheUtilsTest(): void {
  describe('GeneratedImageCacheUtils — buildImageCacheKey', () => {
    it('sessionId + \':\' + imageId', 0, () => {
      expect(buildImageCacheKey('sess_abc', 'img_xyz')).assertEqual('sess_abc:img_xyz');
    });
    it('空串拼接仍合法', 0, () => {
      expect(buildImageCacheKey('', '')).assertEqual(':');
    });
  });

  describe('GeneratedImageCacheUtils — hashKey（djb2 → 8 hex）', () => {
    it('空串 → 00000000', 0, () => {
      expect(hashKey('')).assertEqual('00000000');
    });
    it('单字符 a → 00000061', 0, () => {
      expect(hashKey('a')).assertEqual('00000061');
    });
    it('已知输入 abc → 00017862（手算钉算法）', 0, () => {
      expect(hashKey('abc')).assertEqual('00017862');
    });
    it('确定性：同输入两次相等', 0, () => {
      expect(hashKey('sess1:img1')).assertEqual(hashKey('sess1:img1'));
    });
    it('区分性：不同输入不同 hash', 0, () => {
      expect(hashKey('a') === hashKey('b')).assertEqual(false);
    });
    it('格式：8 位小写 hex（无填充不合法）', 0, () => {
      const h: string = hashKey('some-realistic-session-id:image-123');
      expect(h.length).assertEqual(8);
      expect(/^[0-9a-f]{8}$/.test(h)).assertEqual(true);
    });
  });

  describe('GeneratedImageCacheUtils — extensionForMime', () => {
    it('image/png → png', 0, () => {
      expect(extensionForMime('image/png')).assertEqual('png');
    });
    it('大小写归一：IMAGE/PNG → png', 0, () => {
      expect(extensionForMime('IMAGE/PNG')).assertEqual('png');
    });
    it('image/jpeg → jpg', 0, () => {
      expect(extensionForMime('image/jpeg')).assertEqual('jpg');
    });
    it('image/jpg → jpg', 0, () => {
      expect(extensionForMime('image/jpg')).assertEqual('jpg');
    });
    it('image/gif/webp/bmp/svg', 0, () => {
      expect(extensionForMime('image/gif')).assertEqual('gif');
      expect(extensionForMime('image/webp')).assertEqual('webp');
      expect(extensionForMime('image/bmp')).assertEqual('bmp');
      expect(extensionForMime('image/svg+xml')).assertEqual('svg');
    });
    it('未知 mime → png 回落', 0, () => {
      expect(extensionForMime('image/avif')).assertEqual('png');
    });
    it('空 mime → png 回落', 0, () => {
      expect(extensionForMime('')).assertEqual('png');
    });
  });

  describe('GeneratedImageCacheUtils — buildFileName', () => {
    it('hash + \'.\' + ext', 0, () => {
      expect(buildFileName('00017862', 'png')).assertEqual('00017862.png');
    });
    it('与 hashKey/extensionForMime 串联等价', 0, () => {
      const f: string = buildFileName(hashKey('abc'), extensionForMime('image/jpeg'));
      expect(f).assertEqual('00017862.jpg');
    });
  });

  describe('GeneratedImageCacheUtils — stripExtension', () => {
    it('剥 .png 还原 hash', 0, () => {
      expect(stripExtension('00017862.png')).assertEqual('00017862');
    });
    it('多字符前缀 + 扩展名', 0, () => {
      expect(stripExtension('abcdef12.jpeg')).assertEqual('abcdef12');
    });
    it('无扩展名原样返回', 0, () => {
      expect(stripExtension('noext')).assertEqual('noext');
    });
    it('隐藏文件（点在首位）原样返回', 0, () => {
      expect(stripExtension('.hidden')).assertEqual('.hidden');
    });
  });

  describe('GeneratedImageCacheUtils — sessionOfKey', () => {
    it('取首个冒号前', 0, () => {
      expect(sessionOfKey('sess1:img1')).assertEqual('sess1');
    });
    it('无冒号原样返回', 0, () => {
      expect(sessionOfKey('noColon')).assertEqual('noColon');
    });
    it('冒号在首位 → 空串', 0, () => {
      expect(sessionOfKey(':img1')).assertEqual('');
    });
  });
}
