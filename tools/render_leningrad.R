# =====================================================================
# render_leningrad.R — 把列宁格勒历史场景渲染成 PNG 供人工审图
# 用法: Rscript tools/render_leningrad.R   （输出到 output/ 的帧）
# =====================================================================
for (f in c("config.R", "ballistics.R", "map.R", "fdc.R", "ui.R", "mission.R", "game.R")) {
  p <- file.path("..", f); if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}

st <- init_game(gun_key = "B37", test_mode = TRUE, png_dir = "output")
st <- start_scenario(st, "leningrad")

# 一、初始地图（新建帧，draw_state 写 output/frame_00N.png）
draw_state(st)

# 二、计算诸元 + 试射一发 → 弹着帧 + 弹道侧视图
cd <- calc_firing_data(st, st$mission$target$x, st$mission$target$y, verbose = FALSE)
cat(sprintf("试射: 射击 %d %d %d 1\n", round(cd$az_fire), round(cd$el), cd$charge))
st <- dispatch(st, sprintf("射击 %d %d %d 1", round(cd$az_fire), round(cd$el), cd$charge))

cat("已输出地图帧: output/frame_001.png(初始), output/frame_002.png(试射后) 等\n")
