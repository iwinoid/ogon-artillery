# =====================================================================
# gen_manual_tables.R — 从游戏内射表生成 Markdown 表格（供 TUTORIAL.md 引用）
# 运行: Rscript tools/gen_manual_tables.R  (> docs/manual_tables.md 供复制)
# 保证表格与游戏内 build_range_table 完全一致。
# =====================================================================
for (f in c("config.R", "ballistics.R")) {
  p <- file.path("..", f); if (!file.exists(p)) p <- f
  source(p, encoding = "UTF-8")
}
els <- seq(100, 700, by = 100)
for (gk in names(GUNS)) {
  gun <- calibrate_drag(GUNS[[gk]])$gun
  tab <- build_range_table(gun)
  cat(sprintf("\n### %s\n\n", gun$name))
  cat(sprintf("弹重 %.1f kg · %d 档装药（初速 %d~%d m/s）· 高低射界 %d~%d 密位\n\n",
              gun$shell_mass, length(gun$mv), min(gun$mv), max(gun$mv),
              gun$elev_min, gun$elev_max))
  cat(sprintf("| 装药 | %s | 表上最大射程 | 峰值射角 |\n",
              paste(sprintf("%d密位", els), collapse = " | ")))
  cat(paste0("|---|", paste(rep("---|", length(els) + 2), collapse = "")), "\n")
  for (ch in seq_along(gun$mv)) {
    vals <- vapply(els, function(e) {
      v <- tab$rows[tab$rows$charge == ch & tab$rows$el_mils == e, "range_m"]
      if (length(v) == 1) sprintf("%.0f", v) else "—"
    }, character(1))
    cat(sprintf("| %d号 | %s | %.0f m | %d 密位 |\n",
                ch, paste(vals, collapse = " | "),
                tab$max_range[ch], tab$peak_el[ch]))
  }
}
cat("\n注: 表中射程为平地无风标准值；—表示该射角已过峰值角（高射界，射程随射角减小），查游戏内 `射表` 命令可看完整 10 密位步进射表。\n")
