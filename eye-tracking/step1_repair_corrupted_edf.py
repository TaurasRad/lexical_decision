"""STEP 1 - Repair EyeLink EDF files whose last bytes are corrupted.

Usage (from the eye-tracking folder):
    .venv/bin/python step1_repair_corrupted_edf.py data/raw/sub_10.edf data/raw/sub_50.edf

Why this is needed
------------------
In sub_10.edf and sub_50.edf the final ~2 KB were overwritten with random
bytes. That destroyed the last ~0.3 s of samples, the last two messages
("EndFixationOffset Block 2", "EndBlock 2") and, most importantly, the short
end-of-recording trailer. Without that trailer the SR Research EDF reader
refuses to open the file at all, even though every trial is still intact.

How the repair works
--------------------
An EDF file is a stream of binary records. The final records of a recording
are gaze samples, which come in two forms (monocular recording, 500 Hz):

    a7 81 <time:4 bytes> + 12 data bytes   sample with a full timestamp (18 bytes)
    87 81 02             + 12 data bytes   sample 2 ms after the previous (15 bytes)

A full-timestamp sample appears every 10 samples and after every event, so
after the LAST full-timestamp sample there are only 2 ms samples. We walk
those until the bytes stop looking like samples (that is where the noise
starts), cut the file there, and append the same end-of-recording trailer
that closes every intact recording block in these files.

The original files are never modified: repaired copies go to data/repaired/.
"""

import sys
from pathlib import Path

# Byte patterns of the two sample record types (see docstring above).
# FULL_HDR also includes the first timestamp byte, which is always 0 here
# (timestamps are well below 2^24 ms), making the pattern more specific.
FULL_HDR, FULL_LEN = b"\xa7\x81\x00", 18
DELTA_HDR, DELTA_LEN = b"\x87\x81\x02", 15
SAMPLE_MS = 2  # 500 Hz -> one sample every 2 ms

OUT_DIR = Path(__file__).parent / "data" / "repaired"


def trailer(last_time):
    """Build the end-of-recording trailer, copied from the intact recording blocks.

    Every intact block in all three files ends with exactly these records:
        82 c0 41 <T>   00   end of samples   (T = time of the last sample)
        12 c0 41 <T+1> 00   end of events
        10 00 41 <T+1> 00   end of recording
        00 00               end of file
    Timestamps are 4-byte big-endian milliseconds on the EyeLink clock.
    """
    t0 = last_time.to_bytes(4, "big")
    t1 = (last_time + 1).to_bytes(4, "big")
    return (b"\x82\xc0\x41" + t0 + b"\x00"
            + b"\x12\xc0\x41" + t1 + b"\x00"
            + b"\x10\x00\x41" + t1 + b"\x00"
            + b"\x00\x00")


def last_complete_sample(data):
    """Return (byte offset just after the last whole sample, that sample's timestamp)."""
    # Start from the last full-timestamp sample in the file.
    pos = data.rfind(FULL_HDR)
    time = int.from_bytes(data[pos + 2:pos + 6], "big")  # 4-byte time starts after "a7 81"
    end = pos + FULL_LEN

    # Walk forward through 2 ms samples. A record only counts as complete if the
    # NEXT record also starts with a sample header; the record that runs into
    # the noise is therefore dropped.
    while (data[end:end + 3] == DELTA_HDR
           and data[end + DELTA_LEN:end + DELTA_LEN + 3] == DELTA_HDR):
        end += DELTA_LEN
        time += SAMPLE_MS

    # Edge case: the last record is whole and the file simply ends right after it.
    if data[end:end + 3] == DELTA_HDR and end + DELTA_LEN == len(data):
        end += DELTA_LEN
        time += SAMPLE_MS
    return end, time


def repair(path):
    """Write a repaired copy of `path` to data/repaired/ and return its path."""
    path = Path(path)
    data = path.read_bytes()
    end, time = last_complete_sample(data)
    fixed = data[:end] + trailer(time)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / path.name
    out.write_bytes(fixed)
    print(f"{path.name}: kept {end} of {len(data)} bytes (dropped {len(data) - end}), "
          f"last sample at {time} ms -> {out}")
    return out


if __name__ == "__main__":
    for p in sys.argv[1:]:
        repair(p)
