# 地图观感改进实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让列宁格勒历史场景地图从「死绿糊片 + 方形留白 + 细网噪点」变成「裁剪对齐的宽幅全景 + 分位数对比度 + 自适应组件」的清晰作战图。

**Architecture:** 全部改动集中在 `map.R`（纯函数 + 渲染）与 `game.R`（start_scenario 裁剪、init_game 窗口尺寸）；TDD 先写纯函数测试（map_aspect / canvas_size / elev_norm01），再改渲染，最后场景裁剪与回归。每任务独立提交。

**Tech Stack:** R ≥4.2 纯 base R，项目目录 `Огонь!/`，git 仓库根 `../`。

## Global Constraints

- R ≥ 4.2；运行期零依赖（base graphics/IO 唯一允许）
- 中文注释与界面文本；测试跑法 `Rscript tests/test_*.R`，失败 `quit(status=1)`（test_map.R 用 ok() 即 `quit(status=1)`）
- 现有接口签名不变：`draw_map(map, overlay, file, shade, palette)`、`terrain_rgb(map, palette, shade)`
- 调色板与 hillshade 系数不变（对比图已验证）；仅归一化方式、画布尺寸、网格/标注步长、场景入口改动
- 20×20 km 程序地图的所有输出必须**逐像素不变**（回归底线：`map_aspect=1`、`canvas_size=(1000,1000)`、k=1、网格 1km 与现状一致）

---

## File Structure

| 文件 | 改动 |
|---|---|
| `map.R` | 新增 `map_aspect` / `canvas_size` / `elev_norm01`；`terrain_rgb` 换分位数拉伸；`draw_map` 画布取 canvas_size、网格步长自适应、标注 k 缩放、图例 0.55 |
| `game.R` | `init_game` 窗口宽高按 map_aspect；`start_scenario` DEM 裁剪 + 剔除越界 places |
| `tools/render_leningrad.R` | 已存在（上轮建）；本轮复跑输出 `docs/ln_v2.png` 供人工复核 |
| `tests/test_map.R` | 新增「画布/归一化/场景裁剪」节 |
| `README.md` / `TUTORIAL.md` | 特色/已知限制/第 9 节同步 |

---

### Task 1: 纯函数 map_aspect / canvas_size / elev_norm01

**Files:**
- Modify: `Огонь!/map.R`（新增三个函数，`terrain_rgb` 之前）
- Test: `Огонь!/tests/test_map.R`（末尾追加节，用现有 ok() 风格）

**Interfaces:**
- Produces: `map_aspect(map) -> numeric`；`canvas_size(aspect, base_h=1000) -> c(w,h)`；`elev_norm01(e, land, lo=0.02, hi=0.98) -> matrix[ny,nx]`

- [ ] **Step 1: 测试先行（追加到 test_map.R `cat("完成 ✓\n")` 之前）**

```r
cat("\n===== 画布与归一化：纯函数 =====\n")
m_A <- list(extent_km = c(0, 20, 0, 20), elev = matrix(100, 10, 10))
ok(abs(map_aspect(m_A) - 1) < 1e-9, "20×20 方图 aspect=1")
m_W <- list(extent_km = c(12, 76, 0, 44), elev = matrix(100, 10, 10))
ok(abs(map_aspect(m_W) - 64/44) < 1e-9, "列宁格勒 aspect=64/44")
cs <- canvas_size(64/44)
ok(cs[1] > cs[2] && cs[1] >= 700 && cs[1] <= 1500, sprintf("宽幅画布 %dx%d", cs[1], cs[2]))
ok(identical(canvas_size(1), c(1000, 1000)), "方图 1000×1000 不变")
set.seed(3)
v <- c(0:100, 500); land <- rep(TRUE, length(v)); land[length(v)] <- FALSE
zq <- elev_norm01(v, land)
zmm <- (v - min(v)) / (max(v) - min(v))
ok(median(zq[1:101]) >= 5 * median(zmm[1:101]), sprintf("分位数拉伸拉开低带（med %.2f vs %.2f）", median(zq[1:101]), median(zmm[1:101])))
ok(all(zq[!land] == 0), "水面归一化=0（防污染调色盘）")
ok(max(zq[land]) <= 1 && min(zq[land]) >= 0, "分位数结果在 [0,1]")
```

- [ ] **Step 2: 运行确认失败（函数未定义）**

Run: `Rscript tests/test_map.R`
Expected: `could not find function "map_aspect"`，exit≠0

- [ ] **Step 3: 实现三个纯函数（map.R，`# ---- 调色板 ----` 之前）**

