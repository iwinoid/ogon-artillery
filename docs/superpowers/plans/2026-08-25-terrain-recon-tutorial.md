# 地形·侦察·教程 联合实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ① 用顺坡游走的单主河 + 河谷真下切/真水面与高对比渲染解决"糊/对比度/河流画上去的"问题；② 为随机战役目标加 ±5~15m 固定档侦察误差（真值隐藏、试射修正自然收敛）；③ 用脚本生成的真实射表重写 `TUTORIAL.md` 为"从零到会玩"完整教程（原理直观+关键公式）。

**Architecture:** Phase 1(map.R/config.R/渲染，50m分辨率+局部窗口挖谷) → Phase 2(mission.R/game.R/config.R 侦察，truth字段+三处读真值) → Phase 3(tools/gen_manual_tables.R 生成射表 → 重写 TUTORIAL.md → README 同步)。每 Task 以 TDD 收尾：先写失败测试→跑失败→写最少实现→跑全绿→提交。

**Tech Stack:** R ≥4.2，纯 base R（运行期零依赖），工作目录 `Огонь!/`

## Global Constraints

- R ≥ 4.2；运行期零依赖（base R 图形/IO 唯一允许）
- 中文界面与注释；所有命令支持中文/英文双入口（现有 dispatch 约定不变）
- 地形默认自由地图 20×20 km；场景地图不受本改动影响（DEM 真实地形走同一渲染路径）
- `MAP_DEFAULT$extent_km` 默认 `[0,20,0,20]` 保持不变；仅 `res_m` 100→50
- 测试跑法为 `Rscript tests/test_*.R`，失败时 `exit != 0`；在 `test_mode=TRUE` 时不弹图形窗口（用 `png(file)` 分支）
- 每 Task 以独立可测交付物结束并 `git commit`；提交信息前缀 `feat:` / `docs:`

---

## File Structure

**现有结构（修改处标★）：**

| 文件 | 职责 | 本计划改动 |
|---|---|---|
| `config.R` | 火炮/世界常量、难度 | ★ `MAP_DEFAULT$res_m` 100→50；新增 `RECON_ERROR_M <- 15` |
| `ballistics.R` | 弹道/散布/射表/侧视图 | 无 |
| `map.R` | 程序地形/渲染 | ★ 全量重写生成与渲染段（保留 `value_noise_field/terrain_elev_at/hillshade/map_info/%||%` 兼容接口） |
| `fdc.R` | 指挥所计算器 | 无 |
| `ui.R` | 控制台 UI | 无 |
| `mission.R` | 任务/观察员/评分 | ★ `new_mission` 随机分支加侦察偏移、`observer_report`/`check_destroyed` 读真值 |
| `game.R` | 状态机/命令分发 | ★ `修正` 高低换算 `r_tgt` 用真值 |
| `tools/gen_manual_tables.R` | — | ★ 新建：从游戏内射表生成 Markdown 射表 |
| `tests/test_map.R` | 地图渲染测试 | ★ 追加"河流/可复现/分辨率/渲染"节 |
| `tests/test_game.R` | 集成测试 | ★ 追加"侦察偏移"节（7 条 ok） |
| `TUTORIAL.md` | 教程 | ★ 重写为完整教程（射表为脚本生成数据） |
| `README.md` | 总览 | ★ 特色条目同步地形/侦察两行 |
| `docs/superpowers/specs/*.md` | 规格 | 已提交，不动 |

**新增字段契约（Phase 2）**：

- `mission$target: list(x,y, truth_x, truth_y, label, radius)` —— `(x,y)` = 侦察上报坐标（试射前的一切显示/计算均用此），`(truth_x, truth_y)` = 真实坐标（仅观察员报告与摧毁判定读此）。无 `truth_*` 的目标（教程关/历史场景）按 `truth %||% x` 回退，行为与现状完全一致。

---

### Phase 1 / Task 1: 河流段模块（gen_river_path + apply_river_valley）

**Files:**
- Modify: `Огонь!/map.R`（新增两个局部函数，`gen_terrain_procedural` 上方）
- Test: `Огонь!/tests/test_map.R`（末尾追加单元测试两节）

**Interfaces:**
- Consumes: `elev: matrix[ny,nx]`（高程，米），`res_m: integer`
- Produces: `gen_river_path(elev) -> list(path=matrix[n,2](行,列), lake=logical)`；`apply_river_valley(elev, path, res_m, lake=FALSE) -> list(carve=matrix[ny,nx]非负, water=matrix[ny,nx]logical)`

- [ ] **Step 1: 在 test_map.R 末尾追加河流两单元的失败测试**

