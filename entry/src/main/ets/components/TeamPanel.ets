import { TeamState, TeamMember, TeamTask, TeamMessage } from '../models/Types';
import { fs, paletteOf, PaletteColors, getThemeState } from '../theme/ThemeService';

// 会话内多 agent 团队面板（对照上游 web/src/components/TeamPanel.tsx）。
//   teamState 是 Session 的运行时字段（agent 自治上报，非 spawn 配置）——纯只读展示，无客户端改写。
//   由 ChatPage 在 session.teamState !== null 时渲染于消息列表上方（对照 SessionChat.tsx:556）。
// 结构（逐字对照上游）：
//   - 折叠头：👥 Team: {teamName} · {N} 成员（{M} 活跃）· {done}/{total} 任务   [▾/▲]
//   - 展开体：描述 / 成员 chips（状态点 active=绿·shutdown=红·余=灰）/ 任务行（状态图标+标题+[owner]）/ 最近消息（末 5 条）
// 状态色映射同上游：member 点 active→success·shutdown→error·余→textTertiary；task completed→success·in_progress→primary·blocked→error·余→textTertiary。

@ComponentV2
export struct TeamPanel {
  @Param teamState: TeamState = new TeamState();
  @Local expanded: boolean = false;

  private get c(): PaletteColors { return paletteOf(getThemeState().isDark); }

  // 成员状态点颜色：active→绿 / shutdown→红 / 余（idle·未知）→灰
  private memberDotColor(status: string): ResourceColor {
    if (status === 'active') { return this.c.success; }
    if (status === 'shutdown') { return this.c.error; }
    return this.c.textTertiary;
  }

  // 任务行文字色：completed→绿 / in_progress→主色(链接) / blocked→红 / 余(pending·未知)→提示灰
  private taskColor(status: string): ResourceColor {
    if (status === 'completed') { return this.c.success; }
    if (status === 'in_progress') { return this.c.primary; }
    if (status === 'blocked') { return this.c.error; }
    return this.c.textTertiary;
  }

  // 任务状态图标：completed☑ / in_progress▶ / blocked⚠ / 余☐
  private taskIcon(status: string): string {
    if (status === 'completed') { return '☑'; }
    if (status === 'in_progress') { return '▶'; }
    if (status === 'blocked') { return '⚠'; }
    return '☐';
  }

  // 活跃成员数（status==='active'）
  private activeMemberCount(): number {
    let n: number = 0;
    const list: TeamMember[] = this.teamState.members;
    for (let i = 0; i < list.length; i++) {
      if (list[i].status === 'active') { n = n + 1; }
    }
    return n;
  }

  // 已完成任务数（status==='completed'）
  private completedTaskCount(): number {
    let n: number = 0;
    const list: TeamTask[] = this.teamState.tasks;
    for (let i = 0; i < list.length; i++) {
      if (list[i].status === 'completed') { n = n + 1; }
    }
    return n;
  }

  // 头部计数文案："{N} 成员" + (活跃>0 ? "（{M} 活跃）" : "") + (任务>0 ? " · {done}/{total} 任务" : "")
  private headerCounts(): string {
    const total: number = this.teamState.members.length;
    let s: string = `${total} 成员`;
    const active: number = this.activeMemberCount();
    if (active > 0) { s = `${s}（${active} 活跃）`; }
    const tasks: number = this.teamState.tasks.length;
    if (tasks > 0) {
      s = `${s} · ${this.completedTaskCount()}/${tasks} 任务`;
    }
    return s;
  }

  // 最近消息：末 5 条（对照上游 messages.slice(-5)）。ArkTS 取子数组手写。
  private recentMessages(): TeamMessage[] {
    const all: TeamMessage[] = this.teamState.messages;
    const n: number = all.length;
    if (n === 0) { return []; }
    const start: number = n > 5 ? n - 5 : 0;
    const out: TeamMessage[] = [];
    for (let i = start; i < n; i++) {
      out.push(all[i]);
    }
    return out;
  }

  private toggle(): void {
    this.expanded = !this.expanded;
  }

  @Builder
  private MemberChip(member: TeamMember) {
    Row({ space: 5 }) {
      // 状态点（圆点；宽高 7，圆角 3.5）
      Row()
        .width(7)
        .height(7)
        .borderRadius(3.5)
        .backgroundColor(this.memberDotColor(member.status))
      Text(member.name)
        .fontSize(fs(12))
        .fontColor(this.c.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (member.agentType !== '') {
        Text(`(${member.agentType})`)
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .maxLines(1)
      }
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(10)
    .backgroundColor(this.c.surface)
    .margin({ right: 6, bottom: 6 })
  }

  @Builder
  private TaskRow(task: TeamTask) {
    Row({ space: 6 }) {
      Text(this.taskIcon(task.status))
        .fontSize(fs(12))
        .fontColor(this.taskColor(task.status))
      Text(task.title)
        .fontSize(fs(12))
        .fontColor(this.taskColor(task.status))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (task.owner !== '') {
        Text(`[${task.owner}]`)
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
      }
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  private MessageRow(msg: TeamMessage) {
    Row() {
      Text(`${msg.from} → ${msg.to}: `)
        .fontSize(fs(12))
        .fontColor(this.c.textPrimary)
      Text(msg.summary)
        .fontSize(fs(12))
        .fontColor(this.c.textTertiary)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
  }

  @Builder
  private SectionLabel(label: string) {
    Text(label)
      .fontSize(fs(11))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.c.textTertiary)
      .margin({ top: 6, bottom: 4 })
  }

  build() {
    Column() {
      // 折叠头（点击展开/收起，对照上游 header button）
      Row({ space: 6 }) {
        Text('👥').fontSize(fs(14))
        Text(`Team: ${this.teamState.teamName}`)
          .fontSize(fs(13))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.headerCounts())
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .maxLines(1)
        Text('▾')
          .fontSize(fs(11))
          .fontColor(this.c.textTertiary)
          .rotate({ angle: this.expanded ? 180 : 0 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .borderRadius(10)
      .backgroundColor(this.c.surface)
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.toggle(); })

      // 展开体（描述 / 成员 / 任务 / 最近消息）
      if (this.expanded) {
        Column() {
          if (this.teamState.description !== '') {
            Text(this.teamState.description)
              .fontSize(fs(12))
              .fontColor(this.c.textTertiary)
              .width('100%')
              .margin({ bottom: 4 })
          }

          if (this.teamState.members.length > 0) {
            this.SectionLabel('成员')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.teamState.members, (member: TeamMember) => {
                this.MemberChip(member)
              }, (member: TeamMember) => member.name)
            }
            .width('100%')
          }

          if (this.teamState.tasks.length > 0) {
            this.SectionLabel('任务')
            ForEach(this.teamState.tasks, (task: TeamTask) => {
              this.TaskRow(task)
            }, (task: TeamTask) => task.id !== '' ? task.id : task.title)
          }

          if (this.teamState.messages.length > 0) {
            this.SectionLabel('最近消息')
            ForEach(this.recentMessages(), (msg: TeamMessage, idx: number) => {
              this.MessageRow(msg)
            }, (msg: TeamMessage, idx: number) => `${idx}:${msg.from}>${msg.to}`)
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 8 })
        .margin({ top: 4 })
        .borderRadius(10)
        .backgroundColor(this.c.surface)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
  }
}
