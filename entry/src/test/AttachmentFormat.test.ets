// AttachmentFormat 单测 —— 附件格式化纯逻辑层（无 @kit，LocalUnit 可加载）。
//   对照 CodeHighlight.test 范式：同步断言。
//   覆盖 isImageMimeType（image/* 前缀）+ formatFileSize（B/KB/MB 边界）+
//   parseAttachmentsFromContent（合法/缺必填字段跳过/previewUrl 可选/空数组/非数组/null/元素非对象）。

import { describe, it, expect } from '@ohos/hypium';
import {
  isImageMimeType,
  formatFileSize,
  parseAttachmentsFromContent
} from '../main/ets/chat/AttachmentFormat';

export default function attachmentFormatTest(): void {
  // —— isImageMimeType ——
  describe('AttachmentFormat — isImageMimeType', () => {
    it('image/png → true', 0, () => {
      expect(isImageMimeType('image/png')).assertTrue();
    });
    it('image/jpeg → true', 0, () => {
      expect(isImageMimeType('image/jpeg')).assertTrue();
    });
    it('image/ 前缀即 true（image/webp）', 0, () => {
      expect(isImageMimeType('image/webp')).assertTrue();
    });
    it('application/pdf → false', 0, () => {
      expect(isImageMimeType('application/pdf')).assertFalse();
    });
    it('text/plain → false', 0, () => {
      expect(isImageMimeType('text/plain')).assertFalse();
    });
    it('空串 → false', 0, () => {
      expect(isImageMimeType('')).assertFalse();
    });
  });

  // —— formatFileSize（对照上游 MessageAttachments.tsx:6-10：B/KB/MB 三档，1024 进制，1 位小数）——
  describe('AttachmentFormat — formatFileSize 边界', () => {
    it('0 → 0 B', 0, () => {
      expect(formatFileSize(0)).assertEqual('0 B');
    });
    it('1023 → 1023 B（< 1024 不换档）', 0, () => {
      expect(formatFileSize(1023)).assertEqual('1023 B');
    });
    it('1024 → 1.0 KB（正好换档）', 0, () => {
      expect(formatFileSize(1024)).assertEqual('1.0 KB');
    });
    it('1536 → 1.5 KB', 0, () => {
      expect(formatFileSize(1536)).assertEqual('1.5 KB');
    });
    it('1048575 → 1024.0 KB（< 1MB 仍 KB）', 0, () => {
      expect(formatFileSize(1048575)).assertEqual('1024.0 KB');
    });
    it('1048576 → 1.0 MB（正好 1MB）', 0, () => {
      expect(formatFileSize(1048576)).assertEqual('1.0 MB');
    });
    it('1572864 → 1.5 MB', 0, () => {
      expect(formatFileSize(1572864)).assertEqual('1.5 MB');
    });
    it('5242880 → 5.0 MB', 0, () => {
      expect(formatFileSize(5242880)).assertEqual('5.0 MB');
    });
  });

  // —— parseAttachmentsFromContent 合法 ——
  describe('AttachmentFormat — parseAttachmentsFromContent 合法', () => {
    it('单条合法（含 previewUrl）→ 解析 1 条且字段对', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":100,"path":"/p/a","previewUrl":"data:image/png;base64,AAA"}]');
      const out = parseAttachmentsFromContent(raw);
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('a');
      expect(out[0].filename).assertEqual('f.png');
      expect(out[0].mimeType).assertEqual('image/png');
      expect(out[0].size).assertEqual(100);
      expect(out[0].path).assertEqual('/p/a');
      expect(out[0].previewUrl).assertEqual('data:image/png;base64,AAA');
    });
    it('单条合法（无 previewUrl）→ previewUrl 空串', 0, () => {
      const raw = JSON.parse('[{"id":"b","filename":"d.pdf","mimeType":"application/pdf","size":2048,"path":"/p/b"}]');
      const out = parseAttachmentsFromContent(raw);
      expect(out.length).assertEqual(1);
      expect(out[0].previewUrl).assertEqual('');
    });
    it('多条合法 → 解析 2 条且保序', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":1,"path":"/p/a"},' +
        '{"id":"b","filename":"g.jpg","mimeType":"image/jpeg","size":2,"path":"/p/b"}]');
      const out = parseAttachmentsFromContent(raw);
      expect(out.length).assertEqual(2);
      expect(out[0].id).assertEqual('a');
      expect(out[1].id).assertEqual('b');
    });
  });

  // —— 缺必填字段跳过（id/filename/mimeType/size/path 任一不达标）——
  describe('AttachmentFormat — parseAttachmentsFromContent 缺必填字段跳过', () => {
    it('缺 id → 跳过（0 条）', 0, () => {
      const raw = JSON.parse('[{"filename":"f.png","mimeType":"image/png","size":1,"path":"/p/a"}]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('缺 path → 跳过', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":1}]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('size 非数字（字符串）→ 跳过', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":"100","path":"/p/a"}]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('mimeType 非字符串（数字）→ 跳过', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":1,"size":1,"path":"/p/a"}]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('混合：1 合法 + 1 缺字段 → 仅 1 条', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":1,"path":"/p/a"},' +
        '{"id":"b","filename":"x"}]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(1);
    });
  });

  // —— 容错 ——
  describe('AttachmentFormat — parseAttachmentsFromContent 容错', () => {
    it('空数组 → 0 条', 0, () => {
      const raw = JSON.parse('[]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('非数组（对象）→ 0 条', 0, () => {
      const raw = JSON.parse('{"id":"a"}');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('null → 0 条', 0, () => {
      expect(parseAttachmentsFromContent(null).length).assertEqual(0);
    });
    it('元素非对象（字符串/数字）→ 跳过', 0, () => {
      const raw = JSON.parse('["notobj",1]');
      expect(parseAttachmentsFromContent(raw).length).assertEqual(0);
    });
    it('previewUrl 非字符串（数字）→ 视为空串（条目仍保留）', 0, () => {
      const raw = JSON.parse('[{"id":"a","filename":"f.png","mimeType":"image/png","size":1,"path":"/p/a","previewUrl":5}]');
      const out = parseAttachmentsFromContent(raw);
      expect(out.length).assertEqual(1);
      expect(out[0].previewUrl).assertEqual('');
    });
  });
}
