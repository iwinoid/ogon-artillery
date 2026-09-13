# 分辨率+战术地图+主菜单实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 25m 网格 + 高分辨率画布解决"糊"；新增可切换的"战术地图"样式（米黄底+等高线）；主菜单重构为 开始战役→子菜单（遭遇战/史实/教程关）。

**Architecture:** 全部在 `map.R`（smooth3/contour_step/战术绘制分支/画布）、`game.R`（map_style 状态与命令）、`ui.R`（菜单）三文件内；TDD：先纯函数与接口测试，再渲染/菜单，最后文档。每 Task 独立提交。

**Tech Stack:** R ≥4.2 纯 base R，目录 `Огонь!/`，仓库根 `../`。

## Global Constraints

- R ≥ 4.2；零运行期依赖；中文界面文本；测试 `Rscript tests/test_*.R` 失败 `quit(status=1)`
- 既有签名兼容：`draw_map(map, overlay, file, shade, palette)` 追加参数 `style="photo"`；`canvas_size(aspect, base_h=1000)` 不变
- 旧命令/旧关键字（场景/scenario/教程/tutorial）继续可用；"t"/"p"/"s"/"w" 等单字母别名与现有命令冲突，**不得**为新命令复用
- photo 风格视觉除分辨率提升外不变；20km 程序地图 `demo_map_v4` 尺寸变 1760×1760 属预期

---

### Task 1: 25m 网格 + smooth3/contour_step 纯函数 + 画布/PNG 分辨率

**Files:**
- Modify: `Огонь!/config.R`（res_m 25）、`Огонь!/map.R`（smooth3/contour_step/canvas_size clamp/画布与 res）、`Огонь!/tests/test_map.R`

**Interfaces:**
- Produces: `smooth3(m) -> 同形矩阵`；`contour_step(map) -> 25|50`；`canvas_size` 上限 clamp 改 2200

- [ ] **Step 1: 测试先行（test_map.R 追加在"场景裁剪"节后、`cat("完成 ✓\n")` 前）**

```r
cat("\n===== 平滑/等高线步长/高分辨率画布 =====\n")
ok(all(dim(g1$elev) == c(800, 800)), sprintf("20km/25m → %d×%d", nrow(g1$elev), ncol(g1$elev)))
ok(all(smooth3(matrix(5, 10, 10)) == 5), "平滑：平地恒等")
set.seed(9)
nm <- matrix(runif(100), 10, 10)
ok(sd(smooth3(nm)) < sd(nm), sprintf("平滑降噪（sd %.2f < %.2f）", sd(smooth3(nm)), sd(nm)))
ok(contour_step(g1) == 25, "程序地形(340m高差)主线 25m")
ok(contour_step(stx$map) == 50, "列宁格勒(203m高差)主线 50m")
cs_hi <- canvas_size(1, base_h = 1760)
ok(identical(cs_hi, c(1760, 1760)), "画布 1760×1760 上限内")
# 场景地图 start_scenario 已生成 stx（前节）；demo 帧尺寸由 draw_map 内部决定，不在此断言
```

- [ ] **Step 2: 运行确认失败（当前 400×400、无 smooth3/contour_step）**

Run: `Rscript tests/test_map.R`
Expected: 若于前节后仍可运行，则首项 ✗；`could not find function "smooth3"` exit≠0（建议直接进入 Step 3，先实现纯函数再跑）

- [ ] **Step 3: 实现**

`config.R`：`res_m     = 50,` → `res_m     = 25,               # 地形栅格分辨率 (m)（25m 高清；生成约 1s）`

`map.R canvas_size` 上限：`w <- max(700, min(1500, w))` → `w <- max(700, min(2200, w))`

`map.R` 新增（放在 `map_aspect` 前）：

