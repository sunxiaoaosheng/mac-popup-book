# 独立场景模板

先实现 Sources/PageBehavior 的纯行为与测试，再实现 PageWorker 的画面适配。名称、文案、素材、声音和存档由本场景管理。仅测试样页保留 testOnly=true；正式场景应删除该属性，禁止启用故障注入。

在仓库根目录执行 `python3 scripts/page.py check __PAGE_ID__` 或 `python3 scripts/page.py preview __PAGE_ID__`。不要修改根包注册代码或发布清单；集成者在验收后更新发布清单。