```r
# ---- 地图宽高比（x 跨度 / y 跨度，>1 为宽幅图）----
map_aspect <- function(map) {
  ext <- map$extent_km
  (ext[2] - ext[1]) / (ext[4] - ext[3])
}

# ---- 画布尺寸：宽幅图给宽画布（宽 clamp 700~1500，高固定 base_h）----
canvas_size <- function(aspect, base_h = 1000) {
  w <- round(base_h * aspect)
  w <- max(700, min(1500, w))
  c(w, base_h)
}

# ---- 高程归一化：分位数 2%~98% 拉伸（低带自动拉开；水面置 0；样本 <100 退化为 min-max）----
elev_norm01 <- function(e, land, lo = 0.02, hi = 0.98) {
  z <- matrix(0, nrow(e), ncol(e))
  n <- sum(land)
  if (n >= 100) {
    q <- as.numeric(quantile(e[land], c(lo, hi)))
    z[land] <- pmin(1, pmax(0, (e[land] - q[1]) / (q[2] - q[1] + 1e-9)))
  } else if (n > 0) {
    elo <- min(e[land]); ehi <- max(e[land])
    z[land] <- if (ehi > elo) (e[land] - elo) / (ehi - elo) else 0
  }
  z
}
```

- [ ] **Step 4: 运行确认通过**

Run: `Rscript tests/test_map.R`
Expected: 新节 6 项全 ✓，旧节不变

- [ ] **Step 5: 提交**

```bash
git add Огонь!/map.R Огонь!/tests/test_map.R
git commit -m "feat(map): 纯函数 map_aspect/canvas_size/elev_norm01（分位数拉伸，TDD）"
```

---

### Task 2: terrain_rgb 换分位数归一化

**Files:**
- Modify: `Огонь!/map.R` `terrain_rgb`（现 elo/ehi/e01 块 219~224 行附近）

**Interfaces:**
- Consumes: `elev_norm01`（Task 1）
- Produces: `terrain_rgb(map, palette, shade)` 行为不变，仅 20km 图应逐像素不变（归一化线此前 min-max，新函数对 20×20 图 80~420m 用分位数 2%~98% → 输出略有差异，属预期改进；测试只断言接口不破）

- [ ] **Step 1: 直接改 terrain_rgb（此改动有对比图背书，无需先写失败测试；回归由全量测试兜底）**

旧代码：

```r
  e01 <- matrix(0, nrow(e), ncol(e))
  if (any(land)) {
    elo <- min(e[land]); ehi <- max(e[land])
    if (ehi > elo) e01[land] <- (e[land] - elo) / (ehi - elo)
  }
  idx <- round(e01 * 255) + 1
```

替换为：

```r
  e01 <- elev_norm01(e, land)
  idx <- round(e01 * 255) + 1
```

- [ ] **Step 2: 验证不破坏**

Run: `Rscript tests/test_map.R && Rscript tests/test_ballistics.R && Rscript tests/test_game.R`
Expected: 全 exit=0（test_map 的 demo_map_v3/map_styles 输出变化属预期；test_game 只查维度>100 不查像素）

- [ ] **Step 3: 提交**

```bash
git add Огонь!/map.R
git commit -m "feat(map): terrain_rgb 分位数 2%~98% 归一化（低带提亮，对比图 B）"
```

---

### Task 3: draw_map 画布自适应 + 网格步长 + 标注缩放 + 图例

**Files:**
- Modify: `Огонь!/map.R` `draw_map`

**Interfaces:**
- Consumes: `map_aspect` / `canvas_size`（Task 1）
- Produces: `draw_map(map, overlay, file, shade, palette)`：file 给定时画布尺寸随地图 aspect；网格/刻度/标注/图例自适应

- [ ] **Step 1: 实现（一次到位，视觉改进有图背书）**

```r
# 函数体开头（file 分支）：
if (!is.null(file)) {
  cs <- canvas_size(map_aspect(map))
  png(file, width = cs[1], height = cs[2], res = 110)
}
```

```r
# 坐标轴块（现 lstep/maj/min 三行）替换为：
  d <- ext[2] - ext[1]
  step <- if (d <= 30) 1 else if (d <= 60) 2 else 5
  lstep <- step
  maj <- seq(ceiling(ext[1]), floor(ext[2]), by = lstep)
  min <- seq(ceiling(ext[1]), floor(ext[2]), by = 1)
```

```r
# 标注缩放（halo_text 定义后、地形底色前加入）：
  k <- max(0.55, min(1.15, 20 / d))

# 公里格网块（现 for (g in seq(ceiling(ext[1]), floor(ext[2]))) abline(v=g...)）替换为：
  for (g in seq(ceiling(ext[1]), floor(ext[2]), by = step)) abline(v = g, col = gray(0.85), lty = 3)
  for (g in seq(ceiling(ext[3]), floor(ext[4]), by = step)) abline(h = g, col = gray(0.85), lty = 3)
```

