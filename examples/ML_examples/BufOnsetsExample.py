import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *
import matplotlib.pyplot as plt
import numpy as np
import librosa

d = {
    "path":"resources/Shiverer.wav",
     "thresh":68.0,
     "min_slice_len":0.1,# in seconds
     "window_size":1024,
     "hop_size":512
}
y, sr = librosa.load(d["path"], sr=None)
o = MBufAnalysis.spectral_flux_onsets(d)
print("spectral flux onsets shape:", o.shape)

plt.figure(figsize=(10, 4))
ax = plt.gca()
ax.plot(y, label="Waveform", alpha=1.0)
ax.vlines(o, ymin=y.min(), ymax=y.max(), color='red', label="Spectral Flux Onsets", linestyles="dotted", linewidths=0.5, alpha=0.9)

ax.set_title("Spectral Flux Onsets")
ax.set_xlabel("Sample")
ax.set_ylabel("Amplitude")

lines_1, labels_1 = ax.get_legend_handles_labels()
ax.legend(loc="upper right")

plt.tight_layout()
plt.show()
