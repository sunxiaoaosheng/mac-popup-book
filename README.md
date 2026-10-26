# mac-popup-book

基于 MacBook 铰链角度的互动绘本工程。当前独立应用为《林间小屋》；保留纸雕场景、角色互动、手动预览与静音选项。

需要 macOS 14+、Apple Silicon，以及 Xcode 16+（Swift 6+工具链，Swift 5语言模式）。无需额外 Metal 编译组件；无需屏幕录制、辅助功能或麦克风权限。

```bash
bash scripts/build.sh       # 打包到 build/林间小屋.app
bash scripts/run.sh         # 打开应用，未构建时先构建
bash scripts/test.sh        # 确定性单元测试
bash scripts/check.sh       # 格式、模块边界、测试、打包
bash scripts/integration.sh # 本机图形、窗口、真实角度检查，会短暂显示窗口
```

在应用内关闭“跟随屏幕”可手动预览；35°收合、105°展开，支持80°～120°校准。声音默认关闭；窗口进入后台或最小化时暂停。应用标识与已有校准/声音设置保持兼容。

## 代码组织

- `Modules/`：核心协议与规则、通用运行调度、macOS适配、SceneKit通用表现。
- `Characters/PaperCat/`：纸猫行为与渲染，互为独立编译模块。
- `Apps/ForestCabin/`：林间小屋应用、场景和运行资源。
- `Tests/`：规则、角色、替换协议与几何命中的确定性检查。
- `Tools/`：显式本机检查与资源生成工具。

`Package.swift` 是模块与编译配置的唯一来源。依赖从具体内容/平台指向核心；通用运行层不认识猫或 SceneKit。新增角色实现 `BookCharacter` 与匹配的 `CharacterPresenter`，声明必需锚点，再在应用组装处注册。接口与目录规则见 `AGENTS.md`。

本机检查的日志不代表所有机型兼容；传感器枚举/读取、模拟通知、几何命中与物理合盖体验应分别核验。项目不阻止系统正常睡眠。
