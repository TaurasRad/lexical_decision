plot_exposure <- function(file = NULL) {
  if (is.null(file)) {
    files <- list.files(pattern = "^subject-[0-9]+\\.csv$")
    if (!length(files)) stop("No subject-*.csv files found")
    file <- files[which.max(file.info(files)$mtime)]
  }

  d <- read.csv(file, stringsAsFactors = FALSE)
  d <- d[d$data_row_type == "trial" & d$adaptive_phase == "experimental", ]
  if (!nrow(d)) stop("No experimental trial rows found in ", file)
  d <- d[order(d$experimental_trial_count), ]

  categories <- c("HF", "LF", "Pseudo", "Random")
  columns <- paste0("exposure_", categories)
  if (!all(columns %in% names(d))) stop("Exposure columns are missing")

  limits <- range(c(2000, unlist(d[columns])), na.rm = TRUE)
  if (diff(limits) == 0) limits <- limits + c(-50, 50)
  colors <- c("#0072B2", "#009E73", "#D55E00", "#CC79A7")

  old_par <- par(no.readonly = TRUE)
  on.exit(par(old_par))
  par(mfrow = c(2, 2), mar = c(4, 4, 2, 1), oma = c(0, 0, 2, 0))

  for (i in seq_along(categories)) {
    category <- categories[i]
    changed <- d$adaptive_category == category
    plot(c(0, d$experimental_trial_count), c(2000, d[[columns[i]]]),
         type = "s", col = colors[i], lwd = 2, ylim = limits,
         xlab = "Test word", ylab = "Exposure time (ms)", main = category)
    points(d$experimental_trial_count[changed], d[[columns[i]]][changed],
           pch = 16, col = colors[i])
    grid()
  }

  mtext(paste("Exposure trajectories:", basename(file)),
        outer = TRUE, font = 2)
  invisible(d)
}

show_exposure_plots <- function(file = NULL) {
  if (dev.cur() == 1L) dev.new(width = 10, height = 8)
  plot_exposure(file)
}

save_exposure_plots <- function(file = NULL,
                                output = "exposure_plots.png") {
  png(output, width = 1400, height = 1000, res = 150)
  on.exit(dev.off())
  plot_exposure(file)
  normalizePath(output, mustWork = FALSE)
}

if (interactive()) {
  show_exposure_plots()
} else if (sys.nframe() == 0L) {
  message("Saved: ", save_exposure_plots())
}
