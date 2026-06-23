"""
A polyphonic synthesizer controlled via a MIDI keyboard.

This example demonstrates a couple differnt concepts:
- How to connect to a MIDI keyboard using the supriya-midi library
- How to use a MIDI keyboard to send note and control change messages to MMMAudio.
- How to use Pseq from mmm_python.Patterns to cycle through voices for polyphonic note allocation.
- How to create a thread to handle incoming MIDI messages in the background.

This example is able to run by pressing the "play" button in VSCode or compiling and running the whole file on the command line.

This uses the same MidiSequencer.mojo graph as the MidiSequencer example, but instead of using a sequencer to trigger notes, it uses a MIDI keyboard.
"""


import sys
from pathlib import Path

# In order to do this, it needs to add the parent directory to the path
# (the next line here) so that it can find the mmm_src and mmm_utils packages.
# If you want to run it line by line in a REPL, skip this line!
sys.path.insert(0, str(Path(__file__).parent.parent))
from mmm_python import *

def main():
    # instantiate and load the graph - notice we are using the MidiSequencer graph here (the same as in the MidiSequencer example)
    mmm_audio = MMMAudio(128, graph_name="MidiSequencer", package_name="examples")
    mmm_audio.start_audio()

    # this next chunk of code is all about using a midi keyboard to control the synth---------------
    import supriya_midi as midi

    # find your midi devices
    ports = midi.list_ports()
    print(f"Available MIDI ports: {ports}")
    port_num = ports.index('Oxygen Pro Mini USB MIDI')

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(port_num)

    poly_pal = PolyPal(mmm_audio, "poly", 10)

    def midi_callback(msg, timestamp, data=None):
        msg = midi.MidiMessage.parse(msg)
        print(f"Received {msg=}")
        if type(msg) in [midi.NoteOnMessage, midi.NoteOffMessage, midi.ControllerChangeMessage, midi.PitchWheelMessage]:
            if type(msg) == midi.NoteOnMessage:
                poly_pal.send_floats([midicps(msg.note_number), msg.velocity / 127.0])  # note freq and velocity scaled 0 to 1
            elif type(msg) == midi.ControllerChangeMessage:
                if msg.controller_number == 34:  # Mod wheel
                    # on the desired cc, scale the value exponentially from 100 to 4000
                    # it is best practice to scale midi cc values in the host, rather than in the audio engine
                    mmm_audio.send_float("filt_freq", linexp(msg.controller_value, 0, 127, 100, 4000))
            elif type(msg) == midi.PitchWheelMessage:
                mmm_audio.send_float("bend_mul", linlin(msg.transposition, -8192, 8191, 0.9375, 1.0625))
    # Start the thread
    in_port.set_callback(midi_callback)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Exiting.")

if __name__ == "__main__":
    main()