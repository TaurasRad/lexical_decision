# Eye-tracking: pupil data for the lexical decision task

This folder turns the EyeLink recordings from the pupil version of the lexical
decision experiment (`LexicalDecision_pupil.osexp`) into R data files for
analysis: one row per trial with the behavioural response and pupil
summaries, plus the full pupil time course of every trial.

Only **pupil size** is extracted. Gaze position, fixations and saccades are
not needed for this analysis and are left out.

## Folder layout

```
eye-tracking/
├── data/
│   ├── raw/                  original EDF files from the EyeLink host PC (never modified)
│   └── repaired/             fixed copies of corrupted EDFs (made by step 1)
├── output/
│   ├── per_subject/          two .rda files per subject (made by step 2)
│   └── pupil_all_subjects.rda   all subjects combined (made by step 3)
├── step1_repair_corrupted_edf.py
├── step2_extract_pupil_trials.py
├── step3_combine_subjects.R
├── step4_inspect_pupil_data.R
└── requirements.txt
```

## Quick start

If you only want to analyse the data, open R and load the combined file:

```r
load("output/pupil_all_subjects.rda")   # creates `trials` and `pupil`
```

To rebuild everything from the raw EDF files:

```bash
# one-time setup (Python 3.12)
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# step 1: repair the two corrupted files (see "Corrupted files" below)
.venv/bin/python step1_repair_corrupted_edf.py data/raw/sub_10.edf data/raw/sub_50.edf

# step 2: extract trials + pupil data (use the repaired copy where one exists)
.venv/bin/python step2_extract_pupil_trials.py data/raw/sub_61.edf data/repaired/sub_10.edf data/repaired/sub_50.edf

# step 3: combine all subjects into one .rda
Rscript step3_combine_subjects.R

# step 4: print header, structure and summary of the data
Rscript step4_inspect_pupil_data.R            # all subjects
Rscript step4_inspect_pupil_data.R sub_61     # one subject
```

The R scripts find their own folder, so they also work with **Source** in
RStudio regardless of the working directory.

**Adding a participant:** put the EDF in `data/raw/`, run step 2 on it
(and step 1 first if the EyeLink reader refuses to open it), then rerun step 3.

## The recordings

| | |
|---|---|
| Tracker | EyeLink Portable Duo |
| Recorded | left eye only, 500 Hz |
| Pupil measure | pupil **area** (arbitrary EyeLink units) |
| Screen | 2560 × 1440 px |
| Participants | sub_10, sub_50, sub_61 (recorded 2026-10-12) |

Each session has three recording periods (the tracker stops between them):

| Phase | Block | Trials | Trial IDs |
|---|---|---|---|
| Practice | 0 | 12 | P1–P12 |
| Experimental (random order) | 1 | 50 | 1–50 |
| Experimental (sequential) | 2 | 50 | 51–100 |

There is no separate behavioural file: the experiment sent a message to the
tracker at every step of a trial, so the EDF file contains everything:

```
StartTrial 67
TrialInfo 67 phase=experimental block=2 cond=Pseudo stimulus=aftijn correct_response=m exposure=750 step=50
FixationOnset 67       fixation cross (~1800 ms)
BaselineStart 67       pupil baseline (~200 ms)
StimulusOnset 67       letter string appears
Response 67 key=m rt=568.7 correct=1      or: Timeout 67 exposure=750
StimulusOffset 67
EndTrial 67
```

- `cond`: `HF` / `LF` (high / low frequency word), `Pseudo` (pseudoword), `Random` (random letters)
- keys: `n` = word, `m` = non-word
- `exposure` / `step`: the adaptive staircase for the maximum stimulus duration
  (starts at 1500 ms, step 50 → 25 → 12)
- `Timeout`: no key was pressed before the stimulus disappeared

## Processing

### Pupil cleaning (step 2)
1. Samples where the pupil size is 0, or within 50 ms of a blink detected by
   EyeLink, are marked `invalid`.
2. Invalid samples are filled by linear interpolation between the valid
   samples on either side.

### Per-trial window
Each trial is cut from `FixationOnset` to 2000 ms after `StimulusOnset`.
`time_ms = 0` is stimulus onset. The trial ends at the response (median RT
≈ 700 ms), but the pupil response peaks later (≈ 1.3 s), so the window runs
on into the next trial's fixation cross. Those samples are flagged
`after_trial_end = TRUE`.

### Baseline correction
`pupil_baseline` is the **mean** pupil from `BaselineStart` to `StimulusOnset`
(~200 ms). Every sample gets `pupil_bc = pupil - pupil_baseline`, so positive
values mean the pupil is larger than just before the stimulus.

