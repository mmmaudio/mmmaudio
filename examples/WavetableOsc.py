"""Example of a wavetable oscillator using custom wavetables loaded from files.

You can load your own wavetable files by sending a string message to the "load_file" parameter with the full path to the wavetable file.

MMM_Audio can load commercial .wav files, designed for Vital or Serum, as wavetables. The wavetable should be a single channel audio file made up of one or more cycles of a waveform, each a power of 2 in length. The wavetable will be looped to create the oscillator waveform.

Also demonstrates how to use the PVoiceAllocator class to manage multiple voices for polyphonic MIDI input.
"""

from mmm_python import *
mmm_audio = MMMAudio(128, graph_name="WavetableOsc", package_name="examples")
mmm_audio.start_audio() 

# load a different wavetable if you like - these are just example paths - change to your own files
# if the number of instances of the wave found in the wavetable file is different than the default 256, you may need to change the "wavetables_per_channel" parameter
mmm_audio.send_int("wavetables_per_channel", 128) # set this to the number of waveforms in your wavetable file

mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 10.wav'")
mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 11.wav'")
mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 12.wav'")
mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 13.wav'")
mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 14.wav'")
mmm_audio.send_string("load_file", "'/Users/ted/dev/BVKER - Custom Wavetables/Growl/Growl 15.wav'")

if True:
    import supriya_midi as midi

    # find your midi devices
    ports = midi.list_ports()
    print(f"Available MIDI ports: {ports}")
    port_num = ports.index('Oxygen Pro Mini USB MIDI')

    # open your midi device - you may need to change the device name
    in_port = midi.MidiIn()
    in_port.open_port(port_num)

    voice_allocator = PVoiceAllocator(8)

def note_on(msg):
    voice = voice_allocator.get_free_voice(msg.note_number)
    if voice == -1:
        print("No free voice available")
    else:
        voice_msg = "voice_" + str(voice)
        print(f"Note On: {msg.note_number} Velocity: {msg.velocity} Voice: {voice}")
        mmm_audio.send_float(voice_msg +".freq", midicps(msg.note_number))  # note freq and velocity scaled 0 to 1
        mmm_audio.send_bool(voice_msg +".gate", True)  # note freq and velocity scaled 0 to 1

def note_off(msg):
    found, voice = voice_allocator.release_voice(msg.note_number)
    if found:
        voice_msg = "voice_" + str(voice)
        print(f"Note Off: {msg.note_number} Voice: {voice}")
        mmm_audio.send_bool(voice_msg +".gate", False)  # note freq and velocity scaled 0 to 1

def cc(msg):
    print(f"Control Change: {msg.controller_number} Value: {msg.controller_value}")
    # Example: map CC 1 to wubb_rate of all voices
    if msg.controller_number == 1:
        wubb_rate = linexp(msg.controller_value, 0, 127, 0.1, 10.0)
        for i in range(8):
            voice_msg = "voice_" + str(i)
            mmm_audio.send_float(voice_msg +".wubb_rate", wubb_rate)
    if msg.controller_number == 33:
        mmm_audio.send_float("filter_cutoff", linexp(msg.controller_value, 0, 127, 20.0, 20000.0))
    if msg.controller_number == 34:
        mmm_audio.send_float("filter_resonance", linexp(msg.controller_value, 0, 127, 0.1, 1.0))

def midi_callback(msg, timestamp, data=None):
    msg = midi.MidiMessage.parse(msg)
    print(f"Received {msg=}")
    if type(msg) == midi.NoteOnMessage:
        note_on(msg)
    if type(msg) == midi.NoteOffMessage:
        note_off(msg)
    if type(msg) == midi.ControllerChangeMessage:
        cc(msg)

in_port.set_callback(midi_callback)