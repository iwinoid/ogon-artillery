# =====================================================================
# ballistics.R — 弹道解算、散布、射表、弹道侧视图
# 模型：质点 + 平方律空气阻力（相对风），四阶龙格-库塔数值积分
# =====================================================================

# ---- 角度换算 ----
mils_to_rad <- function(mils) mils * pi / 3000     # 6000 密位 = 2pi
rad_to_mils <- function(rad) rad * 3000 / pi
deg_to_mils <- function(deg) deg * 6000 / 360

# 射向单位矢量（方位密位，自北顺时针）
az_unit <- function(az_mils) {
  a <- mils_to_rad(az_mils)
  c(sin(a), cos(a))            # c(东分量, 北分量)
}

# ---- 空气阻力系数 k = 0.5 * rho * Cd * A / m ----
drag_k <- function(gun, cd) {
  0.5 * AIR_DENSITY * cd * (pi * (gun$caliber / 2)^2) / gun$shell_mass
}

# ---- 单发弹道积分 ----
# gun: 火炮配置; charge: 装药号(1基); az_mils/el_mils: 方位/高低(密位)
# wind: list(from_mils, speed) 风来自方向与风速(m/s)
# ground_fun: function(x_m, y_m) -> 地面海拔 (m)
# 返回: list(path=data.frame(t,x,y,z), impact=list(x,y,z,t), ok=TRUE/FALSE)
trajectory <- function(gun, charge, az_mils, el_mils, wind, ground_fun,
                       dt = RK4_DT, max_t = RK4_MAX_T) {
  th <- mils_to_rad(el_mils)
  u  <- az_unit(az_mils)
  v0 <- gun$mv[charge]
  k  <- drag_k(gun, gun$.cd)
  # 风速矢量（风"来自"方向的反向）
  wu <- az_unit(wind$from_mils)
  wv <- c(-wind$speed * wu[1], -wind$speed * wu[2], 0)

  # 初始状态（z 为绝对海拔：从炮位地面高度起算）
  gz0 <- ground_fun(0, 0)
  s <- c(0, 0, gz0, v0 * cos(th) * u[1], v0 * cos(th) * u[2], v0 * sin(th))
  t <- 0
  xs <- s[1]; ys <- s[2]; zs <- s[3]
  ts <- 0

  accel <- function(st) {
    vrel <- c(st[4] - wv[1], st[5] - wv[2], st[6] - wv[3])
    vr <- sqrt(sum(vrel^2))
    a_drag <- -k * vr * vrel
    c(a_drag[1], a_drag[2], a_drag[3] - GRAVITY)
  }
  deriv <- function(st) c(st[4], st[5], st[6], accel(st))

  impact <- NULL
  n <- 0
  while (t < max_t) {
    n <- n + 1
    # 检查当前点是否触地（n>1 排除炮口起点，避免原地判落）
    if (n > 1) {
      gz <- ground_fun(s[1], s[2])
      if (s[3] <= gz) {
        impact <- list(x = s[1], y = s[2], z = gz, t = t)
        break
      }
    }
    # RK4
    k1 <- deriv(s)
    k2 <- deriv(s + dt/2 * k1)
    k3 <- deriv(s + dt/2 * k2)
    k4 <- deriv(s + dt * k3)
    snew <- s + dt/6 * (k1 + 2*k2 + 2*k3 + k4)
    t <- t + dt
    # 触地检查（用终点，若穿过地面则二分找交点）
    gz2 <- ground_fun(snew[1], snew[2])
    if (snew[3] <= gz2) {
      # 二分法求精确落点
      lo <- s; hi <- snew; tlo <- t - dt; thi <- t
      for (i in 1:30) {
        mid <- (lo + hi) / 2
        tm  <- (tlo + thi) / 2
        if (ground_fun(mid[1], mid[2]) < mid[3]) { lo <- mid; tlo <- tm } else { hi <- mid; thi <- tm }
      }
      hit <- (lo + hi) / 2
      impact <- list(x = hit[1], y = hit[2], z = ground_fun(hit[1], hit[2]), t = (tlo + thi) / 2)
      break
    }
    s <- snew
    xs <- c(xs, s[1]); ys <- c(ys, s[2]); zs <- c(zs, s[3]); ts <- c(ts, t)
  }

  if (is.null(impact)) return(list(ok = FALSE, path = NULL, impact = NULL))
  # 附上落点于路径
  list(ok = TRUE,
       path = data.frame(t = ts, x = xs, y = ys, z = zs),
       impact = impact)
}

