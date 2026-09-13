# =====================================================================
# game.R — 游戏状态、射击执行、命令分发、主循环
# =====================================================================

# ---- 初始化 ----
init_game <- function(map = NULL, mode = "std", gun_key = "D20",
                      seed = NULL, test_mode = FALSE, png_dir = NULL) {
  if (!is.null(seed)) set.seed(seed)
  if (is.null(map)) map <- gen_terrain_procedural()
  if (!mode %in% names(MODES)) stop("未知模式: ", mode)
  if (!gun_key %in% names(GUNS)) stop("未知火炮: ", gun_key)
  gun <- GUNS[[gun_key]]
  res <- calibrate_drag(gun)
  gun <- res$gun
  cat(sprintf("[%s] 阻力系数校准: Cd=%.4f → 45°射程 %.0fm\n",
              gun_key, res$cd, res$range45))
  tab <- build_range_table(gun)
  cat(sprintf("[%s] 射表生成完毕（%d 行），最大射程 %.0fm\n",
              gun_key, nrow(tab$rows), max(tab$max_range)))

  state <- list(
    map = map, mode = mode, mode_cfg = MODES[[mode]],
    gun_key = gun_key, gun = gun, table = tab,
    guns = GUN_POSITIONS, gun_sel = 1,
    wind = NULL, ammo = 0, turns = 0,
    mission = NULL, mission_index = 0,
    shots = NULL, traj_log = list(), last_report = "",
    campaign = list(scores = numeric(), total = 0),
    screen = "menu", tutorial = NULL, scenario = NULL, n_missions = 4,
    map_style = "photo",
    frame = 0, png_dir = png_dir, test_mode = test_mode,
    quit = FALSE, dev_map = NULL, dev_traj = NULL
  )
  if (!test_mode) {
    if (is_rstudio()) {
      # RStudio：用默认设备，地图显示在 Plots 窗格，不开独立窗口
      # （窗格尺寸 IDE 可控，绘图区 asp=1 已等比，用户可拖拽窗格）
      state$dev_map <- NULL
    } else {
      # 窗口宽高随地图幅面：宽幅图（aspect≥1.3）用 14.5×10，方形保持 11.5×11.5
      # 无显示环境（无 X/无 GUI）时 x11/windows 可能失败或阻塞：尝试后失败则退回当前设备
      asp <- map_aspect(map)
      w <- if (asp >= 1.3) 14.5 else 11.5
      h <- if (asp >= 1.3) 10 else 11.5
      state$dev_map <- tryCatch({
        if (.Platform$OS.type == "windows") windows(width = w, height = h)
        else x11(width = w, height = h)
      }, error = function(e) {
        cat(c_yellow("（图形窗口不可用，地图将画在当前设备；无界面环境可用 --test 跑脚本对局）\n"))
        NULL
      })
    }
  }
  draw_state(state)
  state
}

# ---- 开始战役（重置战役，进入第 1 任务）----
start_campaign <- function(state) {
  # 从历史场景回来时，恢复默认随机地图与炮位
  if (!is.null(state$scenario)) {
    state$map <- gen_terrain_procedural()
    state$guns <- GUN_POSITIONS
    state$gun_sel <- 1
    state$scenario <- NULL
  }
  state$mission_index <- 0
  state$tutorial <- NULL
  state$campaign <- list(scores = numeric(), total = 0)
  state$n_missions <- 4
  state$screen <- "game"
  state <- new_mission(state, 1)
  state$mission_index <- 1
  draw_state(state)
  state
}

