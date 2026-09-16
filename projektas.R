# DATA
library(readr)
library(dplyr)
library(mgcv)

results <- "C:/Users/taura/OneDrive/Desktop/Methods in CSS/Project/results"

subject_8 <- read_csv(file.path(results, "subject-8.csv"))
subject_8$file_name <- "subject-8"
View(subject_8)

subject_9 <- read_csv(file.path(results, "subject-9.csv"))
subject_9$file_name <- "subject-9"
View(subject_9)

subject_10 <- read_csv(file.path(results, "subject-10.csv"))
subject_10$file_name <- "subject-10"
View(subject_10)

subject_11 <- read_csv(file.path(results, "subject-11.csv"))
subject_11$file_name <- "subject-11"
View(subject_11)

subject_12 <- read_csv(file.path(results, "subject-12.csv"))
subject_12$file_name <- "subject-12"
View(subject_12)

subject_13 <- read_csv(file.path(results, "subject-13.csv"))
subject_13$file_name <- "subject-13"
View(subject_13)

merged <- rbind(subject_8, subject_9, subject_10, subject_11, subject_12, subject_13)
View(merged)

# Z SCORE
z_cutoff <- 3

plot_data <- merged %>%
  filter(data_row_type == "trial", adaptive_phase == "experimental") %>%
  group_by(file_name) %>%
  mutate(z_rt = as.numeric(scale(RT))) %>%
  ungroup()

removed_trials <- plot_data %>%
  filter(abs(z_rt) > z_cutoff)
View(removed_trials)

plot_data <- plot_data %>%
  filter(abs(z_rt) <= z_cutoff)

# SCATTER PLOTS
subjects <- sort(unique(plot_data$file_name))
categories <- c("HF", "LF", "Pseudo", "Random")
colors <- c(HF = "#0072B2", LF = "#009E73", Pseudo = "#D55E00", Random = "#CC79A7")

png(file.path(results, "rt_scatter_by_subject.png"), width = 10, height = 8, units = "in", res = 300)
par(mfrow = c(3, 2), mar = c(4, 4, 2, 1), oma = c(0, 0, 2, 4))
xlim <- range(plot_data$experimental_trial_count, na.rm = TRUE)
ylim <- range(plot_data$RT, na.rm = TRUE)
for (subj in subjects) {
  d <- plot_data %>% filter(file_name == subj)
  plot(
    d$experimental_trial_count, d$RT,
    col = colors[d$cond], pch = 16,
    xlim = xlim, ylim = ylim,
    xlab = "Trial", ylab = "RT (ms)", main = subj
  )
  grid()
}
mtext("RT by trial, faceted by subject", outer = TRUE, font = 2)
legend("topright", inset = c(-0.22, 0), xpd = NA, legend = categories,
       col = colors[categories], pch = 16, bty = "n", title = "Category")
dev.off()

png(file.path(results, "rt_scatter_all_subjects.png"), width = 10, height = 7, units = "in", res = 300)
plot(
  plot_data$experimental_trial_count, plot_data$RT,
  col = colors[plot_data$cond], pch = 16,
  xlab = "Trial", ylab = "RT (ms)", main = "RT by trial, all subjects"
)
grid()
legend("topright", legend = categories, col = colors[categories],
       pch = 16, bty = "n", title = "Category")
dev.off()

# GAMM
gamm_data <- plot_data %>%
  mutate(
    cond = factor(cond, levels = categories),
    subject_nr = factor(subject_nr)
  )

gamm_model <- gamm(
  RT ~ cond + s(experimental_trial_count, by = cond, k = 8),
  random = list(subject_nr = ~1),
  data = gamm_data
)

summary(gamm_model$gam)
summary(gamm_model$lme)

png(file.path(results, "gamm_smooths.png"), width = 10, height = 8, units = "in", res = 300)
plot(gamm_model$gam, pages = 1)
dev.off()

# RESIDUALS
png(file.path(results, "gamm_check.png"), width = 10, height = 8, units = "in", res = 300)
gam.check(gamm_model$gam)
dev.off()

gamm_residuals <- residuals(gamm_model$gam)
png(file.path(results, "gamm_residuals_by_category.png"), width = 10, height = 8, units = "in", res = 300)
par(mfrow = c(2, 2), mar = c(4, 4, 2, 1), oma = c(0, 0, 2, 0))
for (cat in levels(gamm_data$cond)) {
  idx <- gamm_data$cond == cat
  plot(
    gamm_data$experimental_trial_count[idx], gamm_residuals[idx],
    xlab = "Trial", ylab = "Residual (ms)", main = cat, pch = 16, cex = 0.6
  )
  abline(h = 0, lty = 2)
}
mtext("GAMM residuals by category", outer = TRUE, font = 2)
dev.off()
