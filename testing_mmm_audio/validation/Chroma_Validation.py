"""Chroma validation against librosa."""

import argparse
import csv
import librosa
import matplotlib.pyplot as plt
import numpy as np
import os
import shutil
import sys

sys.path.append(os.getcwd())


def parse_args():
	parser = argparse.ArgumentParser(description="Validate Chroma output.")
	parser.add_argument(
		"--show-plots",
		action="store_true",
		help="Display plots interactively (pauses execution).",
	)
	return parser.parse_args()


args = parse_args()
show_plots = args.show_plots

os.makedirs("./testing_mmm_audio/validation/flucoma_sc_results", exist_ok=True)
os.makedirs("./testing_mmm_audio/validation/validation_results", exist_ok=True)

flucoma_csv_path = "./testing_mmm_audio/validation/flucoma_sc_results/chroma_flucoma_results.csv"
flucoma_results = None
if os.path.exists(flucoma_csv_path):
	with open(flucoma_csv_path, "r", encoding="utf-8") as f:
		reader = csv.reader(f)
		flucoma_rows = []
		for row in reader:
			if row:
				flucoma_rows.append([float(value) for value in row])
	if flucoma_rows:
		flucoma_results = np.array(flucoma_rows).T
else:
	print("FluCoMa CSV not found, skipping FluCoMa comparison")

mojo_bin = shutil.which("mojo") or "./.pixi/envs/default/bin/mojo"
exit_code = os.system(f"{mojo_bin} run -I . ./testing_mmm_audio/validation/Chroma_Validation.mojo")
if exit_code != 0:
	raise RuntimeError("Mojo validation run failed")
print("mojo analysis complete")

with open("./testing_mmm_audio/validation/mojo_results/chroma_mojo_results.csv", "r", encoding="utf-8") as f:
	lines = f.readlines()

windowsize = int(lines[0].strip().split(",")[1])
hopsize = int(lines[1].strip().split(",")[1])
n_chroma = int(lines[2].strip().split(",")[1])

mojo_rows = []
for line in lines[4:]:
	row = [float(value) for value in line.strip().split(",") if value != ""]
	if row:
		mojo_rows.append(row)

if len(mojo_rows) > 2:
	mojo_rows = mojo_rows[2:]

mojo_results = np.array(mojo_rows).T

y, sr = librosa.load("./resources/Shiverer.wav", sr=None)
librosa_results = librosa.feature.chroma_stft(
	y=y,
	sr=sr,
	n_fft=windowsize,
	hop_length=hopsize,
	n_chroma=n_chroma,
	tuning=0.0,
	center=False,
)


def compare_chroma(arr1, arr2):
	diff = arr1 - arr2
	return np.mean(np.abs(diff)), np.std(diff)


if flucoma_results is not None:
	min_frames = min(librosa_results.shape[1], mojo_results.shape[1], flucoma_results.shape[1])
	flucoma_aligned = flucoma_results[:, :min_frames]
else:
	min_frames = min(librosa_results.shape[1], mojo_results.shape[1])
	flucoma_aligned = None

librosa_aligned = librosa_results[:, :min_frames]
mojo_aligned = mojo_results[:, :min_frames]

mojo_vs_librosa_mean, mojo_vs_librosa_std = compare_chroma(mojo_aligned, librosa_aligned)

print("N Librosa Frames: ", librosa_aligned.shape[1])
print("N Mojo Frames: ", mojo_aligned.shape[1])
print(f"MMMAudio vs Librosa Chroma: Mean Difference = {mojo_vs_librosa_mean:.6f}, Std Dev = {mojo_vs_librosa_std:.6f}")

if flucoma_aligned is not None:
	print("N FluCoMa Frames: ", flucoma_aligned.shape[1])
	mojo_vs_flucoma_mean, mojo_vs_flucoma_std = compare_chroma(mojo_aligned, flucoma_aligned)
	librosa_vs_flucoma_mean, librosa_vs_flucoma_std = compare_chroma(librosa_aligned, flucoma_aligned)
	print(f"MMMAudio vs FluCoMa Chroma: Mean Difference = {mojo_vs_flucoma_mean:.6f}, Std Dev = {mojo_vs_flucoma_std:.6f}")
	print(f"Librosa vs FluCoMa Chroma: Mean Difference = {librosa_vs_flucoma_mean:.6f}, Std Dev = {librosa_vs_flucoma_std:.6f}")

print("\n=== Copy-Pasteable Markdown Table ===\n")
print("| Comparison          | Mean Difference | Std Dev of Differences |")
print("| ------------------- | --------------- | ---------------------- |")
print(f"| MMMAudio vs Librosa | {mojo_vs_librosa_mean:.6f} | {mojo_vs_librosa_std:.6f} |")
if flucoma_aligned is not None:
	print(f"| MMMAudio vs FluCoMa | {mojo_vs_flucoma_mean:.6f} | {mojo_vs_flucoma_std:.6f} |")
	print(f"| Librosa vs FluCoMa  | {librosa_vs_flucoma_mean:.6f} | {librosa_vs_flucoma_std:.6f} |")
print()

nrows = 3 if flucoma_aligned is not None else 2
fig, ax = plt.subplots(nrows=nrows, ncols=1, sharex=True)

ax[0].imshow(librosa_aligned, aspect="auto", origin="lower")
ax[0].set(title="Librosa", ylabel="Chroma")

if flucoma_aligned is not None:
	ax[1].imshow(flucoma_aligned, aspect="auto", origin="lower")
	ax[1].set(title="FluCoMa", ylabel="Chroma")
	ax[2].imshow(mojo_aligned, aspect="auto", origin="lower")
	ax[2].set(title="MMMAudio", xlabel="Frame", ylabel="Chroma")
else:
	ax[1].imshow(mojo_aligned, aspect="auto", origin="lower")
	ax[1].set(title="MMMAudio", xlabel="Frame", ylabel="Chroma")

plt.tight_layout()
plt.savefig("testing_mmm_audio/validation/validation_results/chroma_comparison.png")
if show_plots:
	plt.show()
else:
	plt.close()