# ---- 历史场景（如：列宁格勒保卫战 B-37）----
start_scenario <- function(state, key) {
  sc <- SCENARIOS[[key]]
  if (is.null(sc)) { cat(c_red("未知场景！\n")); return(state) }
  # 优先加载真实 DEM 缓存（data/dem_<key>.rds），否则程序生成地形
  dem_file <- file.path("data", paste0("dem_", key, ".rds"))
  if (file.exists(dem_file)) {
    map <- load_dem_cache(dem_file)
    # DEM 裁剪到场景范围（下载缓存常比场景大，避免目标/炮位偏置与大片空旷区）
    ext <- sc$extent_km
    cx <- which(map$x >= ext[1] & map$x <= ext[2])
    cy <- which(map$y >= ext[3] & map$y <= ext[4])
    if (length(cx) > 1 && length(cy) > 1) {
      map$elev <- map$elev[cy, cx, drop = FALSE]
      if (!is.null(map$water_mask)) map$water_mask <- map$water_mask[cy, cx, drop = FALSE]
      map$x <- map$x[cx]; map$y <- map$y[cy]
      # 显示范围对齐场景标定值（网格点步进 0.15km 不在整数上，偏差 <100m 忽略）
      map$extent_km <- ext
    }
    map$water <- NULL          # 真实水域由 DEM 自动渲染，去掉示意多边形
    map$water_labels <- sc$geography$water_labels
    cat(sprintf("[场景] 加载真实地形: %s\n", map$source))
  } else {
    map <- gen_terrain_procedural(extent_km = sc$extent_km, res_m = sc$res_m,
                                  seed = 20240601)
    map$water <- sc$geography$water
    map$water_labels <- sc$geography$water_labels
  }
  map$river <- sc$geography$river
  map$river_arms <- sc$geography$river_arms %||% NULL
  map$city <- sc$geography$city
  map$frontline <- sc$geography$frontline
  # 标注据点吸附到陆地（岛屿据点除外）
  map$places <- lapply(sc$geography$places, function(pl) {
    if (!isTRUE(pl$island)) {
      p <- snap_to_land(map, pl$x, pl$y)
      pl$x <- p[1]; pl$y <- p[2]
    }
    pl
  })
  map$water_labels <- sc$geography$water_labels
  map$front_y <- NULL
  # 剔除场景范围外的标注据点（裁剪后回到地图外；大 DEM 时代它们曾"溜进"视野）
  keep <- sapply(map$places, function(pl) {
    pl$x >= map$extent_km[1] && pl$x <= map$extent_km[2] &&
      pl$y >= map$extent_km[3] && pl$y <= map$extent_km[4]
  })
  if (!all(keep)) {
    cat(c_red(sprintf("（%d 个标注据点在地图范围外，已不进图）\n", sum(!keep))))
  }
  map$places <- map$places[keep]
  map$source <- paste0("场景:", sc$name, " · ", map$source)
  state$map <- map
  state <- set_gun(state, sc$gun_key)
  state$guns <- sc$gun_positions
  state$gun_sel <- 1
  state$scenario <- sc
  state$n_missions <- length(sc$targets)
  state$mission_index <- 0
  state$tutorial <- NULL
  state$campaign <- list(scores = numeric(), total = 0)
  state$screen <- "game"
  cat(c_bold(c_cyan(sprintf("\n════════ %s ════════\n", sc$name))))
  cat(sc$desc, "\n")
  g <- sc$gun_positions[[1]]
  cat(sprintf("炮位: %s (%.1f, %.1f) km\n", g$label, g$x, g$y))
  cat(sprintf("目标: %d 个德军据点（射程 30~41km）\n", length(sc$targets)))
  state <- new_mission(state, 1)
  state$mission_index <- 1
  draw_state(state)
  state
}

