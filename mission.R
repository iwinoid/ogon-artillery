# =====================================================================
# mission.R — 任务生成、观察员报告、评分
# =====================================================================

# 目标类型：摧毁半径 + 说明
MISSION_TYPES <- list(
  list(key = "mortar", name = "压制敌迫击炮阵地",
       desc = "敌迫击炮正在对我前沿射击，阵地已标定。",
       label = "敌迫击炮阵地", radius = 40),
  list(key = "bunker", name = "摧毁敌观察所",
       desc = "混凝土观察所，需命中其半径 20m 内。",
       label = "敌观察所", radius = 20),
  list(key = "ammo", name = "破坏敌弹药堆积点",
       desc = "命中即引爆弹药！半径 30m 内有效。",
       label = "敌弹药堆积点", radius = 30),
  list(key = "area", name = "扰乱敌集结地域",
       desc = "敌连级集结地域，命中区域内任意点即可（半径 150m）。",
       label = "敌集结地域", radius = 150)
)

# ---- 生成任务 ----
# 普通模式：目标随机（北半部，距离 3~13km）；历史场景：固定史实目标
new_mission <- function(state, index) {
  # ---- 历史场景任务（固定德军据点）----
  if (!is.null(state$scenario)) {
    sc <- state$scenario
    tg <- sc$targets[[index]]
    g  <- state$guns[[state$gun_sel]]
    r  <- range_m(g$x, g$y, tg$x, tg$y)
    wind <- list(from_mils = sample(c(0, 450, 900, 1350, 1800, 2250, 2700, 3150), 1),
                 speed = sample(c(2, 4, 6, 8, 10), 1))
    mission <- list(
      index = index, key = "scenario", name = sprintf("目标：%s", tg$label),
      desc = "历史场景：摧毁德军据点，为列宁格勒解围。",
      target = list(x = tg$x, y = tg$y, label = tg$label, radius = tg$radius),
      wind = wind,
      ammo = AMMO_PER_MISSION, turns = 0,
      destroyed = FALSE, done = FALSE, scored = FALSE,
      last_report = "", shells_used = 0
    )
    state$mission <- mission
    state$wind <- wind
    state$ammo <- mission$ammo
    state$turns <- 0
    state$shots <- data.frame(x = numeric(), y = numeric(),
                              turn = integer(), dR = numeric(), dD = numeric())
    state$traj_log <- list()
    state$last_report <- ""
    cat(c_bold(c_cyan("════════ 新任务 ════════")), "\n")
    cat(sprintf("任务 #%d/%d: %s\n", index, length(sc$targets), c_yellow(mission$name)))
    cat(sprintf("德军据点: %s  (%.2f, %.2f) km   摧毁半径 %dm\n",
                tg$label, tg$x, tg$y, tg$radius))
    cat(sprintf("距 B-37: %.1f km   气象: 风自 %d 密位  %d m/s\n",
                r / 1000, wind$from_mils, wind$speed))
    cat(sprintf("弹药基数: %d 发 HE\n", mission$ammo))
    cat("提示: 目标在 30~41km，需用高装药；输入 诸元 target 计算装订诸元。\n")
    return(state)
  }

  # ---- 普通模式（随机目标）----
  types <- MISSION_TYPES
  tp <- types[[((index - 1) %% length(types)) + 1]]
  g <- state$guns[[state$gun_sel]]
  maxr <- max(state$table$max_range)
  found <- FALSE
  for (i in 1:500) {
    tx <- runif(1, 2, 18)
    ty <- runif(1, state$map$front_y + 1.5, 18.5)
    r <- range_m(g$x, g$y, tx, ty)
    if (r > 3000 && r < min(13000, maxr * 0.95)) { found <- TRUE; break }
  }
  if (!found) { tx <- 10; ty <- 12; r <- range_m(g$x, g$y, tx, ty) }

  # 侦察误差：上报坐标 = 真值 + 随机偏移（模长 5~15m，方向随机）
  err_m  <- runif(1, 5, RECON_ERROR_M)
  err_az <- runif(1, 0, 2 * pi)
  rx <- tx + err_m * cos(err_az) / 1000
  ry <- ty + err_m * sin(err_az) / 1000

  wind <- list(from_mils = sample(c(0, 450, 900, 1350, 1800, 2250, 2700, 3150), 1),
               speed = sample(c(2, 4, 6, 8, 10), 1))
  mission <- list(
    index = index, key = tp$key, name = tp$name, desc = tp$desc,
    target = list(x = rx, y = ry, truth_x = tx, truth_y = ty,
                  label = tp$label, radius = tp$radius),
    wind = wind,
    ammo = AMMO_PER_MISSION, turns = 0,
    destroyed = FALSE, done = FALSE, scored = FALSE,
    last_report = "", shells_used = 0
  )
  state$mission <- mission
  state$wind <- wind
  state$ammo <- mission$ammo
  state$turns <- 0
  state$shots <- data.frame(x = numeric(), y = numeric(),
                            turn = integer(), dR = numeric(), dD = numeric())
  state$traj_log <- list()
  state$last_report <- ""
  cat(c_bold(c_cyan("════════ 新任务 ════════")), "\n")
  cat(sprintf("任务 #%d: %s\n", index, c_yellow(mission$name)))
  cat(mission$desc, "\n")
  cat(sprintf("目标: %s  (%.2f, %.2f) km   摧毁半径 %dm\n",
              mission$target$label, rx, ry, mission$target$radius))
  cat(sprintf("气象: 风自 %d 密位  %d m/s\n", wind$from_mils, wind$speed))
  cat(sprintf("弹药基数: %d 发 HE\n", mission$ammo))
  cat("提示: 输入 诸元 target 计算装订诸元；输入 地图 查看目标位置。\n")
  cat("注: 侦察坐标存在 ±15m 内误差，试射修正可消除。\n")
  state
}

