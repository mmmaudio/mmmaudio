"""
Build MMMAudio graphs as SuperCollider UGens, from Python.

Each `export_sc` call compiles the graph, writes a CMake project to
Exporters/SCExporter/builds/<Name>/ and builds it, where <Name> is the UGen's class name (by
default the graph_name). The finished extension folder is left in
Exporters/SCExporter/builds/<Name>/extension/<Name>/, and the call returns its path.
`install=True` copies it into the MMMAudio folder of your SuperCollider Extensions
folder (creating it if needed); then recompile the class library and reboot the server.

The first build downloads SuperCollider's plug-in headers (a few MB) into the
SCExporter folder. It needs git and cmake (`pixi add cmake`), and on macOS Xcode's
command line tools.

The graph's audio inputs become the UGen's first (audio-rate) inputs, and the GUI
script's sliders, check boxes, combo boxes and buttons, plus any Float64, Int or
Bool the graph reads with a Messenger, become control-rate inputs. Any other
message is sent with the class's send methods, e.g. `FM4.sendString(synth, "key", "text")`.
See Exporters/SCExporter/README.md.
"""
from Exporters.SCExporter.export_sc import export_sc, export_struct_sc

# ---- write the project only (into Exporters/SCExporter/builds/), without building it ----

export_sc("FM4", "examples", gui_file="examples/FM4.py", build=False)

# ---- build ----

# The GUI's sliders become control-rate inputs: FM4.ar(osc0_freq: 100, ...)
export_sc("FM4", "examples", gui_file="examples/FM4.py", install=True)
export_sc("ManyOscillators", "examples", install=True)
export_sc('QuadRingMod', 'llm.test_export', num_in=4, install=True) 

# Without a GUI script, the controls come from the graph itself: here the lpf_freq
# and play_rate Float64s it reads with a Messenger. The sound file it loads is bundled.
export_sc("PlayExample", "llm", gui_file="llm/PlayExample.py", install=True)

# A graph that reads sound_in is an effect: PitchShiftExample.ar(SoundIn.ar([0, 1]), pitch_shift: 2)
export_sc("PitchShiftExample", "examples", gui_file="examples/PitchShiftExample.py")

# A different class name, and one audio input.
export_sc("PitchShiftExample", "examples", gui_file="examples/PitchShiftExample.py",
          ugen_name="MMMPitchShift", num_in=1)

# ---- build and install ----

# Strings and lists are sent with unit commands: MessengerExample.sendStrings(x, "strings", ["a", "b"])
export_sc("MessengerExample", "examples", install=True)

# An 8 channel graph gives an 8 channel UGen.
export_sc("PanAzExample", "examples", install=True, num_out=8)

# ---- a single struct ----

# The arguments of a struct's next() become audio-rate arguments: MMMOsc.ar(freq: 440)
export_struct_sc("Osc")
export_struct_sc("Freeverb")

# Its parameters can be set: MMMOsc2.ar(freq: [440, 660]) gives 2 channels.
export_struct_sc("Osc", ugen_name="MMMOscSinc",params={"num_chans": 2, "interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"})

# The method's parameters can be set too, as Mojo code: a saw wave.
export_struct_sc("Osc", ugen_name="MMMOscSaw", method_params={"osc_type": "OscType.saw"})

# Another method. A parameter pack takes a list:
# MMMOscNextBasicWaveforms.ar(200, osc_frac: 0.5) is halfway from sine to square.
export_struct_sc("Osc", method="next_basic_waveforms",
                 method_params={"osc_types": ["OscType.sine", "OscType.triangle", "OscType.saw", "OscType.square"]})

# next_all_basic_waveforms returns an MFloat[4], so the UGen has 4 outputs.
export_struct_sc("WavetableOsc", module="examples.export_examples", ugen_name="MMMWavetableOsc", params={"num_chans": 1, "interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"})
