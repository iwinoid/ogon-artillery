# =====================================================================
# map.R — 地形与地图渲染
# 地形来源：程序生成（零依赖）或 DEM 缓存文件（--map 加载）
# 渲染：base graphics 俯瞰图（山体阴影地形 + 等高线 + 地物 + 格网）
# =====================================================================

# ---- 平滑值噪声（smoothstep 插值，修复二维插值索引）----
# 返回 [ny, nx] 平滑场
value_noise_field <- function(nx, ny, cells) {
  g <- matrix(runif(cells * cells), cells, cells)
  xs <- seq(0, 1, length.out = nx) * (cells - 1) + 1
  ys <- seq(0, 1, length.out = ny) * (cells - 1) + 1
  x0 <- pmin(floor(xs), cells - 1)
  y0 <- pmin(floor(ys), cells - 1)
  tx <- xs - x0; ty <- ys - y0
  # smoothstep：t^2(3-2t)，消除格点处拐角
  sx <- tx * tx * (3 - 2 * tx)
  sy <- ty * ty * (3 - 2 * ty)
  # 完整二维网格的四角取值（ny × nx 矩阵）
  i00 <- g[y0, x0]
  i10 <- g[y0, x0 + 1]
  i01 <- g[y0 + 1, x0]
  i11 <- g[y0 + 1, x0 + 1]
  sxm <- matrix(sx, ny, nx, byrow = TRUE)   # 每行 = sx（沿列广播）
  sym <- matrix(sy, ny, nx)                 # 每列 = sy（沿行广播）
  a <- i00 + (i10 - i00) * sxm
  b <- i01 + (i11 - i01) * sxm
  a + (b - a) * sym
}

