# =====================================================================
# fdc.R — 指挥所计算器（Fire Direction Center）
# 方位/距离/高差/横风修正、密位换算、装订卡片
# =====================================================================

# ---- 方位角（密位，自北顺时针）----
azimuth_mils <- function(gx, gy, tx, ty) {
  rad <- atan2(tx - gx, ty - gy)
  if (rad < 0) rad <- rad + 2 * pi
  (rad * 3000 / pi) %% MIL_PER_CIRCLE
}

# ---- 水平距离 (m) ----
range_m <- function(gx, gy, tx, ty) {
  sqrt((tx - gx)^2 + (ty - gy)^2) * 1000
}

# ---- 瞄准点高低角（密位，目标高于炮位为正）----
site_mils <- function(g_alt, t_alt, r_m) {
  atan2(t_alt - g_alt, r_m) * 3000 / pi
}

# ---- 横风引起的落点方向偏移 (m)，正 = 偏右 ----
wind_drift_m <- function(wind, az_mils, tof) {
  wu <- az_unit(wind$from_mils)
  wv <- c(-wind$speed * wu[1], -wind$speed * wu[2])  # 风速矢量（来自方向的反向）
  u  <- az_unit(az_mils)
  p  <- c(u[2], -u[1])                               # 射向右侧单位矢量
  cross <- sum(wv * p)
  cross * tof * WIND_DRIFT_FACTOR
}

