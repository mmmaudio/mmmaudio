"""An example showing how to record audio input from a microphone to a buffer and play it back using MIDI note messages."""
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
    # set your audio input and output devices here:
    in_device = "Fireface UCX II (24219339)"
    out_device = "Fireface UCX II (24219339)"

    # in_device = "MacBook Pro Microphone"
    # out_device = "External Headphones"

    # instantiate and load the graph
    mmm_audio = MMMAudio(128, num_input_channels=18, num_output_channels=2, in_device=in_device, out_device=out_device, graph_name="Record", package_name="examples")

    # the default input channel (in the Record_Synth) is 0, but you can change it
    mmm_audio.send_int("set_input_chan", 0) 
    mmm_audio.start_audio() 

    import supriya_midi as midi

    # find your midi devices
    ports = midi.list_ports()
    print(f"Available MIDI ports: {ports}")

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(ports.index('Oxygen Pro Mini USB MIDI'))

    def midi_callback(msg, timestamp, data=None):
        msg = midi.MidiMessage.parse(msg)
        print(f"Received {msg=}")

        if type(msg) == midi.NoteOnMessage and msg.note_number == 48:
            mmm_audio.send_bool("is_recording", True)
        elif type(msg) == midi.NoteOffMessage and msg.note_number == 48:
            mmm_audio.send_bool("is_recording", False)

    in_port.set_callback(midi_callback)

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Exiting.")

if __name__ == "__main__":
    main()