```r
# 标注 cex 缩放：把下面各处的 cex 乘 k（据点 0.62*k 原文为 0.55/0.9/0.75/0.8 等，均匀乘 k 即可，
# 据点 cex=0.55 加倍到 0.62 由 h*绘制；统一约定）：
# - 据点 places: cex = 0.55 * k
# - 目标 label:  cex = 0.8 * k
# - 炮位 label:  cex = 0.75 * k
# - 城市/水域/河/战线/风标/弹着/已摧毁 原有 cex 全部乘 k
# - halo_text 内部偏移 0.07 改为 0.004 * d（调用处传 dx/dy 参数无需变，改 halo_text 内两行）
halo_text <- function(x, y, labels, cex, col, ...) {
  h <- 0.004 * d
  for (dx in c(-h, 0, h)) for (dy in c(-h, 0, h)) {
    if (dx == 0 && dy == 0) next
    text(x + dx, y + dy, labels, cex = cex, col = "white")
  }
  text(x, y, labels, cex = cex, col = col, ...)
}
```

```r
# 图例 cex 0.65 改为 0.55，并乘 k 的平方根（大图小字、小图大字）：
legend("bottomright", ..., cex = 0.55 * sqrt(k), ...)
```

注意：`d` 在 halo_text 词法闭包内可见（halo_text 定义于 draw_map 内、`d` 在函数前部定义）——确认顺序：`d` 定义放在 halo_text 定义**之前**。

- [ ] **Step 2: 验证**

Run: `Rscript tests/test_map.R > /tmp/tm.log 2>&1; echo exit=$?; tail -8 /tmp/tm.log`
Expected: exit=0；`docs/demo_map_v4.png` 仍 1000×1000（20km 方图），文件成功写出

- [ ] **Step 3: 提交**

```bash
git add Огонь!/map.R
git commit -m "feat(map): 画布自适应宽幅 + 网格/刻度/标注/图例随图幅缩放"
```

---

### Task 4: start_scenario 裁剪 DEM + 剔除越界据点；init_game 窗口比例

**Files:**
- Modify: `Огонь!/game.R`

**Interfaces:**
- Consumes: `map_aspect`（Task 1）
- Produces: `start_scenario` 后 `map$extent_km == sc$extent_km`（DEM 分支）；`init_game` 窗口宽高随 aspect

- [ ] **Step 1: 测试先行（test_map.R 追加，不依赖渲染设备）**

```r
cat("\n===== 场景裁剪 =====\n")
stx <- init_game(gun_key = "B37", test_mode = TRUE)
stx <- start_scenario(stx, "leningrad")
ok(identical(stx$map$extent_km, c(12, 76, 0, 44)), "场景地图 extent 裁剪为 64×44")
ok(!any(sapply(stx$map$places, function(p) p$x < 12 || p$x > 76 || p$y < 0 || p$y > 44)),
   "越界据点已剔除")
ok(any(sapply(stx$map$places, function(p) p$label == "普尔科沃高地·苏军")), "范围内据点保留")
ok(abs(map_aspect(stx$map) - 64/44) < 1e-9, "裁剪后 aspect=64/44")
```

注意：此节需 `init_game/start_scenario`（来自 game.R/mission.R），test_map.R 目前只 source config/map/ballistics——需在文件头部追加 source（见 Step 2 失败后 Step 3 实现说明）。

- [ ] **Step 2: 运行确认失败**

Run: `Rscript tests/test_map.R`
Expected: 截断在 source 报错或 `extent_km` 仍为 6.5~81.5（未裁剪），exit≠0

- [ ] **Step 3: 实现**

test_map.R 头部 source 行改为：

```r
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f); if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
```

game.R `start_scenario` DEM 分支（`map <- load_dem_cache(dem_file)` 之后、`map$water <- NULL` 之前）加裁剪：

```r
  # DEM 裁剪到场景范围（下载缓存常比场景大，避免目标/炮位偏置与空旷区）
  ext <- sc$extent_km
  cx <- which(map$x >= ext[1] & map$x <= ext[2])
  cy <- which(map$y >= ext[3] & map$y <= ext[4])
  if (length(cx) > 1 && length(cy) > 1) {
    map$elev <- map$elev[cy, cx, drop = FALSE]
    if (!is.null(map$water_mask)) map$water_mask <- map$water_mask[cy, cx, drop = FALSE]
    map$x <- map$x[cx]; map$y <- map$y[cy]
    map$extent_km <- c(min(map$x), max(map$x), min(map$y), max(map$y))
    map$res_m <- map$res_m
  }
```

`map$places` 吸附循环后加剔除（放在 `map$front_y <- NULL` 附近）：

