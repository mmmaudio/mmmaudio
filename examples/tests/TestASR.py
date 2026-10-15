from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="TestASR", package_name="examples.tests")
mmm_audio.start_audio()

mmm_audio.send_floats("curves", [4.0, -4.0])  # set the curves to logarithmic attack and exponential decay

# any midi note on opens the envelope's gate and any note off closes it, so we forward the keyboard's messages to mmm_audio:
if True:
    import supriya_midi as midi

    # find your midi devices
    midi_ports = midi.list_ports()
    print(f"Available MIDI ports: {midi_ports}")

    port_num = midi_ports.index('Oxygen Pro Mini USB MIDI')  # change this to your device name

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(port_num)

    # send_midi forwards every message to the graph the same way an exported plugin does
    def midi_callback(msg, timestamp, data=None):
        print(f"Received {midi.MidiMessage.parse(msg)}")
        mmm_audio.send_midi(msg)

    in_port.set_callback(midi_callback)