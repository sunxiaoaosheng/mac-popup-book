# mac-popup-book

基于 MacBook 铰链角度的互动绘本工程。当前独立应用为《林间小屋》；支持纸雕场景、靠近/轻抚/邀请、角色自主活动、相处记忆、手动预览与静音选项。

需要 macOS 14+、Apple Silicon，以及 Xcode 16+（Swift 6+工具链，Swift 5语言模式）。无需额外 Metal 编译组件；无需屏幕录制、辅助功能或麦克风权限。

```bash
bash scripts/build.sh       # 打包到 build/林间小屋.app
bash scripts/run.sh         # 打开应用，未构建时先构建
bash scripts/test.sh        # 确定性单元测试
bash scripts/check.sh       # 格式、模块边界、测试、打包
bash scripts/integration.sh # 本机图形、窗口、真实角度检查，会短暂显示窗口
bash scripts/companion-check.sh 600 # 受控十分钟渲染与动作检查，交互为代码注入
bash scripts/check-assets.sh       # 可选：已有Blender时验证骨骼资产导出及SceneKit导入
bash scripts/check-cat-candidate.sh # 可选：生成立体候选，验证四动作与三状态；不替换默认纸猫
```

当前本地版本0.1.1：场景铺满窗口，随窗口和全屏比例自动取景；猫放大，靠近与轻抚姿态增强，邀请立即回应并向用户方向走近。控制条可收起，菜单和快捷键仍可互动。

在应用内靠近小猫、按住缓慢移动可轻抚；也可使用“轻轻摸摸”“邀请靠近”按钮，或Option（选项键）+M / Option+I。角色会观察、理毛、换姿势和换位置；相处记忆保存在系统应用支持目录，损坏或版本不兼容时保留文件并提示。呼噜已采用Kerzoven的真实猫录音；猫叫、脚步、纸声和环境声仍为合成素材。来源和加工记录随应用资源一起打包。

在应用内关闭“跟随屏幕”可手动预览；35°收合、105°展开，支持80°～120°校准。声音默认关闭；窗口进入后台或最小化时暂停。应用标识与已有校准/声音设置保持兼容。

## 代码组织

- `Modules/`：核心协议与规则、通用运行调度、macOS适配、SceneKit通用表现。
- `Characters/PaperCat/`：纸猫行为与渲染，互为独立编译模块。
- `Apps/ForestCabin/`：林间小屋应用、场景和运行资源。
- `Tests/`：规则、角色、替换协议与几何命中的确定性检查。
- `Tools/`：显式本机检查与资源生成工具。

`Package.swift` 是模块与编译配置的唯一来源。依赖从具体内容/平台指向核心；通用运行层不认识猫或 SceneKit。新增角色实现 `BookCharacter` 与匹配的 `CharacterPresenter`，声明必需锚点，再在应用组装处注册。接口与目录规则见 `AGENTS.md`。

每次打包同时生成`build/build-receipt.json`，记录签名后可执行文件、应用文件清单与构建后工程源文件的SHA-256指纹，以及可用的Git基线/工作区状态。无Git元数据的源文件快照也能构建，凭据会明确标为无Git信息。该文件帮助辨认本地版本，不表示已提交或通过人工验收。

本机检查的日志不代表所有机型兼容；传感器枚举/读取、模拟通知、几何命中与物理合盖体验应分别核验。项目不阻止系统正常睡眠。`CompanionCheck`报告渲染更新回调频率与间隔，不等同屏幕显示帧率或GPU耗时，也不代替用户相处验收。Blender仅用于可选资产预检，正常构建应用不需要安装。

立体候选输出位于忽略目录`build/cat-candidate/`；可编辑源、导入检查和书页三状态预览一并生成。候选仅具备四个基础片段，部分行为使用替代动作，尚未作为正式角色交付。生成过程使用隔离的Blender后台进程，不加载用户插件；校验失败保留原候选。

`swift run OffscreenCheck 3600`测量离屏GPU（图形处理器）成本；追加`--candidate`可测已有立体候选。`swift run OffscreenCheck 108000 --paced`按真实30分钟节拍重放纸猫互动与收合。此工具不显示窗口、不播放声音、不存储用户数据，报告不能替代窗口帧率或主观体验验收。

性能比较应统一使用`swift run -c release OffscreenCheck ...`的优化构建，并保留同等分辨率、抗锯齿和输入条件。默认`swift run`为调试构建，其CPU占用不能直接当作正式应用的数据。`swift run RealityAssetCheck`只检查同一候选文件在RealityKit（苹果另一套三维框架）中的结构导入，不代表完整后端比较通过。

`python3 Tools/AudioPipeline/prepare_cat_audio.py`从保留的CC0真实猫录音生成处理文件与无自动播放的本地试听页`build/audio-candidate/index.html`。原作者、许可与原始文件校验值位于`Characters/PaperCat/Assets/AudioSources/Kerzoven/`；脚本不会自动覆盖应用资源。正式呼噜的加工指纹见`Apps/ForestCabin/Resources/Audio/purr-source.json`。`ExportAudio`中的合成呼噜仅供历史原型重现，不应用它覆盖当前真实呼噜。

界面语言跟随 macOS 的语言偏好（含系统为本应用指定的语言），目前提供简体中文与英文；其他语言回退英文。更改语言后重新打开应用生效。界面、角色回应与错误提示的语言资源归各自模块管理，运行逻辑与存档不依赖文案。