# ---- 教程关（固定易打目标，无风）----
start_tutorial <- function(state) {
  m <- list(
    index = 0, key = "tutorial", name = "教程关：首发命中",
    desc = "这是教程关：目标已标定，风平浪静，跟着提示一步步完成你的第一次射击。",
    target = list(x = 6.0, y = 10.0, label = "训练靶", radius = 150),
    wind = list(from_mils = 0, speed = 0),
    ammo = AMMO_PER_MISSION, turns = 0,
    destroyed = FALSE, done = FALSE, scored = FALSE,
    last_report = "", shells_used = 0
  )
  state$mission <- m
  state$wind <- m$wind
  state$ammo <- m$ammo
  state$turns <- 0
  state$shots <- data.frame(x = numeric(), y = numeric(), turn = integer(),
                            dR = numeric(), dD = numeric())
  state$traj_log <- list()
  state$last_report <- ""
  state$mission_index <- 0
  state$tutorial <- list(active = TRUE)
  state$screen <- "game"
  draw_state(state)
  cat(c_bold(c_cyan("\n════════ 教程关 ════════\n")))
  cat("目标：训练靶 (6.0, 10.0) km，摧毁半径 150m（很大，很容易命中）。\n")
  cat("提示：输入 任务 查看简报，然后按我的指引一步步来。\n")
  state
}

# ---- 教程关提示（按当前状态给出下一步指引）----
tutorial_hint <- function(state) {
  if (is.null(state$tutorial) || !isTRUE(state$tutorial$active)) return(invisible(state))
  m <- state$mission
  if (is.null(m) || isTRUE(m$scored)) return(invisible(state))
  n_shots <- nrow(state$shots)
  if (n_shots == 0) {
    cat(c_cyan("→ 下一步：输入 诸元 target，让指挥所计算器给出装订卡片。\n"))
  } else if (!m$destroyed && n_shots < 4) {
    cat(c_cyan("→ 观察员报偏差了？近弹加高低、远弹减高低；偏左加方位、偏右减方位。\n"))
    cat(c_cyan("  输入 修正 <近远偏差> <左右偏差> 换算成密位，再按建议重射。\n"))
  } else if (!m$destroyed) {
    cat(c_cyan("→ 还没摧毁？输入 急促 <方位> <高低> <装药> 来一次 3 发急促射。\n"))
  } else {
    cat(c_green("→ 目标已摧毁！输入 结束 结算，完成教程关。\n"))
  }
  invisible(state)
}

# ---- 切换火炮 / 模式 ----
set_gun <- function(state, gun_key) {
  if (!gun_key %in% names(GUNS)) { cat(c_red("未知火炮！\n")); return(state) }
  gun <- GUNS[[gun_key]]
  res <- calibrate_drag(gun); gun <- res$gun
  state$gun_key <- gun_key; state$gun <- gun
  state$table <- build_range_table(gun)
  cat(sprintf("已切换: %s（最大射程 %.0fm）\n", gun$name, max(state$table$max_range)))
  state
}

