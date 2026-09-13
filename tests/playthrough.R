# =====================================================================
# playthrough.R — AI 玩家试玩：三个模式各打一整场战役（4任务），
# 全程通过命令界面操作并转录到 docs/playthrough_logs/
# 运行: Rscript tests/playthrough.R
# =====================================================================
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f)
  if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}

# 观察员报告读数（取最后一发）
last_deviation <- function(st) {
  last <- tail(st$shots, 1)
  c(dR = last$dR, dD = last$dD)
}

# 打一个任务
play_mission <- function(st) {
  st <- dispatch(st, "任务")
  t <- st$mission$target
  g <- st$guns[[st$gun_sel]]

  # 1) 装订诸元：街机/标准用计算器，全真手算
  if (st$mode_cfg$calculator) {
    st <- dispatch(st, "诸元 target")
    cd <- calc_firing_data(st, t$x, t$y, verbose = FALSE)
    az <- round(cd$az_fire); el <- round(cd$el); ch <- cd$charge
  } else {
    r <- range_m(g$x, g$y, t$x, t$y)
    ch <- charge_for_range(st$table, r)
    el0 <- elevation_for_range(st$table, ch, r)
    g_alt <- terrain_elev_at(st$map, g$x * 1000, g$y * 1000)
    t_alt <- terrain_elev_at(st$map, t$x * 1000, t$y * 1000)
    site <- site_mils(g_alt, t_alt, r)
    az <- round(azimuth_mils(g$x, g$y, t$x, t$y))
    el <- round(el0 + site)
    cat(sprintf("（全真手算: 方位%d密位 射程%.0fm 装药%d 射表%d+高差%.1f → 高低%d）\n",
                az, r, ch, round(el0), site, el))
  }

  # 2) 试射 1 发
  cat("> 射击", az, el, ch, "1\n")
  st <- dispatch(st, sprintf("射击 %d %d %d 1", az, el, ch))

  # 3) 看观察报告 → 修正 → 再射（直到偏差进入半径的 40% 或摧毁）
  rad <- st$mission$target$radius
  for (i in 1:8) {
    if (st$mission$destroyed) break
    dev <- last_deviation(st)
    if (abs(dev["dR"]) < 0.4 * rad && abs(dev["dD"]) < 0.4 * rad) break
    if (st$mode_cfg$calculator) {
      st <- dispatch(st, sprintf("修正 %.0f %.0f", dev["dR"], dev["dD"]))
    } else {
      cat(sprintf("（全真手算修正: 近远%.0fm 左右%.0fm → 换算密位）\n",
                  dev["dR"], dev["dD"]))
    }
    last <- st$traj_log[[length(st$traj_log)]]
    r_tgt <- range_m(g$x, g$y, t$truth_x %||% t$x, t$truth_y %||% t$y)
    cc <- correction_from_observer(st$table, last$charge, r_tgt, last$el,
                                   dev["dR"], dev["dD"])
    az <- round((last$az + cc$daz_mils) %% MIL_PER_CIRCLE)
    el <- round(last$el + cc$del_mils)
    ch <- last$charge
    cat("> 射击", az, el, ch, "1\n")
    st <- dispatch(st, sprintf("射击 %d %d %d 1", az, el, ch))
  }

  # 4) 急促射 3 发
  if (!st$mission$destroyed) {
    cat("> 急促", az, el, ch, "\n")
    st <- dispatch(st, sprintf("急促 %d %d %d", az, el, ch))
  }
  # 5) 效力射（最多三轮，摧毁即停）
  for (k in 1:3) {
    if (st$mission$destroyed || st$mission$done) break
    cat("> 效力", az, el, ch, "\n")
    st <- dispatch(st, sprintf("效力 %d %d %d", az, el, ch))
  }
  # 6) 结算 → 下一任务
  cat("> 结束\n")
  st <- dispatch(st, "结束")
  st
}

# 打一整场战役（4 个任务），转录到文件
play_campaign <- function(mode, seed) {
  out <- file.path("docs", "playthrough_logs", sprintf("session_%s_seed%d.txt", mode, seed))
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  sink(out)
  on.exit(sink(), add = TRUE)
  cat("══════════════════════════════════════════════════\n")
  cat(sprintf("ОГОНЬ! 试玩对局   模式: %s   随机种子: %d\n",
              MODES[[mode]]$name, seed))
  cat("══════════════════════════════════════════════════\n\n")
  st <- init_game(mode = mode, seed = seed, test_mode = TRUE, png_dir = NULL)
  st <- start_campaign(st)
  repeat {
    if (st$screen != "game") break
    st <- play_mission(st)
  }
  invisible(st)
}

play_campaign("arcade", 20240601)
play_campaign("std", 777)
play_campaign("hard", 55555)
cat("试玩结束，转录见 docs/playthrough_logs/\n")