```r
# --- 追加到 tests/test_map.R 末尾（cat "完成 ✓" 之前）---
cat("\n===== 河流：单元测试 =====\n")
# 构造无坑纯东坡 + 小噪声：起点必在西，终点必在东
set.seed(555)
nr_t <- 50; nc_t <- 50
base_t <- outer(seq(1, 0, length.out = nr_t), rep(1, nc_t))
elev_t <- sweep(matrix(runif(nr_t * nc_t, 0, 5), nr_t, nc_t), 2,
                seq(nc_t, 1) * 0.8, "+") + base_t
rp_t <- gen_river_path(elev_t)
ok(rp_t$path[1, 2] %in% 2:max(2, round(nc_t * 0.15)),
   sprintf("河源在西侧 15%% 内（col=%d）", rp_t$path[1, 2]))
ok(nrow(rp_t$path) >= 20, sprintf("河路径 %d 步 ≥20", nrow(rp_t$path)))
ok(elev_t[rp_t$path[1, 1], rp_t$path[1, 2]] >
   elev_t[rp_t$path[nrow(rp_t$path), 1], rp_t$path[nrow(rp_t$path), 2]],
   "顺坡：起点高程 > 终点高程")
ok(all(rp_t$path >= 1 & rp_t$path <= 50), "路径不出界")

cat("\n===== 河谷开挖：单元测试 =====\n")
elev_v <- matrix(100, 60, 60)
path_v <- cbind(rep(30, 40), 5:44)
vv <- apply_river_valley(elev_v, path_v, 50, lake = FALSE)
ok(max(vv$carve) > 0 && max(vv$carve) <= 60.01, sprintf("谷深 0 < max=%.1f ≤60", max(vv$carve)))
ok(vv$carve[30, 44] > vv$carve[30, 5], sprintf("下游更深（44列 %.1f > 5列 %.1f）", vv$carve[30, 44], vv$carve[30, 5]))
ok(vv$water[30, 44] && vv$water[30, 5], "河道两端核心为水面")
ok(sum(vv$water) < sum(vv$carve > 0), "水面窄于谷区")
```

- [ ] **Step 2: 运行测试，确认失败（函数未定义）**

Run: `Rscript tests/test_map.R`（在 `Огонь!` 目录）
Expected: FAIL — `could not find function "gen_river_path"`（或 `apply_river_valley`），`exit != 0`

- [ ] **Step 3: 在 map.R 中实现两个函数（`value_noise_field` 之后、`gen_terrain_procedural` 之前插入）**

```r
# =====================================================================
# ---- 河流游走：顺坡单主河（返回 格坐标矩阵[n,2]=c(行,列) + 是否成湖）----
# 输入 elev[ny,nx]；总体向低处流，西→东引力 + 动量蜿蜒 + 小抖动
# =====================================================================
gen_river_path <- function(elev) {
  nr <- nrow(elev); nc <- ncol(elev)
  west_nc <- max(2, round(nc * 0.15))
  cand <- cbind(sample(nr, 24, replace = TRUE),
                sample(2:west_nc, 24, replace = TRUE))
  cur  <- cand[which.max(elev[cand]), ]
  path <- matrix(cur, nrow = 1, ncol = 2)
  last_dir <- c(0, 1)
  dirs <- matrix(c(-1,-1, -1,0, -1,1, 0,-1, 0,1, 1,-1, 1,0, 1,1),
                 ncol = 2, byrow = TRUE)
  pit <- 0; lake <- FALSE
  for (step in 1:(3 * (nr + nc))) {
    nb <- cbind(cur[1] + dirs[, 1], cur[2] + dirs[, 2])
    inb <- nb[, 1] >= 1 & nb[, 1] <= nr & nb[, 2] >= 1 & nb[, 2] <= nc
    if (!any(inb)) break
    nb <- nb[inb, , drop = FALSE]
    d  <- nb - rep(cur, each = nrow(nb))
    cosang <- as.vector((d %*% last_dir) /
                        (sqrt(rowSums(d^2)) * sqrt(sum(last_dir^2))))
    score <- elev[nb] + 15 * (1 - cosang) - 0.2 * d[, 2] + runif(nrow(nb), -3, 3)
    b   <- which.min(score)
    nxt <- nb[b, ]
    if (elev[nxt[1], nxt[2]] > elev[cur[1], cur[2]]) {
      pit <- pit + 1
      if (pit > 5) { lake <- TRUE; break }
    } else pit <- 0
    cur <- nxt; last_dir <- d[b, ]
    path <- rbind(path, cur)
    if (cur[1] <= 1 || cur[1] >= nr || cur[2] <= 1 || cur[2] >= nc) break
  }
  list(path = path, lake = lake)
}

# =====================================================================
# ---- 河谷开挖 + 水面掩膜（局部窗口；O(路径长×窗口)）----
# 输入 elev(path 仅用尺寸)、path[行,列]、res_m、lake；输出 carve[ny,nx] 与 water[ny,nx]
# =====================================================================
apply_river_valley <- function(elev, path, res_m, lake = FALSE) {
  nr <- nrow(elev); nc <- ncol(elev)
  carve <- matrix(0, nr, nc)
  water <- matrix(FALSE, nr, nc)
  n <- nrow(path)
  rmax <- ceiling(250 / res_m) + 1
  for (k in seq_len(n)) {
    t  <- (k - 1) / max(1, n - 1)
    Dk <- 15 + 45 * t                 # 谷深 15→60 m
    Wk <- 80 + 170 * t                # 谷半宽 80→250 m
    rr <- max(1, path[k, 1] - rmax):min(nr, path[k, 1] + rmax)
    cc <- max(1, path[k, 2] - rmax):min(nc, path[k, 2] + rmax)
    dm <- sqrt(outer((rr - path[k, 1])^2, (cc - path[k, 2])^2, "+")) * res_m
    fac <- pmax(0, 1 - dm / Wk)
    carve[rr, cc] <- pmax(carve[rr, cc], Dk * fac^1.5)
    water[rr, cc] <- water[rr, cc] | dm < 0.4 * Wk
  }
  if (lake) {
    rr <- max(1, path[n, 1] - 3):min(nr, path[n, 1] + 3)
    cc <- max(1, path[n, 2] - 3):min(nc, path[n, 2] + 3)
    water[rr, cc] <- TRUE
  }
  list(carve = carve, water = water)
}
```