```r
  # 剔除场景范围外的标注据点（上轮大 DEM 让它们"溜进"了视野；裁剪后回到地图外）
  keep <- sapply(map$places, function(pl) {
    pl$x >= map$extent_km[1] && pl$x <= map$extent_km[2] &&
      pl$y >= map$extent_km[3] && pl$y <= map$extent_km[4]
  })
  if (!all(keep)) {
    cat(c_red(sprintf("（%d 个标注据点在地图范围外，已不进图）\n", sum(!keep))))
  }
  map$places <- map$places[keep]
```

`init_game` 设备创建（非 RStudio 分支）替换：

```r
    } else {
      asp <- map_aspect(map)
      w <- if (asp >= 1.3) 14.5 else 11.5
      h <- if (asp >= 1.3) 10 else 11.5
      if (.Platform$OS.type == "windows") state$dev_map <- windows(width = w, height = h)
      else state$dev_map <- x11(width = w, height = h)
    }
```

（现结构是 windows/x11 分两行；换成上面单分支即可。）

- [ ] **Step 4: 验证**

Run: `Rscript tests/test_map.R && Rscript tests/test_scenario.R && Rscript tests/test_game.R`
Expected: 全 exit=0；场景节 4 项 ✓；列宁格勒 7 目标仍全毁

- [ ] **Step 5: 提交**

```bash
git add Огонь!/game.R Огонь!/tests/test_map.R
git commit -m "feat(game): 场景 DEM 裁剪对齐+越界据点剔除；窗口尺寸随地图幅面"
```

---

### Task 5: 渲染复核 + 文档同步 + 全量回归

**Files:**
- Modify: `Огонь!/README.md`、`Огонь!/TUTORIAL.md`；复跑 `tools/render_leningrad.R`

- [ ] **Step 1: 重跑场景渲染出 v2 图**

```bash
Rscript tools/render_leningrad.R > docs/ln_run2.log 2>&1
cp docs/frame_001.png docs/ln_v2.png
```

人工复核 `docs/ln_v2.png`：64×44 全景、宽幅画布、分位数对比度、网格 5km、标注重叠改善。

- [ ] **Step 2: README 同步（三处）**

特色区「自然地形」条目后追加：

```markdown
- **自适应地图**：画布/窗口宽高比随地图幅面（20×20 方图、64×44 宽幅）、
  网格与刻度密度随幅宽自适应、高程分位数色带（低地对比度不再糊）
```

已知限制区追加：

```markdown
- 列宁格勒 DEM 存在疑似瓦片接缝伪影（湾内对角线暗线、x≈55 竖向暗线），已记录待修复
```

- [ ] **Step 3: TUTORIAL.md 第 9 节追加一句（放在故障排查前）**

```markdown
地图按幅面自动调整画布比例与网格密度；列宁格勒场景已按 64×44km 裁切对齐（历史 DEM 缓存范围比场景大）。
```

- [ ] **Step 4: 全量回归**

```bash
rm -rf docs/frames*
Rscript tests/test_ballistics.R; echo $?
Rscript tests/test_map.R; echo $?
Rscript tests/test_scenario.R; echo $?
Rscript tests/test_game.R; echo $?
Rscript tests/playthrough.R; echo $?
```

Expected: 全 0；且 20km 方图 `docs/demo_map_v4.png` 尺寸仍 1000×1000。

- [ ] **Step 5: 提交**

```bash
git add Огонь!/README.md Огонь!/TUTORIAL.md Огонь!/docs/ln_v2.png Огонь!/tools/render_leningrad.R
git commit -m "docs(map): 自适应地图说明+DEM 伪影记录；场景渲染复核图"
```

---

## Self-Review

**Spec coverage:** 第1节→Task1+3+4（画布/窗口/裁剪/剔除）；第2节→Task1+2；第3节→Task3；第4节→Task1(测试),Task4(场景测试),Task5(文档/回归)。无遗漏。

**Placeholder scan:** 无 TBD/TODO；所有代码块完整。

**Type consistency:** `map_aspect(map)`、`canvas_size(aspect, base_h=1000)->c(w,h)`、`elev_norm01(e,land,lo,hi)->matrix` 跨 Task 签名一致；`d`（幅宽 km）与 `step` 在 draw_map 内定义顺序：d/step → halo_text → 使用，已注明。

**Known deviation (已在设计批准时注明):** 20×20 程序地图 `terrain_rgb` 从 min-max 变分位数后，demo_map_v4/demo_map_v3 像素会轻微变化——仅影响演示图，不影响任何断言。

## Execution Handoff

Plan complete and saved to `Огонь!/docs/superpowers/plans/2026-08-29-map-polish.md`. Two execution options:

1. Subagent-Driven (recommended) - 我为每 Task 起独立子代理，Task 间我复核
2. Inline Execution - 本会话内执行，检查点复核

Which approach?
