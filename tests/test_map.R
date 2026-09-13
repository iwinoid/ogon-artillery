# test_map.R — 地图渲染测试：新版地形 + 风格对比图
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f); if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
set.seed(7)
dir.create("output", showWarnings = FALSE, recursive = TRUE)  # 生成物目录（整目录 .gitignore）

m <- gen_terrain_procedural(seed = 20240601)
cat(map_info(m), "\n")
cat("地形点 (5,5) 高程:", round(terrain_elev_at(m, 5000, 5000)), "m\n")
cat("地形点 (10,10) 高程:", round(terrain_elev_at(m, 10000, 10000)), "m\n")

overlay <- list(
  guns = GUN_POSITIONS, gun_sel = 1,
  targets = list(list(x = 14.6, y = 13.2, label = "敌迫击炮阵地", radius = 40)),
  shots = data.frame(x = c(14.5, 14.7), y = c(13.3, 13.1)),
  destroyed = 1, show_radius = TRUE,
  wind = list(from_mils = 2250, speed = 6),
  title = "ОГОНЬ! — 地图（风格 B：平色 + 调色板1）"
)
draw_map(m, overlay, file = "output/demo_map_v3.png", shade = FALSE, palette = terrain_palette)
cat("已输出 output/demo_map_v3.png\n")

# ---- 2×2 风格对比 ----
png("output/map_styles.png", width = 1100, height = 1100, res = 110)
op <- par(mfrow = c(2, 2), mar = c(3, 3, 2.5, 1), oma = c(0, 0, 2, 0))
draw_map(m, list(title = "A: 阴影 + 调色板1", wind = list(from_mils = 2250, speed = 6)),
         shade = TRUE, palette = terrain_palette)
draw_map(m, list(title = "B: 无阴影 + 调色板1"), shade = FALSE, palette = terrain_palette)
draw_map(m, list(title = "C: 阴影 + 调色板2", wind = list(from_mils = 2250, speed = 6)),
         shade = TRUE, palette = terrain_palette2)
draw_map(m, list(title = "D: 无阴影 + 调色板2"), shade = FALSE, palette = terrain_palette2)
mtext("地图风格对比（请挑选最接近你想要的一版）", outer = TRUE, cex = 1.2, font = 2)
par(op)
invisible(dev.off())
cat("已输出 output/map_styles.png\n")

ok <- function(cond, msg) { if (isTRUE(cond)) cat("  ✓", msg, "\n") else { cat("  ✗", msg, "\n"); quit(status = 1) } }

cat("\n===== 河流：单元测试 =====\n")
set.seed(555)
nr_t <- 50; nc_t <- 50
elev_t <- sweep(matrix(runif(nr_t * nc_t, 0, 5), nr_t, nc_t), 2,
                seq(nc_t, 1) * 0.8, "+")
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

cat("\n===== 地形集成：分辨率/河谷/可复现 =====\n")
t0 <- proc.time()
g1 <- gen_terrain_procedural(seed = 12345)
cat(sprintf("地形生成耗时 %.2fs\n", (proc.time() - t0)[3]))
ok(all(dim(g1$elev) == c(800, 800)), sprintf("20km/25m → %d×%d", nrow(g1$elev), ncol(g1$elev)))
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

cat("\n===== v4 渲染：默认阴影 + 新调色板 + 自然河流 =====\n")
overlay4 <- list(
  guns = GUN_POSITIONS, gun_sel = 1,
  targets = list(list(x = 14.6, y = 13.2, label = "敌迫击炮阵地", radius = 40)),
  shots = data.frame(x = c(14.5, 14.7), y = c(13.3, 13.1)),
  destroyed = 1, show_radius = TRUE,
  wind = list(from_mils = 2250, speed = 6),
  title = paste0(map_info(g1), " · v4")
)
t1 <- proc.time()
draw_map(g1, overlay4, file = "output/demo_map_v4.png")
cat(sprintf("渲染耗时 %.1fs，已输出 output/demo_map_v4.png\n", (proc.time() - t1)[3]))

cat("\n===== 画布与高程分带：纯函数 =====\n")
m_A <- list(extent_km = c(0, 20, 0, 20), elev = matrix(100, 10, 10))
ok(abs(map_aspect(m_A) - 1) < 1e-9, "20×20 方图 aspect=1")
m_W <- list(extent_km = c(12, 76, 0, 44), elev = matrix(100, 10, 10))
ok(abs(map_aspect(m_W) - 64/44) < 1e-9, "列宁格勒 aspect=64/44")
cs <- canvas_size(64/44)
ok(cs[1] > cs[2] && cs[1] >= 700 && cs[1] <= 2200, sprintf("宽幅画布 %dx%d", cs[1], cs[2]))
ok(identical(canvas_size(1), c(1000, 1000)), "方图 1000×1000 不变")
cat("\n===== 高程分带：纯函数 =====\n")
v <- c(0:100, 500); land <- rep(TRUE, length(v)); land[length(v)] <- FALSE
bid <- elev_band_id(v, land, band_m = 25)
ok(all(bid[!land] == 0), "水面分带=0")
ok(min(bid[land]) == 1 && max(bid[land]) >= 4, sprintf("分带 1..%d（100m 至少4带）", max(bid[land])))
# 0~24 为一带（1），25~49 一带（2）… 分带单调且带宽恒定
ok(all(diff(bid[1:100]) >= 0), "分带单调不减")
ok(bid[1] == 1 && bid[25] == 1 && bid[26] == 2, "25m 带边界正确")
# 超出上限的高值归入顶带（顶带=调色板末端一档，非连续渐变的白/纯色截断）
ok(bid[101] == max(bid[land]), sprintf("最高值分带=%d（顶带）", bid[101]))

cat("\n===== 场景裁剪 =====\n")
stx <- init_game(gun_key = "B37", test_mode = TRUE)
stx <- start_scenario(stx, "leningrad")
ok(identical(stx$map$extent_km, c(12, 76, 0, 44)), "场景地图 extent 裁剪为 64×44")
ok(!any(sapply(stx$map$places, function(p) p$x < 12 || p$x > 76 || p$y < 0 || p$y > 44)),
   "越界据点已剔除")
ok(any(sapply(stx$map$places, function(p) p$label == "普尔科沃高地·苏军")), "范围内据点保留")
ok(abs(map_aspect(stx$map) - 64/44) < 1e-9, "裁剪后 aspect=64/44")

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

cat("\n===== 战术地图渲染 =====\n")
t5 <- proc.time()
draw_map(g1, overlay4, file = "output/demo_tactical.png", style = "tactical")
ok(file.exists("output/demo_tactical.png"), sprintf("战术图输出（%.1fs）", (proc.time() - t5)[3]))
ok(contour_step(g1) == 25, "战术主线 25m（程序图）")

cat("完成 ✓\n")