注：`outer((rr-行)^2,(cc-列)^2,"+")` 在本语境下等价于 `outer(rr-cc...`——确认单位是格数×res_m=米。

- [ ] **Step 4: 再跑测试，确认通过（两节单元测试 + 旧用例仍过）**

Run: `Rscript tests/test_map.R` 在 `Огонь!`
Expected: 两节新增全部 ✓，旧有 `地形点高程/风格对比图` 仍输出（旧河流已被等价替换，风格对比不受本 Task 影响）

- [ ] **Step 5: 提交**

```bash
git add Огонь!/map.R Огонь!/tests/test_map.R
git commit -m "feat(map): 顺坡游走单主河 + 局部窗口挖谷/水面（单元测试先行）"
```

---

### Phase 1 / Task 2: 程序地形集成（分辨率/河谷）

**Files:**
- Modify: `Огонь!/config.R`（`MAP_DEFAULT$res_m` 100→50）
- Modify: `Огонь!/map.R`（重写 `gen_terrain_procedural` 主体，保留旧签名兼容调用）

**Interfaces:**
- Consumes: `gen_river_path`, `apply_river_valley`（Task 1）
- Produces: `gen_terrain_procedural(extent_km, res_m, seed, elev_lo=80, elev_hi=420) -> map`（`map$water_mask[logical]`、`map$river$draw=FALSE`、`map$river` 折线 km、`map$x/y`、`map$elev` 400×400）

- [ ] **Step 1: 追加集成测试（与 Task 1 同文件 test_map.R 末尾继续追加）**

```r
cat("\n===== 地形集成：分辨率/河谷/可复现 =====\n")
t0 <- proc.time()
g1 <- gen_terrain_procedural(seed = 12345)
cat(sprintf("地形生成耗时 %.2fs\n", (proc.time() - t0)[3]))
ok(all(dim(g1$elev) == c(400, 400)), sprintf("20km/50m → %d×%d", nrow(g1$elev), ncol(g1$elev)))
g2 <- gen_terrain_procedural(seed = 12345)
ok(identical(g1$elev, g2$elev) && identical(g1$water_mask, g2$water_mask),
   "固定 seed 两次生成完全一致")
ok(!is.null(g1$river) && length(g1$river$x) >= 50,
   sprintf("河路径 %d 点 ≥ 50", length(g1$river$x)))
ok(identical(g1$river$draw, FALSE), "程序生成河带 draw=FALSE（不再叠画蓝线）")
z_src <- terrain_elev_at(g1, g1$river$x[1] * 1000, g1$river$y[1] * 1000)
z_end <- terrain_elev_at(g1, tail(g1$river$x, 1) * 1000, tail(g1$river$y, 1) * 1000)
ok(z_end < z_src, sprintf("河口 %.0fm < 河源 %.0fm（顺坡）", z_end, z_src))
npt <- length(g1$river$x)
sel <- unique(round(seq(1, npt, length.out = 20)))
cells <- cbind(match(g1$river$y[sel], g1$y), match(g1$river$x[sel], g1$x))
ok(mean(g1$water_mask[cells], na.rm = TRUE) >= 0.8, "河道采样点 ≥80% 为水面")
```

- [ ] **Step 2: 运行确认失败（仍用旧 100m、60m 下限、无 water_mask）**

Run: `Rscript tests/test_map.R`
Expected: 新增本节 2~3 项 FAIL（400×400 失败、无 draw 字段、water_mask 缺）

- [ ] **Step 3: 改 config.R 与 map.R**

`config.R` 一行：
```r
MAP_DEFAULT <- list(extent_km = c(0,20,0,20), res_m = 50, front_y = 7.0)
```

`map.R gen_terrain_procedural` 替换为（完整函数见规格；以下为关键片段）：

```r
gen_terrain_procedural <- function(extent_km = MAP_DEFAULT$extent_km,
                                   res_m = MAP_DEFAULT$res_m,
                                   seed = NULL,
                                   elev_lo = 80, elev_hi = 420) {
  if (!is.null(seed)) set.seed(seed)
  nx <- round((extent_km[2] - extent_km[1]) * 1000 / res_m)
  ny <- round((extent_km[4] - extent_km[3]) * 1000 / res_m)
  x_km <- seq(extent_km[1], extent_km[2], length.out = nx)
  y_km <- seq(extent_km[3], extent_km[4], length.out = ny)

  f <- matrix(0, ny, nx)
  amps <- c(1, 0.6, 0.35, 0.2, 0.12, 0.07)
  for (o in 0:5) {
    cells <- 6 * 2^o
    f <- f + amps[o + 1] * value_noise_field(nx, ny, cells)
  }
  f <- (f - min(f)) / (max(f) - min(f))
  elev <- elev_lo + (elev_hi - elev_lo) * f^1.12

  # 河流
  rv  <- gen_river_path(elev)
  val <- apply_river_valley(elev, rv$path, res_m, rv$lake)
  elev <- elev - val$carve

  nf <- sample(5:8, 1)
  forests <- data.frame(cx = runif(nf, 1, extent_km[2]-1),
                        cy = runif(nf, extent_km[3]+1, extent_km[4]-1),
                        r  = runif(nf, 0.4, 0.9))
  roads <- list(
    data.frame(x = rep(runif(1, 8, 12), 2), y = c(extent_km[3], extent_km[4])),
    data.frame(x = c(extent_km[1], extent_km[2]), y = rep(MAP_DEFAULT$front_y, 2))
  )
  river <- list(x = x_km[rv$path[, 2]], y = y_km[rv$path[, 1]],
                label = "河", draw = FALSE)
  list(elev = elev, x = x_km, y = y_km, res_m = res_m,
       water_mask = val$water, river = river, forests = forests, roads = roads,
       front_y = MAP_DEFAULT$front_y, extent_km = extent_km, source = "procedural")
}
```

