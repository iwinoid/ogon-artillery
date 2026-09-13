# =====================================================================
# fetch_dem.R — 下载真实地形 DEM 并缓存为游戏可加载的 RDS
# 需要联网，且安装: install.packages(c("elevatr", "terra"))
# 用法:
#   Rscript tools/fetch_dem.R --center 116.4 39.9 --size 20 --zoom 11 --out data/dem_cache.rds
#     --center 目标区域中心经纬度（东经 北纬）
#     --size   区域边长 (km)
#     --zoom   分辨率档: 10≈90m, 11≈30m, 12≈15m（越大越精细越慢）
#     --out    输出缓存文件（默认 data/dem_cache.rds）
# 游戏加载: Rscript main.R --map data/dem_cache.rds
# =====================================================================

args <- commandArgs(trailingOnly = TRUE)
get_flag <- function(name, default = NULL) {
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}

if (!requireNamespace("elevatr", quietly = TRUE)) stop("请先安装 elevatr: install.packages('elevatr')")
if (!requireNamespace("terra", quietly = TRUE)) stop("请先安装 terra: install.packages('terra')")
suppressPackageStartupMessages({ library(elevatr); library(terra) })

center <- suppressWarnings(as.numeric(get_flag("--center", "")))
size   <- suppressWarnings(as.numeric(get_flag("--size", "20")))
zoom   <- suppressWarnings(as.integer(get_flag("--zoom", "11")))
out    <- get_flag("--out", file.path("data", "dem_cache.rds"))
if (length(center) != 2 || any(is.na(center))) stop("用法: --center <东经> <北纬>")
if (is.na(size) || size <= 0) stop("--size 无效")
if (is.na(zoom) || zoom < 1 || zoom > 14) stop("--zoom 须在 1~14")

lon <- center[1]; lat <- center[2]
# 经纬度→边长（纬度 1° ≈ 111km；经度按纬度缩放）
dlat <- size / 2 / 111
dlon <- size / 2 / (111 * cos(lat * pi / 180))
bb <- data.frame(x = c(lon - dlon, lon + dlon), y = c(lat - dlat, lat + dlat))
cat(sprintf("下载区域: 中心(%.4f, %.4f)  %.0f×%.0f km  zoom=%d\n",
            lon, lat, size, size, zoom))

e <- suppressWarnings(get_elev_raster(locations = bb, z = zoom,
                                      prj = "EPSG:4326", clip = "bbox"))
r <- terra::rast(e)
if (terra::res(r)[1] > 120) {
  r <- terra::disagg(r, fact = ceiling(terra::res(r)[1] / 100))
  cat("已重采样到 ≤120m 分辨率\n")
}
m <- as.matrix(r, wide = TRUE)            # 行=北→南
m <- m[nrow(m):1, ]                       # 翻转为 行=南→北（游戏约定）
xs <- terra::xFromCol(r)
ys <- terra::yFromCol(r)
x_km <- (xs - min(xs)) / 1000
y_km <- (ys - min(ys)) / 1000
res_m <- round(terra::res(r)[1])

dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
saveRDS(list(elev = m, x = x_km, y = y_km, res_m = res_m,
             source = sprintf("DEM center(%.4f,%.4f) zoom=%d", lon, lat, zoom)),
        out)
cat(sprintf("已缓存 %d×%d 格点（分辨率 %dm）→ %s\n", ncol(m), nrow(m), res_m, out))
cat("游戏加载: Rscript main.R --map", out, "\n")
