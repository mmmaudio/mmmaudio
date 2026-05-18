import sys
from pathlib import Path
import argparse

sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python import *

def main():
    parser = argparse.ArgumentParser(description="Run the MMMAudio Classifier example.")
    parser.add_argument("--src", type=str, help="Source audio file to classify", required=False)
    args = parser.parse_args()
    # outdevice = 'BlackHole 2ch'
    outdevice = 'default'
    mmm_audio = MMMAudio(in_device=None, out_device=outdevice, blocksize=512, graph_name="Classifier", package_name="examples")
    if args.src:
        mmm_audio.send_string("src", args.src)
    mmm_audio.start_audio()

if __name__ == "__main__":
    main()