# ---- 弹着附近（within_km 内）最近的标注据点；无则 NULL ----
nearby_place <- function(state, x_km, y_km, within_km = 2.0) {
  if (is.null(state$map$places)) return(NULL)
  best <- NULL; bd <- within_km
  for (pl in state$map$places) {
    d <- sqrt((x_km - pl$x)^2 + (y_km - pl$y)^2)
    if (d <= bd) { best <- pl; bd <- d }
  }
  best
}

# ---- 观察员报告 ----
# 以目标为基准: dR = 弹着射程 - 目标射程（负=近弹），dD = 横向偏差（正=偏右）
# sh$actual 为相对炮位的米制坐标；入库时换算为地图 km 坐标
observer_report <- function(state, volley) {
  m <- state$mission
  g <- state$guns[[state$gun_sel]]
  t <- m$target
  tx <- t$truth_x %||% t$x
  ty <- t$truth_y %||% t$y
  r_tgt <- range_m(g$x, g$y, tx, ty)
  az_tgt <- azimuth_mils(g$x, g$y, tx, ty)
  lines <- character(0)
  for (i in seq_along(volley)) {
    sh <- volley[[i]]
    r_imp <- sqrt(sh$actual[1]^2 + sh$actual[2]^2)
    az_imp <- azimuth_mils(0, 0, sh$actual[1] / 1000, sh$actual[2] / 1000)
    dR <- r_imp - r_tgt
    dAz <- (az_imp - az_tgt + 3000) %% 6000 - 3000      # ±3000 密位内
    dD <- dAz * r_tgt / 1000
    dist <- sqrt(dR^2 + dD^2)
    hit <- dist <= t$radius
    if (hit) {
      s <- sprintf("第%d发: ★命中目标区！距目标 %.0fm（%s %.0fm，%s %.0fm）",
                   i, dist, if (dR < 0) "近弹" else "远弹", abs(dR),
                   if (dD < 0) "偏左" else "偏右", abs(dD))
    } else {
      s <- sprintf("第%d发: %s %.0fm，%s %.0fm",
                   i, if (dR < 0) "近弹" else "远弹", abs(dR),
                   if (dD < 0) "偏左" else "偏右", abs(dD))
    }
    # 弹着附近是否有标注据点（非目标）：射击其他据点也报告
    imp_km <- c(g$x + sh$actual[1] / 1000, g$y + sh$actual[2] / 1000)
    pl <- nearby_place(state, imp_km[1], imp_km[2])
    if (!is.null(pl)) {
      dpl <- sqrt((imp_km[1] - pl$x)^2 + (imp_km[2] - pl$y)^2)
      pname <- sub("·.*$", "", pl$label)
      if (pl$side == "soviet") {
        s <- paste0(s, sprintf("  ⚠弹着落在苏军据点%s附近(%.0fm)！", pname, dpl * 1000))
      } else {
        s <- paste0(s, sprintf("  弹着接近德军据点%s(%.0fm)", pname, dpl * 1000))
      }
    }
    lines <- c(lines, s)
    state$shots <- rbind(state$shots, data.frame(
      x = g$x + sh$actual[1] / 1000, y = g$y + sh$actual[2] / 1000,
      turn = state$turns, dR = dR, dD = dD))
  }
  # 弹群中心与散布（地图坐标）
  if (length(volley) > 1) {
    cx <- g$x + mean(sapply(volley, function(sh) sh$actual[1])) / 1000
    cy <- g$y + mean(sapply(volley, function(sh) sh$actual[2])) / 1000
    spread <- max(sapply(volley, function(sh) {
      sqrt((sh$actual[1] / 1000 - (cx - g$x))^2 + (sh$actual[2] / 1000 - (cy - g$y))^2)
    })) * 1000
    lines <- c(lines, sprintf("弹群: 中心(%.2f, %.2f) 最大散布半径 %.0fm",
                              cx, cy, spread))
  }
  for (s in lines) cat("  ", s, "\n")
  state$last_report <- lines[1]
  state
}

