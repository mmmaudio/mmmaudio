"""Example of a wavetable oscillator using custom wavetables loaded from files.

This example uses SIMDBuffer instead of Buffer to load the wavetable. This allows for more efficient processing for wavetables with a small number of channels (2-8), where the number of channels is known ahead of time, but it should not be used with wavetables that have a large number of waveforms.

This example also uses Mojo-side Poly vs PVoiceAllocator.
"""

import sys
from pathlib import Path

# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *
import mido

def main():
    mmm_audio = MMMAudio(128, graph_name="WavetableOscSIMD", package_name="examples")
    mmm_audio.start_audio() 

    # PolyPal correctly formats messages to be sent to a Synth that uses a Poly object
    poly_pal = PolyPal(mmm_audio, "poly", 16) # the 16 here should match the number of voices in the Poly in the Mojo code

    def midi_callback(msg):
        print(f"Received MIDI message: {msg}")
        if msg.type in ["note_on", "note_off", "control_change"]:
            if msg.type == "note_on":
                poly_pal.send_ints([msg.note, (msg.velocity)])  
            if msg.type == "note_off":
                poly_pal.send_ints([msg.note, 0.0])  
            if msg.type == "control_change":
                print(f"Control Change: {msg.control} Value: {msg.value}")
                # Example: map CC 1 to wubb_rate of all voices
                if msg.control == 1:
                    wubb_rate = linexp(msg.value, 0, 127, 0.1, 10.0)
                    mmm_audio.send_float("wubb_rate", wubb_rate)
                if msg.control == 33:
                    mmm_audio.send_float("filter_cutoff", linexp(msg.value, 0, 127, 20.0, 20000.0))
                if msg.control == 34:
                    mmm_audio.send_float("filter_resonance", linexp(msg.value, 0, 127, 0.1, 1.0))

    # open your midi device - you may need to change the device name
    in_port = mido.open_input('Oxygen Pro Mini USB MIDI', callback = midi_callback)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Exiting.")

if __name__ == "__main__":
    main()