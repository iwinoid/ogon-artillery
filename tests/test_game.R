# =====================================================================
# test_game.R — 集成测试：几何、任务、试射-修正-效力射、脚本对局
# 运行: Rscript tests/test_game.R    （失败时退出码非0）
# =====================================================================
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f)
  if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
fail <- 0
ok <- function(cond, msg) {
  if (isTRUE(cond)) cat("  ✓", msg, "\n")
  else { cat("  ✗", msg, "\n"); fail <<- fail + 1 }
}

cat("===== 1. 几何与单位 =====\n")
ok(azimuth_mils(0, 0, 1, 0) == 1500, "正东=1500密位")
ok(azimuth_mils(0, 0, 0, 1) == 0, "正北=0密位")
ok(azimuth_mils(0, 0, -1, 0) == 4500, "正西=4500密位")
ok(abs(range_m(0, 0, 3, 4) - 5000) < 1, "距离计算 5000m")
ok(abs(site_mils(100, 200, 10000) - atan2(100, 10000) * 3000 / pi) < 1e-6, "高差角公式")
ok(wind_drift_m(list(from_mils = 900, speed = 10), 0, 30) < 0, "东风→弹向西(左)偏")

cat("\n===== 2. 初始化、主菜单与战役 =====\n")
st <- init_game(seed = 11, mode = "std", test_mode = TRUE, png_dir = "docs/frames")
ok(st$screen == "menu" && is.null(st$mission), "初始化停在主菜单")
ok(st$gun$name == GUNS$D20$name, "默认 D-20")
st <- dispatch_menu(st, "5")   # 帮助
ok(st$map_style == "photo", "默认照片样式")
st <- dispatch_menu(st, "4")   # 样式切换
ok(st$map_style == "tactical", "菜单切换地图样式→战术")
st <- dispatch_menu(st, "4")
ok(st$map_style == "photo", "样式切回照片")
st <- dispatch_menu(st, "2")   # 切模式 std→hard
ok(st$mode == "hard", "菜单切换模式")
st <- dispatch_menu(st, "2")
st <- dispatch_menu(st, "2")   # 循环回 std
ok(st$mode == "std", "模式循环")
st <- dispatch_menu(st, "3")   # D20→M46
ok(st$gun_key == "M46", "菜单切换火炮")
st <- dispatch_menu(st, "3")   # M46→M109
ok(st$gun_key == "M109", "循环到 M109")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "B4", "循环到 B-4")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "B37", "循环到 B-37")
st <- dispatch_menu(st, "3")
ok(st$gun_key == "D20", "循环回 D20")
# 开始战役子菜单：0 返回 → 1 遭遇战
st <- menu_campaign(st)              # test_mode 直接返回（无 commands）
ok(st$screen == "menu", "子菜单：test_mode 无命令即返回")
st <- menu_campaign(st, commands = c("0"))
ok(st$screen == "menu", "子菜单：0 返回")
st <- menu_campaign(st, commands = c("1"))
ok(st$screen == "game" && st$mission_index == 1 && !is.null(st$mission), "子菜单：遭遇战进入任务1")
ok(st$ammo == AMMO_PER_MISSION, "弹药基数正确")
ok(st$mission$target$y > st$map$front_y, "目标在前沿以北")
ok(max(st$table$max_range) > 17000, "D-20 表上最大射程 >17km")
ok(nrow(st$map$elev) > 100, "地形矩阵规模")

cat("\n===== 3. 试射-修正-效力射流程 =====\n")
m <- st$mission
cd <- calc_firing_data(st, m$target$x, m$target$y)
ok(cd$ok, "计算器出卡")
ok(cd$charge >= 1 && cd$charge <= length(st$gun$mv), "装药号合法")
st <- fire_volley(st, round(cd$az_fire), round(cd$el), cd$charge, 1)
ok(nrow(st$shots) == 1, "试射 1 发入账")
ok(st$ammo == AMMO_PER_MISSION - 1, "弹药扣减正确")
ok(length(st$traj_log) == 1, "弹道记录保存")
corr <- correction_from_observer(st$table, cd$charge, cd$range, cd$el, -120, -35)
ok(corr$del_mils > 0 && corr$daz_mils > 0, "近弹偏左→加高低+加方位")
# 修正换算符号方向验证：近弹-120m → 弹道修正应让射程增加
rpm <- range_per_mil(st$table, cd$charge, round(cd$el))
ok(abs(corr$del_mils * rpm - 120) < 1, "高低修正量×每密位射程≈偏差距离")
# 计算器装订 → 急促射×多轮直到摧毁（固定种子，确定性）
for (i in 1:6) {
  if (!is.null(st$mission) && st$mission$destroyed) break
  st <- fire_volley(st, round(cd$az_fire), round(cd$el), cd$charge, 3)
}
ok(!is.null(st$mission) && st$mission$destroyed, "目标被摧毁")
sc <- score_mission(st)
ok(sc$score >= 0 && sc$score <= 100, "评分范围 0~100")
ok(sc$shells == nrow(st$shots), "用弹数一致")
st <- next_mission(st)
ok(st$mission_index == 2 && !is.null(st$mission), "自动进入任务2")
ok(length(st$campaign$scores) == 1, "任务1成绩已入账")