### Trial summaries
| Column | Computation | Window (from stimulus onset) |
|---|---|---|
| `pupil_baseline` | mean of `pupil` | BaselineStart → 0 |
| `pupil_stim_bc` | mean of `pupil_bc` | 0 → stimulus offset (= response) |
| `pupil_mean_bc` | mean of `pupil_bc` | 0 → 2000 ms |
| `pupil_peak_bc` | maximum of `pupil_bc` | 0 → 2000 ms |
| `pupil_peak_latency` | time of that maximum (ms) | 0 → 2000 ms |
| `prop_invalid` | share of samples that were interpolated | 0 → 2000 ms |

The window length and blink padding are set at the top of
`step2_extract_pupil_trials.py` (`POST_MS`, `BLINK_PAD_MS`). Because the full
time course is kept in `pupil`, other windows or measures can be computed in R
without rerunning Python, e.g. the mean from 500 to 1500 ms:

```r
aggregate(pupil_bc ~ subject + trial_index,
          data = subset(pupil, time_ms >= 500 & time_ms <= 1500), FUN = mean)
```

## Output data

`output/pupil_all_subjects.rda` contains two data frames.

### `trials`: one row per trial (336 rows = 3 subjects × 112)

| Column | Meaning |
|---|---|
| `subject` | participant ID (`sub_10`, ...) |
| `trial_index` | 1–112, order within the session |
| `phase`, `block`, `trial`, `trial_id` | practice/experimental, block 0–2, number within phase, ID as in the messages |
| `cond`, `stimulus`, `correct_response` | condition, letter string, expected key |
| `key`, `correct`, `rt`, `timeout` | response (missing on timeouts), RT in ms |
| `exposure`, `step` | staircase values for this trial |
| `stim_duration` | ms the stimulus was actually on screen |
| `pupil_*`, `prop_invalid` | pupil summaries (see table above) |
| `t_start` … `t_end` | raw EyeLink timestamps (ms) of each trial event |

### `pupil`: one row per sample (2 ms), ~2000 per trial

| Column | Meaning |
|---|---|
| `subject`, `trial_index`, `trial_id` | link to `trials` |
| `time_ms` | time relative to stimulus onset |
| `after_trial_end` | sample falls after the trial's `EndTrial` message |
| `pupil_raw` | pupil area as recorded (0 during blinks) |
| `pupil` | cleaned, interpolated pupil area |
| `invalid` | sample was interpolated |
| `pupil_bc` | `pupil` minus the trial's baseline |

Add trial information to the samples with:

```r
pupil <- merge(pupil, trials[, c("subject", "trial_index", "cond", "block", "correct")])
```

## Corrupted files

In `sub_10.edf` and `sub_50.edf` the last ~2 KB were overwritten with random
bytes, so the SR Research EDF reader refused to open them. No uncorrupted
copies exist. `step1_repair_corrupted_edf.py` keeps everything up to the last
complete gaze sample and appends the end-of-recording records that close every
intact block in these files; details are in the script's docstring.

What was lost: the last ~0.3 s of the fixation period after block 2 and the
messages `EndFixationOffset Block 2` / `EndBlock 2`. All 112 trials, every
response, and the full 2000 ms pupil window of the last trial are intact.

## EDF reader fixes

Step 2 reads EDF files with `eyelinkio` **0.3.0** (pinned in
`requirements.txt`) and patches two problems in that version:

1. It drops the last character of every message (`correct=1` would become
   `correct=`, `exposure=1500` would become `exposure=150`).
2. It replaces the EyeLink clock with sample-count time, which hides the
   pauses between recording blocks. The original clock is kept instead.

## Data quality notes

| | invalid samples | blinks | trials > 25 % invalid (0–2000 ms) |
|---|---|---|---|
| sub_10 | 1.7 % | 24 | 0 |
| sub_50 | **17.6 %** | **221** | **44** |
| sub_61 | 2.3 % | 36 | 0 |

- **sub_50** blinked far more than the others. No trial loses more than 45 %,
  but an exclusion rule on `prop_invalid` should be decided before analysis.
- **Calibration:** only sub_10's file contains a calibration/validation
  record, and it was rated POOR (0.59° average, 2.21° max error). The other
  two files contain none, so their calibration quality cannot be checked.
  This matters little for pupil size, but should be reported.
- **Recording settings differ from `LAB_SETUP.txt`**, which asks for binocular
  2000 Hz recording and calibration before each block. All three files are
  monocular (left eye) at 500 Hz.
- Pupil area is in arbitrary units and differs between people; compare
  baseline-corrected values, not raw sizes, across subjects.