# ---- 散布模型 ----
# 理想落点 (ix, iy)，射程 range_m，方向 az_mils
# 距离概率误差 PE_R = range * disp[1]，方向 PE_D = range * disp[2]
# sigma = PE / 0.6745
disperse_impact <- function(ix, iy, az_mils, range_m, gun, scale = 1.0) {
  sigR <- range_m * gun$disp[1] / 0.6745 * scale
  sigD <- range_m * gun$disp[2] / 0.6745 * scale
  dR <- rnorm(1, 0, sigR)
  dD <- rnorm(1, 0, sigD)
  u  <- az_unit(az_mils)
  p  <- c(-u[2], u[1])               # 射向右侧单位矢量
  c(ix + dR * u[1] + dD * p[1],
    iy + dR * u[2] + dD * p[2])
}

# ---- 阻力系数校准：使 45° 全装药射程 ≈ 历史最大射程 ----
calibrate_drag <- function(gun, tol = 0.005, maxit = 40) {
  flat <- function(x, y) 0
  f <- function(cd) {
    gun$.cd <- cd
    tr <- trajectory(gun, length(gun$mv), 0, deg_to_mils(45), list(from_mils = 0, speed = 0), flat)
    if (!tr$ok) return(NA_real_)
    sqrt(tr$impact$x^2 + tr$impact$y^2)
  }
  lo <- 0.02; hi <- 0.8
  flo <- f(lo); fhi <- f(hi)
  # 粗扫出可行区间（f 随 Cd 单调递减）
  for (i in 1:20) {
    if (!is.na(flo) && !is.na(fhi) && flo >= gun$max_range_hist && fhi <= gun$max_range_hist) break
    if (is.na(flo) || flo < gun$max_range_hist) { lo <- lo * 0.7; flo <- f(lo) }
    if (is.na(fhi) || fhi > gun$max_range_hist) { hi <- hi * 1.3; fhi <- f(hi) }
  }
  # 二分法求 f(Cd) = target
  for (i in 1:maxit) {
    mid <- (lo + hi) / 2
    fm  <- f(mid)
    if (fm > gun$max_range_hist) lo <- mid else hi <- mid
    if (abs(hi - lo) < 1e-4) break
  }
  cd <- (lo + hi) / 2
  gun$.cd <- cd
  list(gun = gun, cd = cd, range45 = f(cd), target = gun$max_range_hist)
}

# ---- 射表生成 ----
# 标准条件：平地（炮位海拔 0），无风。
# 只保留升序段（射角 0 到最大射程角为止）；更大射角为高射界分支，
# 射程随射角增大而减小，供玩家手动高射界射击（不在表内）。
# 返回 list(rows=data.frame(charge, el_mils, range_m), max_range=每装药表上最大射程,
#            peak_el=每装药最大射程角, gun_name)
build_range_table <- function(gun, el_step = 10) {
  flat <- function(x, y) 0
  rows <- NULL
  maxr <- numeric(length(gun$mv))
  peak_el <- numeric(length(gun$mv))
  scan_max <- min(gun$elev_max, deg_to_mils(45) + 200)   # 覆盖各装药峰值角
  for (ch in seq_along(gun$mv)) {
    els <- seq(gun$elev_min, scan_max, by = el_step)
    r <- numeric(length(els))
    for (i in seq_along(els)) {
      tr <- trajectory(gun, ch, 0, els[i], list(from_mils = 0, speed = 0), flat)
      r[i] <- if (tr$ok) sqrt(tr$impact$x^2 + tr$impact$y^2) else NA
    }
    peak <- which.max(r)
    maxr[ch] <- r[peak]
    peak_el[ch] <- els[peak]
    rows <- rbind(rows, data.frame(charge = ch, el_mils = els[1:peak], range_m = r[1:peak]))
  }
  list(rows = rows, max_range = maxr, peak_el = peak_el, gun_name = gun$name)
}

# 查表：给定装药与射程 -> 高低密位（升序段线性内插）
elevation_for_range <- function(table, charge, range_m) {
  sub <- table$rows[table$rows$charge == charge & !is.na(table$rows$range_m), ]
  if (nrow(sub) < 2) return(NA_real_)
  if (range_m <= min(sub$range_m)) return(sub$el_mils[which.min(sub$range_m)])
  if (range_m >= max(sub$range_m)) return(NA_real_)
  idx <- findInterval(range_m, sub$range_m)
  r1 <- sub$range_m[idx]; r2 <- sub$range_m[idx + 1]
  e1 <- sub$el_mils[idx]; e2 <- sub$el_mils[idx + 1]
  e1 + (range_m - r1) * (e2 - e1) / (r2 - r1)
}