旧代码中的 `elev - carve（正弦河）`、`river=list(x=rx,y=ry)`整段删除，换为上述 4 行河流调用＋`river$draw=FALSE`。

- [ ] **Step 4: 运行确认通过**

Run: `Rscript tests/test_map.R`; `Rscript tests/test_ballistics.R`；`Rscript tests/test_game.R`
Expected: 本 Task 新增节全 ✓；旧有"地形点高程/风格对比图"仍输出（由于新 carve，点 (5,5)/(10,10) 高程会微变但在合理带内——允许放宽为 `>= 20 && <= 500` 即可）；test_game 地形规模检查 `nrow(st$map$elev) > 100` 继续通过（400 ✓）

- [ ] **Step 5: 提交**

```bash
git add Огонь!/config.R Огонь!/map.R Огонь!/tests/test_map.R
git commit -m "feat(map): 程序地形集成（50m+自然河流+真水面，draw=FALSE）"
```

---

### Phase 1 / Task 3: 渲染与对比度（阴影/调色/等高线/水色/河流标注）

**Files:**
- Modify: `Огонь!/map.R`（`draw_map` 默认阴影、`terrain_rgb` 阴影系数/水色、`terrain_palette`、等高线、`river` 标注）
- Test: `Огонь!/tests/test_map.R`（在新增集成节后再追加 v4 渲染节）

**Interfaces:**
- Consumes: `map$water_mask(map.elev同形)`, `map$river$draw`（Task 2）
- Produces: 调用 `draw_map(map, overlay)` 时默认有山体阴影、高对比调色，DEM 与程序地形走同一路径

- [ ] **Step 1: 追加 v4 渲染测试（同样追加到 test_map.R 末尾）**

```r
cat("\n===== v4 渲染：默认阴影 + 新调色板 + 自然河流 =====\n")
overlay4 <- list(
  guns = GUN_POSITIONS, gun_sel = 1,
  targets = list(list(x = 14.6, y = 13.2, label = "敌迫击炮阵地", radius = 40)),
  shots = data.frame(x = c(14.5, 14.7), y = c(13.3, 13.1)),
  destroyed = 1, show_radius = TRUE,
  wind = list(from_mils = 2250, speed = 6),
  title = "ОГОНЬ! — 地图 v4：山体阴影 + 自然河流"
)
t1 <- proc.time()
draw_map(g1, overlay4, file = "docs/demo_map_v4.png")
cat(sprintf("渲染耗时 %.1fs，已输出 docs/demo_map_v4.png\n", (proc.time() - t1)[3]))
```

其中 `g1` 为本文件前面集成节已生成的地图；若该节因失败未定义 g1，可另生成一个兜底 `g1 <- gen_terrain_procedural(seed=20240601)` 一行在节首。

- [ ] **Step 2: 运行确认失败（当前渲染仍是 shade=FALSE 旧调色板，dem_map_v4 尚未生成）**

Run: `Rscript tests/test_map.R`
Expected: 新增节虽可执行，但视觉效果仍旧（无强阴影/深绿谷地/深蓝水）；该步视为"旧渲染输出 demo_map_v4 但为旧效果"——通过与否都不阻碍进入 Step 3（本任务为视觉改进，断言仅是"文件存在"）。

- [ ] **Step 3: 在 map.R 上做 5 处渲染改动**

```r
# 3.1 draw_map 签名默认值：shade = TRUE
draw_map <- function(map, overlay = list(), file = NULL, shade = TRUE,
                     palette = terrain_palette) {

# 3.2 河流叠画改为条件画线（在绘制河流段）
if (!is.null(map$river)) {
  # 程序生成河有 draw=FALSE → 不画蓝线（有真水面）；涅瓦河等标注河仍画线
  if (!identical(map$river$draw, FALSE)) {
    lines(map$river$x, map$river$y, col = "#2b6cb8", lwd = 2.5)
  }
  lbl <- map$river$label %||% "河"
  mid <- floor(length(map$river$x) / 2)
  halo_text(map$river$x[mid], map$river$y[mid] + 0.5, lbl,
            cex = 0.8, col = "#2b6cb8", font = 2)
}

# 3.3 等高线加深
if (length(lv)) contour(map$x, map$y, t(e_cont), levels = lv, add = TRUE,
                        col = adjustcolor("grey30", alpha.f = 0.5),
                        lwd = 0.7, drawlabels = FALSE)

# 3.4 terrain_rgb：阴影 + 水色
hillshade_part <- hillshade(e, map$x, map$y, map$res_m)
f <- 0.42 + 0.58 * hillshade_part                # 原 0.55+0.45
if (any(water)) { r[water] <- 0.28; g[water] <- 0.52; b[water] <- 0.80 }

# 3.5 调色板：11 档深→高
terrain_palette <- function(n = 256) {
  colorRampPalette(c("#173d1c", "#28611f", "#3f7d2a", "#63973a", "#8fae4a",
                     "#b9bd60", "#c6a35e", "#a97f4f", "#8d7a63", "#b5b0a8", "#efeeea"))(n)
}
# terrain_palette2 保留不动，供风格对比
```