# ---- 完整诸元计算 ----
# 返回: list(az, az_wind_corr, el, el_site, charge, range, tof, ok, msg)
# 输出"装订卡片"文本
calc_firing_data <- function(state, tx_km, ty_km, verbose = TRUE) {
  gun <- state$guns[[state$gun_sel]]
  map <- state$map
  gx <- gun$x; gy <- gun$y
  if (tx_km < map$extent_km[1] || tx_km > map$extent_km[2] ||
      ty_km < map$extent_km[3] || ty_km > map$extent_km[4]) {
    return(list(ok = FALSE, msg = "目标坐标超出地图范围！"))
  }
  az  <- azimuth_mils(gx, gy, tx_km, ty_km)
  r   <- range_m(gx, gy, tx_km, ty_km)
  tab <- state$table
  ch  <- charge_for_range(tab, r)
  if (r > max(tab$max_range)) {
    return(list(ok = FALSE, msg = sprintf("射程 %.0fm 超出本炮最大射程 %.0fm！", r, max(tab$max_range))))
  }
  el0 <- elevation_for_range(tab, ch, r)
  if (is.na(el0)) return(list(ok = FALSE, msg = "射程不在射表范围内！"))
  g_alt <- terrain_elev_at(map, gx * 1000, gy * 1000)
  t_alt <- terrain_elev_at(map, tx_km * 1000, ty_km * 1000)
  site  <- site_mils(g_alt, t_alt, r)
  # 理想弹道（含风、真实地形）→ 飞行时间（用于风向修正）
  ground_fun <- function(x, y) terrain_elev_at(map, x, y)
  tr0 <- trajectory(state$gun, ch, az, el0 + site, state$wind, ground_fun)
  if (!tr0$ok) return(list(ok = FALSE, msg = "弹道解算失败！"))
  tof0 <- tr0$impact$t
  drift <- wind_drift_m(state$wind, az, tof0)
  az_corr <- -drift / (r / 1000)          # 密位
  az_fire <- (az + az_corr) %% MIL_PER_CIRCLE
  # 精确高低：以真实地形+风迭代弹道，使理想落点射程最接近目标
  # （平地射表+高差修正对 152mm 大落角弹道会系统性打近/打远）
  el <- el0 + site
  # 方位迭代：用真实含风弹道把侧风引起的横向偏差消到零
  # （远射程长飞行时间下，0.55 漂移系数的近似会低估侧风，必须用弹道本身校正）
  for (k in 1:4) {
    tr <- trajectory(state$gun, ch, az_fire, el, state$wind, ground_fun)
    if (!tr$ok) break
    imp_az <- azimuth_mils(0, 0, tr$impact$x / 1000, tr$impact$y / 1000)
    imp_r  <- sqrt(tr$impact$x^2 + tr$impact$y^2)
    dAz <- (imp_az - az + 3000) %% 6000 - 3000     # 落点相对目标方位差
    lat <- dAz * imp_r / 1000                      # 横向偏差 m（正=偏右）
    az_fire <- (az_fire - lat / (imp_r / 1000)) %% MIL_PER_CIRCLE
    if (abs(lat) < 5) break
  }
  # 精确高低：以真实地形+风迭代弹道，使理想落点射程最接近目标
  # （平地射表+高差修正对 152mm 大落角弹道会系统性打近/打远）
  if (el >= 0 && el <= state$gun$elev_max) {
    el_lo <- max(el - 120, 0)
    el_hi <- min(el + 120, state$gun$elev_max)
    for (i in 1:22) {
      el_mid <- (el_lo + el_hi) / 2
      tr <- trajectory(state$gun, ch, az_fire, el_mid, state$wind, ground_fun)
      if (!tr$ok) break
      r_imp <- sqrt(tr$impact$x^2 + tr$impact$y^2)
      if (r_imp < r) el_lo <- el_mid else el_hi <- el_mid
    }
    el <- (el_lo + el_hi) / 2
  }
  tr <- trajectory(state$gun, ch, az_fire, el, state$wind, ground_fun)
  if (!tr$ok) return(list(ok = FALSE, msg = "弹道解算失败！"))
  tof <- tr$impact$t
  res <- sqrt((tr$impact$x / 1000 - (tx_km - gx))^2 + (tr$impact$y / 1000 - (ty_km - gy))^2) * 1000

  if (verbose) {
    cat(c_cyan("┌─ 装订卡片 ─────────────────────────────────┐"), "\n")
    cat(sprintf("│ 目标: (%.2f, %.2f) km   射程: %8.0f m   │\n", tx_km, ty_km, r))
    cat(sprintf("│ 方位: %4d 密位 (风向修正 %+5.1f 密位)     │\n",
                round(az_fire), az_corr))
    cat(sprintf("│ 高低: %4d 密位 (射表 %4d + 高差 %+5.1f，地形迭代) │\n",
                round(el), round(el0), site))
    cat(sprintf("│ 装药: %d (%s)   飞行时间: %5.1f s        │\n",
                ch, state$gun$charge_names[ch], tof))
    if (res < 100) {
      cat(sprintf("│ 理想弹道落点偏差: %.0f m                  │\n", res))
    }
    cat(c_cyan("└──────────────────────────────────────────────┘"), "\n")
  }
  list(ok = TRUE, az = az, az_corr = az_corr, az_fire = az_fire,
       el = el, el0 = el0, site = site, charge = ch, range = r, tof = tof)
}

# ---- 观察员修正换算 ----
# dR: 距离偏差 (m, 近弹为负); dD: 方向偏差 (m, 偏右为正)
# 返回 list(del_mils, daz_mils)
correction_from_observer <- function(table, charge, range_m, el_mils, dR, dD) {
  rpm <- range_per_mil(table, charge, el_mils)
  del  <- -dR / rpm                      # 近弹→加射角
  daz  <- -dD / (range_m / 1000)         # 偏右→左转方位
  list(del_mils = del, daz_mils = daz)
}

# ---- 手算帮助（全真模式）----
manual_formula_help <- function() {
  cat("全真模式手算公式：\n")
  cat("  方位(密位) = atan2(Δ东, Δ北) 换算为密位，自北顺时针，取模 6000\n")
  cat("  射程(m)   = 1000 × sqrt(Δ东² + Δ北²)（Δ 为 km）\n")
  cat("  查射表得标准高低(密位)；再加高差修正 = atan2(目标高-炮位高, 射程)\n")
  cat("  横风修正(密位) ≈ 横风(m/s) × 飞行时间(s) × 0.55 ÷ (射程km)\n")
  cat("  1 密位 ≈ 距离 1000m 处的 1m 横向偏移\n")
}
