# =====================================================================
# fetch_dem_leningrad.R — 直连 AWS Terrain Tiles 下载列宁格勒地区真实 DEM
# 依赖: install.packages(c("terra", "png"))；需要联网
# 数据源: AWS Terrain Tiles (terrarium, z=10 ≈ 76m@60°N)
# 输出: data/dem_leningrad.rds —— 与"列宁格勒保卫战"场景坐标对齐
#   (原点 59.94N,30.32E → 本地 km (30,30)；地图范围 x∈[12,76], y∈[0,44])
# 运行: Rscript tools/fetch_dem_leningrad.R
# =====================================================================
suppressPackageStartupMessages({ library(terra); library(png) })

LAT0 <- 59.94; LON0 <- 30.32
KM_LAT <- 111.0
KM_LON <- 111.0 * cos(LAT0 * pi / 180)
XMIN <- 12; XMAX <- 76; YMIN <- 0; YMAX <- 44

# ---- Web Mercator 换算 ----
deg2xyz <- function(lon, lat, z) {
  n <- 2^z
  x <- floor((lon + 180) / 360 * n)
  r <- lat * pi / 180
  y <- floor((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n)
  c(x, y)
}
tile_extent_3857 <- function(z, x, y) {
  n <- 2^z
  res <- 40075016.686 / n / 256
  off <- 20037508.34                       # 半世界周长：原点在中央经线而非左边缘
  c(xmin = x * 256 * res - off, xmax = (x + 1) * 256 * res - off,
    ymin = (n * 256 - (y + 1) * 256) * res - off, ymax = (n * 256 - y * 256) * res - off)
}
decode_terrarium <- function(a) {
  if (length(dim(a)) == 2) a <- array(a, dim = c(dim(a), 3))
  R <- a[, , 1] * 255; G <- a[, , 2] * 255; B <- a[, , 3] * 255
  R * 256 + G + B / 256 - 32768
}

# ---- 目标范围（加 ~0.1° 边距）----
Z <- 10
lon0 <- LON0 + (XMIN - 30) / KM_LON - 0.10
lon1 <- LON0 + (XMAX - 30) / KM_LON + 0.10
lat0 <- LAT0 + (YMIN - 30) / KM_LAT - 0.10
lat1 <- LAT0 + (YMAX - 30) / KM_LAT + 0.10
xy0 <- deg2xyz(lon0, lat1, Z)      # 西北角瓦片
xy1 <- deg2xyz(lon1, lat0, Z)      # 东南角瓦片
xr <- xy0[1]:xy1[1]; yr <- xy0[2]:xy1[2]
ntile <- length(xr) * length(yr)
cat(sprintf("下载: z=%d 瓦片 x %d~%d, y %d~%d（共 %d 张）\n",
            Z, min(xr), max(xr), min(yr), max(yr), ntile))

tiles <- list(); k <- 0
for (x in xr) for (y in yr) {
  k <- k + 1
  url <- sprintf("https://elevation-tiles-prod.s3.amazonaws.com/terrarium/%d/%d/%d.png", Z, x, y)
  f <- tempfile(fileext = ".png")
  ok <- FALSE
  for (tr in 1:3) {
    ok <- tryCatch({ download.file(url, f, quiet = TRUE, mode = "wb", timeout = 60); TRUE },
                   error = function(e) FALSE)
    if (ok) break
    Sys.sleep(1)
  }
  if (!ok) { cat(sprintf("  [跳过] 瓦片 %d,%d 下载失败\n", x, y)); next }
  m <- decode_terrarium(readPNG(f))
  e <- tile_extent_3857(Z, x, y)
  tiles[[k]] <- terra::rast(m, ext = terra::ext(e[1], e[2], e[3], e[4]), crs = "EPSG:3857")
  if (k %% 5 == 0) cat(sprintf("  已下载 %d/%d\n", k, ntile))
}
cat("合并瓦片并投影到经纬度...\n")
r <- do.call(terra::merge, tiles[!vapply(tiles, is.null, logical(1))])
cat(sprintf("  合并后: %d×%d 单元，范围 %.1f~%.1f m\n",
            ncol(r), nrow(r), minmax(r)[1], minmax(r)[2]))
r <- terra::project(r, "EPSG:4326", method = "bilinear")

# ---- 重采样到 ~150m 规则网格（目标栅格必须带 EPSG:4326 CRS）----
res_target_m <- 150
ncol_t <- max(2, round((lon1 - lon0) * KM_LON * 1000 / res_target_m))
nrow_t <- max(2, round((lat1 - lat0) * KM_LAT * 1000 / res_target_m))
tr <- terra::rast(terra::ext(lon0, lon1, lat0, lat1), nrow = nrow_t, ncol = ncol_t,
                  crs = "EPSG:4326")
tr <- terra::resample(r, tr, method = "bilinear")
cat(sprintf("  重采样后: 值域 %.1f~%.1f m\n", minmax(tr)[1], minmax(tr)[2]))

m <- as.matrix(tr, wide = TRUE)       # 行=北→南
m <- m[nrow(m):1, ]                   # 行=南→北（游戏约定）
x_km <- (terra::xFromCol(tr) - LON0) * KM_LON + 30
y_km <- (rev(terra::yFromRow(tr)) - LAT0) * KM_LAT + 30

# ---- 水面掩膜：海(≤0.5m) + 拉多加湖（触到上/右边界的 ≤8m 连通平坦区）----
sea <- !is.na(m) & m <= 0.5
lake_cand <- !is.na(m) & m <= 8
lc <- terra::rast(lake_cand)
lc[lc == 0] <- NA
cl <- terra::patches(lc, directions = 8)     # terra 的连通分量（= raster 包的 clump）
# 注意：as.matrix(wide=TRUE) 原样保留矩阵方向（行1=南，与 m 一致），不要再翻转
cm <- as.matrix(cl, wide = TRUE)
edge_ids <- unique(c(cm[nrow(cm), ], cm[, ncol(cm)]))   # 北行 / 东列
edge_ids <- edge_ids[!is.na(edge_ids)]
lake <- !is.na(cm) & cm %in% edge_ids & lake_cand
water <- sea | lake

dir.create("data", showWarnings = FALSE, recursive = TRUE)
saveRDS(list(elev = m, x = x_km, y = y_km, res_m = res_target_m,
             water_mask = water,
             source = "DEM: 列宁格勒地区 (AWS Terrain Tiles z10)"),
        "data/dem_leningrad.rds")
cat(sprintf("已缓存 %d×%d 格点(%.0fm) → data/dem_leningrad.rds\n",
            ncol(m), nrow(m), res_target_m))
cat(sprintf("水面占比: 海+湖 %.1f%%（其中拉多加湖 %.1f%%）\n",
            100 * mean(water, na.rm = TRUE), 100 * mean(lake, na.rm = TRUE)))
cat(sprintf("陆地高程 %.0f~%.0f m\n",
            min(m[!water], na.rm = TRUE), max(m, na.rm = TRUE)))