```r
# ---- 3×3 均值平滑（战术地图等高线用；边界按 clamp 复制）----
smooth3 <- function(m) {
  nr <- nrow(m); nc <- ncol(m)
  s <- matrix(0, nr, nc)
  for (dr in c(-1, 0, 1)) for (dc in c(-1, 0, 1)) {
    sh <- m
    if (dr < 0) sh <- rbind(m[2:nr, , drop = FALSE], m[nr, , drop = FALSE])
    else if (dr > 0) sh <- rbind(m[1, , drop = FALSE], m[1:(nr - 1), , drop = FALSE])
    if (dc < 0) sh <- cbind(sh[, 2:nc, drop = FALSE], sh[, nc])
    else if (dc > 0) sh <- cbind(sh[, 1], sh[, 1:(nc - 1), drop = FALSE])
    s <- s + sh
  }
  s / 9
}

# ---- 战术地图等高线步长：高差 ≥250m 用 25m 主曲线，否则 50m ----
contour_step <- function(map) {
  e <- map$elev
  if (!is.null(map[["water_mask"]])) e <- e[!map[["water_mask"]]]
  if (diff(range(e, na.rm = TRUE)) >= 250) 25 else 50
}
```

`draw_map` 开头的画布块：

```r
  if (!is.null(file)) {
    base_h <- max(1000, min(1800, round(nrow(map$elev) * 2.2)))
    cs <- canvas_size(map_aspect(map), base_h = base_h)
    png(file, width = cs[1], height = cs[2], res = 150)
  }
```

- [ ] **Step 4: 运行验证**

Run: `Rscript tests/test_map.R`
Expected: 新节全 ✓（程序地形生成耗时约 0.5~1.5s）；旧节 800×800 相关沿用新断言

- [ ] **Step 5: 快速全量回归**

Run: `Rscript tests/test_ballistics.R && Rscript tests/test_game.R && Rscript tests/test_scenario.R`
Expected: exit=0（地形更大生成更慢，整体正常）

- [ ] **Step 6: 提交**

```bash
git add Огонь!/config.R Огонь!/map.R Огонь!/tests/test_map.R
git commit -m "feat(map): 25m 网格 + smooth3/contour_step + 画布 1760/150dpi"
```

---

### Task 2: 战术地图样式（draw_map 分支 + state + 命令 + 菜单入口）

**Files:**
- Modify: `Огонь!/map.R`, `Огонь!/game.R`, `Огонь!/tests/test_map.R`（战术渲染帧）

**Interfaces:**
- Produces: `draw_map(..., style="photo"|"tactical")`；`state$map_style`；命令 `地图样式 [战术/照片]`

- [ ] **Step 1: 先加渲染测试（test_map.R 末尾追加）**

```r
cat("\n===== 战术地图渲染 =====\n")
t5 <- proc.time()
draw_map(g1, overlay4, file = "docs/demo_tactical.png", style = "tactical")
ok(file.exists("docs/demo_tactical.png"), sprintf("战术图输出（%.1fs）", (proc.time() - t5)[3]))
ok(contour_step(g1) == 25, "战术主线 25m（程序图）")
```

- [ ] **Step 2: 运行确认失败（style 参数未实现，报 unused argument）**

Run: `Rscript tests/test_map.R`
Expected: `unused argument (style = "tactical")`，exit≠0

- [ ] **Step 3: 实现 draw_map 战术分支（三处）**

a) 签名：`draw_map <- function(map, overlay = list(), file = NULL, shade = TRUE, palette = terrain_palette, style = "photo") {`

b) 把 `rasterImage(terrain_rgb(map, palette, shade), ext[1], ext[3], ext[2], ext[4], interpolate = TRUE)` 替换为：

```r
  if (style == "tactical") {
    # 米黄纸底 + 轻阴影 + 水墨蓝水（预览 A2 风格）
    e0 <- map$elev
    wt <- if (!is.null(map[["water_mask"]])) map[["water_mask"]] else (is.na(e0) | e0 <= 0.5)
    if (!identical(dim(wt), dim(e0))) wt <- is.na(e0) | e0 <= 0.5
    fa <- 0.82 + 0.18 * hillshade(e0, map$x, map$y, map$res_m)
    ra <- fa; ga <- fa * 0.988; ba <- fa * 0.905
    ra[wt] <- 0.58; ga[wt] <- 0.74; ba[wt] <- 0.88
    arr <- array(c(ra, ga, ba), dim = c(nrow(e0), ncol(e0), 3))
    arr <- arr[nrow(e0):1, , , drop = FALSE]
    rasterImage(arr, ext[1], ext[3], ext[2], ext[4], interpolate = TRUE)
  } else {
    rasterImage(terrain_rgb(map, palette, shade), ext[1], ext[3], ext[2], ext[4], interpolate = TRUE)
  }
```