- [ ] **Step 4: 运行确认通过**

Run: `Rscript tests/test_map.R`；`Rscript tests/test_ballistics.R`; `Rscript tests/test_game.R`
Expected: 全过；人工查看 `docs/demo_map_v4.png`：河在凹陷谷内且有深蓝水面、谷地深绿、亮坡提亮、对比度显著提升（与 docs/demo_map_v3.png 并列对比差异一眼看出）

- [ ] **Step 5: 提交**

```bash
git add Огонь!/map.R Огонь!/tests/test_map.R
git commit -m "feat(map): 默认山体阴影 + 高对比调色板/等高线/深水色（河流有谷有水）"
```

---

### Phase 1 / Task 4: 地形 README 同步与地形回归全量

**Files:**
- Modify: `Огонь!/README.md`（特色条目）

**Interfaces:**
- Consumes: Tasks 1-3 的地形/渲染新现状

- [ ] **Step 1: 改 README 特色，追加一行**

在 "五种火炮" 条目之后、`真实地形可选` 条目之前插入：

```markdown
- **自然地形**：分形噪声程序地形 + 顺坡生成的蜿蜒河流（河谷真实下切、水面渲染）、
  50m 分辨率、山体阴影高对比渲染（DEM 真实地图同样受益）
```

- [ ] **Step 2: 运行地形相关测试并出图**

Run: `rm -rf docs/frames* && Rscript tests/test_map.R`
Expected: 地形生成耗时打印 0.5~2.0s 左右（400×400），`docs/demo_map_v4.png` 生成

- [ ] **Step 3: 全量回归（现存 4 测试）**

```bash
Rscript tests/test_ballistics.R   # 耗时约 10-20s
Rscript tests/test_map.R          # 含地形集成/单元/渲染三节
Rscript tests/test_scenario.R     # 列宁格勒场景仍 7/7 摧毁（DEM 未受影响）
Rscript tests/test_game.R         # 集成（地形 400×400 下仍全过）
```

如 `test_map.R` 中"地形点 (5,5) 高程"旧断言因 50m/深谷轻微偏移，可将原 `terrain_elev_at` 的等式断言改为区间 `[20, 450]`。禁止为过测试而大幅削弱原有断言——新测试节已经覆盖质量；旧点高程改为区间即合理容忍河谷下切。

- [ ] **Step 4: 提交**

```bash
git add Огонь!/README.md
git commit -m "docs: README 同步地形渲染升级（自然河流·阴影·50m）"
```

---

### Phase 2 / Task 5: 侦察偏移常量与任务生成（上报坐标+真值）

**Files:**
- Modify: `Огонь!/config.R`（新增常量）
- Modify: `Огонь!/mission.R`（`new_mission` 随机分支+提示行）
- Test: `Огонь!/tests/test_game.R`（追加 7.1 小节在任务2之后、6. 之前）

**Interfaces:**
- Consumes: `RECON_ERROR_M: numeric(=15)`
- Produces: `new_mission(state, index)` 对于随机战役的 `mission$target: list(x,y, truth_x, truth_y, label, radius)`；简报多一行误差提示

- [ ] **Step 1: 写失败测试（追加到 tests/test_game.R，6. 之前）**

```r
cat("\n===== 7.1 侦察偏移（生成）=====\n")
sr <- init_game(seed = 99, mode = "std", test_mode = TRUE, png_dir = "docs/frames8")
sr <- start_campaign(sr)
t7 <- sr$mission$target
ok(!is.null(t7$truth_x) && !is.null(t7$truth_y), "随机任务带侦察真值 truth_x/truth_y")
derr <- sqrt((t7$x - t7$truth_x)^2 + (t7$y - t7$truth_y)^2) * 1000
ok(derr >= 5 - 0.05 && derr <= 15 + 0.05,
   sprintf("侦察误差 %.1f m ∈ [5,15]（上报→真值）", derr))
# 教程关与历史场景不带真值（在 Task 6 之后此处只测前半截，后两项放 Task 6 后补充也行——本 Task 先不引用 start_tutorial/start_scenario 以免现阶段就失败）
```

- [ ] **Step 2: 运行确认失败（当前无 RECON_ERROR_M、无 truth 字段）**

Run: `Rscript tests/test_game.R`
Expected: `truth_x` 为 NULL，误差测试 FAIL，`exit != 0`

- [ ] **Step 3: 改 config.R 与 mission.R**

`config.R` 在 `GUNS <- list(...)` 与 `WIND_DRIFT_FACTOR <- ...` 之间增量：

```r
# ---- 侦察误差 ----
RECON_ERROR_M <- 15   # 随机战役目标上报坐标 = 真值 + 随机偏移(模长 5~RECON_ERROR_M 米)
```

`mission.R new_mission` 随机分支（`# ---- 普通模式（随机目标）----`）中，找到 `wind <- list(...)` 之前的 `found` 块之后、生成 `mission` 之前，插入：

