# STEP 3 - Combine all subjects into one R data file.
#
# Usage (from anywhere):  Rscript step3_combine_subjects.R
#   or open in RStudio and click Source.
#
# Reads every output/per_subject/sub_*_trial_summary.rda and
# sub_*_pupil_timecourse.rda written by step2_extract_pupil_trials.py and
# stacks them into output/pupil_all_subjects.rda, which holds two objects:
#   trials  one row per trial per subject (behaviour + pupil summaries)
#   pupil   one row per 2 ms sample per trial per subject
# New participants are picked up automatically after running step 2 on them.

# Folder containing this script, so paths work whatever the working directory
# is (Rscript, RStudio "Source", or running lines one by one in RStudio).
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
subject_dir <- file.path(out_dir, "per_subject")

# Subject IDs from the file names, e.g. "sub_10", "sub_50", "sub_61"
subjects <- sub("_trial_summary\\.rda$", "",
                list.files(subject_dir, pattern = "^sub_.*_trial_summary\\.rda$"))

# Load the single data frame stored in an .rda file and return it.
read_object <- function(path) {
  env <- new.env()
  load(path, envir = env)
  obj <- get(ls(env)[1], envir = env)
  attr(obj, "datalabel") <- NULL   # metadata attributes added by pyreadr
  attr(obj, "var.labels") <- NULL
  obj
}

trials <- do.call(rbind, lapply(subjects, function(s)
  read_object(file.path(subject_dir, paste0(s, "_trial_summary.rda")))))
pupil <- do.call(rbind, lapply(subjects, function(s)
  read_object(file.path(subject_dir, paste0(s, "_pupil_timecourse.rda")))))
rownames(trials) <- NULL
rownames(pupil) <- NULL

save(trials, pupil, file = file.path(out_dir, "pupil_all_subjects.rda"), compress = "xz")

cat("Saved", file.path(out_dir, "pupil_all_subjects.rda"), "\n")
print(table(trials$subject))
cat(nrow(trials), "trials,", nrow(pupil), "pupil samples\n")
