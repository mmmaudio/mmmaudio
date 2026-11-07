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

    # by changing this variable, you can change the style of MIDI messaging.
    # in each case, the same messages are used by the graph
    # the first sends every midi message. the second sends only selected midi message with formatting done in the function, the last sends only parsed messages, but uses the raw MIDI router after parsing out the relevant messages.
    messaging_format = 0

    def midi_callback(msg, timestamp, data=None):
        parsed = midi.MidiMessage.parse(msg)
        print(f"Received MIDI message: {parsed}")
        
        # depending on the setting above, we can send the MIDI message in different ways.
        if messaging_format == 0:
            # one way to handle MIDI messages is to forward raw MIDI messages directly to the graph using route_raw_midi
            mmm_audio.route_raw_midi(msg)

        elif messaging_format == 1:
            # a second way is to parse the MIDI message and handle it manually, as shown below.
            if type(parsed) == midi.NoteOnMessage:
                mmm_audio.send_ints("midi_note_on", [parsed.channel_id, parsed.note_number, parsed.velocity])
            elif type(parsed) == midi.NoteOffMessage:
                mmm_audio.send_ints("midi_note_off", [parsed.channel_id, parsed.note_number, parsed.velocity])
            elif type(parsed) == midi.ControllerChangeMessage and parsed.controller_number == 33:
                mmm_audio.send_ints("midi_cc", [parsed.channel_id, parsed.controller_number, parsed.controller_value])
            elif type(parsed) == midi.PitchWheelMessage:
                mmm_audio.send_ints("midi_pitch_bend", [parsed.channel_id, parsed.transposition])

        else:
            # this is equivalent to:
            if type(parsed) == midi.NoteOnMessage or type(parsed) == midi.NoteOffMessage or type(parsed) == midi.PitchWheelMessage:
                mmm_audio.route_raw_midi(msg)
            elif type(parsed) == midi.ControllerChangeMessage and parsed.controller_number == 33:
                mmm_audio.route_raw_midi(msg)


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