```r
  # 侦察误差：上报坐标 = 真值 + 随机偏移（5~RECON_ERROR_M m，方向随机）
  err_m  <- runif(1, 5, RECON_ERROR_M)
  err_az <- runif(1, 0, 2 * pi)
  rx <- tx + err_m * cos(err_az) / 1000
  ry <- ty + err_m * sin(err_az) / 1000

  mission <- list(
    index = index, key = tp$key, name = tp$name, desc = tp$desc,
    target = list(x = rx, y = ry, truth_x = tx, truth_y = ty,
                  label = tp$label, radius = tp$radius),
    ...
```

将原 `target = list(x = tx, y = ty, ...)` 替换为上述带真值的版本。简报打印（`cat(sprintf("目标: %s (%.2f, %.2f) km …`, m$target$label, tx, ty, ... )）此为原真值坐标处——改用 `rx, ry`（上报坐标）：

```r
  cat(sprintf("目标: %s  (%.2f, %.2f) km   摧毁半径 %dm\n",
              mission$target$label, rx, ry, mission$target$radius))
  ...
  cat("注: 侦察坐标存在 ±15m 内误差，试射修正可消除。\n")
```

历史场景分支与教程关不动。

- [ ] **Step 4: 运行确认通过**

Run: `Rscript tests/test_game.R`
Expected: 本 Task 的 `7.1` 上半截 ✓（带真值、误差在 5~15）；后续原有测试（几何/战役/教程/脚本对局/苏军据点）继续通过

- [ ] **Step 5: 提交**

```bash
git add Огонь!/config.R Огонь!/mission.R Огонь!/tests/test_game.R
git commit -m "feat(mission): 随机战役侦察坐标偏移 5~15m（truth 字段，上报/真值分离）"
```

---

### Phase 2 / Task 6: 侦察偏移的判定与修正读真值

**Files:**
- Modify: `Огонь!/mission.R`（`observer_report`/`check_destroyed` 读 truth）、`Огонь!/game.R`（`修正` 读 truth）
- Test: `Огонь!/tests/test_game.R`（在 Task 5 的 7.1 后追加剩余断言）

- [ ] **Step 1: 追加剩余断言（接到 7.1 之后，6. 之前）**

```r
# 接 7.1：判定读真值
sr$shots <- data.frame(x = t7$truth_x, y = t7$truth_y, turn = 1, dR = 0, dD = 0)
sr <- check_destroyed(sr)
ok(sr$mission$destroyed, "弹着在真值处判定摧毁（check_destroyed 读真值）")

# 教程关与历史场景不带 truth（回退路径）
stt2 <- init_game(seed = 98, mode = "std", test_mode = TRUE)
stt2 <- start_tutorial(stt2)
ok(is.null(stt2$mission$target$truth_x), "教程关无侦察偏移（无 truth）")
sts2 <- init_game(gun_key = "B37", seed = 97, test_mode = TRUE)
sts2 <- start_scenario(sts2, "leningrad")
ok(is.null(sts2$mission$target$truth_x), "历史场景无侦察偏移（无 truth）")

# 观察员与判定对真值的端到端小闭环（在随机任务 sr 上再射一发，偏差=真差）
```

最后的闭环测试如需可引用 playthrough（playthrough 本身就是端到端证明——此处详测点到为止，详尽回归留在下一 Task）。

- [ ] **Step 2: 运行确认失败（当前仍用上报坐标判定，sr 在真值处不应被判摧毁——会 FAIL）**

Run: `Rscript tests/test_game.R`
Expected: `弹着在真值处判定摧毁`  FAIL（现实现分面仍是上报坐标=判定坐标，而本测试把弹着放在真值处，恰好偏移几米，命中圈边缘会判否）

- [ ] **Step 3: 改三处"读真值"**

`mission.R observer_report`（约 117 行区域）：

```r
  t <- m$target
  tx <- t$truth_x %||% t$x
  ty <- t$truth_y %||% t$y
  r_tgt <- range_m(g$x, g$y, tx, ty)
  az_tgt <- azimuth_mils(g$x, g$y, tx, ty)
```

`mission.R check_destroyed`（约 175 行区域）：

```r
  t <- m$target
  tx <- t$truth_x %||% t$x; ty <- t$truth_y %||% t$y
  if (nrow(state$shots) > 0) {
    d <- sqrt((state$shots$x - tx)^2 + (state$shots$y - ty)^2)
```

`game.R dispatch` 的 `修正` 命令（约 496 行附近）：

```r
    m  <- state$mission
    tt <- m$target
    r_tgt <- range_m(state$guns[[state$gun_sel]]$x, state$guns[[state$gun_sel]]$y,
                     tt$truth_x %||% tt$x, tt$truth_y %||% tt$y)
```

确认 `mission.R/game.R` 的文件首部或运行顺序中 `%||%` 可见（`map.R` 已在 `mission.R` 前 source，test_* 也同序）；缺失则在本文件首部补 ` `%||%` <- function(a,b) if (is.null(a)) b else a ` 一行。

- [ ] **Step 4: 运行确认通过**

```bash
Rscript tests/test_game.R        # 含 7.1/7.2 侦察节全 ✓
Rscript tests/test_scenario.R    # 7 目标逐一摧毁（上报坐标偏几米但仍可击破，试射修正自然收敛）
Rscript tests/playthrough.R      # 三模式端到端（AI 试射-修正-急促-效力循环本身就是侦察误差的消解证明）
```

