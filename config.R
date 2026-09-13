# =====================================================================
# config.R — 火炮/弹药/世界 数据与常量（历史性能，近似值）
# Огонь! 炮兵射击指挥所模拟
# =====================================================================

# ---- 世界常量 ----
MIL_PER_CIRCLE <- 6000      # 密位制：整圆 6000 密位（苏/中式炮兵制）
GRAVITY        <- 9.81      # m/s^2
AIR_DENSITY    <- 1.225     # kg/m^3 海平面标准空气密度

# ---- 地图默认参数 ----
MAP_DEFAULT <- list(
  extent_km = c(0, 20, 0, 20),   # xmin, xmax, ymin, ymax (km)，x 向东 y 向北
  res_m     = 25,               # 地形栅格分辨率 (m)（25m 高清；生成约 1s）
  front_y   = 7.0                # 前沿线 y (km)，炮位在南侧（己方），目标在北侧（敌方）
)

# ---- 火炮构造 ----
# mv: 各装药号初速 (m/s)
# elev_range: 高低射界 (密位)
# max_range_hist: 历史最大射程 (m)，用于校准空气阻力系数
# lethal: HE 弹对软目标杀伤半径 (m)
# disp: c(距离概率误差/射程, 方向概率误差/射程) —— 概率误差 (50% 落弹带)
# explosive_kg: 弹丸装药量 (kg)，仅用于显示（信息字段）
make_gun <- function(name, caliber, shell_mass, mv, charge_names, elev_range,
                     max_range_hist, lethal, dispersion, explosive_kg = NULL) {
  list(name = name, caliber = caliber, shell_mass = shell_mass, mv = mv,
       charge_names = charge_names, elev_min = elev_range[1], elev_max = elev_range[2],
       max_range_hist = max_range_hist, lethal = lethal, disp = dispersion,
       explosive_kg = explosive_kg)
}

# ---- 可选火炮（历史性能近似）----
GUNS <- list(
  D20 = make_gun(
    name = "152mm D-20 榴弹炮（中国59式）",
    caliber = 0.1524, shell_mass = 43.5,
    mv = c(230, 300, 370, 440, 510, 580, 655),
    charge_names = c("0号装药", "1号装药", "2号装药", "3号装药", "4号装药", "5号装药", "6号全装药"),
    elev_range = c(0, 1050),          # 约 -5°~+63°
    max_range_hist = 17410,
    lethal = 40,
    dispersion = c(1/270, 1/600)
  ),
  M46 = make_gun(
    name = "130mm M-46 加农炮（中国59式）",
    caliber = 0.130, shell_mass = 33.4,
    mv = c(420, 540, 660, 780, 930),
    charge_names = c("1号装药", "2号装药", "3号装药", "4号装药", "5号全装药"),
    elev_range = c(0, 750),           # 约 -2.5°~+45°
    max_range_hist = 27150,
    lethal = 35,
    dispersion = c(1/320, 1/700)
  ),
  M109 = make_gun(
    name = "155mm M109A6 自行榴弹炮（M284 39倍径）",
    caliber = 0.155, shell_mass = 43.2,          # M107 HE 榴弹
    mv = c(204, 260, 316, 372, 428, 484, 540, 684),
    charge_names = c("1号装药", "2号装药", "3号装药", "4号装药",
                     "5号装药", "6号装药", "7号装药", "8号全装药"),
    elev_range = c(0, 1250),          # 实际 -3°~+75°（游戏取 0~75°=1250密位）
    max_range_hist = 18100,           # M107 HE 最大射程
    lethal = 50,
    dispersion = c(1/300, 1/650)
  ),
  B4 = make_gun(
    name = "203mm B-4 榴弹炮（M1931 斯大林之锤）",
    caliber = 0.203, shell_mass = 100,          # F-625/OF-625 榴弹 ~100kg
    mv = c(240, 310, 380, 450, 520, 607),
    charge_names = c("1号装药", "2号装药", "3号装药", "4号装药", "5号装药", "6号全装药"),
    elev_range = c(0, 1000),          # 0°~+60°
    max_range_hist = 18025,           # OF-625 最大射程 ~18.0km
    lethal = 75,
    dispersion = c(1/250, 1/550)
  ),
  B37 = make_gun(
    name = "406mm B-37 舰炮（50倍径，未上舰）",
    caliber = 0.406, shell_mass = 1108,         # 穿甲弹 1108kg（战争雷霆数据）
    explosive_kg = 88,                          # 弹丸装药 88kg
    mv = c(300, 410, 520, 630, 730, 830),
    charge_names = c("1号装药", "2号装药", "3号装药", "4号装药", "5号装药", "6号全装药"),
    elev_range = c(0, 750),           # 0°~+45°（最大射程角）
    max_range_hist = 45500,           # 45° 时 ~45.5km
    lethal = 100,
    dispersion = c(1/300, 1/650)
  )
)

