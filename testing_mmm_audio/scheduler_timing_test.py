"""Timing test for Scheduler.wait.

Plays a long run of notes with random gaps on a Scheduler routine, doing a random mix of
calculations between notes, and measures how far each note lands from its intended time.

Each note's error is reported in milliseconds and as a percentage of the gap before it
(a 5 ms late note after a 100 ms gap is 5% off). Every note is written to a CSV, and the
total duration is compared with the intended duration at the end.

Run from the MMMAudio root:

    pixi run python testing_mmm_audio/scheduler_timing_test.py
    pixi run python testing_mmm_audio/scheduler_timing_test.py --duration 30 --baseline

--baseline uses asyncio.sleep(gap) instead of Scheduler.wait, to compare against no drift correction.
"""

import argparse
import asyncio
import csv
import json
import math
import random
import statistics
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python.Scheduler import Scheduler


def make_gaps(duration: float, rng: random.Random) -> list:
    """Random gaps between notes, adding up to `duration` seconds.

    Mostly short notes, with some bursts of very short ones and occasional long ones.
    """
    gaps = []
    total = 0.0
    while True:
        r = rng.random()
        if r < 0.2:
            gap = rng.uniform(0.005, 0.02)  # bursts
        elif r < 0.95:
            gap = rng.uniform(0.02, 0.15)
        else:
            gap = rng.uniform(0.15, 0.5)
        if total + gap > duration:
            break
        gaps.append(gap)
        total += gap
    return gaps


def do_work(rng: random.Random, state: dict) -> str:
    """One random chunk of the kind of work a routine might do between notes. Returns its name."""
    kind = rng.choice(["fft", "matmul", "python_loop", "sort", "json", "trig", "none"])
    if kind == "fft":
        x = np.random.default_rng(rng.randrange(1 << 30)).standard_normal(rng.choice([1024, 8192, 65536]))
        np.abs(np.fft.rfft(x)).sum()
    elif kind == "matmul":
        n = rng.choice([32, 128, 256])
        a = np.random.default_rng(rng.randrange(1 << 30)).standard_normal((n, n))
        (a @ a.T).trace()
    elif kind == "python_loop":
        total = 0.0
        for i in range(rng.choice([1_000, 20_000, 100_000])):
            total += math.sin(i) * math.sqrt(i + 1)
    elif kind == "sort":
        sorted(rng.random() for _ in range(rng.choice([1_000, 20_000, 80_000])))
    elif kind == "json":
        state["blob"] = json.loads(json.dumps({str(i): [i, i * 0.5, str(i)] for i in range(rng.choice([100, 2_000, 10_000]))}))
    elif kind == "trig":
        # midi to frequency and a little pattern logic, like a sequencer would do
        notes = [rng.randint(36, 96) for _ in range(rng.choice([8, 64, 512]))]
        state["freqs"] = [440.0 * 2 ** ((n - 69) / 12) for n in notes]
    return kind


async def play(scheduler: Scheduler, gaps: list, rng: random.Random, baseline: bool, results: list):
    """Play one note per gap, recording when each was intended and when it actually happened."""
    state = {}
    intended = 0.0
    t0 = time.perf_counter()
    for i in range(len(gaps) + 1):
        actual = time.perf_counter() - t0
        work_start = time.perf_counter()
        kind = do_work(rng, state)
        work_ms = (time.perf_counter() - work_start) * 1000
        gap_before = gaps[i - 1] if i > 0 else None
        results.append((i, intended, actual, gap_before, kind, work_ms))
        if i < len(gaps):
            if baseline:
                await asyncio.sleep(gaps[i])
            else:
                await scheduler.wait(gaps[i])
            intended += gaps[i]


def report(results: list, csv_path: Path, label: str):
    rows = []
    for i, intended, actual, gap_before, kind, work_ms in results:
        err_ms = (actual - intended) * 1000
        pct = abs(err_ms) / (gap_before * 1000) * 100 if gap_before else 0.0
        rows.append((i, intended, actual, err_ms, gap_before, pct, kind, work_ms))

    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["note", "intended_s", "actual_s", "error_ms", "gap_before_s", "error_pct_of_gap", "work", "work_ms"])
        for r in rows:
            w.writerow([r[0], f"{r[1]:.6f}", f"{r[2]:.6f}", f"{r[3]:.3f}",
                        "" if r[4] is None else f"{r[4]:.6f}", f"{r[5]:.3f}", r[6], f"{r[7]:.3f}"])

    errs = [abs(r[3]) for r in rows[1:]]
    pcts = [r[5] for r in rows[1:]]
    works = [r[7] for r in rows]
    # the work after a note delays the next one, so compare it with the next note's gap
    late_over_gap = sum(1 for a, b in zip(rows, rows[1:]) if a[7] > b[4] * 1000)

    def pctile(xs, p):
        xs = sorted(xs)
        return xs[min(len(xs) - 1, int(len(xs) * p / 100))]

    last = rows[-1]
    print(f"\n=== {label} ===")
    print(f"notes:                {len(rows)}")
    print(f"work between notes:   mean {statistics.mean(works):.2f} ms, max {max(works):.2f} ms")
    print(f"  work longer than the following gap: {late_over_gap} times")
    print("error per note (ms):  mean {:.3f}  median {:.3f}  p95 {:.3f}  p99 {:.3f}  max {:.3f}".format(
        statistics.mean(errs), statistics.median(errs), pctile(errs, 95), pctile(errs, 99), max(errs)))
    print("error per note (% of gap before it):  mean {:.2f}%  median {:.2f}%  p95 {:.2f}%  p99 {:.2f}%  max {:.2f}%".format(
        statistics.mean(pcts), statistics.median(pcts), pctile(pcts, 95), pctile(pcts, 99), max(pcts)))
    print(f"intended duration:    {last[1]:.6f} s")
    print(f"actual duration:      {last[2]:.6f} s")
    print(f"total off by:         {last[3]:+.3f} ms ({last[3] / (last[1] * 1000) * 100:+.5f}%)")
    print(f"every note:           {csv_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--duration", type=float, default=200.0, help="seconds of notes (default 200)")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--baseline", action="store_true", help="use asyncio.sleep instead of Scheduler.wait")
    parser.add_argument("--csv", type=Path, default=None, help="where to write every note (default next to this file)")
    args = parser.parse_args()

    label = "asyncio.sleep (baseline)" if args.baseline else "Scheduler.wait"
    csv_path = args.csv or Path(__file__).parent / ("scheduler_timing_baseline.csv" if args.baseline else "scheduler_timing.csv")

    gap_rng = random.Random(args.seed)
    gaps = make_gaps(args.duration, gap_rng)
    print(f"{label}: playing {len(gaps) + 1} notes over {sum(gaps):.1f} s...")

    scheduler = Scheduler()
    results = []
    try:
        scheduler.sched(play(scheduler, gaps, random.Random(args.seed + 1), args.baseline, results)).result()
    finally:
        scheduler.loop.call_soon_threadsafe(scheduler.loop.stop)
        scheduler.thread.join()

    report(results, csv_path, label)


if __name__ == "__main__":
    main()