# ---- 摧毁判定 ----
check_destroyed <- function(state) {
  m <- state$mission
  if (m$destroyed) return(state)
  t <- m$target
  tx <- t$truth_x %||% t$x; ty <- t$truth_y %||% t$y
  if (nrow(state$shots) > 0) {
    d <- sqrt((state$shots$x - tx)^2 + (state$shots$y - ty)^2)
    if (min(d) <= t$radius / 1000) {
      m$destroyed <- TRUE
      m$done <- TRUE
      cat(c_bold(c_green("\n  ★★★ 目标被摧毁！★★★\n")), "\n")
      if (m$key == "ammo") cat("  弹药堆积点发生殉爆，冲天火光照亮夜空。\n")
      if (m$key == "area") cat("  敌集结地域陷入混乱，任务完成。\n")
      state$mission <- m
      return(state)
    }
  }
  # 任务失败条件
  fail <- NULL
  if (state$ammo <= 0) fail <- "弹药耗尽！"
  if (state$turns >= TURNS_LIMIT) fail <- "射击命令次数用尽！"
  if (!is.null(fail)) {
    m$done <- TRUE
    state$mission <- m
    cat(c_bold(c_red(sprintf("\n  %s 任务未完成。\n", fail))), "\n")
  }
  state
}

# ---- 评分 ----
score_mission <- function(state) {
  m <- state$mission
  shells <- nrow(state$shots)
  score <- max(0, 100 - shells * SCORE_SHELL_PENALTY - m$turns * SCORE_TURN_PENALTY)
  if (!m$destroyed) {
    score <- 0
    rating <- "未完成"
  } else {
    rating <- if (score >= 85) "S" else if (score >= 70) "A" else if (score >= 55) "B" else "C"
  }
  list(score = score, rating = rating, shells = shells, turns = m$turns)
}

end_mission <- function(state) {
  m <- state$mission
  sc <- score_mission(state)
  cat(c_bold("\n════════ 任务结算 ════════\n"))
  cat(sprintf("%s: %s\n", mission_label(m), m$name))
  cat(sprintf("结果: %s\n", if (m$destroyed) c_green("已完成") else c_red("未完成")))
  cat(sprintf("用弹: %d 发    射击命令: %d 次\n", sc$shells, sc$turns))
  cat(sprintf("成绩: %s  %d 分\n", c_yellow(sc$rating), sc$score))
  m$scored <- TRUE
  state$mission <- m
  state$campaign$scores <- c(state$campaign$scores, sc$score)
  state$campaign$total <- state$campaign$total + sc$score
  state
}

campaign_summary <- function(state) {
  cat(c_bold("\n════════ 战役总结 ════════\n"))
  sc <- state$campaign$scores
  for (i in seq_along(sc)) {
    cat(sprintf("  任务 #%d: %d 分\n", i, sc[i]))
  }
  cat(sprintf("  总分: %d / %d\n", state$campaign$total, 100 * length(sc)))
  avg <- if (length(sc)) round(mean(sc)) else 0
  grade <- if (avg >= 85) "优秀射手" else if (avg >= 70) "合格炮手" else if (avg >= 55) "见习炮手" else "仍需训练"
  cat(sprintf("  综合评定: %s\n", c_bold(c_cyan(grade))))
}
