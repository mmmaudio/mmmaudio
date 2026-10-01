"""This is a non-realtime example that demonstrates how to use the MMMAudio class combined with the NRT class to generate audio and save it to a WAV file. It loads a JSON score file that contains events to be processed by the MMMAudio instance and iterates over the events in the NRT instance. The example uses the WavetableOscSIMD graph to generate audio based on the events in the score file (resources/bach2.json).

The json file needs to be in the following format:
[
    {
        "time": 0.0, # time in seconds when the event should be processed
        "message": "mmm_audio.send_float", # target and method to call on the target - targets are passed to the NRT.save_to_wav function
        "key": "filter_cutoff", # not all messages need a key, so this can be omitted if not needed
        "value": 1000.0 # the value to send to the target method, may be a float, int, string, bool, or list of floats, ints, strings, or bools
    }
]
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *
import json

def main():
    mmm_audio = MMMAudio(16, num_output_channels = 2, graph_name="WavetableOscSIMD", package_name="examples")
    poly_pal = PolyPal(mmm_audio, "poly", 16) 

    # in this case we use poly_pal.send_floats AND mmm_audio.send_float, so we need to pass both of them as targets to the NRT.save_to_wav function 
    targets = {
        "poly_pal": poly_pal,
        "mmm_audio": mmm_audio,
    }

    NRT.save_to_wav(mmm_audio, "tmp/bach.wav", duration_seconds=60, score_path="resources/bach2.json", targets=targets, verbose=False)

if __name__ == "__main__":
    main()