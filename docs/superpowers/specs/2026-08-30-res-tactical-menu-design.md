# 设计文档：分辨率提升 + 战术地图样式 + 主菜单重构

日期：2026-08-30
状态：四节设计已获用户批准；战术风格以预览图 `docs/style_tactical_A2.png`（50m 主曲线/100m 计曲线/3×3 平滑/轻阴影）为准

## 已确认决策

| 决策点 | 结论 |
|---|---|
| 分辨率 | 程序地形 50→25m（20km=800×800）；画布 base_h=clamp(ny×2.2,1000,1800)、宽 clamp(aspect×base_h,700,2200)、png res 150；DEM 源 150m 不变 |
| 战术风格 | 米黄纸底 `#f2ecd8` + 阴影 0.82+0.18 + 水墨蓝水 (0.58,0.74,0.88) + 平滑等高线（高差≥250m→25m/100m 计曲线，否则 50m/100m）+ 2km 浅灰点线网格 |
| 切换 | 命令 `地图样式 [战术/照片]`（无参=切换）+ 主菜单第 4 项；`state$map_style` 持久于本局 |
| 主菜单 | 1 开始战役→子菜单【1 遭遇战/2 史实战役/3 教程关/0 返回】；2 模式 3 火炮 4 地图样式 5 帮助 0 退出；旧关键字兼容（场景/scenario→史实列表、教程→教程关、开始→子菜单） |

## 改动清单

**config.R**：`MAP_DEFAULT$res_m = 25`（注释注明 25m）

**map.R**：
1. 新增 `smooth3(m)`：9 个移位副本求和 ÷9（3×3 均值，纯 base R）
2. 新增 `contour_step(map)`：`max(e)-min(e) >= 250 → 25 else 50`
3. `draw_map(map, overlay, file, shade=TRUE, palette=terrain_palette, style="photo")`：
   - 画布：base_h 按 `nrow(map$elev)*2.2` clamp(1000,1800)，宽 clamp(base_h×aspect,700,2200)，png res=150
   - `style=="tactical"`：地形底色用米黄纸底+阴影；水色 0.58/0.74/0.88；等高线用 `smooth3` 后的矩阵，主曲线 step、计曲线每 4 条(25m)或每 2 条(50m)，均为 100m 间隔，加粗带稀疏标注（drawlabels=TRUE, cex 0.45）；网格 2km 灰(0.8) lty3
   - `style=="photo"`：现状不变（含现 50m 等高线、1/2/5km 网格逻辑）
   - 说明：photo 现有网格 step 逻辑（1/2/5km）保留
4. 图例/标注/风标等在两种样式共用（tactical 下图例 cex 同 photo）

**game.R**：
1. `init_game`：`state$map_style <- "photo"`
2. `draw_state`：调用 `draw_map(..., style = state$map_style)` 透传
3. `dispatch` 新增 `地图样式`/`style`：可带参数（战术/tactical/照片/photo）或切换；切换后 `draw_state` 重绘

**ui.R（主菜单）**：
1. `menu_banner`：`1) 开始战役  2) 模式  3) 火炮  4) 地图样式  5) 帮助  0) 退出`
2. `dispatch_menu`：`1/开始/start` → `menu_campaign(state)`；`2/模式` → set_mode；`3/火炮` → set_gun；`4/地图样式/style` → toggle 样式（同步 cat 当前样式）；`5/帮助`；`0/退出`；旧关键字 `历史/场景/scenario/hist` → 直接进史实列表；`教程/tutorial` → start_tutorial
3. `menu_campaign`：`1 遭遇战 2 史实战役 3 教程关 0 返回`（史实列表复用现有 SCENARIOS 序号逻辑）
4. help_text 面板/命令提示行同步“地图样式”

**tests/test_map.R**：400×400 → 800×800 两处断言与文字；新增：`smooth3(matrix(5,...))` 恒等、噪声版均值<原（方差下降）；`contour_step` 两档；战术渲染 `draw_map(g1, overlay, file="docs/demo_tactical.png", style="tactical")` 输出成功

**tests/test_game.R**：
- 第 2 节菜单测试改为：`dispatch_menu(st,"4")` 样式photo→tactical（map_style 断言）→ 再切回；`"3"` 火炮循环（D20→M46→…→D20）；`"2"` 模式循环（std→hard→std）；`"1"` 开始战役→子菜单：先 `dispatch_menu(st,"0")` 返回验证，再 `"1"` 遭遇战进 start_campaign
- 教程关：`dispatch_menu(st, "1"); dispatch_menu(st, "3")`；史实：`dispatch_menu(st,"1"); dispatch_menu(st,"2"); dispatch_menu(st,"1")` 进 leningrad
- 保留旧关键字兼容测试：`dispatch_menu(st,"教程")` 直达教程关

**文档**：README 特色加“战术地图样式（米黄底+等高线可切换）+25m 分辨率高画布”；命令表加 `地图样式`；主菜单说明改新结构；TUTORIAL 第 2 节主菜单与第 7 节命令速查同步 + 第 9 节地图句式更新。

## 超出范围

- DEM 源数据重采样（150m 是下载分辨率）
- 标注自动避让、等高线注记自动化（本期只做计曲线稀疏标注）
- 作战单位/兵棋棋子动画

## 回归底线

20×20 程序地图 photo 风格观感除变细变清晰外不变；所有旧命令（含中英文别名）继续可用；tests 全绿 + playthrough 三模式全通。
