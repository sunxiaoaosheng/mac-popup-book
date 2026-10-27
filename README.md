# mac-popup-book

基于MacBook铰链角度的互动立体书。正式应用目前只发布《林间小屋》，采用整书主程序与每页XPC（应用内进程通信服务）独立进程。离页即停止业务、释放画面和声音资源，允许空闲服务由系统回收，避免频繁重启限速。其余五个主题仍是产品规划，不包含正式新场景。

需要Apple Silicon、macOS14+及Xcode/Swift工具链；当前本机验证使用Swift6.4、Swift5语言模式。无需屏幕录制、辅助功能或麦克风权限，正常使用不需要Blender。

```bash
bash scripts/build.sh                       # 严格构建已发布整书
bash scripts/run.sh                         # 打开 build/林间小屋.app
bash scripts/test.sh                        # 公共确定性测试
bash scripts/check.sh                       # 格式、边界、语言、公共/发布页测试、签名打包
python3 scripts/page.py list                # 发现本地可开发场景
python3 scripts/page.py check forest-cabin  # 单页测试，不编译其他页面
python3 scripts/page.py preview forest-cabin # 手动展开、临时存储的独立预览
python3 scripts/page.py new pocket-town     # 创建场景模板，不会启用发布
bash scripts/integration.sh                # 无窗口后台进程、故障与离屏渲染检查
```

`Modules`管理共享协议、运行、平台、渲染、进程通信与Worker适配；`Apps/BookHost`只负责整书界面和组装；`Scenes/<id>`含场景、角色、素材、测试与独立包；`Book/published-pages.json`由集成者维护。场景分支不修改根包注册。接口与Cursor/Codex协作见[工程契约](docs/engineering/PAGE_CONTRACT.md)和[研发流程](docs/engineering/SCENE_WORKFLOW.md)。

《林间小屋》保持既有应用标识local.ssr.forestbook、校准与声音设置、resident.json相处记忆。35°收合、默认105°展开，可校准80°～120°；后台、最小化和睡眠暂停。真实呼噜声来源及加工指纹在该页的Assets与Resources/Audio中；其他历史声音仍为合成素材。界面跟随系统简体中文或英文，不支持的语言回退英文。改变语言后重开应用。

`Scenes/forest-cabin`保留角色行为和表现分模块；按钮与角色提供的选项键快捷操作均通过通用页面动作接入。目录、前后页和手势由整书控制，不与角度开合混用。页面失败提供重试和目录，普通进程崩溃或卡死不应拖垮其他页面；不承诺隔离驱动、系统或整机资源耗尽。

开发预览使用独立应用标识、临时目录、手动角度和静音。正式主程序才读取真实铰链、设置和存档。`build/build-receipt.json`记录打包后的文件指纹和本地源码基线，不代表已推送或完成人工体验验收。

三维猫与骨骼实验完整保留在`Experiments/VolumeCat`，不进入正式注册。其独立包可运行原OffscreenCheck、AssetCheck等工具，例如：

```bash
swift run --package-path Experiments/VolumeCat -c release OffscreenCheck 3600
bash scripts/check-cat-candidate.sh # 可选，需要现有Blender环境
```

旧单场景界面代码在`Experiments/LegacyForestApp`作为历史参考，不进入新主程序；原可构建基线可从Git提交b69ce03与a4b40ec恢复。`Tools/IsolationProbe`为跨进程技术样件；正式工程验收使用整书测试配置，不将纯色样件成绩冒充森林场景成绩。

自动调试默认不弹窗、不抢焦点；前台效果与真实开合验收须集中安排。后台验收程序打包在build/后台验收-*.app，仅以无窗口命令行程序运行，不访问用户设置与真实存档。
