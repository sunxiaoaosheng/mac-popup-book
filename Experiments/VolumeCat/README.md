# 可选立体猫与资产实验

本目录保留原第二阶段的实验和工具，不被整书注册或正式构建依赖。需要现有Blender时使用根目录的check-assets.sh、check-cat-candidate.sh；独立Swift包可直接构建/运行OffscreenCheck、CandidateSceneCheck、PlaybackCheck、AssetCheck、RealityAssetCheck。

实验输出仍在根目录忽略的build下。在根目录运行 `swift run --package-path Experiments/VolumeCat -c release OffscreenCheck 3600`。资产不存在时部分图形测试按既有规则跳过；不得将跳过当作资产验收成功。

纸猫与森林库依赖Scenes/forest-cabin的公开产品，共享能力依赖根包；没有复制第二套角色或场景源码。
