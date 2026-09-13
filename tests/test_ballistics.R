# test_ballistics.R — 弹道模块自检：校准、射表、查表、带风弹道
source("config.R", encoding = "UTF-8")
source("ballistics.R", encoding = "UTF-8")
set.seed(42)
dir.create("docs", showWarnings = FALSE, recursive = TRUE)   # PNG 输出目录（不存在时自建）

cat("===== 阻力系数校准（45°全装药射程应≈历史最大射程）=====\n")
for (g in names(GUNS)) {
  t0 <- proc.time()
  res <- calibrate_drag(GUNS[[g]])
  cat(sprintf("%s: Cd=%.4f  45°射程=%.0fm  目标=%.0fm  误差=%.2f%%  (%.1fs)\n",
              g, res$cd, res$range45, res$target,
              100 * (res$range45 - res$target) / res$target,
              (proc.time() - t0)[3]))
  GUNS[[g]] <- res$gun
}

cat("\n===== 射表生成 =====\n")
t0 <- proc.time()
TAB <- build_range_table(GUNS$D20)
cat(sprintf("D20 射表行数=%d 耗时 %.1fs\n", nrow(TAB$rows), (proc.time() - t0)[3]))
cat("各装药最大射程(m)：", round(TAB$max_range), "\n")

# 单调性检查（升序段）
cat("\n===== 单调性检查 =====\n")
mono_ok <- TRUE
for (ch in 1:length(GUNS$D20$mv)) {
  sub <- TAB$rows[TAB$rows$charge == ch & !is.na(TAB$rows$range_m), ]
  if (any(diff(sub$range_m) < 0)) { mono_ok <- FALSE; cat("装药", ch, "射表非单调!\n") }
}
cat(if (mono_ok) "全部装药射表单调递增 ✓\n" else "存在非单调 ✗\n")

cat("\n===== 查表测试（往返验证）=====\n")
rt_ok <- TRUE
for (r in c(3000, 5000, 8000, 10000, 15000)) {
  ch <- charge_for_range(TAB, r)
  el <- elevation_for_range(TAB, ch, r)
  # 验证：用查到的密位打一发平地，射程应≈r
  flat <- function(x, y) 0
  tr <- trajectory(GUNS$D20, ch, 0, el, list(from_mils = 0, speed = 0), flat)
  got <- if (tr$ok) sqrt(tr$impact$x^2 + tr$impact$y^2) else NA
  err <- got - r
  if (is.na(err) || abs(err) > 30) rt_ok <- FALSE
  cat(sprintf("目标 %.0fm -> 装药%d 高低%d密位 -> 实射 %.0fm (偏差 %.1fm) %s\n",
              r, ch, round(el), got, err, if (abs(err) <= 30) "✓" else "✗"))
}
cat(if (rt_ok) "查表往返全部通过 ✓\n" else "查表往返存在超差 ✗\n")

cat("\n===== 带风弹道测试 =====\n")
# 东风(900密位) 10m/s，向北打 8000m
flat <- function(x, y) 0
tr <- trajectory(GUNS$D20, 3, 0, elevation_for_range(TAB, 3, 8000),
                 list(from_mils = 900, speed = 10), flat)
cat(sprintf("无横风影响检查: 落点 x=%.1fm y=%.1fm 飞行时间=%.1fs 弹道顶点=%.0fm\n",
            tr$impact$x, tr$impact$y, tr$impact$t, max(tr$path$z)))

cat("\n===== 散布测试 =====\n")
imp <- disperse_impact(0, 8000, 0, 8000, GUNS$D20)
cat(sprintf("散布1: dR=%.0fm dD=%.0fm\n", imp[2] - 8000, imp[1]))
imp <- disperse_impact(0, 8000, 0, 8000, GUNS$D20)
cat(sprintf("散布2: dR=%.0fm dD=%.0fm\n", imp[2] - 8000, imp[1]))

cat("\n===== 弹道侧视图输出 PNG =====\n")
png("docs/demo_side.png", width = 900, height = 560, res = 110)
tr$actual <- c(tr$impact$x + 30, tr$impact$y - 45)
tr$charge <- 3; tr$az <- 0; tr$range_m <- 8000
plot_side_view(tr, GUNS$D20, 0, list(from_mils = 0, speed = 0), ground_fun = flat)
dev.off()
cat("已输出 docs/demo_side.png\n")

cat("\n全部完成 ✓\n")