c) 等高线条：`if (length(lv)) contour(...)` 整块替换为：

```r
  if (style == "tactical") {
    es <- smooth3(e_cont)
    step_c <- contour_step(map)
    lv_c <- seq(ceiling(min(es, na.rm = TRUE) / step_c) * step_c, max(es, na.rm = TRUE), by = step_c)
    idx_c <- lv_c[seq_along(lv_c) %% (if (step_c == 25) 4 else 2) == 0]
    if (length(lv_c)) contour(map$x, map$y, t(es), levels = lv_c, add = TRUE,
                              col = adjustcolor("grey40", alpha.f = 0.6), lwd = 0.55,
                              drawlabels = FALSE)
    if (length(idx_c)) contour(map$x, map$y, t(es), levels = idx_c, add = TRUE,
                               col = "#3a3a3a", lwd = 1.15, drawlabels = TRUE,
                               cex = 0.45, labcex = 0.45, clabel = 0.6)
  } else if (length(lv)) {
    contour(map$x, map$y, t(e_cont), levels = lv, add = TRUE,
            col = adjustcolor("grey30", alpha.f = 0.5), lwd = 0.7, drawlabels = FALSE)
  }
```

d) 公里格网块替换为：

```r
  if (style == "tactical") {
    for (g in seq(ceiling(ext[1]), floor(ext[2]), by = 2)) abline(v = g, col = gray(0.8), lty = 3)
    for (g in seq(ceiling(ext[3]), floor(ext[4]), by = 2)) abline(h = g, col = gray(0.8), lty = 3)
  } else {
    for (g in seq(ceiling(ext[1]), floor(ext[2]), by = step)) abline(v = g, col = gray(0.85), lty = 3)
    for (g in seq(ceiling(ext[3]), floor(ext[4]), by = step)) abline(h = g, col = gray(0.85), lty = 3)
  }
```

- [ ] **Step 4: game.R 状态与命令**

`init_game` state 列表（`screen = "menu"` 附近）加：`map_style = "photo",`

`draw_state` 内三处 `draw_map(state$map, overlay)` / `draw_map(state$map, overlay)`（test 与 RStudio 分支）改为传入 `style = state$map_style`（`draw_map(state$map, overlay, style = state$map_style)`）。

`dispatch` 新增（放在"气象"块之后）：

```r
  # 地图样式切换（战术=米黄底+等高线 / 照片=现状）
  if (a %in% c("地图样式", "style", "sty", "战术", "照片", "tactical", "photo")) {
    v <- if (!is.null(arg(2))) tolower(arg(2)) else NULL
    if (!is.null(v) && v %in% c("战术", "tactical", "tact")) {
      state$map_style <- "tactical"
    } else if (!is.null(v) && v %in% c("照片", "photo", "photo", "phot")) {
      state$map_style <- "photo"
    } else {
      state$map_style <- if (state$map_style == "photo") "tactical" else "photo"
    }
    cat(sprintf("地图样式: %s（输入 地图 或任意射击后刷新）\n",
                if (state$map_style == "tactical") "战术（米黄底+等高线）" else "照片"))
    draw_state(state)
    return(state)
  }
```

- [ ] **Step 5: 验证**

Run: `Rscript tests/test_map.R > /tmp/t2.log 2>&1; echo exit=$?; tail -6 /tmp/t2.log`
Expected: 全 ✓；`docs/demo_tactical.png` 生成（人工查看确认与 A2 预览一致：米黄底/蓝水/优美等高线）

- [ ] **Step 6: 提交**

```bash
git add Огонь!/map.R Огонь!/game.R Огонь!/tests/test_map.R
git commit -m "feat(map): 战术地图样式（米黄底+等高线+水墨蓝水）+ 地图样式命令"
```

---

### Task 3: 主菜单重构（子菜单 + 新旧关键字兼容）

