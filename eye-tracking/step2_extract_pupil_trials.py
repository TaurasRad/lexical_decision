"""STEP 2 - Extract trial information and pupil data from EyeLink EDF files.

Usage (from the eye-tracking folder):
    .venv/bin/python step2_extract_pupil_trials.py data/raw/sub_61.edf data/repaired/sub_10.edf ...

For each EDF file this writes two R data files to output/per_subject/:
    <sub>_trial_summary.rda    object `trials`: one row per trial
                               (stimulus, response, RT + pupil summaries)
    <sub>_pupil_timecourse.rda object `pupil`: one row per sample (500 Hz)
                               for every trial, time-locked to stimulus onset

Where the trial information comes from
--------------------------------------
The OpenSesame experiment sent a message to the eye tracker at every step of
a trial, so the EDF file alone contains the full behavioural record:

    StartTrial 67
    TrialInfo 67 phase=experimental block=2 cond=Pseudo stimulus=aftijn correct_response=m exposure=750 step=50
    FixationOnset 67        fixation cross appears (~1800 ms)
    BaselineStart 67        start of the ~200 ms pupil baseline
    StimulusOnset 67        letter string appears
    Response 67 key=m rt=568.7 correct=1      (or: Timeout 67 exposure=750)
    StimulusOffset 67
    EndTrial 67

Practice trials use "P1".."P12" as IDs and Start/EndPracticeTrial messages.

Pupil processing (per sample, then per trial)
---------------------------------------------
1. Samples with pupil size 0, or within BLINK_PAD_MS of an EyeLink blink,
   are set to missing and filled by linear interpolation.
2. Each trial is cut from FixationOnset to StimulusOnset + POST_MS.
3. Baseline = mean pupil from BaselineStart to StimulusOnset (~200 ms).
   Baseline-corrected pupil: pupil_bc = pupil - baseline (subtractive).
4. Trial summaries (means / maximum of pupil_bc, see summarise()).
"""

import ctypes as ct
import importlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadr

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
POST_MS = 2000      # length of the pupil window after stimulus onset (ms)
BLINK_PAD_MS = 50   # samples this close to a blink are treated as invalid (ms)

OUT_DIR = Path(__file__).parent / "output" / "per_subject"


# ---------------------------------------------------------------------------
# Reading the EDF file
# ---------------------------------------------------------------------------
# We use eyelinkio (pinned to 0.3.0), which wraps SR Research's EDF API.
# That version has two problems with these files, which we patch here:
#   1. It drops the last character of every message, which would turn
#      "correct=1" into "correct=" and "exposure=1500" into "exposure=150".
#   2. It replaces the EyeLink clock with "sample number / 500 Hz", hiding the
#      pauses between recording blocks. We keep the original clock (ms) so
#      messages, samples and blinks all share one time axis.
_R = importlib.import_module("eyelinkio.edf.read_edf")
_orig_times = {}  # filled by _keep_clock() while the file is read


def _handle_message(edf, res):
    """Replacement message reader that keeps the full message text."""
    e = _R.edf_get_float_data(edf).contents.fe
    # The message is stored as <2-byte length><text>; read length + 2 bytes,
    # skip the length field and stop at the first null byte.
    raw = ct.string_at(ct.byref(e.message[0]), e.message.contents.len + 2)[2:]
    off = res["offsets"]["messages"]
    res["discrete"]["messages"]["stime"][off] = e.sttime
    res["discrete"]["messages"]["msg"][off] = raw.split(b"\0")[0][: _R._MAX_MSG_LEN]
    res["offsets"]["messages"] += 1


def _keep_clock(x, orig_times, times):
    """Replacement for eyelinkio's time conversion: store the real clock, change nothing."""
    _orig_times["t"] = orig_times.copy()


_R._element_handlers["MESSAGEEVENT"] = _handle_message
_R._adjust_time = _keep_clock


def read_edf(path):
    """Read an EDF file and return (samples, messages, blinks) as DataFrames.

    All times are in ms on the EyeLink clock. The recording is monocular (left
    eye), so the third sample field is the pupil size (EyeLink pupil AREA,
    arbitrary units).
    """
    edf = _R.read_edf(str(path))
    samples = pd.DataFrame({"time": _orig_times["t"], "pupil_raw": edf["samples"][2]})
    messages = pd.DataFrame({
        "time": edf["discrete"]["messages"]["stime"],
        "msg": [m.decode("ascii", "ignore") for m in edf["discrete"]["messages"]["msg"]],
    })
    blinks = pd.DataFrame({
        "start": edf["discrete"]["blinks"]["stime"],
        "end": edf["discrete"]["blinks"]["etime"],
    })
    return samples, messages, blinks


