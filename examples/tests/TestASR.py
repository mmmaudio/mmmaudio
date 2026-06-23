from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="TestASR", package_name="examples.tests")
mmm_audio.start_audio()

mmm_audio.send_floats("curves", [4.0, -4.0])  # set the curves to logarithmic attack and exponential decay

# this program is looking for midi note_on and note_off from note 48, so we prepare the keyboard to send messages to mmm_audio:
if True:
    import supriya_midi as midi

    # find your midi devices
    midi_ports = midi.list_ports()
    print(f"Available MIDI ports: {midi_ports}")

    port_num = midi_ports.index('Oxygen Pro Mini USB MIDI')  # change this to your device name

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(port_num)

    def midi_callback(msg, timestamp, data=None):
        msg = midi.MidiMessage.parse(msg)
        print(f"Received {msg=}")
        if type(msg) == midi.NoteOnMessage:
            mmm_audio.send_bool("gate", True)
        elif type(msg) == midi.NoteOffMessage:
            mmm_audio.send_bool("gate", False)

    in_port.set_callback(midi_callback)