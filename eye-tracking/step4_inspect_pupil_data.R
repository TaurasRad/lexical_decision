# STEP 4 - Load the pupil data in R and print its header, structure and summary.
#
# Usage:
#   Rscript step4_inspect_pupil_data.R          all subjects (output/pupil_all_subjects.rda)
#   Rscript step4_inspect_pupil_data.R sub_61   one subject (output/per_subject/)
# or open in RStudio and click Source (loads all subjects).
#
# After running, two data frames are in the workspace:
#   trials  one row per trial (see README.md for every column)
#   pupil   one row per 2 ms sample; time_ms = 0 is stimulus onset
# Join trial information onto the samples with:
#   merge(pupil, trials[, c("subject", "trial_index", "cond", "block", "correct")])

args <- commandArgs(trailingOnly = TRUE)
subject <- if (length(args) > 0) args[1] else NA

# Folder containing this script, so paths work whatever the working directory is.
script_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)
  if (length(file_arg) > 0) return(dirname(normalizePath(sub("^--file=", "", file_arg))))
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    path <- rstudioapi::getSourceEditorContext()$path
    if (nzchar(path)) return(dirname(normalizePath(path)))
  }
  getwd()
}
out_dir <- file.path(script_dir(), "output")

if (is.na(subject)) {
  load(file.path(out_dir, "pupil_all_subjects.rda"))                              # -> trials, pupil
} else {
  load(file.path(out_dir, "per_subject", paste0(subject, "_trial_summary.rda")))     # -> trials
  load(file.path(out_dir, "per_subject", paste0(subject, "_pupil_timecourse.rda")))  # -> pupil
}

# Factors for the design variables
trials$subject <- factor(trials$subject)
pupil$subject  <- factor(pupil$subject, levels = levels(trials$subject))
trials$phase   <- factor(trials$phase, levels = c("practice", "experimental"))
trials$block   <- factor(trials$block)  # 0 = practice, 1 = random order, 2 = sequential
trials$cond    <- factor(trials$cond, levels = c("HF", "LF", "Pseudo", "Random"))
pupil$trial_id <- factor(pupil$trial_id, levels = unique(trials$trial_id))

# --- Trials: one row per trial ----------------------------------------------
cat("\n==== trials: header ====\n")
print(head(trials, 10))
cat("\n==== trials: structure ====\n")
str(trials)
cat("\n==== trials: summary ====\n")
print(summary(trials))

# --- Pupil: one row per sample (500 Hz), time_ms relative to stimulus onset ---
cat("\n==== pupil: header ====\n")
print(head(pupil, 10))
cat("\n==== pupil: structure ====\n")
str(pupil)
cat("\n==== pupil: summary ====\n")
print(summary(pupil))