# ---- 侦察误差 ----
RECON_ERROR_M <- 15   # 随机战役目标上报坐标 = 真值 + 随机偏移(模长 5~RECON_ERROR_M 米)

# ---- 弹道模型系数（自动校准，见 ballistics.R）----
WIND_DRIFT_FACTOR <- 0.55   # 横风漂移 ≈ 横风分量 × 飞行时间 × 系数
RK4_DT            <- 0.20   # 积分步长 (s)
RK4_MAX_T         <- 200    # 最大飞行时间 (s)

# ---- 难度/辅助模式 ----
MODES <- list(
  arcade = list(name = "街机模式", calculator = TRUE,  suggest = TRUE,  disp_scale = 0.70, show_radius = TRUE),
  std    = list(name = "标准模式", calculator = TRUE,  suggest = FALSE, disp_scale = 1.00, show_radius = TRUE),
  hard   = list(name = "全真模式", calculator = FALSE, suggest = FALSE, disp_scale = 1.00, show_radius = FALSE)
)

# ---- 任务/弹药 ----
AMMO_PER_MISSION <- 60      # 每任务 HE 弹基数
TURNS_LIMIT      <- 30      # 每任务射击命令次数上限
SCORE_SHELL_PENALTY <- 2    # 每发弹扣分
SCORE_TURN_PENALTY  <- 4    # 每次射击命令扣分

# ---- 炮位预设（炮位坐标 km，位于前沿以南）----
GUN_POSITIONS <- list(
  list(x = 3.0,  y = 3.0,  label = "1号炮位"),
  list(x = 10.0, y = 2.5,  label = "2号炮位"),
  list(x = 17.0, y = 3.5,  label = "3号炮位")
)

