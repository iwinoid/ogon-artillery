# 设计文档：地图观感改进（场景对齐 + 宽幅画布 + 分位数配色 + 自适应组件）

日期：2026-08-29
状态：设计四节已经用户批准（配色方向在对比图确认后批准；范围=B；DEM 伪影=记录不修）

## 背景

试玩列宁格勒历史场景（`tools/render_leningrad.R`）后确认地图观感问题清单：

1. DEM 实际范围 75×66 km（x 6.5~81.5，y -11~55）≠ 场景配置 64×44 km，目标/炮位挤在左半、右侧大片空绿、轴刻度溢出（x 轴显示到 97）
2. 1000×1000 方形画布装 64:44 宽幅地图 → 约 30% 上下留白、像素密度浪费
3. min-max 高程归一化：列宁格勒地表 80% 在 0~60m，全挤进调色板最暗的 1/4 → 绿糊一片（对比图 A）；分位数拉伸后（对比图 B）河谷/丘陵/沼泽层次全部现出
4. 1km 小网格在 64km 图上 64 条 → 全图细网噪点
5. 标注 3×3 白描边按固定 0.07km 偏移、固定字号，大图上描边细到不可见、左中区红字重叠
6. 图例 11 项 cex0.65 白块压内容
7. DEM 疑似瓦片接缝/水掩膜误判伪影（湾内对角线暗线、x≈55 竖直暗线）→ **本轮记录不修**

## 已确认决策

| 决策点 | 结论 |
|---|---|
| 范围 | B 完整方案（场景对齐+画布/窗口比例+分位数配色+网格/标注/图例自适应） |
| 配色 | 分位数 2%~98% 拉伸（对比图 B 胜出；若顶端过曝改用 3%~97%+软压缩，实现时以图为准） |
| 窗口 | 交互窗口按地图宽高比自定尺寸；RStudio 认可其窗格不可控，绘图区 asp=1 等比 + 用户可拖拽 |
| DEM 伪影 | 记录到 README 已知限制，另立后续任务 |

## 第 1 节：场景对齐 + 画布/窗口比例自适应

**map.R（新增纯函数，便于单测）**

```r
map_aspect <- function(map) {
  ext <- map$extent_km
  (ext[2] - ext[1]) / (ext[4] - ext[3])
}
canvas_size <- function(aspect, base_h = 1000) {
  w <- round(base_h * aspect)
  w <- max(700, min(1500, w))      # 20km 方图 → 1000; 64/44 → 1454×1000
  c(w, base_h)
}
```

**draw_map**：`file` 参数给定时宽高用 `canvas_size(map_aspect(map))`；交互设备不受影响（窗口由 init_game 定）。
**init_game**：非 RStudio 时按 `map_aspect` 建窗——宽图（aspect≥1.3）`x11(w=14.5,h=10)`，方图保持 11.5×11.5；windows() 同值。RStudio 分支不变（Plots 窗格外部可控，注释说明）。
**start_scenario**：DEM 加载后按 `sc$extent_km` 裁剪：subset x/y 索引（含边界 clamp），elev/water_mask 同步子集；随后 `map$places <- Filter(pl 在 extent 内)`，被剔除的据点（加特契纳/托斯诺 y=-10.5、克朗施塔特 x=7.0、谢斯特罗列茨克 y=47.8）打印一句提示；water_labels/城市/战线在范围内的保留。
程序生成回退分支已按 extent 生成，无需改。

## 第 2 节：分位数色带拉伸

**map.R**：`terrain_rgb` 中 min-max 换为：

```r
elev_norm01 <- function(e, land, lo = 0.02, hi = 0.98) {
  q <- quantile(e[land], c(lo, hi))
  z <- pmin(1, pmax(0, (e - q[1]) / (q[2] - q[1])))
  z[!land] <- 0
  z
}
```

调色板与 hillshade 系数维持现状（对比图 B 即此组合）；`e[land]` 少于 100 点时退化为 min-max（防 quantile 边界抖动）——写进函数注释。

## 第 3 节：网格 / 图例 / 标注自适应

- 网格步长（公里格网循环与 `lstep`）：幅宽 `d <- ext[2]-ext[1]`；d≤30→1km；d≤60→2km；d>60→5km；主轴刻度同 step。
- 标注：`k <- max(0.55, min(1.15, 20 / d))`；据点 `cex=0.62*k`、目标/炮位/城市 `cex≈1*k`（在现基数上乘 k）；白描边偏移 `0.004*d`（代替固定 0.07km）；`halo_text` 内偏移量按 k 传递。
- 图例 `cex = 0.65 → 0.55`，位置保持 bottomright。
- 不做标注碰撞检测/自动避让（YAGNI）。

## 第 4 节：测试与文档

**test_map.R 新增节：**
1. `map_aspect`：程序地形 20×20 → 1.0；构造 extent(12,76,0,44) 的 map → 64/44
2. `canvas_size(64/44)` 宽 > 高（1454 > 1000）；`canvas_size(1)` = (1000,1000)
3. `elev_norm01`：v=0:100 加 outlier 500 → 分位数中位数 ≥ 5×min-max 版本中位数（低带被拉开）；山顶过曝允许（clamp）
4. 场景裁剪：`init_game(B37)→start_scenario("leningrad")` 后 `map$extent_km == c(12,76,0,44)`；`map$places` 不包含 (19.4,-10.5) 等越界据点；elev 维度与范围一致
5. 渲染帧：draw_state 输出帧经 `canvas_size`（宽幅>高，函数级断言，不做 PNG 头解析——零依赖）

**回归**：test_ballistics / test_scenario / test_game 全绿；`tools/render_leningrad.R` 重跑出 `docs/ln_v2.png` 人工复核。
**README**：特色补“宽幅画布自适应 + 分位数色带 + 自适应网格”；已知限制补 DEM 接缝伪影记录。
**TUTORIAL.md**：第 9 节一句“地图按幅面自动调画布比例与网格密度”。

## 范围外（明确不做）

- DEM 伪影修复（记录，后续任务）
- 湿地专属色带
- 标注自动避让算法
- 交互窗口的响应式重设（RStudio 用户自行拖拽）