cat("\n===== 3.5 教程关 =====\n")
stt <- init_game(seed = 20, mode = "std", test_mode = TRUE, png_dir = "docs/frames")
stt <- menu_campaign(stt, commands = c("3"))
ok(stt$screen == "game" && stt$mission$key == "tutorial", "菜单进入教程关")
ok(stt$mission$target$radius == 150 && stt$wind$speed == 0, "教程目标大半径无风")
stt <- dispatch(stt, "诸元 target")   # 计算器给卡片
ok(nrow(stt$shots) == 0, "教程尚未射击")
# 打一发（目标半径150，计算器装订必命中）
cdt <- calc_firing_data(stt, stt$mission$target$x, stt$mission$target$y, verbose = FALSE)
stt <- dispatch(stt, sprintf("射击 %d %d %d 1", round(cdt$az_fire), round(cdt$el), cdt$charge))
ok(stt$mission$destroyed, "教程一发命中摧毁")
stt <- dispatch(stt, "结束")
ok(stt$screen == "menu" && is.null(stt$tutorial), "教程结束回主菜单")
stt3 <- init_game(seed = 21, mode = "std", test_mode = TRUE)
stt3 <- dispatch_menu(stt3, "教程")
ok(stt3$screen == "game" && stt3$mission$key == "tutorial", "旧关键字 教程 直达教程关")
stt4 <- init_game(gun_key = "B37", seed = 22, test_mode = TRUE)
stt4 <- menu_campaign(stt4, commands = c("2", "1"))   # 史实 → 场景1 列宁格勒
ok(stt4$screen == "game" && stt4$scenario$key == "leningrad", "子菜单：史实→列宁格勒")
stt5 <- init_game(gun_key = "B37", seed = 23, test_mode = TRUE)
stt5 <- dispatch_menu(stt5, "场景")
ok(is.null(stt5$scenario), "旧关键字 场景 不崩溃（test_mode 无输入返回）")

cat("\n===== 5.5 侦察偏移（生成）=====\n")
sr <- init_game(seed = 99, mode = "std", test_mode = TRUE, png_dir = "docs/frames8")
sr <- start_campaign(sr)
t7 <- sr$mission$target
ok(!is.null(t7$truth_x) && !is.null(t7$truth_y), "随机任务带侦察真值 truth_x/truth_y")
derr <- sqrt((t7$x - t7$truth_x)^2 + (t7$y - t7$truth_y)^2) * 1000
ok(derr >= 5 - 0.05 && derr <= 15 + 0.05, sprintf("侦察误差 %.1f m ∈ [5,15]（上报→真值）", derr))
# 接 5.5: 判定读真值（构造极小半径，仅真值处命中才摧毁）
# 用固定 15m 偏移 + 5m 半径，只有真值读法会判摧毁，上报读法会判未摧毁
st_manual <- sr
st_manual$mission$target <- list(x = 10.015, y = 10.0,
                                truth_x = 10.0, truth_y = 10.0,
                                label = "测试靶", radius = 5)
st_manual$mission$destroyed <- FALSE; st_manual$mission$done <- FALSE
st_manual$shots <- data.frame(x = 10.0, y = 10.0, turn = 1, dR = 0, dD = 0)
st_manual <- check_destroyed(st_manual)
ok(st_manual$mission$destroyed, "弹着在真值处判定摧毁（读真值，5m半径）")
st_manual2 <- sr
st_manual2$mission$target <- list(x = 10.015, y = 10.0,
                                 truth_x = 10.0, truth_y = 10.0,
                                 label = "测试靶", radius = 5)
st_manual2$mission$destroyed <- FALSE; st_manual2$mission$done <- FALSE
st_manual2$shots <- data.frame(x = 10.015, y = 10.0, turn = 1, dR = 0, dD = 0)
st_manual2 <- check_destroyed(st_manual2)
ok(!st_manual2$mission$destroyed, "弹着在上报处不应摧毁（真值 15m 外，5m半径）")
# 教程关与历史场景不带 truth（回退路径，行为不变）
stt2 <- init_game(seed = 98, mode = "std", test_mode = TRUE)
stt2 <- start_tutorial(stt2)
ok(is.null(stt2$mission$target$truth_x), "教程关无侦察偏移（无 truth）")
sts2 <- init_game(gun_key = "B37", seed = 97, test_mode = TRUE)
sts2 <- start_scenario(sts2, "leningrad")
ok(is.null(sts2$mission$target$truth_x), "历史场景无侦察偏移（无 truth）")