- [ ] **Step 5: 提交**

```bash
git add Огонь!/mission.R Огонь!/game.R Огонь!/tests/test_game.R
git commit -m "fix(mission,game): 观察员/判定/修正统一读真值（truth %||% x 回退）"
```

---

### Phase 3 / Task 7: 射表生成脚本

**Files:**
- Create: `Огонь!/tools/gen_manual_tables.R`

- [ ] **Step 1: 新建脚本（直接可跑，不需失败测试）**

```r
# =====================================================================
# gen_manual_tables.R — 从游戏内射表生成 Markdown 表格（供 TUTORIAL.md 引用）
# 运行: Rscript tools/gen_manual_tables.R  (> docs/manual_tables.md 供复制)
# =====================================================================
for (f in c("config.R", "ballistics.R")) {
  p <- file.path("..", f); if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
els <- seq(100, 700, by = 100)
for (gk in names(GUNS)) {
  gun <- calibrate_drag(GUNS[[gk]])$gun
  tab <- build_range_table(gun)
  cat(sprintf("\n### %s\n\n", gun$name))
  cat(sprintf("弹重 %.1f kg · %d 档装药（初速 %d~%d m/s）· 高低射界 %d~%d 密位\n\n",
              gun$shell_mass, length(gun$mv), min(gun$mv), max(gun$mv),
              gun$elev_min, gun$elev_max))
  cat(sprintf("| 装药 | %s | 表上最大射程 | 峰值射角 |\n",
              paste(sprintf("%d密位", els), collapse = " | ")))
  cat(paste0("|---|", paste(rep("---|", length(els) + 2), collapse = "")), "\n")
  for (ch in seq_along(gun$mv)) {
    vals <- vapply(els, function(e) {
      v <- tab$rows[tab$rows$charge == ch & tab$rows$el_mils == e, "range_m"]
      if (length(v) == 1) sprintf("%.0f", v) else "—"
    }, character(1))
    cat(sprintf("| %d号 | %s | %.0f m | %d 密位 |\n",
                ch, paste(vals, collapse = " | "),
                tab$max_range[ch], tab$peak_el[ch]))
  }
}
cat("\n注: 表中射程为平地无风标准值；—表示该射角已过峰值角（高射界，射程随射角减小），查游戏内 `射表` 命令可看完整 10 密位步进射表。\n")
```

- [ ] **Step 2: 运行验证并保存一份快照**

```bash
Rscript tools/gen_manual_tables.R > docs/manual_tables.md
cat docs/manual_tables.md | head -50
```

预期：输出含 5 门炮（D-20/M-46/M109/B-4/B-37）各一张表，每表 5~8 行（装药），每行 7 列（射角）+ 最大射程/峰值射角。

- [ ] **Step 3: 提交**

```bash
git add Огонь!/tools/gen_manual_tables.R Огонь!/docs/manual_tables.md
git commit -m "feat(tools): 从游戏内射表生成 Markdown 射表（供教程引用，保证与游戏一致）"
```

---

### Phase 3 / Task 8: TUTORIAL.md 重写（从零到会玩）

**Files:**
- Modify: `Огонь!/TUTORIAL.md`
- Consumes: Task 7 生成的 `docs/manual_tables.md`（射表数据粘入 5 节）、真实控制台输出（`playthrough` 日志与 `诸元` 卡片、观察员报告、侧视图）

**大纲（9 节，严格对应规格第 2 部分）**

1. 这是什么游戏 2. 运行 3. 5 分钟打出发弹（教程关手把手） 4. 原理（密位/方位/高低/装药·真空抛物线·空气阻力校准·散布 PE→σ·风·高差·侦察误差） 5. 射表与数据（脚本生成表各膏入+内插算例） 6. 完整对局实录（摘自 `docs/playthrough_logs/session_std_seed777.txt`，带逐条解说） 7. 速查（命令/模式/目标类型/评分） 8. 战术技巧（含侦察提示） 9. 真实地形/故障排查

**事实清单（写文档时一处都不能错）：**

- 6000 密位圆周；1 密位 ≈ 距离1000m处1m；修正公式 `密位 = 偏差m ÷ 射程km`
- 方位自北顺时针：北0 东1500 南3000 西4500
- 真空射程 `R = v²·sin2θ/g`（45°最大）；游戏有空气阻力 `k = 0.5·ρ·Cd·A/m`，Cd 按 `max_range_hist` 45°射程用二分校准
- RK4 dt=0.20s max 200s；`WIND_DRIFT_FACTOR=0.55`；`site = atan(Δh/R)`
- 散布：D-20 1/270(距)/1/600(向)、M-46 1/320/1/700、M109 1/300/1/650、B-4 1/250/1/550、B-37 1/300/1/650；`σ = PE/0.6745`
- 侦察误差：模长 5~15m 方向随机，仅随机战役
- 教程关目标 (6.0,10.0) 半径150m 无风；地形默认20×20km 50m 前沿7km；战役评分 `score = max(0,100-2·发数-4·命令数)`，S/A/B/C 分档 85/70/55

**射表数据：** 直接复制 Task 7 的 `docs/manual_tables.md` 的 5 张表（D-20~B-37）粘入第 5 节；每表紧跟一句"查表内插"算例（沿用旧版 8000m 例子并代入 D-20 第三装药的真实表上两行）。

