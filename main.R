# =====================================================================
# main.R — ОГОНЬ! 炮兵射击指挥所 入口
# 用法:
#   Rscript main.R                    标准模式
#   Rscript main.R --mode arcade      街机模式
#   Rscript main.R --mode hard        全真模式
#   Rscript main.R --gun M46          130mm 加农炮
#   Rscript main.R --seed 42          固定随机种子
#   Rscript main.R --map data/dem_cache.rds   真实地形
#   Rscript main.R --test cmds.txt --pngdir docs/frames   脚本化对局(测试)
# =====================================================================

# ---- 定位本脚本目录并切换到游戏目录 ----
# 兼容三种启动方式:
#   Rscript main.R          → 命令行 --file= 参数
#   RStudio Source / source() → 调用帧的 ofile（脚本文件路径）
#   控制台逐行粘贴          → 无路径信息，保持当前目录（后续相对路径按惯例）
# 修复: 在 RStudio 控制台 source(".../Огонь!/main.R") 但工作目录不在游戏目录时，
#       原来 source("config.R") 等相对路径会找不到文件。
locate_game_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  if (length(fa)) return(dirname(normalizePath(sub("^--file=", "", fa[1]))))
  for (fr in sys.frames()) {
    if (!is.null(fr$ofile)) return(dirname(normalizePath(fr$ofile)))
  }
  NULL
}
args <- commandArgs(trailingOnly = TRUE)
get_flag <- function(name, default = NULL) {
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args

mode    <- get_flag("--mode", "std")
gun_key <- get_flag("--gun", "D20")
map_file<- get_flag("--map", NULL)
seed_s  <- get_flag("--seed", NULL)
test_f  <- get_flag("--test", NULL)
png_dir <- get_flag("--pngdir", file.path("docs", "frames"))
scen_s  <- get_flag("--scenario", NULL)

# 路径参数按启动目录语义解析（setwd 前先绝对化，防止切换目录后相对路径失效）
abs_path <- function(p) if (!is.null(p) && nzchar(p)) normalizePath(path.expand(p), mustWork = FALSE) else p
test_f   <- abs_path(test_f)
map_file <- abs_path(map_file)
png_dir  <- abs_path(png_dir)

# ---- 切换到游戏目录（在路径绝对化之后、source 模块之前）----
gdir <- locate_game_dir()
if (!is.null(gdir) && normalizePath(getwd()) != normalizePath(gdir)) {
  setwd(gdir)
  cat(sprintf("（已切换到游戏目录: %s）\n", gdir))
}

for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  source(f, encoding = "UTF-8")
}
if (has_flag("--nocolor")) set_color(FALSE)

if (!mode %in% names(MODES)) stop("未知模式: ", mode, "（可选 arcade/std/hard）")
if (!gun_key %in% names(GUNS)) stop("未知火炮: ", gun_key, "（可选 ", paste(names(GUNS), collapse = "/"), "）")
if (!is.null(scen_s) && !scen_s %in% names(SCENARIOS)) {
  stop("未知场景: ", scen_s, "（可选 ", paste(names(SCENARIOS), collapse = "/"), "）")
}

seed <- if (!is.null(seed_s)) as.integer(seed_s) else NULL
map  <- if (!is.null(map_file)) {
  if (!file.exists(map_file)) stop("DEM 缓存不存在: ", map_file)
  load_dem_cache(map_file)
} else NULL

if (!is.null(test_f)) {
  cmds <- readLines(test_f, warn = FALSE, encoding = "UTF-8")
  cmds <- cmds[!grepl("^\\s*(#|$)", cmds)]
  st <- init_game(map = map, mode = mode, gun_key = gun_key, seed = seed,
                  test_mode = TRUE, png_dir = png_dir)
  st <- if (!is.null(scen_s)) start_scenario(st, scen_s) else start_campaign(st)
  invisible(game_loop(st, commands = cmds))
} else {
  cat("ОГОНЬ! 炮兵射击指挥所 —— 教程见 TUTORIAL.md，输入 帮助 查看命令\n")
  if (is_rstudio()) {
    cat("（RStudio 模式：地图显示在 Plots 窗格；射击后弹道侧视图会临时覆盖，输入 地图 重绘回地图）\n")
  }
  st <- init_game(map = map, mode = mode, gun_key = gun_key, seed = seed,
                  test_mode = FALSE)
  if (!is.null(scen_s)) {
    st <- start_scenario(st, scen_s)
    while (!st$quit && st$screen == "game") st <- game_loop(st)
  } else {
    while (!st$quit) {
      if (st$screen == "menu") {
        st <- main_menu(st)
      } else {
        st <- game_loop(st)
      }
    }
  }
  cat("已退出，再见！\n")
}
