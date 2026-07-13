// GitParsers 纯逻辑单测 —— 对照 web src/lib/gitParsers.ts 行为。
// 覆盖 parseStatusSummaryV2（porcelain v2：branch/ordinary/untracked）、parseNumStat（含 binary '-'）、
//   createDiffStatsMap（rename newPath/oldPath）、buildGitStatusFiles（staged/unstaged 分流 + ±行数 + branch）、
//   normalizeNumstatPath（brace=> / plain=> / 无）、getFileStatus。

import { describe, it, expect } from '@ohos/hypium';
import {
  parseStatusSummaryV2,
  parseNumStat,
  createDiffStatsMap,
  buildGitStatusFiles,
  normalizeNumstatPath,
  getFileStatus
} from '../main/ets/chat/GitParsers';

export default function gitParsersTest(): void {
  describe('parseStatusSummaryV2', () => {
    it('parses branch headers + ordinary change + untracked', 0, () => {
      const out = parseStatusSummaryV2(
        '# branch.oid abc111\n' +
        '# branch.head main\n' +
        '# branch.upstream origin/main\n' +
        '# branch.ab +2 -1\n' +
        '1 .M N... 100644 100644 100644 a1b2c3 d4e5f6 src/foo.ts\n' +
        '? new.txt\n');
      expect(out.branch.head).assertEqual('main');
      expect(out.branch.upstream).assertEqual('origin/main');
      expect(out.branch.ahead).assertEqual(2);
        expect(out.branch.behind).assertEqual(1);
      expect(out.files.length).assertEqual(1);
      expect(out.files[0].index).assertEqual('.');
      expect(out.files[0].workingDir).assertEqual('M');
      expect(out.files[0].path).assertEqual('src/foo.ts');
      expect(out.notAdded.length).assertEqual(1);
      expect(out.notAdded[0]).assertEqual('new.txt');
    });

    it('returns empty summary for blank input', 0, () => {
      const out = parseStatusSummaryV2('   \n  ');
      expect(out.files.length).assertEqual(0);
      expect(out.notAdded.length).assertEqual(0);
      expect(out.branch.head).assertEqual('');
    });

    it('skips detached head as empty branch name', 0, () => {
      const out = parseStatusSummaryV2('# branch.head (detached)\n');
      expect(out.branch.head).assertEqual('(detached)');
    });
  });

  describe('parseNumStat', () => {
    it('parses added/deleted per file and aggregates', 0, () => {
      const s = parseNumStat('5\t2\tsrc/foo.ts\n10\t0\tREADME.md\n');
      expect(s.files.length).assertEqual(2);
      expect(s.files[0].insertions).assertEqual(5);
      expect(s.files[0].deletions).assertEqual(2);
      expect(s.files[0].changes).assertEqual(7);
      expect(s.files[0].binary).assertFalse();
      expect(s.insertions).assertEqual(15);
      expect(s.deletions).assertEqual(2);
      expect(s.changed).assertEqual(2);
    });

    it('marks binary files (- tab -)', 0, () => {
      const s = parseNumStat('-\t-\timage.png\n');
      expect(s.files.length).assertEqual(1);
      expect(s.files[0].binary).assertTrue();
      expect(s.files[0].insertions).assertEqual(0);
      expect(s.files[0].deletions).assertEqual(0);
    });

    it('ignores non-matching lines', 0, () => {
      const s = parseNumStat('garbage line\n5\t2\tok.ts\n');
      expect(s.files.length).assertEqual(1);
      expect(s.files[0].file).assertEqual('ok.ts');
    });
  });

  describe('createDiffStatsMap', () => {
    it('maps by file path', 0, () => {
      const s = parseNumStat('5\t2\tsrc/foo.ts\n');
      const m = createDiffStatsMap(s);
      const stat = m.get('src/foo.ts');
      expect(stat !== undefined).assertTrue();
      if (stat !== undefined) {
        expect(stat.added).assertEqual(5);
        expect(stat.removed).assertEqual(2);
      }
    });

    it('handles brace rename {old => new}', 0, () => {
      const s = parseNumStat('1\t1\tsrc/{old.ts => new.ts}\n');
      const m = createDiffStatsMap(s);
      expect(m.get('src/new.ts') !== undefined).assertTrue();
      expect(m.get('src/old.ts') !== undefined).assertTrue();
    });

    it('handles plain rename old => new', 0, () => {
      const s = parseNumStat('1\t1\told.ts => new.ts\n');
      const m = createDiffStatsMap(s);
      expect(m.get('new.ts') !== undefined).assertTrue();
      expect(m.get('old.ts') !== undefined).assertTrue();
    });
  });

  describe('buildGitStatusFiles', () => {
    it('splits staged/unstaged, maps numstat ±lines, branch, untracked', 0, () => {
      const status =
        '# branch.oid abc111\n' +
        '# branch.head main\n' +
        '# branch.ab +0 -0\n' +
        '1 .M N... 100644 100644 100644 a1 a2 src/foo.ts\n' +     // index='.' workingDir='M' → unstaged modified
        '1 M. N... 100644 100644 100644 a1 a2 README.md\n' +      // index='M' workingDir='.' → staged modified
        '? new.txt\n';                                             // untracked → unstaged
      const unstaged = '3\t1\tsrc/foo.ts\n';                       // foo +3/-1
      const staged = '10\t2\tREADME.md\n';                         // README +10/-2
      const r = buildGitStatusFiles(status, unstaged, staged);

      expect(r.branch).assertEqual('main');
      expect(r.totalStaged).assertEqual(1);
      expect(r.totalUnstaged).assertEqual(2);

      expect(r.stagedFiles[0].fileName).assertEqual('README.md');
      expect(r.stagedFiles[0].status).assertEqual('modified');
      expect(r.stagedFiles[0].isStaged).assertTrue();
      expect(r.stagedFiles[0].linesAdded).assertEqual(10);
      expect(r.stagedFiles[0].linesRemoved).assertEqual(2);

      expect(r.unstagedFiles[0].fileName).assertEqual('foo.ts');
      expect(r.unstagedFiles[0].filePath).assertEqual('src');
      expect(r.unstagedFiles[0].fullPath).assertEqual('src/foo.ts');
      expect(r.unstagedFiles[0].linesAdded).assertEqual(3);
      expect(r.unstagedFiles[0].linesRemoved).assertEqual(1);

      expect(r.unstagedFiles[1].fileName).assertEqual('new.txt');
      expect(r.unstagedFiles[1].status).assertEqual('untracked');
      expect(r.unstagedFiles[1].linesAdded).assertEqual(0);
    });

    it('skips untracked directory placeholders (trailing /)', 0, () => {
      const r = buildGitStatusFiles('# branch.head main\n? builddir/\n', '', '');
      expect(r.totalUnstaged).assertEqual(0);   // 目录占位被跳过
    });

    it('returns empty branch for detached', 0, () => {
      const r = buildGitStatusFiles('# branch.head (detached)\n', '', '');
      expect(r.branch).assertEqual('');
    });
  });

  describe('normalizeNumstatPath', () => {
    it('rewrites brace rename', 0, () => {
      const p = normalizeNumstatPath('src/{old.ts => new.ts}');
      expect(p.newPath).assertEqual('src/new.ts');
      expect(p.oldPath).assertEqual('src/old.ts');
    });

    it('rewrites plain rename', 0, () => {
      const p = normalizeNumstatPath('old.ts => new.ts');
      expect(p.newPath).assertEqual('new.ts');
      expect(p.oldPath).assertEqual('old.ts');
    });

    it('passes through plain path', 0, () => {
      const p = normalizeNumstatPath('src/foo.ts');
      expect(p.newPath).assertEqual('src/foo.ts');
      expect(p.oldPath).assertEqual('');
    });
  });

  describe('getFileStatus', () => {
    it('maps git status chars', 0, () => {
      expect(getFileStatus('M')).assertEqual('modified');
      expect(getFileStatus('A')).assertEqual('added');
      expect(getFileStatus('D')).assertEqual('deleted');
      expect(getFileStatus('R')).assertEqual('renamed');
      expect(getFileStatus('C')).assertEqual('renamed');
      expect(getFileStatus('?')).assertEqual('untracked');
      expect(getFileStatus('U')).assertEqual('conflicted');
      expect(getFileStatus('Z')).assertEqual('modified');   // 未知回退 modified
    });
  });
}
