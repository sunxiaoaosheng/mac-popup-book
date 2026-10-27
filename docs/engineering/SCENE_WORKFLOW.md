# 场景研发与集成

## 工具分工

Cursor负责场景实现、测试与修复；Codex主要做需求拆解、公共契约审查、构建/体验验收及必要修复。工具都从本仓库文件读取规则，不要求访问彼此聊天记录，也不自动派发编辑器任务。

共同入口为AGENTS.md、PAGE_CONTRACT.md、本文以及统一脚本。Cursor规则只引用它们。产品计划和人工体验资料保存在研究目录，工程契约、模板和自动测试纳入版本管理。

## 独立工作目录

从验收过的main创建 `scene/<id>` 分支，并使用独立Git工作目录；例如在仓库根执行：

```bash
git worktree add ../mac-popup-book-town -b scene/pocket-town main
cd ../mac-popup-book-town
python3 scripts/page.py new pocket-town
python3 scripts/page.py check pocket-town
python3 scripts/page.py preview pocket-town
```

单页预览为独立应用、默认手动展开、使用临时存储且声音默认关闭。真实硬件验证在正式主程序单独进行；两个开发者不应在同一工作目录写文件。

场景分支默认仅修改Scenes/<id>。不要更改共享包注册、主程序或发布清单；公共接口不足时先提交单独的底座变更，所有开发分支更新基线后再使用。

`Templates/Page`包含纯行为模块、独立Worker与测试，生成后必须替换名称和完善中英文文案。仅契约测试页可保留testOnly=true；正式场景须移除，禁止正式服务接受故障注入。

## 交接内容

使用TASK_HANDOFF_TEMPLATE.md填写：目标和非目标、允许修改范围、基线提交、契约版本、可复现命令、验收项、代码提交、结果、证据位置、已知限制。不得把“编译通过”写成真实操作或视觉试听通过。

## 合并检查

1. 场景行为测试、资源来源、中英文、开合三态与可取消交互通过。
2. `python3 scripts/page.py check <id>`和预览打包通过。
3. Codex/人工按任务验收，核对实际提交，不仅采信开发工具总结。
4. 集成者合并场景，并单独更新Book/published-pages.json；同次集成严格检查发布列表，不静默跳过失败页。
5. `bash scripts/check.sh`和本机进程集成检查在合并后的代码再次运行。
6. 本地合并与远程推送分开；未经明确授权不推送、不强制覆盖历史。

格式检查可能需要在自己的场景目录执行swift format；全仓格式入口用于集成，不能借格式化修改其他开发分支的文件。
