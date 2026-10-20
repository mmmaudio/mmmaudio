"""Example of a wavetable oscillator using custom wavetables loaded from files.

You can load your own wavetable files by sending a string message to the "load_file" parameter with the full path to the wavetable file.

MMM_Audio can load commercial .wav files, designed for Vital or Serum, as wavetables. The wavetable should be a single channel audio file made up of one or more cycles of a waveform, each a power of 2 in length. The wavetable will be looped to create the oscillator waveform.

Also demonstrates how to forward MIDI to the graph with send_midi and let a Poly in the graph manage the voices.
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

# send_midi forwards every message to the graph the same way an exported plugin does:
# note ons go to "note_on", note offs to "note_off", ccs to "cc", etc.
# the graph allocates the voices and maps cc 1 to the wubb rate, cc 33 to the filter cutoff and cc 34 to the filter resonance.
def midi_callback(msg, timestamp, data=None):
    print(f"Received {midi.MidiMessage.parse(msg)}")
    mmm_audio.send_midi(msg)

in_port.set_callback(midi_callback)
