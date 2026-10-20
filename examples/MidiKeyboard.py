"""Example of a wavetable oscillator using custom wavetables loaded from files.

This example uses SIMDBuffer instead of Buffer to load the wavetable. This allows for more efficient processing for wavetables with a small number of channels (2-8), where the number of channels is known ahead of time, but it should not be used with wavetables that have a large number of waveforms.
"""

import sys
from pathlib import Path

# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *
import supriya_midi as midi

def main():
    mmm_audio = MMMAudio(128, graph_name="MidiKeyboard", package_name="examples")
    mmm_audio.start_audio() 

    # send_midi forwards every message to the graph in the same format that an exported plugin does:
    # note ons go to "note_on", note offs to "note_off", ccs to "cc", etc.
    # the Messenger pools all of the messages received during a block, so playing a chord doesn't lose any notes.
    # the graph maps cc 1 to the wubb rate, cc 33 to the filter cutoff and cc 34 to the filter resonance.
    def midi_callback(msg, timestamp, data=None):
        print(f"Received MIDI message: {midi.MidiMessage.parse(msg)}")
        mmm_audio.send_midi(msg)

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    ports = midi.list_ports()
    port_num = ports.index('Oxygen Pro Mini USB MIDI')
    in_port.open_port(port_num)
    in_port.set_callback(midi_callback)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Exiting.")

if __name__ == "__main__":
    main()