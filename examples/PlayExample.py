"""
Shows how to load and audio buffer from a sound file and play it using the Play UGen. 

This example uses open sound control to control Play's playback speed and VAMoogFilter's cutoff frequency. These can be sent from a simple touchosc patch or any other OSC controller. A touchosc patch is provided for control.

This example is able to run by pressing the "play" button in VSCode or compiling and running the whole file on the command line.
"""

import sys
from pathlib import Path

# This example is able to run by pressing the "play" button in VSCode
# that executes the whole file.
# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *

def main():
    mmm_audio = MMMAudio(128, graph_name="PlayExample", package_name="examples")

    mmm_audio.start_audio() # start the audio thread - or restart it where it left off
    # time.sleep(10.0) 

    # this example uses open sound control to control Play's playback speed and VAMoogFilter's cutoff frequency
    # there is a simple touchosc patch provided for control
    # it is looking for /fader1 and /fader2 on port 5005; these can be adjusted
    # Start the OSC server on its own thread
    # this is a bug, but this thread has to start after audio or audio won't start

    # Usage:
    def osc_msg_handler(source, *args):
        print(f"Received OSC message from {source}: with arguments: {args}")
        if args[0] == "/fader1":
            val = args[1]
            if val > 0.5:
                val = lincurve(val, 0.5, 1.0, 0.0, 4.0, 2.0)
            else:
                val = lincurve(val, 0.0, 0.5, -4.0, 0.0, 2.0)
            print(f"Mapped play_rate value: {val}")
            mmm_audio.send_float("play_rate", val)
        elif args[0] == "/fader2":
            val = linexp(args[1], 0.0, 1.0, 100.0, 20000.0)
            mmm_audio.send_float("lpf_freq", val)

    # Start server
    osc_server = OSCServer("0.0.0.0", 5005, osc_msg_handler)
    osc_server.start()

if __name__ == "__main__":
    main()