**Files:**
- Modify: `Огонь!/ui.R`（menu_banner/dispatch_menu/新增 menu_campaign/scenario_pick）、`Огонь!/tests/test_game.R`

**Interfaces:**
- Produces: `menu_campaign(state, commands=NULL) -> state`（子菜单，test_mode 下 commands 驱动）

- [ ] **Step 1: 实现 ui.R（置换 menu_banner 与 dispatch_menu 主体）**

```r
menu_banner <- function(state) {
  cls()
  cat(c_bold(c_cyan("  ══════════════════════════════\n")))
  cat(c_bold(c_cyan("     ОГОНЬ! 炮兵射击指挥所\n")))
  cat(c_bold(c_cyan("  ══════════════════════════════\n")))
  cat("   1) 开始战役        2) 模式\n")
  cat(sprintf("   3) 火炮：%s\n", state$gun$name))
  cat(sprintf("   4) 地图样式：%s\n", if (state$map_style == "tactical") "战术（等高线）" else "照片"))
  cat("   5) 帮助    0) 退出\n")
}

# ---- 开始战役子菜单：遭遇战 / 史实战役 / 教程关 ----
menu_campaign <- function(state, commands = NULL) {
  repeat {
    cat(c_bold("\n  ══ 开始战役 ══\n"))
    cat("   1) 遭遇战（随机战役）\n")
    cat("   2) 史实战役（历史场景）\n")
    cat("   3) 教程关（固定新手目标）\n")
    cat("   0) 返回\n请选择: ")
    if (!is.null(commands) && length(commands) > 0) {
      choice <- commands[1]; commands <- commands[-1]; cat(choice, "\n")
    } else if (state$test_mode) {
      break
    } else {
      choice <- read_cmd("")
    }
    choice <- norm_input(tolower(trimws(choice)))
    if (choice %in% c("1", "遭遇战", "遭遇", "skirmish")) return(start_campaign(state))
    if (choice %in% c("2", "史实", "史实战役", "scenario", "历史")) {
      st2 <- scenario_pick(state)
      if (!is.null(st2)) return(st2)
      next
    }
    if (choice %in% c("3", "教程", "教程关", "tutorial", "tut")) return(start_tutorial(state))
    if (choice %in% c("0", "返回", "back", "q")) break
    cat(c_red("无效选择！请输入 0~3。\n"))
  }
  invisible(state)
}

# ---- 史实场景选择（返回新 state 或 NULL=仅打印）----
scenario_pick <- function(state) {
  cat("历史场景:\n")
  for (i in seq_along(SCENARIOS)) {
    cat(sprintf("  %d) %s\n", i, SCENARIOS[[i]]$name))
  }
  cat(sprintf("  0) 返回\n请选择场景(1/%d): ", length(SCENARIOS)))
  k <- read_cmd("")
  if (nzchar(k) && k != "0") {
    key <- names(SCENARIOS)[suppressWarnings(as.integer(k))]
    if (!is.na(key) && !is.null(key)) return(start_scenario(state, key))
    cat(c_red("无效场景！\n"))
  }
  NULL
}

dispatch_menu <- function(state, choice) {
  choice <- norm_input(tolower(trimws(choice)))
  if (!nzchar(choice)) return(state)
  if (choice %in% c("1", "开始", "开始战役", "start", "play")) return(menu_campaign(state))
  if (choice %in% c("2", "模式", "mode")) {
    order <- c("arcade", "std", "hard")
    return(set_mode(state, order[(match(state$mode, order) %% 3) + 1]))
  }
  if (choice %in% c("3", "火炮", "gun")) {
    order <- names(GUNS)
    return(set_gun(state, order[(match(state$gun_key, order) %% length(order)) + 1]))
  }
  if (choice %in% c("4", "地图样式", "style", "战术", "照片", "tactical", "photo")) {
    state$map_style <- if (state$map_style == "photo") "tactical" else "photo"
    cat(sprintf("已切换地图样式: %s\n", if (state$map_style == "tactical") "战术（等高线）" else "照片"))
    return(state)
  }
  if (choice %in% c("5", "帮助", "help", "h", "?")) { help_text(); return(state) }
  if (choice %in% c("0", "退出", "quit", "q")) { state$quit <- TRUE; return(state) }
  # 旧关键字兼容：历史/场景直达史实列表；教程直达教程关
  if (choice %in% c("历史", "场景", "历史场景", "scenario", "history", "hist")) {
    st2 <- scenario_pick(state)
    return(if (is.null(st2)) state else st2)
  }
  if (choice %in% c("教程", "tutorial", "tut")) return(start_tutorial(state))
  cat(c_red("无效选择！请输入 0~5。\n"))
  state
}
```