cat("\n===== 4. 脚本化对局（命令解析）=====\n")
script <- c("帮助", "地图", "任务", "气象", "炮位", "选择 2",
            "诸元 target", "射击 100 100 1 1",
            "诸元", "射击", "修正", "选择", "急促", "效力", "弹道",  # 裸命令应给用法提示而非崩溃
            "退出", "退出")
st2 <- init_game(seed = 5, mode = "arcade", test_mode = TRUE, png_dir = "docs/frames2")
st2 <- start_campaign(st2)
st2 <- game_loop(st2, commands = script)
ok(st2$screen == "menu", "脚本对局：退出返回主菜单")
ok(st2$gun_sel == 2, "选择 2 切换炮位")
frames <- list.files("docs/frames", pattern = "\\.png$")
ok(length(frames) > 2, sprintf("地图帧已输出 (%d 张)", length(frames)))
trajs <- list.files("docs/frames", pattern = "^traj_")
ok(length(trajs) >= 1, "弹道侧视图帧已输出")

cat("\n===== 5. 其他火炮与模式 =====\n")
st3 <- init_game(gun_key = "M46", mode = "hard", seed = 3, test_mode = TRUE,
                 png_dir = "docs/frames3")
ok(length(st3$gun$mv) == 5, "M-46 五档装药")
ok(max(st3$table$max_range) > 25000, "M-46 表上最大射程 >25km")
ok(st3$mode_cfg$calculator == FALSE && st3$mode_cfg$show_radius == FALSE, "全真模式关闭辅助")

st4 <- init_game(gun_key = "M109", mode = "std", seed = 4, test_mode = TRUE,
                 png_dir = "docs/frames4")
ok(length(st4$gun$mv) == 8, "M109 八档装药")
ok(max(st4$table$max_range) > 18000 && max(st4$table$max_range) < 19500, "M109 表上最大射程≈18km")
ok(st4$gun$elev_max == 1250, "M109 高低射界 75°(1250密位)")

st5 <- init_game(gun_key = "B4", mode = "std", seed = 6, test_mode = TRUE,
                 png_dir = "docs/frames5")
ok(length(st5$gun$mv) == 6, "B-4 六档装药")
ok(max(st5$table$max_range) > 17500 && max(st5$table$max_range) < 19000, "B-4 表上最大射程≈18km")
ok(st5$gun$elev_max == 1000, "B-4 高低射界 60°(1000密位)")
ok(st5$gun$shell_mass == 100, "B-4 弹重 100kg")

st6 <- init_game(gun_key = "B37", mode = "std", seed = 8, test_mode = TRUE,
                 png_dir = "docs/frames6")
ok(length(st6$gun$mv) == 6, "B-37 六档装药")
ok(max(st6$table$max_range) > 44000 && max(st6$table$max_range) < 47000, "B-37 表上最大射程≈45.5km")
ok(st6$gun$shell_mass == 1108, "B-37 弹重 1108kg（战争雷霆数据）")
ok(st6$gun$explosive_kg == 88, "B-37 装药 88kg")
ok(st6$gun$disp[1] == 1/300, "B-37 距离散布 1/300")

cat("\n===== 6. 据点附近弹着报告 =====\n")
stp <- init_game(gun_key = "B37", mode = "std", seed = 7, test_mode = TRUE,
                 png_dir = "docs/frames7")
stp <- start_scenario(stp, "leningrad")
# 加特契纳(19.4,-10.5)/托斯诺在场景范围外已被剔除；用范围内合成德军据点测识别
stp$map$places <- c(stp$map$places,
                    list(list(x = 20, y = 10, label = "测试·德军", side = "german")))
pl_g <- nearby_place(stp, 20, 10)
ok(!is.null(pl_g) && pl_g$side == "german", "德军据点被识别")
pl_s <- nearby_place(stp, 45.0, 8.9)            # 科尔皮诺（苏军）
ok(!is.null(pl_s) && pl_s$side == "soviet", "苏军据点被识别")
ok(is.null(nearby_place(stp, 30, 30)), "远离据点的弹着无报告")
# 实际射击：故意打偏到苏军据点科尔皮诺附近（目标第1个是红村，射向偏右）
cat("（模拟弹着报告）\n")
stp$shots <- data.frame(x = 45.2, y = 9.1, turn = 1, dR = 100, dD = 100)
pl2 <- nearby_place(stp, 45.2, 9.1)
ok(!is.null(pl2) && pl2$side == "soviet", "弹着靠近苏军据点可被报告")

cat("\n===== 结果 =====\n")
if (fail == 0) {
  cat("全部通过 ✓\n")
} else {
  cat(sprintf("失败 %d 项 ✗\n", fail))
  quit(status = 1)
}