set_mode <- function(state, mode) {
  if (!mode %in% names(MODES)) { cat(c_red("未知模式！\n")); return(state) }
  state$mode <- mode; state$mode_cfg <- MODES[[mode]]
  cat(sprintf("已切换模式: %s\n", state$mode_cfg$name))
  state
}

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
      if (!is.null(commands) && length(commands) > 0) {
        # 测试兼容：commands 剩余时直接消费场景号（避免 read_cmd 挂起；交互路径仍走 scenario_pick）
        cat("历史场景:\n")
        for (i in seq_along(SCENARIOS)) {
          cat(sprintf("  %d) %s\n", i, SCENARIOS[[i]]$name))
        }
        cat(sprintf("  0) 返回\n请选择场景(1/%d): ", length(SCENARIOS)))
        k <- commands[1]; commands <- commands[-1]; cat(k, "\n")
        if (nzchar(k) && k != "0") {
          key <- names(SCENARIOS)[suppressWarnings(as.integer(k))]
          if (!is.null(key) && !is.na(key)) return(start_scenario(state, key))
          cat(c_red("无效场景！\n"))
        }
        next
      }
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
  if (isTRUE(state$test_mode)) return(NULL)
  k <- read_cmd("")
  if (nzchar(k) && k != "0") {
    key <- names(SCENARIOS)[suppressWarnings(as.integer(k))]
    if (!is.null(key) && !is.na(key)) return(start_scenario(state, key))
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

main_menu <- function(state, commands = NULL) {
  repeat {
    menu_banner(state)
    if (!is.null(commands) && length(commands) > 0) {
      choice <- commands[1]; commands <- commands[-1]
      cat(choice, "\n")
    } else if (state$test_mode) {
      break
    } else {
      choice <- read_cmd("")
    }
    state <- dispatch_menu(state, choice)
    if (state$quit || state$screen == "game") break
  }
  invisible(state)
}

# ---- 地图绘制（含测试模式 PNG 输出）----
draw_state <- function(state, tag = "") {
  m <- state$mission
  overlay <- list(
    guns = state$guns, gun_sel = state$gun_sel,
    targets = if (!is.null(m)) list(m$target) else NULL,
    shots = state$shots,
    destroyed = if (!is.null(m) && m$destroyed) 1 else NULL,
    show_radius = state$mode_cfg$show_radius,
    wind = state$wind,
    title = if (!is.null(m)) sprintf("ОГОНЬ! %s %s（%s）", mission_label(m), m$name, state$mode_cfg$name)
            else "ОГОНЬ! 炮兵射击指挥所"
  )
  if (state$test_mode) {
    if (!is.null(state$png_dir)) {
      dir.create(state$png_dir, showWarnings = FALSE, recursive = TRUE)
      state$frame <- state$frame + 1
      draw_map(state$map, overlay,
               file = file.path(state$png_dir, sprintf("frame_%03d%s.png", state$frame, tag)), style = state$map_style)
    }
    # 无 png_dir 时不绘图（避免向 null 设备写非 ASCII 文本产生编码警告）
  } else if (!is.null(state$dev_map)) {
    dev.set(state$dev_map)
    draw_map(state$map, overlay, style = state$map_style)
  } else {
    # RStudio 等无独立窗口环境：直接画在当前（默认）设备
    draw_map(state$map, overlay, style = state$map_style)
  }
  invisible(state)
}

# ---- 射击执行 ----
# az/el 密位整数，ch 装药号(1基)，n 弹数 1~6
fire_volley <- function(state, az, el, ch, n = 1) {
  gun <- state$gun
  m <- state$mission
  if (is.null(m) || m$done) {
    cat(c_red("当前没有进行中的任务！\n")); return(state)
  }
  if (state$ammo < n) { cat(c_red("弹药不足！\n")); return(state) }
  if (az < 0 || az >= MIL_PER_CIRCLE) { cat(c_red("方位须在 0~5999 密位！\n")); return(state) }
  if (el < gun$elev_min || el > gun$elev_max) {
    cat(sprintf(c_red("高低须在 %d~%d 密位！\n"), gun$elev_min, gun$elev_max)); return(state)
  }
  if (ch < 1 || ch > length(gun$mv)) {
    cat(sprintf(c_red("装药号须在 1~%d！\n"), length(gun$mv))); return(state)
  }
  if (n < 1 || n > 6) { cat(c_red("弹数须在 1~6！\n")); return(state) }

  map <- state$map
  ground_fun <- function(x, y) terrain_elev_at(map, x, y)
  cat(sprintf("射击！ 方位 %d 高低 %d 装药%d %s  ×%d\n",
              az, el, ch, gun$charge_names[ch], n))
  volley <- list()
  for (i in 1:n) {
    tr <- trajectory(gun, ch, az, el, state$wind, ground_fun)
    if (!tr$ok) { cat(c_red("弹道解算失败！\n")); break }
    range_ideal <- sqrt(tr$impact$x^2 + tr$impact$y^2)
    act <- disperse_impact(tr$impact$x, tr$impact$y, az, range_ideal, gun,
                           scale = state$mode_cfg$disp_scale)
    tr$actual <- act
    tr$charge <- ch; tr$az <- az; tr$el <- el
    tr$range_m <- range_ideal
    volley[[i]] <- tr
  }
  if (!length(volley)) return(state)
  state$ammo <- state$ammo - length(volley)
  state$turns <- state$turns + 1
  state$mission$turns <- state$turns
  state$traj_log[[length(state$traj_log) + 1]] <- volley[[length(volley)]]
  state$mission$shells_used <- state$mission$shells_used + length(volley)

  state <- observer_report(state, volley)
  state <- draw_state(state)
  state <- check_destroyed(state)
  state <- draw_state(state, tag = "_x")
  # 弹道侧视图（交互模式：首射开副窗口，之后刷新）
  show_trajectory(state, n_shot = length(state$traj_log), interactive = !state$test_mode)
  state
}

# ---- 弹道侧视图 ----
show_trajectory <- function(state, n_shot = length(state$traj_log), interactive = TRUE) {
  if (n_shot < 1 || n_shot > length(state$traj_log)) {
    cat(c_red("没有该发弹道数据！\n")); return(invisible(state))
  }
  shot <- state$traj_log[[n_shot]]
  m <- state$mission
  target <- if (!is.null(m)) m$target else NULL
  ground_fun <- function(x, y) terrain_elev_at(state$map, x, y)
  if (interactive) {
    if (is_rstudio()) {
      # RStudio：画到当前设备（Plots 窗格），可输入 地图 重绘回地图
      plot_side_view(shot, state$gun, shot$az, state$wind, target = target,
                     ground_fun = ground_fun)
    } else {
      if (is.null(state$dev_traj)) {
        # 无显示环境下窗口失败则退回当前设备（dev=NULL 即当前设备），不阻塞
        state$dev_traj <- tryCatch({
          if (.Platform$OS.type == "windows") windows(width = 10, height = 6.5)
          else x11(width = 10, height = 6.5)
        }, error = function(e) NULL)
      }
      plot_side_view(shot, state$gun, shot$az, state$wind, target = target,
                     ground_fun = ground_fun, dev = state$dev_traj)
    }
  } else if (!is.null(state$png_dir)) {
    f <- file.path(state$png_dir, sprintf("traj_%03d.png", n_shot))
    png(f, width = 1000, height = 620, res = 110)
    plot_side_view(shot, state$gun, shot$az, state$wind, target = target,
                   ground_fun = ground_fun)
    dev.off()
    cat("  弹道侧视图已输出:", f, "\n")
  }
  invisible(state)
}

# ---- 命令分发 ----
dispatch <- function(state, cmd) {
  cmd <- trimws(cmd)
  if (!nzchar(cmd)) return(state)
  toks <- strsplit(cmd, "\\s+")[[1]]
  a <- tolower(toks[1])
  arg <- function(i, default = NULL) if (length(toks) >= i) toks[i] else default
  # 数值参数：缺省/非数字一律返回 NA（避免 is.na() 遇空向量而崩溃）
  num_arg <- function(i) {
    v <- if (length(toks) >= i) toks[i] else NULL
    if (is.null(v)) return(NA_real_)
    suppressWarnings(as.numeric(v))
  }
  int_arg <- function(i) {
    v <- if (length(toks) >= i) toks[i] else NULL
    if (is.null(v)) return(NA_integer_)
    suppressWarnings(as.integer(v))
  }

  # 帮助/教程
  if (a %in% c("帮助", "help", "h", "?")) { help_text(); return(state) }
  if (a %in% c("教程", "tutorial", "tut")) { tutorial_text(); return(state) }

  # 地图/情况/任务
  if (a %in% c("地图", "map", "m")) { draw_state(state); return(state) }
  if (a %in% c("情况", "status", "s")) {
    cat(map_info(state$map), "\n")
    cat(sprintf("火炮: %s   弹药 %d/%d   射击命令 %d/%d\n",
                state$gun$name, state$ammo, AMMO_PER_MISSION, state$turns, TURNS_LIMIT))
    if (!is.null(state$gun$explosive_kg)) {
      cat(sprintf("炮弹: 弹重 %.0f kg · 装药 %.0f kg\n",
                  state$gun$shell_mass, state$gun$explosive_kg))
    }
    if (!is.null(state$mission)) {
      m <- state$mission
      cat(sprintf("任务#%d: %s 目标(%.2f, %.2f) 摧毁半径%dm 状态:%s\n",
                  m$index, m$name, m$target$x, m$target$y, m$target$radius,
                  if (m$done) "已结束" else "进行中"))
    }
    return(state)
  }
  if (a %in% c("任务", "mission")) {
    m <- state$mission
    if (is.null(m)) { cat("（无任务）\n"); return(state) }
    cat(sprintf("%s: %s\n", mission_label(m), c_yellow(m$name)))
    cat(m$desc, "\n")
    cat(sprintf("目标: %s (%.2f, %.2f) km  摧毁半径 %dm\n",
                m$target$label, m$target$x, m$target$y, m$target$radius))
    cat(sprintf("气象: 风自 %d 密位 %d m/s  弹药 %d 发  已用 %d 发 / %d 次射击\n",
                state$wind$from_mils, state$wind$speed,
                state$ammo, m$shells_used, state$turns))
    return(state)
  }

  # 炮位选择
  if (a %in% c("炮位", "guns", "gun")) {
    for (i in seq_along(state$guns)) {
      g <- state$guns[[i]]
      mark <- if (i == state$gun_sel) c_green(" ◀当前") else ""
      cat(sprintf("  %s (%.1f, %.1f) km%s\n", g$label, g$x, g$y, mark))
    }
    cat("用 选择 <n> 切换炮位\n")
    return(state)
  }
  if (a %in% c("选择", "sel", "select")) {
    i <- int_arg(2)
    if (is.na(i) || i < 1 || i > length(state$guns)) {
      cat(c_red("炮位编号无效！用法: 选择 <n>\n")); return(state)
    }
    state$gun_sel <- i
    cat(sprintf("已选择 %s\n", state$guns[[i]]$label))
    draw_state(state)
    return(state)
  }

  # 射表
  if (a %in% c("射表", "table", "t")) {
    nch <- length(state$gun$mv)
    chs <- if (!is.null(arg(2))) suppressWarnings(as.integer(arg(2))) else NULL
    if (!is.null(chs) && (is.na(chs) || chs < 1 || chs > nch)) {
      cat(c_red("装药号无效！\n")); return(state)
    }
    tab <- state$table
    for (ch in if (is.null(chs)) 1:nch else chs) {
      sub <- tab$rows[tab$rows$charge == ch, ]
      sel <- seq(1, nrow(sub), by = 5)
      cat(sprintf("装药%d %s  最大射程 %.0fm（%d密位）\n",
                  ch, state$gun$charge_names[ch], tab$max_range[ch], tab$peak_el[ch]))
      cat("   高低(密位)  射程(m)\n")
      for (i in sel) {
        cat(sprintf("   %5d   %8.0f\n", sub$el_mils[i], sub$range_m[i]))
      }
      if (is.null(chs)) cat("\n")
    }
    cat("提示: 射程在相邻两行之间时，按比例内插取密位。\n")
    return(state)
  }

  # 气象
  if (a %in% c("气象", "wind", "w")) {
    cat(sprintf("风自 %d 密位（北0 东1500 南3000 西4500），风速 %d m/s\n",
                state$wind$from_mils, state$wind$speed))
    cat("提示: 侧风会把弹吹偏，横风修正量见 诸元 卡片。\n")
    return(state)
  }

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

  # 指挥所计算器
  if (a %in% c("诸元", "calc", "c")) {
    if (!state$mode_cfg$calculator) {
      cat(c_red("全真模式禁用计算器！"), "手算公式: 帮助 修正\n")
      manual_formula_help()
      return(state)
    }
    m <- state$mission
    if (is.null(m)) { cat(c_red("没有任务！\n")); return(state) }
    if (!is.null(arg(2)) && tolower(arg(2)) %in% c("target", "目标", "t")) {
      tx <- m$target$x; ty <- m$target$y
    } else {
      tx <- num_arg(2); ty <- num_arg(3)
      if (is.na(tx) || is.na(ty)) {
        cat("用法: 诸元 <x> <y>（目标坐标 km）或 诸元 target\n")
        return(state)
      }
    }
    cd <- calc_firing_data(state, tx, ty)
    if (!cd$ok) { cat(c_red(cd$msg), "\n"); return(state) }
    if (state$mode_cfg$suggest) {
      cat(c_cyan(sprintf("建议装订: 射击 %d %d %d\n",
                         round(cd$az_fire), round(cd$el), cd$charge)))
    }
    return(state)
  }

  # 观察员修正换算
  if (a %in% c("修正", "corr")) {
    if (!state$mode_cfg$calculator) {
      cat(c_red("全真模式禁用修正计算！"), "手算: 偏左加方位、偏右减方位，近弹加高低、远弹减高低；")
      cat("方位密位 = 偏差m ÷ 射程km；高低密位 = 偏差m ÷ 每密位射程变化(m)。\n")
      return(state)
    }
    dR <- num_arg(2)
    dD <- num_arg(3)
    if (is.na(dR) || is.na(dD)) {
      cat("用法: 修正 <距离偏差m 近弹为负> <方向偏差m 偏右为正>\n")
      cat("例: 观察员报\"近弹120 偏左35\" → 修正 -120 -35\n")
      return(state)
    }
    if (!length(state$traj_log)) { cat(c_red("还没有射击记录！\n")); return(state) }
    last <- state$traj_log[[length(state$traj_log)]]
    m <- state$mission
    tt <- m$target
    r_tgt <- range_m(state$guns[[state$gun_sel]]$x, state$guns[[state$gun_sel]]$y,
                     tt$truth_x %||% tt$x, tt$truth_y %||% tt$y)
    cc <- correction_from_observer(state$table, last$charge, r_tgt, last$el, dR, dD)
    new_az <- (last$az + cc$daz_mils) %% MIL_PER_CIRCLE
    new_el <- last$el + cc$del_mils
    cat(sprintf("上次装订: 方位 %d 高低 %d\n", round(last$az), round(last$el)))
    cat(sprintf("修正量:   方位 %+5.1f 密位（%s），高低 %+5.1f 密位（%s）\n",
                cc$daz_mils, if (dD < 0) "偏左→加" else "偏右→减",
                cc$del_mils, if (dR < 0) "近弹→加" else "远弹→减"))
    cat(sprintf("新装订建议: 射击 %d %d %d 1\n",
                round(new_az), round(new_el), last$charge))
    return(state)
  }

  # 射击
  if (a %in% c("射击", "fire", "f")) {
    az <- int_arg(2)
    el <- int_arg(3)
    ch <- int_arg(4)
    n  <- int_arg(5)
    if (is.na(az) || is.na(el) || is.na(ch)) {
      cat("用法: 射击 <方位密位> <高低密位> <装药号> [弹数1~6]\n")
      cat("例: 射击 2350 420 3 1\n")
      return(state)
    }
    return(fire_volley(state, az, el, ch, if (is.na(n)) 1 else n))
  }
  if (a %in% c("急促", "rapid", "r")) {
    az <- int_arg(2)
    el <- int_arg(3)
    ch <- int_arg(4)
    if (is.na(az) || is.na(el) || is.na(ch)) {
      cat("用法: 急促 <方位> <高低> <装药>（3发急促射）\n"); return(state)
    }
    cat(c_yellow("急促射！3发连射\n"))
    return(fire_volley(state, az, el, ch, 3))
  }
  if (a %in% c("效力", "eff", "e")) {
    az <- int_arg(2)
    el <- int_arg(3)
    ch <- int_arg(4)
    if (is.na(az) || is.na(el) || is.na(ch)) {
      cat("用法: 效力 <方位> <高低> <装药>（效力射≤6发，摧毁即停）\n"); return(state)
    }
    m <- state$mission
    if (!is.null(m) && m$done) { cat(c_red("任务已结束！\n")); return(state) }
    cat(c_yellow("效力射！\n"))
    state <- fire_volley(state, az, el, ch, 3)
    if (!is.null(state$mission) && !state$mission$done) {
      state <- fire_volley(state, az, el, ch, 3)
    }
    return(state)
  }

  # 弹道侧视图
  if (a %in% c("弹道", "traj", "tr")) {
    n_shot <- int_arg(2)
    if (is.na(n_shot)) n_shot <- length(state$traj_log)
    return(show_trajectory(state, n_shot, interactive = !state$test_mode))
  }

  # 成绩/结束/继续/退出
  if (a %in% c("成绩", "score", "sc")) {
    if (is.null(state$mission)) { cat("（无任务）\n"); return(state) }
    sc <- score_mission(state)
    cat(sprintf("当前: 用弹 %d 发 / %d 次射击，预计 %d 分（%s）\n",
                sc$shells, sc$turns, sc$score, sc$rating))
    return(state)
  }
  if (a %in% c("结束", "end")) {
    return(next_mission(state))
  }
  if (a %in% c("继续", "next", "n")) {
    return(next_mission(state))
  }
  if (a %in% c("退出", "quit", "q")) {
    if (!is.null(state$mission) && !state$mission$done) {
      cat("任务未完成，退出将放弃任务！再输一次 退出 确认。\n")
      state$mission$done <- TRUE
      return(state)
    }
    state$screen <- "menu"     # 返回主菜单（而非退出程序）
    return(state)
  }

  cat(sprintf("未知命令: %s（输入 帮助 查看命令列表）\n", a))
  state
}

# ---- 下一任务（未结算先结算）----
next_mission <- function(state) {
  if (!is.null(state$mission) && !isTRUE(state$mission$scored)) {
    state <- end_mission(state)
  }
  # 教程关结束 → 回主菜单
  if (!is.null(state$tutorial) && isTRUE(state$tutorial$active)) {
    state$tutorial$active <- FALSE
    state$tutorial <- NULL
    cat(c_green("教程完成！返回主菜单。\n"))
    state$screen <- "menu"
    return(state)
  }
  # 战役结束 → 总结并回主菜单
  if (state$mission_index >= state$n_missions) {
    campaign_summary(state)
    state$screen <- "menu"
    return(state)
  }
  state$mission_index <- state$mission_index + 1
  state <- new_mission(state, state$mission_index)
  draw_state(state)
  state
}

# ---- 主循环 ----
game_loop <- function(state, commands = NULL) {
  empty_streak <- 0
  repeat {
    if (!state$test_mode) panel(state)
    if (!is.null(commands) && length(commands) > 0) {
      cmd <- commands[1]; commands <- commands[-1]
      cat("> ", cmd, "\n", sep = "")
    } else if (state$test_mode) {
      break
    } else {
      cmd <- read_cmd()
    }
    cmd <- norm_input(trimws(cmd))
    if (!nzchar(cmd)) {
      empty_streak <- empty_streak + 1
      if (empty_streak >= 5) { cat("（输入流结束，退出）\n"); state$quit <- TRUE; break }
      next
    }
    empty_streak <- 0
    state <- tryCatch(dispatch(state, cmd), error = function(e) {
      cat(c_red(sprintf("命令执行出错: %s\n", conditionMessage(e))))
      state
    })
    # 教程关：每步之后给出下一步指引
    if (!is.null(state$tutorial) && isTRUE(state$tutorial$active) &&
        state$screen == "game" && !state$quit) {
      tutorial_hint(state)
    }
    if (state$quit || state$screen != "game") break
  }
  if (state$test_mode) {
    cat("\n===== 脚本对局结束 =====\n")
    campaign_summary(state)
  }
  invisible(state)
}