注意：旧 `dispatch_menu` 中"历史场景"块整体删除替换；`menu_banner` 原第 5/6 项删除。`help_text()` 加一行 `地图样式`（放在"弹道/气象"行附近）

```r
  cat("  地图样式/style   战术/照片切换（米黄底+等高线 / 实景）\n")
```

- [ ] **Step 2: 更新 test_game.R 第 2 节与 3.5 节（菜单新编号 + 子菜单 + 旧关键字）**

替换第 2 节菜单段：

```r
st <- init_game(seed = 11, mode = "std", test_mode = TRUE, png_dir = "docs/frames")
ok(st$screen == "menu" && is.null(st$mission), "初始化停在主菜单")
ok(st$gun$name == GUNS$D20$name, "默认 D-20")
st <- dispatch_menu(st, "5")   # 帮助
ok(st$map_style == "photo", "默认照片样式")
st <- dispatch_menu(st, "4")   # 样式切换
ok(st$map_style == "tactical", "菜单切换地图样式→战术")
st <- dispatch_menu(st, "4")
ok(st$map_style == "photo", "样式切回照片")
st <- dispatch_menu(st, "2")   # 切模式 std→hard
ok(st$mode == "hard", "菜单切换模式")
st <- dispatch_menu(st, "2")
st <- dispatch_menu(st, "2")   # 循环回 std
ok(st$mode == "std", "模式循环")
st <- dispatch_menu(st, "3")   # D20→M46
ok(st$gun_key == "M46", "菜单切换火炮")
st <- dispatch_menu(st, "3")   # M46→M109
ok(st$gun_key == "M109", "循环到 M109")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "B4", "循环到 B-4")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "B37", "循环到 B-37")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "D20", "循环回 D20")
# 开始战役子菜单：0 返回 → 1 遭遇战
st <- menu_campaign(st)              # test_mode 直接返回（无 commands）
ok(st$screen == "menu", "子菜单：test_mode 无命令即返回")
st <- menu_campaign(st, commands = c("0"))
ok(st$screen == "menu", "子菜单：0 返回")
st <- menu_campaign(st, commands = c("1"))
ok(st$screen == "game" && st$mission_index == 1 && !is.null(st$mission), "子菜单：遭遇战进入任务1")
```

3.5 教程关开头的 `stt <- dispatch_menu(stt, "2")` 改为：

```r
stt <- menu_campaign(stt, commands = c("3"))
```

4 节脚本对局不变（直接 start_campaign）。

新增旧关键字兼容测试（3.5 之后）：

```r
stt3 <- init_game(seed = 21, mode = "std", test_mode = TRUE)
stt3 <- dispatch_menu(stt3, "教程")
ok(stt3$screen == "game" && stt3$mission$key == "tutorial", "旧关键字 教程 直达教程关")
stt4 <- init_game(gun_key = "B37", seed = 22, test_mode = TRUE)
stt4 <- menu_campaign(stt4, commands = c("2", "1"))   # 史实 → 场景1 列宁格勒
ok(stt4$screen == "game" && stt4$scenario$key == "leningrad", "子菜单：史实→列宁格勒")
```

- [ ] **Step 3: 运行验证**

Run: `Rscript tests/test_game.R`
Expected: 全 ✓（含新菜单流 16 项 + 旧关键字 2 项）；`Rscript tests/test_scenario.R` 全 ✓

- [ ] **Step 4: 提交**

```bash
git add Огонь!/ui.R Огонь!/tests/test_game.R
git commit -m "feat(ui): 主菜单重构（开始战役→遭遇战/史实/教程子菜单）+ 样式菜单项 + 旧关键字兼容"
```

