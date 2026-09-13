# =====================================================================
# ui.R — 控制台界面：颜色、面板、命令读取、帮助、游戏内教程
# =====================================================================
# 菜单函数在 game.R（source 顺序下 game.R 覆盖本文件同名定义）

.USE_COLOR <- TRUE
set_color <- function(on) .USE_COLOR <<- on

# 是否运行在 RStudio 中（RStudio 用 Plots 窗格显示图形，不开独立窗口）
is_rstudio <- function() identical(Sys.getenv("RSTUDIO"), "1")

cc <- function(code, s) if (.USE_COLOR) paste0("\033[", code, "m", s, "\033[0m") else s
c_red    <- function(s) cc(31, s)
c_green  <- function(s) cc(32, s)
c_yellow <- function(s) cc(33, s)
c_cyan   <- function(s) cc(36, s)
c_bold   <- function(s) cc(1, s)

cls <- function() cat("\014")
hr  <- function(ch = "=", n = 64) cat(strrep(ch, n), "\n")

# 中文输入兼容：把可能的 GBK/BIG5 控制台输入转成 UTF-8
norm_input <- function(s) {
  if (is.null(s) || !nzchar(s)) return(s)
  s <- trimws(s)
  if (grepl("[\u4e00-\u9fff]", s)) return(s)          # 已是含中文的 UTF-8
  for (enc in c("GBK", "GB18030", "BIG5")) {
    s2 <- tryCatch(iconv(s, from = enc, to = "UTF-8"),
                   error = function(e) NA_character_)
    if (!is.na(s2) && grepl("[\u4e00-\u9fff]", s2)) return(s2)
  }
  s
}

read_cmd <- function(prompt = "指挥所> ") {
  norm_input(readline(prompt))
}

# 任务标题（教程关显示"教程关"，其余显示"任务 #N"）
mission_label <- function(m) {
  if (is.null(m)) return("")
  if (m$index == 0) "教程关" else sprintf("任务 #%d", m$index)
}

# ---- 状态面板（每回合打印，不清屏，避免擦掉上一条命令的输出）----
panel <- function(state) {
  m <- state$mission
  cat(c_bold(c_cyan("  ОГОНЬ! 炮兵射击指挥所  ")), "  [",
      state$mode_cfg$name, "]\n", sep = "")
  hr("-")
  if (is.null(m) || m$done) {
    cat("  （当前无进行中的任务）\n")
  } else {
    cat(sprintf("  %s  %s\n", mission_label(m), c_yellow(m$name)))
    cat(sprintf("  目标: (%.2f, %.2f) km  %s  摧毁半径 %dm\n",
                m$target$x, m$target$y, m$target$label, m$target$radius))
  }
  g <- state$guns[[state$gun_sel]]
  cat(sprintf("  炮位: %s (%.1f, %.1f)   %s\n",
              g$label, g$x, g$y, state$gun$name))
  cat(sprintf("  弹药: %s  射击命令: %d/%d\n",
              c_yellow(sprintf("%d/%d", state$ammo, AMMO_PER_MISSION)),
              state$turns, TURNS_LIMIT))
  if (!is.null(state$wind)) {
    cat(sprintf("  气象: 风自 %d 密位  %d m/s\n", state$wind$from_mils, state$wind$speed))
  }
  if (nzchar(state$last_report)) {
    cat("  观察: ", state$last_report, "\n", sep = "")
  }
  hr("-")
  cat("  命令: 帮助  任务  地图  诸元  射击  修正  射表  弹道  结束  退出\n")
}

# ---- 帮助 ----
help_text <- function() {
  cat(c_bold("命令速查（中文/英文均可）\n"))
  hr("-")
  cat("  帮助/help         命令列表      教程/tutorial   游戏内教程\n")
  cat("  任务/mission      任务简报      地图/map        重绘地图窗口\n")
  cat("  情况/status       状态总览      炮位/guns       列出炮位\n")
  cat("  选择 <n>/sel <n>  切换炮位      射表 [装药]/table  查射表\n")
  cat("  诸元 <x> <y>      指挥所计算器（目标坐标 km；或诸元 target）\n")
  cat("  射击 <方位> <高低> <装药> [弹数]   试射/射击（弹数 1~6）\n")
  cat("  急促 <方位> <高低> <装药>   急促射 3 发\n")
  cat("  效力 <方位> <高低> <装药>   效力射（≤6发，摧毁即停）\n")
  cat("  修正 <距离偏差> <方向偏差>  观察员报告→密位修正量（米→密位）\n")
  cat("  弹道 [n]/traj    第 n 发弹道侧视图（默认上一发）\n")
  cat("  地图样式/style   战术/照片切换（米黄底+等高线 / 实景）\n")
  cat("  气象/wind         风况          成绩/score     当前成绩\n")
  cat("  结束/end         结束任务结算    退出/quit      退出游戏\n")
  hr("-")
  cat("  例: 射击 2350 420 3 1   → 方位2350密位 高低420密位 3号装药 1发\n")
  cat("  例: 诸元 target         → 对当前任务目标计算装订卡片\n")
  cat("  RStudio: 地图在 Plots 窗格；射击后输 地图 重绘回地图\n")
  cat("  完整教程见 TUTORIAL.md\n")
}

# ---- 游戏内教程（简版）----
tutorial_text <- function() {
  cat(c_bold("炮兵知识速成\n"))
  hr("-")
  cat("  密位: 整圆6000密位。1密位 ≈ 距离1000m处的1m。\n")
  cat("  方位: 自北顺时针 0~5999（北0 东1500 南3000 西4500）\n")
  cat("  高低: 炮管仰角(密位)，1000密位=60°。射角越大射程越远，\n")
  cat("        超过约40°(最大射程角)后进入高射界，射程反而变短。\n")
  cat("  装药: 越大初速越高射程越远。够用就行——小装药散布小。\n")
  cat("  射表: 射角→射程对照，射程内插取密位（命令: 射表）\n")
  hr("-")
  cat("  修正口诀（观察员: 近弹120 偏左35，单位米）:\n")
  cat("    近弹→加射角  远弹→减射角  偏左→方位加  偏右→方位减\n")
  cat("    方位密位 = 偏差米 ÷ 射程(km)；高低密位 = 偏差米 ÷ 每密位米数\n")
  cat("    用 修正 <近远偏差> <左右偏差> 自动换算\n")
  hr("-")
  cat("  流程: 任务 → 诸元 target → 试射1发 → 看观察报告 → 修正 → 急促射 → 效力射\n")
  cat("  散布: 距离/方向随机误差随射程增大，10km 处约 ±30~55m 级，\n")
  cat("        所以试射修正必不可少。弹药60发，每发扣2分、每次射击扣4分。\n")
  cat("  弹道侧视图: 每次射击后刷新副窗口（弹道/traj 可重看）\n")
  cat("  详细教程见 TUTORIAL.md\n")
}
