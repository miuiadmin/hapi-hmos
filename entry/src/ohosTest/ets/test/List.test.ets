// ohosTest（设备端/ARunit）入口 —— 对照 chatcube entry/src/ohosTest/ets/test/List.test.ets
// 运行：DevEco Studio「ARunit / 设备测试」，或命令行 hvigorw testOhos。
// 这里只挂载「设备侧公开行为」套件：不依赖真 Hub，全部走确定性的早退分支 / 监听者管线。
//   网络相关逻辑（SSE 分帧、URL/审批 body 拼装、登录错误归类）已在 entry/src/test LocalUnit 覆盖。
import sseClientTest from './SSEClient.test';
import hubClientTest from './HubClient.test';
import hubIntegrationTest from './HubIntegration.test';

export default function testsuite() {
  sseClientTest();
  hubClientTest();
  hubIntegrationTest();   // 集成测试：需起 Hub，未起时自动跳过（见文件头手册）
}