---

### Task 4: 文档同步 + 战术演示帧 + 全量回归

**Files:**
- Modify: `Огонь!/README.md`、`Огонь!/TUTORIAL.md`

- [ ] **Step 1: README 同步（三处）**

快速开始第 2 步菜单说明改：

```markdown
2. 先出现**主菜单**（1 开始战役→子菜单 遭遇战/史实战役/教程关 / 2 模式 / 3 火炮 / 4 地图样式 / 5 帮助 / 0 退出）
```

特色区新增（自然地形条目后）：

```markdown
- **高清自适应**：程序地形 25m 分辨率、画布随网格密度升到 1760~2200px（150dpi）；**战术地图样式**可切换（米黄纸底 + 平滑等高线 + 计曲线注记 + 水墨蓝水，`地图样式` 命令或主菜单第 4 项）
```

命令速查表新增行：

```markdown
| `地图样式 [战术/照片]` | 切换战术/照片地图风格 |
```

- [ ] **Step 2: TUTORIAL.md 同步（两处）**

第 2 节菜单行改为：

```markdown
2. 出现主菜单：`1` 开始战役（进入后选 遭遇战/史实战役/教程关）· `2` 模式 · `3` 火炮 · `4` 地图样式 · `5` 帮助 · `0` 退出
```

第 7 节命令表新增：`| 地图样式 [战术/照片] | style | 战术（等高线）与照片风格切换 |`

- [ ] **Step 3: 战术演示帧 + 全量回归**

```bash
# 生成照片版与战术版场景图各一张
Rscript -e 'for (f in c("config.R","ballistics.R","map.R","fdc.R","ui.R","mission.R","game.R")) { p<-file.path("..",f); if (!file.exists(p)) p<-f; source(p,encoding="UTF-8") }
st<-init_game(gun_key="B37", test_mode=TRUE); st<-start_scenario(st,"leningrad")
draw_state(st); st$map_style<-"tactical"; draw_state(st)'
cp docs/frame_001.png docs/ln_tactical.png 2>/dev/null
rm -f docs/frame_001.png docs/frame_002_x.png docs/frame_002.png docs/traj_001.png
```

人工查看 `docs/ln_tactical.png`：米黄底战术风列宁格勒。

```bash
Rscript tests/test_ballistics.R; echo $?
Rscript tests/test_map.R; echo $?
Rscript tests/test_scenario.R; echo $?
Rscript tests/test_game.R; echo $?
Rscript tests/playthrough.R; echo $?
```

Expected: 全 0。

- [ ] **Step 4: 提交**

```bash
git add Огонь!/README.md Огонь!/TUTORIAL.md Огонь!/docs/ln_tactical.png Огонь!/docs/demo_tactical.png
git commit -m "docs(map): 高清/战术样式/新主菜单说明 + 战术渲染演示图"
```

---

## Self-Review

**Spec coverage:** 分辨率→T1；战术样式→T2（含命令+菜单入口）；主菜单→T3；测试/文档→T1~T4；兼容关键字→T3。无遗漏。

**Placeholder scan:** 无 TBD/TODO；代码完整。Step 4 的 `|| true` 两行是同义重复命令（冗余但无害），执行时直接用第二支 Rscript 命令即可。

**Type consistency:** `draw_map(..., style)` 三处调用（draw_state 两个分支 + test）签名一致；`menu_campaign(state, commands=NULL)` 在 ui.R 定义、test_game 引用一致；`scenario_pick` 返回 state 或 NULL，两处调用（menu_campaign/dispatch_menu）都处理 NULL。

**已知冲突规避:** 新命令别名不使用 t/p/s/w（已占用）；`照片`/`战术` 中文首参在 dispatch 与 menu 中都做关键字。

## Execution Handoff

Plan complete and saved to `Огонь!/docs/superpowers/plans/2026-08-30-res-tactical-menu.md`. Two execution options:

1. Subagent-Driven (recommended) - 每 Task 独立子代理，Task 间复核
2. Inline Execution - 本会话内执行，检查点复核

Which approach?