# ---------------------------------------------------------------------------
# Building the trial table from the messages
# ---------------------------------------------------------------------------
# Timing messages -> column holding their timestamp
EVENT_COLS = {
    "FixationOnset": "t_fixation",
    "BaselineStart": "t_baseline",
    "StimulusOnset": "t_stim_on",
    "StimulusOffset": "t_stim_off",
}


def parse_trials(messages):
    """Turn the message stream into one row per trial (see module docstring)."""
    trials = {}  # trial ID ("P1", "1", ...) -> dict of columns
    for time, msg in zip(messages["time"], messages["msg"]):
        parts = msg.split()
        if not parts:
            continue
        kind = parts[0]

        if kind == "TrialInfo":
            # "TrialInfo 67 phase=... block=..." -> {"phase": ..., "block": ...}
            tid = parts[1]
            info = dict(p.split("=", 1) for p in parts[2:])
            trials.setdefault(tid, {"trial_id": tid}).update(info)

        elif kind in ("StartTrial", "StartPracticeTrial", "EndTrial", "EndPracticeTrial"):
            # Start/End messages carry a bare number; practice IDs need a "P" prefix.
            tid = ("P" if "Practice" in kind else "") + parts[1]
            col = "t_start" if kind.startswith("Start") else "t_end"
            trials.setdefault(tid, {"trial_id": tid})[col] = time

        elif kind in EVENT_COLS:
            trials[parts[1]][EVENT_COLS[kind]] = time

        elif kind == "Response":
            info = dict(p.split("=", 1) for p in parts[2:])
            trials[parts[1]].update(key=info["key"], rt=info["rt"], correct=info["correct"], timeout=False)

        elif kind == "Timeout":
            # No key pressed before the stimulus disappeared: key/rt/correct stay missing.
            trials[parts[1]].update(timeout=True)

    df = pd.DataFrame(trials.values())
    df["trial_index"] = np.arange(1, len(df) + 1)          # 1..112 across the session
    df["trial"] = df["trial_id"].str.lstrip("P").astype(int)  # number within phase
    df["block"] = df["block"].astype(int)
    for col in ("exposure", "step", "rt", "correct"):
        df[col] = pd.to_numeric(df[col])
    df["stim_duration"] = df["t_stim_off"] - df["t_stim_on"]
    return df


# ---------------------------------------------------------------------------
# Pupil processing
# ---------------------------------------------------------------------------
def clean_pupil(samples, blinks):
    """Mark invalid samples (pupil 0 or near a blink) and interpolate across them.

    Adds two columns:
        invalid  True where the raw sample was unusable
        pupil    cleaned pupil size (linearly interpolated over invalid samples;
                 gaps at the very start/end of the recording stay missing)
    """
    t = samples["time"].to_numpy()
    p = samples["pupil_raw"].to_numpy(dtype=float)
    invalid = ~np.isfinite(p) | (p <= 0)
    for start, end in zip(blinks["start"], blinks["end"]):
        invalid |= (t >= start - BLINK_PAD_MS) & (t <= end + BLINK_PAD_MS)
    pupil = pd.Series(np.where(invalid, np.nan, p)).interpolate(limit_area="inside")

    out = samples.copy()
    out["invalid"] = invalid
    out["pupil"] = pupil.to_numpy()
    return out


