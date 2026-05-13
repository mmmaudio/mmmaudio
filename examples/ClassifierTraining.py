import glob
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python import *

if __name__ == "__main__":
    dog = glob.glob("/Users/ted/Desktop/dog-dataset/_bounces/dog/*")
    other = glob.glob("/Users/ted/Desktop/dog-dataset/_bounces/other/*")

    d = {
        "fftsize": 1024,
        "hopsize": 512
    }

    dog_mfccs = np.array([])
    other_mfccs = np.array([])

    for path in dog:
        d["path"] = path
        mfccs = MBufAnalysis.mfcc(d)
        dog_mfccs = np.append(dog_mfccs, mfccs)

    for path in other:
        d["path"] = path
        mfccs = MBufAnalysis.mfcc(d)
        other_mfccs = np.append(other_mfccs, mfccs)

    print("dog_mfccs =", dog_mfccs.shape)
    print("other_mfccs =", other_mfccs.shape)