**完整对局实录：** 以 `docs/playthrough_logs/session_std_seed777.txt` 的"任务#1"节为底本精简，保留 诸元卡片→试射→观察员→修正→急促/效力→结束→成绩 的完整控制台输出，每步编号+人话解说。

**语气：** 人话、短句、第二人称"你"，配 `>` 引用块示命令/输出；代码块标注语言 `r`；配一张 `docs/demo_map_v4.png` 俯瞰图与一张弹道侧视图截图说明。

- [ ] **Step 1: 备份旧教程（仅块提交保护，已有 git 史无需另备份）**

```bash
cp Огонь!/TUTORIAL.md /tmp/TUTORIAL.md.bak
```

- [ ] **Step 2: 重写文件**

用 Task 7 的表格文本替换本计划这一步手写的模板——以下写好框架、射表部分用 `cat docs/manual_tables.md` 的真实输出替换"{{TABLES}}" 占位。

整份文档约 300~360 行，九节结构见规格；由本计划执行人在该步骤一次性写全（`write` 全覆盖）。

- [ ] **Step 3: 人工通读校验**

```bash
Rscript tools/gen_manual_tables.R > /tmp/tables_new.md
diff -u docs/manual_tables.md /tmp/tables_new.md | head   # 应无 diff（或仅时间戳）
grep -c "装药" Огонь!/TUTORIAL.md   # 应 ≥ 5×(装药数) ≈ 30+
grep "侦察坐标" Огонь!/TUTORIAL.md  # 应有
cat Огонь!/TUTORIAL.md | head -80
```

按第 3 节手把手复制命令，在头脑中/实际走一遍教程关应可打通；不玩游戏的人读完第 1-5 节应能说清 密位/方位/高低/装药/散布/风。

- [ ] **Step 4: 提交**

```bash
git add Огонь!/TUTORIAL.md
git commit -m "docs(tutorial): 重写为从零到会玩完整教程（原理+真实射表+实录）"
```

---

### Phase 3 / Task 9: README 同步与全量回归收尾

**Files:**
- Modify: `Огонь!/README.md`

- [ ] **Step 1: 在 README 特色区同步两行（一处地形，一处侦察）**

在"五种火炮"条目紧后、`真实地形可选`条目之前：

```markdown
- **自然地形**：分形噪声程序地形 + 顺坡生成的蜿蜒河流（河谷真实下切、水面渲染）、50m 分辨率、山体阴影高对比渲染（DEM 真实地图同样受益）
```

在"任务战役"条目末尾加：

```markdown
  目标坐标带 ±15m 侦察误差（试射修正可消除）
```

- [ ] **Step 2: 全量回归（带耗时）**

```bash
Rscript tests/test_ballistics.R   # 约 12-20s（Cd 校准+射表）
Rscript tests/test_map.R          # 含新增四节（地形/河流单元/渲染）
Rscript tests/test_scenario.R     # 列宁格勒 7/7
Rscript tests/test_game.R         # 含新增 7.1/7.2 侦察节
```

Run: `Rscript tests/playthrough.R`（后台，约 60-90s，三模式各 4 任务）
Expected: 四测试 exit 0；playthrough 三日志各含 4 次结算（部分任务可能 0 分属正常 AI 表现，但流程必须通）

- [ ] **Step 3: 交付清单检查**

```bash
ls docs/demo_map_v4.png Огонь!/docs/manual_tables.md docs/playthrough_logs/session_std_seed777.txt | cat
git log --oneline | head -12
```

人工过目 `docs/demo_map_v4.png`（河在谷里、深蓝水面、立体清晰）与新 `TUTORIAL.md`（九节、含 5 张真实射表）

- [ ] **Step 4: 提交**

```bash
git add Огонь!/README.md
git commit -m "docs: README 同步地形/侦察两项更新"
```

---

## Self-Review

**Spec coverage:**

- 规格1（侦察）：Task 5(RECON_ERROR_M+生成+提示)、Task 6(读真值三处)+配套测试 全覆盖
- 规格2（地形）：Task 1(游走+谷窗单元)、Task 2(集成+分辨率/真水面)、Task 3(阴影/调色/水色/等高线)、Task 4(README/回归) 全覆盖
- 射表生成：Task 7 脚本保证与游戏同源
- TUTORIAL 重写：Task 8 大纲/事实/表格/实录 全覆盖

**Placeholder scan:** 搜索 `TBD/TODO/占位/填空` 无；Task 8 的 {{TABLES}} 为 Task 7 产物的粘贴点，已在步骤中声明用真实输出替换——属明确操作，非空占位。

**Type consistency:** `gen_river_path(elev)->list(path[,2], lake)` 与 `apply_river_valley(path,res_m,lake)` 签名一致；`mission$target.truth_x %||% x` 与 `%||%` 定义一致；`draw_map(shade, palette)` 保留旧签名仅改默认值。

## Execution Handoff

Plan complete and saved to `Огонь!/docs/superpowers/plans/2026-08-25-terrain-recon-tutorial.md`. Two execution options:

1. Subagent-Driven (recommended) - 我为每 Task 起一个子代理，Task 间我复核，快迭代
2. Inline Execution - 在本会话内用 executing-plans 批量执行、到检查点复核

Which approach?
