import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from mmm_python import *
import matplotlib.pyplot as plt
import numpy as np

d = {"path":"resources/Shiverer.wav"}
sc = MBufAnalysis.spectral_centroid(d)

print("spectral centroid shape:", sc.shape)
print("spectral centroid min max:", sc.min(), sc.max())

p = MBufAnalysis.yin(d)

print("YIN shape:", p.shape)
print("YIN frequency min max:", p[:,0].min(), p[:,0].max())
print("YIN confidence min max:", p[:,1].min(), p[:,1].max())

a = MBufAnalysis.rms(d)

print("RMS shape:", a.shape)
print("RMS min max:", a.min(), a.max())

m = MBufAnalysis.mfcc(d)

print("MFCC shape:", m.shape)
print("MFCC min max:", m.min(), m.max())

mb = MBufAnalysis.mel_bands(d)

print("mel bands shape:", mb.shape)
print("mel bands min max:", mb.min(), mb.max())

mb_db = 10 * np.log10(mb + 1e-12)

print("mel bands (dB) shape:", mb_db.shape)
print("mel bands (dB) min max:", mb_db.min(), mb_db.max())

fig, axs = plt.subplots(5, 1, figsize=(10, 10))
axs[0].plot(sc[:,0])
axs[0].set_title("Spectral Centroid Analysis")
axs[0].set_xlabel("Frame")
axs[0].set_ylabel("Spectral Centroid (Hz)")

axs[1].plot(p[:,0])
axs[1].set_title("YIN Analysis")
axs[1].set_xlabel("Frame")
axs[1].set_ylabel("Frequency (Hz)")

axs[1].twinx().plot(p[:,1], color='orange')
axs[1].set_ylabel("Confidence", color='orange')

axs[2].plot(a[:,0])
axs[2].set_title("RMS Analysis")
axs[2].set_xlabel("Frame")
axs[2].set_ylabel("RMS Amplitude")

for i in range(0, m.shape[1]):
    axs[3].plot(m[:,i], label=f"MFCC Coefficient {i}")
axs[3].set_title("MFCC Analysis")
axs[3].set_xlabel("Frame")
axs[3].set_ylabel("MFCC Coefficient Value")

axs[4].imshow(mb_db.T, origin="lower", aspect="auto")
axs[4].set_title("Mel Bands Analysis (dB)")
axs[4].set_xlabel("Frame")
axs[4].set_ylabel("Mel Band")

plt.tight_layout()
plt.show()