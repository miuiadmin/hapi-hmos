// 纯逻辑单测入口（LocalUnit 本地单元测试）—— 对照 chatcube entry/src/test/List.test.ets
// 运行：DevEco Studio「Local Test」，或命令行 hvigorw testLocal。
// 这里只挂载纯逻辑套件（无 ArkUI / 无 ohos.* 依赖）。
import diffTest from './Diff.test';
import checklistTest from './Checklist.test';
import reducerTest from './Reducer.test';
import messageTest from './Message.test';
import toolInputUtilsTest from './ToolInputUtils.test';
import syncEventTest from './SyncEvent.test';
import agentStateTest from './AgentState.test';
import typesTest from './Types.test';
import sseClientUtilsTest from './SSEClientUtils.test';
import hubClientUtilsTest from './HubClientUtils.test';
import chatSearchTest from './ChatSearch.test';

export default function testsuite() {
  diffTest();
  checklistTest();
  reducerTest();
  messageTest();
  toolInputUtilsTest();
  syncEventTest();
  agentStateTest();
  typesTest();
  sseClientUtilsTest();
  hubClientUtilsTest();
  chatSearchTest();
}