# =====================================================================
# ---- 河流游走：顺坡单主河（返回 格坐标矩阵[n,2]=c(行,列) + 是否成湖）----
# 输入 elev[ny,nx]；总体向低处流，西→东引力 + 动量蜿蜒 + 小抖动
# =====================================================================
gen_river_path <- function(elev) {
  nr <- nrow(elev); nc <- ncol(elev)
  # 起点取西侧 5~20% 内陆的高点（留一段流程长度，避免起点贴边即出界）
  c1 <- max(5, round(nc * 0.05)); c2 <- max(c1 + 1, round(nc * 0.20))
  cand <- cbind(sample(nr, 24, replace = TRUE),
                sample(c1:c2, 24, replace = TRUE))
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
    score <- elev[nb] + 18 * (1 - cosang) - 0.8 * d[, 2] + runif(nrow(nb), -3, 3)
    b   <- which.min(score)
    nxt <- nb[b, ]
    if (elev[nxt[1], nxt[2]] > elev[cur[1], cur[2]]) {
      pit <- pit + 1
      if (pit > 8) { lake <- TRUE; break }
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

# ---- 程序生成地形 ----
# seed=NULL 时用当前全局随机流（每局地形都不同）；给 seed 才固定地形（可复现/历史场景用）。
# 注意：不再无条件 set.seed，避免劫持整局游戏的随机序列（否则每局任务/风/弹着完全相同）。
gen_terrain_procedural <- function(extent_km = MAP_DEFAULT$extent_km,
                                   res_m = MAP_DEFAULT$res_m,
                                   seed = NULL,
                                   elev_lo = 80, elev_hi = 420) {
  if (!is.null(seed)) set.seed(seed)
  nx <- round((extent_km[2] - extent_km[1]) * 1000 / res_m)
  ny <- round((extent_km[4] - extent_km[3]) * 1000 / res_m)
  x_km <- seq(extent_km[1], extent_km[2], length.out = nx)
  y_km <- seq(extent_km[3], extent_km[4], length.out = ny)

  # 分形噪声：6 个倍频，smoothstep 插值 → 连续起伏无块状
  f <- matrix(0, ny, nx)
  amps <- c(1, 0.6, 0.35, 0.2, 0.12, 0.07)
  for (o in 0:5) {
    cells <- 6 * 2^o
    f <- f + amps[o + 1] * value_noise_field(nx, ny, cells)
  }
  f <- (f - min(f)) / (max(f) - min(f))
  elev <- elev_lo + (elev_hi - elev_lo) * f^1.12

  # 河流：顺坡游走单主河 → 挖谷 → 水面（有谷有水，非叠画蓝线）
  rv  <- gen_river_path(elev)
  val <- apply_river_valley(elev, rv$path, res_m, rv$lake)
  elev <- elev - val$carve

  # 树林斑块（随机圆，集中在前沿以北的敌方区域）
  nf <- sample(5:8, 1)
  forests <- data.frame(
    cx = runif(nf, 1, extent_km[2] - 1),
    cy = runif(nf, extent_km[3] + 1, extent_km[4] - 1),
    r  = runif(nf, 0.4, 0.9)
  )

  # 道路：一条南北向联络线 + 沿前沿横向简易路
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

# ---- DEM 缓存加载（--map 参数）----
# 缓存格式：list(elev=矩阵[ny,nx] m, x=km, y=km, res_m, water=水面掩膜[可选], source)
load_dem_cache <- function(path) {
  d <- readRDS(path)
  if (!all(c("elev", "x", "y") %in% names(d))) {
    stop("DEM 缓存格式错误：需要 list(elev, x, y, res_m)")
  }
  d$extent_km <- c(min(d$x), max(d$x), min(d$y), max(d$y))
  d$front_y   <- MAP_DEFAULT$front_y
  # 水面掩膜（海+湖逻辑矩阵）；兼容旧缓存里的 water 字段
  if (is.null(d[["water_mask"]])) {
    if (!is.null(d[["water"]]) && is.matrix(d[["water"]])) d[["water_mask"]] <- d[["water"]]
    else d[["water_mask"]] <- !is.na(d[["elev"]]) & d[["elev"]] <= 0.5
  }
  d[["water"]] <- NULL   # water 字段专指地理水体多边形（DEM 地图不用）
  if (is.null(d$river))   d$river   <- NULL
  if (is.null(d$forests)) d$forests <- NULL
  if (is.null(d$roads))   d$roads   <- NULL
  d$source <- paste0("DEM:", basename(path))
  d
}

# ---- 地形高程查询（米制坐标，双线性内插，越界取最近边缘）----
terrain_elev_at <- function(map, xs_m, ys_m) {
  xs_km <- xs_m / 1000; ys_km <- ys_m / 1000
  nx <- length(map$x); ny <- length(map$y)
  ix <- pmax(1, pmin(nx - 1, findInterval(xs_km, map$x)))
  iy <- pmax(1, pmin(ny - 1, findInterval(ys_km, map$y)))
  tx <- (xs_km - map$x[ix]) / (map$x[ix + 1] - map$x[ix])
  ty <- (ys_km - map$y[iy]) / (map$y[iy + 1] - map$y[iy])
  tx <- pmax(0, pmin(1, tx)); ty <- pmax(0, pmin(1, ty))
  z00 <- map$elev[cbind(iy, ix)]
  z10 <- map$elev[cbind(iy, ix + 1)]
  z01 <- map$elev[cbind(iy + 1, ix)]
  z11 <- map$elev[cbind(iy + 1, ix + 1)]
  (1 - ty) * ((1 - tx) * z00 + tx * z10) + ty * ((1 - tx) * z01 + tx * z11)
}

# ---- 山体阴影（西北光照 315°/45°，ESRI 公式，返回 0..1）----
hillshade <- function(elev, x, y, res_m = NULL, az_deg = 315, alt_deg = 45) {
  nr <- nrow(elev); nc <- ncol(elev)
  if (is.null(res_m)) res_m <- mean(diff(x)) * 1000
  gx <- elev; gy <- elev
  gx[, 2:(nc - 1)] <- (elev[, 3:nc] - elev[, 1:(nc - 2)]) / (2 * res_m)
  gy[2:(nr - 1), ] <- (elev[3:nr, ] - elev[1:(nr - 2), ]) / (2 * res_m)
  gx[, 1] <- gx[, 2]; gx[, nc] <- gx[, nc - 1]
  gy[1, ] <- gy[2, ]; gy[nr, ] <- gy[nr - 1, ]
  slope  <- atan(sqrt(gx^2 + gy^2))
  aspect <- atan2(gy, gx)
  zen <- (90 - alt_deg) * pi / 180
  az  <- az_deg * pi / 180
  hs <- cos(zen) * cos(slope) + sin(zen) * sin(slope) * cos(az - aspect)
  hs[hs < 0] <- 0
  (hs - min(hs)) / (max(hs) - min(hs) + 1e-9)
}

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

# ---- 地图宽高比（x 跨度 / y 跨度，>1 为宽幅图）----
map_aspect <- function(map) {
  ext <- map$extent_km
  (ext[2] - ext[1]) / (ext[4] - ext[3])
}

# ---- 画布尺寸：宽幅图给宽画布（宽 clamp 700~2200，高固定 base_h）----
canvas_size <- function(aspect, base_h = 1000) {
  w <- round(base_h * aspect)
  w <- max(700, min(2200, w))
  c(w, base_h)
}

# ---- 高程分带：每 band_m 米一档纯色区（等高线分带填色；水面=0）----
# 返回整数矩阵：1..nb 为陆地带号，0 为水面/无效
elev_band_id <- function(e, land, band_m = 25) {
  bin <- e * 0L
  n <- sum(land)
  if (n == 0) return(bin)
  elo <- min(e[land]); ehi <- max(e[land])
  if (!is.finite(band_m) || band_m <= 0) band_m <- max(1, ehi - elo)
  breaks <- seq(floor(elo / band_m) * band_m, ehi + band_m, by = band_m)
  nb <- length(breaks) - 1
  if (nb < 2) { breaks <- range(e[land]); nb <- 1 }
  b <- findInterval(e, breaks, rightmost.closed = TRUE)
  b <- pmin(pmax(b, 1L), nb)
  bin[land] <- b[land]
  bin
}

# ---- 调色板（高对比 11 档：深谷绿→草→土黄→棕→岩灰→雪）----
terrain_palette <- function(n = 256) {
  colorRampPalette(c("#173d1c", "#28611f", "#3f7d2a", "#63973a", "#8fae4a",
                     "#b9bd60", "#c6a35e", "#a97f4f", "#8d7a63", "#b5b0a8", "#efeeea"))(n)
}
terrain_palette2 <- function(n = 256) {
  colorRampPalette(c("#1a3d1f", "#3f6b2c", "#6f963f", "#9fb654", "#c9c06c",
                     "#b99860", "#96784f", "#8a857c", "#f5f5f3"))(n)
}

# ---- 生成带阴影的 RGB 数组 [ny, nx, 3] ----
# 等高线分带填色：每 band_m 米一档纯色（不再连续渐变），带间边界即等高线位置；
# 山体阴影叠乘保留立体感。band_m=25 时 20km 图约 14 档、列宁格勒约 8 档。
terrain_rgb <- function(map, palette = terrain_palette, shade = TRUE, band_m = 25) {
  e <- map$elev
  # 水面：优先用缓存的掩膜（海+湖），否则按高程 ≤0.5m 判定
  water <- if (!is.null(map[["water_mask"]])) map[["water_mask"]] else (is.na(e) | e <= 0.5)
  if (!identical(dim(water), dim(e))) water <- is.na(e) | e <= 0.5
  land <- !water
  bin <- elev_band_id(e, land, band_m)
  nb <- max(bin)
  # 每带取一个代表色（调色板按带数采样），带间不渐变
  pal <- col2rgb(if (nb <= 256) palette(nb) else colorRampPalette(palette(256))(nb)) / 255
  idx <- pmax(as.vector(bin), 1L)   # 水面 bin=0 → 索引 0 会被 R 丢弃，先抬到 1（水色随后覆盖）
  r <- matrix(pal[1, idx], nrow(e), ncol(e))
  g <- matrix(pal[2, idx], nrow(e), ncol(e))
  b <- matrix(pal[3, idx], nrow(e), ncol(e))
  if (any(water)) {
    r[water] <- 0.28; g[water] <- 0.52; b[water] <- 0.80
  }
  if (shade) {
    f <- 0.42 + 0.58 * hillshade(e, map$x, map$y, map$res_m)
    r <- r * f; g <- g * f; b <- b * f
  }
  arr <- array(c(r, g, b), dim = c(nrow(e), ncol(e), 3))
  # rasterImage 把数组第 1 行渲染在图像顶部，因此输出第 1 行 = 北（地图北在上）
  arr[nrow(e):1, , , drop = FALSE]
}

# ---- 把坐标吸附到最近陆地（岸上城镇不能落在水里；island 据点除外）----
snap_to_land <- function(map, x, y) {
  if (is.null(map[["water_mask"]])) return(c(x, y))
  ix <- which.min(abs(map$x - x)); iy <- which.min(abs(map$y - y))
  if (!isTRUE(map[["water_mask"]][iy, ix])) return(c(x, y))   # 已在陆地
  w <- map[["water_mask"]]
  nr <- nrow(w); nc <- ncol(w)
  for (r in 1:80) {                                      # 逐圈扩展找最近陆地
    rows <- max(1, iy - r):min(nr, iy + r)
    cols <- max(1, ix - r):min(nc, ix + r)
    land <- !w[rows, cols]
    if (any(land)) {
      idx <- which(land, arr.ind = TRUE)
      d <- (idx[, 1] - (iy - rows[1] + 1))^2 + (idx[, 2] - (ix - cols[1] + 1))^2
      j <- which.min(d)
      return(c(map$x[cols[idx[j, 2]]], map$y[rows[idx[j, 1]]]))
    }
  }
  c(x, y)
}

# ---- 渲染 ----
# overlay: list(guns, gun_sel, targets, shots, destroyed, show_radius, wind, title)
# shade: 是否山体阴影；palette: terrain_palette / terrain_palette2
# shade: 是否山体阴影（默认 TRUE，有阴影的高对比模式）；palette: terrain_palette / terrain_palette2
draw_map <- function(map, overlay = list(), file = NULL, shade = TRUE, palette = terrain_palette, style = "photo") {
  ext <- map$extent_km
  d <- ext[2] - ext[1]                      # 幅宽 km
  if (!is.null(file)) {
    base_h <- max(1000, min(1800, round(nrow(map$elev) * 2.2)))
    cs <- canvas_size(map_aspect(map), base_h = base_h)
    png(file, width = cs[1], height = cs[2], res = 150)
  }
  op <- par(mar = c(4, 4, 2.5, 1))
  # 注意顺序：先恢复 par 再关设备（否则 par() 会在关闭后的设备上重开 pdf）
  on.exit({ par(op); if (!is.null(file)) invisible(dev.off()) })
  # 标注缩放系数：20km 图为 1；越大图越小（下限 0.55）
  k <- max(0.55, min(1.15, 20 / d))
  # 白色描边文字（地形上可读；描边偏移随幅宽缩放）
  halo_text <- function(x, y, labels, cex, col, ...) {
    h <- 0.004 * d
    for (dx in c(-h, 0, h)) for (dy in c(-h, 0, h)) {
      if (dx == 0 && dy == 0) next
      text(x + dx, y + dy, labels, cex = cex, col = "white")
    }
    text(x, y, labels, cex = cex, col = col, ...)
  }
  # 地形底色（山体阴影）
  plot(NA, xlim = ext[1:2], ylim = ext[3:4],
       xlab = "东向 (km)", ylab = "北向 (km)",
       main = overlay$title %||% "ОГОНЬ! — 炮兵射击指挥所",
       asp = 1, axes = FALSE)
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
  # 水体（拉多加湖/芬兰湾等示意图例）
  if (!is.null(map[["water"]])) {
    for (wp in map[["water"]]) {
      if (!is.null(wp)) polygon(wp$x, wp$y, col = "#cfe0ee", border = NA)
    }
    if (!is.null(map[["water_labels"]])) {
      for (wl in map[["water_labels"]]) {
        text(wl$x, wl$y, wl$label, col = "#3a6ea5", cex = 0.85, font = 2)
      }
    }
  }
  # 坐标轴：主刻度与网格步长随幅宽自适应（≤30km:1km；≤60:2km；>60:5km）
  step <- if (d <= 30) 1 else if (d <= 60) 2 else 5
  maj <- seq(ceiling(ext[1]), floor(ext[2]), by = step)
  min <- seq(ceiling(ext[1]), floor(ext[2]), by = 1)
  axis(1, at = maj, cex.axis = 0.7)
  axis(2, at = maj, cex.axis = 0.7)
  axis(1, at = min, labels = FALSE, tck = -0.012)
  axis(2, at = min, labels = FALSE, tck = -0.012)
  box()
  # 等高线（半透明、无标注；水面置 NA，等高线自然绕开海岸/湖泊）
  # 注意：contour 的 x/y 约定与 image 相反（x 对应矩阵行），需转置 elev
  e_cont <- map$elev
  wm <- if (!is.null(map[["water_mask"]])) map[["water_mask"]] else (!is.na(e_cont) & e_cont <= 0.5)
  if (identical(dim(wm), dim(e_cont))) e_cont[wm] <- NA
  # 照片样式等高线与分带边界对齐（25m 一档），即"按等高线填色"的边界线
  lv <- seq(ceiling(min(e_cont, na.rm = TRUE) / 25) * 25,
            max(e_cont, na.rm = TRUE), by = 25)
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
  # 河流（程序生成河有 draw=FALSE，不再叠画蓝线——有真水面与真谷地；涅瓦河等标注河仍按原样画线）
  if (!is.null(map$river)) {
    if (!identical(map$river$draw, FALSE)) {
      lines(map$river$x, map$river$y, col = "#2b6cb8", lwd = 2.5)
    }
    lbl <- map$river$label %||% "河"
    mid <- floor(length(map$river$x) / 2)
    halo_text(map$river$x[mid], map$river$y[mid] + 0.5, lbl,
              cex = 0.8 * k, col = "#2b6cb8", font = 2)
    # 三角洲分汊等支线（细一号的蓝线）
    if (!is.null(map$river_arms)) {
      for (ra in map$river_arms) {
        if (!is.null(ra)) lines(ra$x, ra$y, col = "#4a8ec0", lwd = 1.4)
      }
    }
  }
  # 城市标记
  if (!is.null(map$city)) {
    points(map$city$x, map$city$y, pch = 22, cex = 1.2, col = "black", bg = "white")
    halo_text(map$city$x, map$city$y + 0.6, map$city$label, cex = 0.9 * k, col = "black", font = 2)
  }
  # 道路
  if (!is.null(map$roads)) for (rd in map$roads) {
    if (!is.null(rd)) lines(rd$x, rd$y, col = gray(0.35), lty = 2, lwd = 1.2)
  }
  # 树林
  if (!is.null(map$forests) && nrow(map$forests)) {
    symbols(map$forests$cx, map$forests$cy, circles = map$forests$r,
            inches = FALSE, add = TRUE, fg = "#1f5e1f", lwd = 1.4)
  }
  # 前沿/战线（历史场景用折线，普通模式用横线）
  if (!is.null(map$frontline)) {
    lines(map$frontline$x, map$frontline$y, col = "#a52a2a", lty = 4, lwd = 1.5)
    halo_text(map$frontline$x[2], map$frontline$y[2] - 0.6, "战线(示意)",
              cex = 0.8 * k, col = "#a52a2a")
  } else if (!is.null(map$front_y)) {
    abline(h = map$front_y, col = "#a52a2a", lty = 4, lwd = 1.5)
    halo_text(ext[1] + 0.3, map$front_y + 0.25, "前沿", cex = 0.8 * k, col = "#a52a2a")
  }
  # 公里格网（随幅宽自适应，大图不再 1km 密网）
  if (style == "tactical") {
    for (g in seq(ceiling(ext[1]), floor(ext[2]), by = 2)) abline(v = g, col = gray(0.8), lty = 3)
    for (g in seq(ceiling(ext[3]), floor(ext[4]), by = 2)) abline(h = g, col = gray(0.8), lty = 3)
  } else {
    for (g in seq(ceiling(ext[1]), floor(ext[2]), by = step)) abline(v = g, col = gray(0.85), lty = 3)
    for (g in seq(ceiling(ext[3]), floor(ext[4]), by = step)) abline(h = g, col = gray(0.85), lty = 3)
  }
  # 指北针（左下角，箭头指向北=上）
  cx0 <- ext[1] + 1.5; cy0 <- ext[3] + 1.5
  arrows(cx0, cy0, cx0, cy0 + 0.8, length = 0.13, col = "black", lwd = 2)
  text(cx0, cy0 + 1.2, "北", cex = 0.9 * k, font = 2, col = "white")
  text(cx0, cy0 + 1.2, "北", cex = 0.9 * k, font = 2)
  # 炮位
  if (!is.null(overlay$guns)) {
    for (i in seq_along(overlay$guns)) {
      g <- overlay$guns[[i]]
      col <- if (!is.null(overlay$gun_sel) && overlay$gun_sel == i) "red" else "black"
      points(g$x, g$y, pch = 17, cex = 1.6, col = col)
      halo_text(g$x, g$y - 0.35, g$label, cex = 0.75 * k, col = col)
      if (!is.null(overlay$gun_sel) && overlay$gun_sel == i) {
        points(g$x, g$y, pch = 1, cex = 3.2, col = "red")
      }
    }
  }
  # 目标（棕色实心圆 + 浅棕外圈；可显示摧毁半径虚线圆）
  if (!is.null(overlay$targets)) {
    for (i in seq_along(overlay$targets)) {
      t <- overlay$targets[[i]]
      points(t$x, t$y, pch = 16, cex = 1.3, col = "#8b4513")
      points(t$x, t$y, pch = 1, cex = 2.2, col = "#d4a86a", lwd = 2)
      halo_text(t$x, t$y + 0.4, t$label, cex = 0.8 * k, col = "#8b4513")
      if (!is.null(overlay$show_radius) && overlay$show_radius) {
        symbols(t$x, t$y, circles = t$radius / 1000, inches = FALSE, add = TRUE,
                fg = "#8b4513", lty = 2)
      }
      if (!is.null(overlay$destroyed) && i %in% overlay$destroyed) {
        points(t$x, t$y, pch = 4, cex = 3, col = "#5a3310", lwd = 2.5)
        halo_text(t$x, t$y + 0.9, "已摧毁", cex = 0.9 * k, col = "#5a3310")
      }
    }
  }
  # 标注地点（德军/苏军据点，非打击目标；德军=棕三角，苏军=红方块）
  if (!is.null(map$places)) {
    for (pl in map$places) {
      col <- switch(pl$side, german = "#8b4513", soviet = "red", gray(0.3))
      pch <- if (pl$side == "german") 17 else 15
      points(pl$x, pl$y, pch = pch, cex = 0.9, col = col)
      halo_text(pl$x, pl$y + 0.9, sub("·.*$", "", pl$label),
                cex = 0.55 * k, col = col)
    }
  }
  # 弹着
  if (!is.null(overlay$shots) && nrow(overlay$shots)) {
    sh <- tail(overlay$shots, 20)
    points(sh$x, sh$y, pch = 1, cex = 1.1, col = "orange", lwd = 2)
    points(sh$x, sh$y, pch = 20, cex = 0.5, col = gray(0.25))
    last <- tail(overlay$shots, 1)
    halo_text(last$x, last$y + 0.35, nrow(overlay$shots), cex = 0.7 * k, col = "darkorange")
  }
  # 风向标
  if (!is.null(overlay$wind)) {
    wu <- az_unit(overlay$wind$from_mils)
    wx <- ext[2] - 1.4; wy <- ext[4] - 1.4
    arrows(wx, wy, wx - wu[1] * 0.9, wy - wu[2] * 0.9, length = 0.12,
           col = "blue", lwd = 2)
    halo_text(wx, wy - 0.45, sprintf("风自 %d 密位 · %d m/s",
                                     overlay$wind$from_mils, overlay$wind$speed),
              cex = 0.7 * k, col = "blue")
  }
  legend("bottomright", bty = "o", bg = "white", box.col = gray(0.55),
         inset = 0.02, cex = 0.55 * sqrt(k), ncol = 2, pt.cex = 1.1,
         legend = c("炮位(选中)", "目标", "德军据点", "苏军据点", "弹着", "前沿",
                    "河流", "道路", "树林", "风向",
                    sprintf("地形 %d~%dm", round(min(map$elev)), round(max(map$elev)))),
         pch = c(17, 16, 17, 15, 1, NA, NA, NA, 1, NA, NA),
         col = c("black", "#8b4513", "#8b4513", "red", "orange", "#a52a2a",
                 "#2b6cb8", gray(0.35), "#1f5e1f", "blue", gray(0.4)),
         lty = c(NA, NA, NA, NA, NA, 4, 1, 2, NA, NA, NA),
         lwd = c(NA, NA, NA, NA, NA, 1.5, 2.5, 1.2, NA, NA, NA))
  invisible(map)
}

# 输出地图文字信息
map_info <- function(map) {
  sprintf("地图: %s  %.0f×%.0f km  分辨率 %d m  高程 %d~%d m",
          map$source, diff(map$extent_km[1:2]), diff(map$extent_km[3:4]),
          map$res_m, round(min(map$elev)), round(max(map$elev)))
}

# 小工具：%||% 空值回退
`%||%` <- function(a, b) if (is.null(a)) b else a
