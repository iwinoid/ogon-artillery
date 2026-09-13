# test_scenario.R — 列宁格勒保卫战历史场景测试：7 个史实目标逐一摧毁
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f)
  if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
t0 <- proc.time()
st <- init_game(mode = "std", seed = 1, test_mode = TRUE, png_dir = NULL)
st <- start_scenario(st, "leningrad")
cat(sprintf("场景启动耗时 %.1fs\n", (proc.time() - t0)[3]))

fail <- 0
for (mi in 1:7) {
  if (mi > 1) st <- dispatch(st, "结束")
  if (st$screen != "game") break
  m <- st$mission
  g <- st$guns[[1]]
  r_km <- range_m(g$x, g$y, m$target$x, m$target$y) / 1000
  cd <- calc_firing_data(st, m$target$x, m$target$y, verbose = FALSE)
  for (k in 1:3) {
    if (st$mission$destroyed) break
    st <- fire_volley(st, round(cd$az_fire), round(cd$el), cd$charge, 3)
  }
  ok <- st$mission$destroyed
  if (!ok) fail <- fail + 1
  cat(sprintf("目标%d/7 %-12s 距B37 %5.1fkm 摧毁=%s 累计用弹%2d\n",
              mi, m$target$label, r_km, ok, nrow(st$shots)))
}
cat("战役结束: screen =", st$screen, " 总分 =", st$campaign$total, "\n")
if (fail == 0) cat("全部目标摧毁 ✓\n") else cat(sprintf("失败 %d 个目标 ✗\n", fail))
quit(status = if (fail == 0) 0 else 1)
