"""Example of a wavetable oscillator using custom wavetables loaded from files.

This example uses SIMDBuffer instead of Buffer to load the wavetable. This allows for more efficient processing for wavetables with a small number of channels (2-8), where the number of channels is known ahead of time, but it should not be used with wavetables that have a large number of waveforms.

This example also uses Mojo-side Poly vs PVoiceAllocator.
"""

import sys
from pathlib import Path

import supriya_midi

# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent.parent))
from mmm_python import *

def main():
    mmm_audio = MMMAudio(128, graph_name="WavetableOscSIMDStrings", package_name="examples.tests")
    mmm_audio.start_audio() 

    import supriya_midi as midi

    # find your midi devices
    midi_ports = midi.list_ports()
    print(f"Available MIDI ports: {midi_ports}")

    port_num = midi_ports.index('Oxygen Pro Mini USB MIDI')  # change this to your device name

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(port_num)

    # PolyPal correctly formats messages to be sent to a Synth that uses a Poly object
    poly_pal = PolyPal(mmm_audio, "poly", 10)

    # just intonation ratios for a chromatic scale based on C major
    just_offset = [
    0.0,       # C
    0.1173,    # C#
    0.0391,    # D
    0.1564,    # Eb
   -0.1369,    # E
   -0.0196,    # F
   -0.0978,    # F#
    0.0196,    # G
    0.1369,    # Ab
   -0.1564,    # A
    0.1760,    # Bb
   -0.1173     # B
    ]

    def midi_callback(msg, timestamp, data=None):
        msg = midi.MidiMessage.parse(msg)
        if type(msg) == supriya_midi.NoteOnMessage:
            midi_note = msg.note_number+just_offset[msg.note_number % 12]
            print(f"Note On: {midi_note} Velocity: {msg.velocity}")
            poly_pal.send_floats([midi_note, (msg.velocity)])  
        elif type(msg) == supriya_midi.NoteOffMessage:
            midi_note = msg.note_number+just_offset[msg.note_number % 12]
            print(f"Note Off: {midi_note} Velocity: {msg.velocity}")
            poly_pal.send_floats([midi_note, 0.0])  
        elif type(msg) == supriya_midi.ControllerChangeMessage:
            print(f"Control Change: {msg.controller_number} Value: {msg.controller_value}")
            # Example: map CC 1 to wubb_rate of all voices
            if msg.controller_number == 1:
                wubb_rate = linexp(msg.controller_value, 0, 127, 0.1, 10.0)
                mmm_audio.send_float("wubb_rate", wubb_rate)
            if msg.controller_number == 33:
                mmm_audio.send_float("filter_cutoff", linexp(msg.controller_value, 0, 127, 20.0, 20000.0))
            if msg.controller_number == 34:
                mmm_audio.send_float("filter_resonance", linexp(msg.controller_value, 0, 127, 0.1, 1.0))

    in_port.set_callback(midi_callback)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Exiting.")

if __name__ == "__main__":
    main()