def trial_pupil(samples, trials, subject):
    """Cut every trial out of the continuous recording and baseline-correct it.

    Window: FixationOnset -> StimulusOnset + POST_MS. Because the trial ends at
    the response, the window usually runs into the next trial's fixation cross;
    those samples are flagged with after_trial_end = TRUE.

    Returns (pupil time-course table, baseline per trial_index).
    """
    pieces = []
    for tr in trials.itertuples():
        win = samples[(samples["time"] >= tr.t_fixation) & (samples["time"] <= tr.t_stim_on + POST_MS)]
        pieces.append(pd.DataFrame({
            "subject": subject,
            "trial_index": tr.trial_index,
            "trial_id": tr.trial_id,
            "time_ms": win["time"].to_numpy() - tr.t_stim_on,  # 0 = stimulus onset
            "after_trial_end": win["time"].to_numpy() > tr.t_end,
            "pupil_raw": win["pupil_raw"].to_numpy(),
            "pupil": win["pupil"].to_numpy(),
            "invalid": win["invalid"].to_numpy(),
        }))
    pupil = pd.concat(pieces, ignore_index=True)

    # Baseline: mean cleaned pupil from BaselineStart to StimulusOnset (~200 ms).
    base_len = (trials["t_stim_on"] - trials["t_baseline"]).set_axis(trials["trial_index"])
    in_baseline = (pupil["time_ms"] >= -pupil["trial_index"].map(base_len)) & (pupil["time_ms"] < 0)
    baseline = pupil[in_baseline].groupby("trial_index")["pupil"].mean()

    # Subtractive baseline correction: positive = larger than before the stimulus.
    pupil["pupil_bc"] = pupil["pupil"] - pupil["trial_index"].map(baseline)
    return pupil, baseline


def summarise(trials, pupil, baseline):
    """Collapse each trial's pupil time course into one row of summary measures.

    pupil_baseline      mean pupil, BaselineStart -> StimulusOnset
    pupil_stim_bc       mean pupil_bc, stimulus onset -> offset (= response)
    pupil_mean_bc       mean pupil_bc, 0 -> POST_MS
    pupil_peak_bc       maximum pupil_bc, 0 -> POST_MS
    pupil_peak_latency  time (ms after onset) of that maximum
    prop_invalid        share of samples in 0 -> POST_MS that were interpolated
    """
    post = pupil[(pupil["time_ms"] >= 0) & (pupil["time_ms"] <= POST_MS)]
    g = post.groupby("trial_index")
    peak_idx = g["pupil_bc"].idxmax().dropna()
    summ = pd.DataFrame({
        "pupil_baseline": baseline,
        "pupil_mean_bc": g["pupil_bc"].mean(),
        "pupil_peak_bc": g["pupil_bc"].max(),
        "pupil_peak_latency": post.loc[peak_idx].set_index("trial_index")["time_ms"],
        "prop_invalid": g["invalid"].mean(),
    })
    # Mean while the stimulus was on screen only (length differs per trial).
    dur = trials.set_index("trial_index")["stim_duration"]
    on_stim = post[post["time_ms"] <= post["trial_index"].map(dur)]
    summ["pupil_stim_bc"] = on_stim.groupby("trial_index")["pupil_bc"].mean()
    return trials.merge(summ, left_on="trial_index", right_index=True, how="left")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# Column order of the trial table: design -> behaviour -> pupil -> raw timestamps
TRIAL_COLS = [
    "subject", "trial_index", "phase", "block", "trial", "trial_id", "cond", "stimulus",
    "correct_response", "key", "correct", "rt", "timeout", "exposure", "step", "stim_duration",
    "pupil_baseline", "pupil_stim_bc", "pupil_mean_bc", "pupil_peak_bc", "pupil_peak_latency",
    "prop_invalid", "t_start", "t_fixation", "t_baseline", "t_stim_on", "t_stim_off", "t_end",
]


def process(edf_path):
    """Run the whole extraction for one EDF file and write its two .rda files."""
    edf_path = Path(edf_path)
    subject = edf_path.stem  # e.g. "sub_61"

    samples, messages, blinks = read_edf(edf_path)
    trials = parse_trials(messages)
    trials.insert(0, "subject", subject)

    samples = clean_pupil(samples, blinks)
    pupil, baseline = trial_pupil(samples, trials, subject)
    trials = summarise(trials, pupil, baseline)[TRIAL_COLS]

    # pyreadr can only store one data frame per .rda file, hence two files.
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    pyreadr.write_rdata(str(OUT_DIR / f"{subject}_trial_summary.rda"), trials,
                        df_name="trials", compress="gzip")
    pyreadr.write_rdata(str(OUT_DIR / f"{subject}_pupil_timecourse.rda"), pupil,
                        df_name="pupil", compress="gzip")

    print(f"{subject}: {len(trials)} trials, {len(pupil)} pupil samples, "
          f"{trials['timeout'].sum()} timeouts, {samples['invalid'].mean():.1%} invalid samples overall")


if __name__ == "__main__":
    for path in sys.argv[1:] or ["data/raw/sub_61.edf"]:
        process(path)