# ---- 历史场景 ----
# 列宁格勒保卫战场景：B-37 巨炮部署在勒热夫卡靶场（东北郊），轰击南线德军据点。
# 坐标为居民点级近似（纬度 1°≈111km，经度 1°@60°N≈55.5km，以市中心 59.94N,30.32E 为原点 30,30）。
SCENARIOS <- list(
  leningrad = list(
    key = "leningrad",
    name = "列宁格勒保卫战（1942 · B-37 巨炮）",
    desc = paste0(
      "1942 年，实验型 406mm B-37 舰炮（未及上舰）被部署在列宁格勒东北郊的勒热夫卡靶场，\n",
      "依托其 45km 超远射程轰击南线德军。围城期间这门炮共发射约 81 发炮弹，\n",
      "轰击目标包括克拉斯内博尔方向的德军。现在由你接管这门巨炮，\n",
      "把列宁格勒从围困中解救出来。"),
    extent_km = c(12, 76, 0, 44),   # ~64×44 km，覆盖列宁格勒与南线德军
    res_m = 150,
    gun_key = "B37",
    gun_positions = list(
      list(x = 41.1, y = 38.9, label = "B-37 勒热夫卡靶场")
    ),
    targets = list(
      list(x = 16.7, y = 7.8,  label = "红村德军阵地",     radius = 150),
      list(x = 34.4, y = 5.6,  label = "普希金城·德军炮兵", radius = 150),
      list(x = 37.2, y = 1.1,  label = "巴甫洛夫斯克德军",  radius = 150),
      list(x = 48.9, y = 1.1,  label = "克拉斯内博尔",      radius = 150),
      list(x = 70.5, y = 8.9,  label = "姆加·铁路枢纽",     radius = 200),
      list(x = 69.4, y = 30.0, label = "什利谢利堡要塞",    radius = 120),
      list(x = 71.6, y = 25.6, label = "锡尼亚维诺高地",    radius = 150)
    ),
    # 示意地理：涅瓦河、拉多加湖、芬兰湾、列宁格勒城区、战线
    geography = list(
      city = list(x = 30.0, y = 30.0, label = "列宁格勒"),
      # 涅瓦河主河道：按沿线城镇经纬度换算（km 坐标，精度 ~1km）
      # 源头拉多加湖 59.944N,31.03E → 杜布罗夫卡 59.85,30.93 → 奥特拉德诺耶 59.77,30.82
      # → 乌斯季伊若拉 59.82,30.55 → 城区 59.94,30.31 → 芬兰湾口 59.96,30.2
      river = list(
        x = c(68.6, 67.0, 63.9, 61.2, 57.8, 53.5, 48.5, 42.8, 38.5, 34.4, 30.5, 27.7, 25.0),
        y = c(29.6, 26.5, 20.0, 14.8, 11.1, 11.9, 14.0, 16.7, 21.5, 28.9, 30.1, 30.8, 31.4),
        label = "涅瓦河"),
      # 三角洲分汊（城区→芬兰湾两岔）
      river_arms = list(
        list(x = c(34.4, 31.5, 28.5, 26.0), y = c(28.9, 31.2, 32.2, 32.8)),
        list(x = c(34.4, 31.8, 28.8, 26.2), y = c(28.9, 27.2, 26.2, 25.6))
      ),
      water = list(
        data.frame(x = c(65, 76, 76, 69, 65), y = c(28, 28, 44, 41, 35)),  # 拉多加湖（东北）
        data.frame(x = c(12, 20, 21, 17, 12), y = c(0, 2, 16, 31, 28))      # 芬兰湾（西）
      ),
      water_labels = list(
        list(x = 72, y = 37, label = "拉多加湖"),
        list(x = 15, y = 24, label = "芬兰湾")
      ),
      frontline = data.frame(
        x = c(14, 40, 58, 69, 76),
        y = c(12, 7, 10, 28, 26)
      ),
      # 地图标注地点（非打击目标的德军据点 + 苏军据点；坐标按经纬度换算）
      places = list(
        list(x = 19.4, y = -10.5, label = "加特契纳·德军",     side = "german"),
        list(x = 61.1, y = -10.5, label = "托斯诺·德军",       side = "german"),
        list(x = 7.0,  y = 36.7,  label = "克朗施塔特·苏军",   side = "soviet", island = TRUE),
        list(x = 7.0,  y = 26.7,  label = "奥拉宁鲍姆·苏军",   side = "soviet"),
        list(x = 13.9, y = 20.0,  label = "斯特列利纳·苏军",   side = "soviet"),
        list(x = 30.0, y = 12.2,  label = "普尔科沃高地·苏军", side = "soviet"),
        list(x = 45.0, y = 8.9,   label = "科尔皮诺·苏军",     side = "soviet"),
        list(x = 10.0, y = 47.8,  label = "谢斯特罗列茨克·苏军", side = "soviet"),
        list(x = 66.7, y = 23.3,  label = "基洛夫斯克·苏军",   side = "soviet"),
        list(x = 50.0, y = 38.9,  label = "弗谢沃洛日斯克·苏军", side = "soviet")
      )
    )
  )
)