# 选择装药：能覆盖目标射程的最小装药号
charge_for_range <- function(table, range_m, margin = 0.03) {
  ok <- which(table$max_range >= range_m * (1 + margin))
  if (length(ok) == 0) return(which.max(table$max_range))
  ok[1]
}

# 当前高低处 1 密位的射程变化率 (m/密位)，用于距离修正换算
range_per_mil <- function(table, charge, el_mils) {
  sub <- table$rows[table$rows$charge == charge & !is.na(table$rows$range_m), ]
  idx <- findInterval(el_mils, sub$el_mils)
  idx <- max(1, min(idx, nrow(sub) - 1))
  (sub$range_m[idx + 1] - sub$range_m[idx]) / (sub$el_mils[idx + 1] - sub$el_mils[idx])
}

# ---- 弹道侧视图 ----
# shot: trajectory 返回对象 + 落点散布后的实际落点 (ax, ay)
plot_side_view <- function(shot, gun, az_mils, wind, target = NULL, ground_fun = NULL,
                           dev = NULL) {
  if (is.null(shot) || !shot$ok) { cat("（无弹道数据）\n"); return(invisible(NULL)) }
  if (!is.null(dev)) { cur <- dev.cur(); dev.set(dev) } else cur <- NULL
  # 加高底边距，给底部装订信息行留出位置（避免与 x 轴标题重叠）
  op <- par(mar = c(7.5, 4.1, 4.1, 2.1))
  on.exit({ par(op); if (!is.null(cur)) dev.set(cur) }, add = TRUE)
  path <- shot$path
  dist <- sqrt(path$x^2 + path$y^2)      # 沿射向的水平距离
  maxd <- max(dist, shot$range_m / 1000 * 1000 * 1.05, na.rm = TRUE)

  ground_x <- seq(0, maxd, length.out = 300)
  gz0 <- 0
  ground_z <- rep(0, length(ground_x))
  if (!is.null(ground_fun)) {
    u <- az_unit(az_mils)
    ground_z <- sapply(ground_x, function(d) ground_fun(u[1] * d, u[2] * d))
    gz0 <- ground_fun(0, 0)
    ground_z <- ground_z - gz0            # 相对炮位海拔
  }

  maxz <- max(c(path$z - gz0, ground_z, 100), na.rm = TRUE) * 1.08
  plot(ground_x, ground_z, type = "l", col = "#8B5A2B", lwd = 2,
       xlab = "水平距离 (m)", ylab = "高度 (m)", main = "弹道侧视图",
       xlim = c(0, maxd), ylim = c(0, maxz))
  grid(col = "gray90")
  lines(dist, path$z - gz0, col = "black", lwd = 2)
  points(0, 0, pch = 17, cex = 1.4, col = "blue")
  text(0, maxz * 0.03, "炮位", pos = 4, col = "blue", cex = 0.8)
  # 理想落点
  ix <- shot$impact$x; iy <- shot$impact$y
  points(sqrt(ix^2 + iy^2), shot$impact$z - if (!is.null(ground_fun)) ground_fun(0,0) else 0,
         pch = 16, cex = 1.2, col = "darkred")
  # 实际落点（散布后）
  if (!is.null(shot$actual)) {
    ax <- shot$actual[1]; ay <- shot$actual[2]
    ad <- sqrt(ax^2 + ay^2)
    azz <- if (!is.null(ground_fun)) ground_fun(ax, ay) - ground_fun(0, 0) else 0
    points(ad, azz, pch = 4, cex = 1.6, col = "red", lwd = 2)
  }
  if (!is.null(target)) {
    td <- sqrt((target$x * 1000)^2 + (target$y * 1000)^2)  # 目标坐标需为 km
    abline(v = td, col = "red", lty = 2)
    text(td, maxz * 0.95, "目标", col = "red", cex = 0.8, pos = 3)
  }
  legend("topright", legend = c("弹道", "地面", "理想落点", "实际落点"),
         col = c("black", "#8B5A2B", "darkred", "red"), lty = c(1, 1, NA, NA),
         pch = c(NA, NA, 16, 4), cex = 0.8)
  mtext(sprintf("装药%d · 方位%d密位 · 飞行时间 %.1fs · 射程 %.0fm",
                shot$charge, round(shot$az), shot$impact$t, shot$range_m),
        side = 1, line = 5, cex = 0.8)
  invisible(shot)
}
