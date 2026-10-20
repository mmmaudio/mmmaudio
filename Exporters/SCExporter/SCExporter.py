"""
Build MMMAudio graphs and structs as SuperCollider UGens, from Python.

Each `export_sc` or `export_struct_sc` call compiles the graph, writes a CMake project to
Exporters/SCExporter/builds/Mojo<version>/<Name>/ and builds it, where <Name> is the
UGen's class name (by default the graph_name). The finished extension folder is left in
builds/Mojo<version>/<Name>/extension/<Name>/, and the call returns its path. The Mojo
runtime libraries, which all UGens built with that Mojo version share, are in
builds/Mojo<version>/shared_libraries/. `install=True` copies the extension into the
MMMAudio folder of your SuperCollider Extensions folder (creating it if needed), as
Mojo<version>/<Name>/, and the runtime into Mojo<version>/shared_libraries/;
`install_dir="..."` installs somewhere else instead.
Then recompile the class library and reboot the server.

The first build downloads SuperCollider's plug-in headers (a few MB) into the
SCExporter folder. It needs git and cmake (`pixi add cmake`), and on macOS Xcode's
command line tools.

There are key differences between compiling a graph and a struct:

The graph has no arguments in its next function, so audio inputs from Environment.sound_in become the 
UGen's first argument. Set this number of inputs with `num_in`. 

The graph's parameters (from the GUI script) become control-rate inputs. Messages can also be sent to the graph with the class's send methods, e.g. `FM4.sendString(synth, "key", "text")`. This is most useful for sending strings, like file paths, or lists, which can't be sent as control-rate inputs.

The struct exporter allows you to build a single UGen from a Mojo struct. The key difference is that the struct's next function can have arguments, which become audio-rate inputs to the UGen. The struct's parameters and method parameters can also be set at compile-time, so the UGen can be specialized for a particular use. The struct's Messenger can also be used to receive messages from sclang.

See Exporters/SCExporter/README.md.
"""
from Exporters.SCExporter.export_sc import export_sc, export_struct_sc

# ---- write the project only (into Exporters/SCExporter/builds/Mojo<version>/), without building it ----

export_sc("FM4", "examples", gui_file="examples/FM4.py", build=False)

# ---- build ----

# The GUI's sliders become control-rate inputs: FM4.ar(osc0_freq: 100, ...)
export_sc("FM4", "examples", gui_file="examples/FM4.py", install=True)
export_sc("ManyOscillators", "examples.export_examples", install=True)
export_sc('QuadRingMod', 'examples.export_examples', num_in=4, install=True) 

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

# ---- exporting a single struct ----

# The arguments of a struct's next() become audio-rate arguments: MMMOsc.ar(freq: 440)
export_struct_sc("Osc")
export_struct_sc("Freeverb")

# Two channel sinc interpolated sawtooth oscillator, with 2x oversampling. 
export_struct_sc("Osc", ugen_name="MMMOscSincSaw",params={"num_chans": 2, "interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"}, method_params={"osc_type": "OscType.saw"}, install=True)

# The method's parameters can be set too, as Mojo code: a saw wave.
export_struct_sc("Osc", ugen_name="MMMOscSaw", method_params={"osc_type": "OscType.saw"})

# Another method. A parameter pack takes a list:
# MMMOscNextBasicWaveforms.ar(200, osc_frac: 0.5) is halfway from sine to square.
export_struct_sc("Osc", method="next_basic_waveforms",
                 method_params={"osc_types": ["OscType.sine", "OscType.triangle", "OscType.saw", "OscType.square"]})

# next_all_basic_waveforms returns an MFloat[4], so the UGen has 4 outputs.
export_struct_sc("WavetableOsc", module="examples.export_examples", ugen_name="MMMWavetableOsc", params={"num_chans": 1, "interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"})

# A struct outside mmm_audio, with oversampling (TimesOversampling.x2, not 2x). It reads
# messages with its own Messenger: MMMWavetableOsc.sendString(x, "load_wavetable", path)
export_struct_sc("WavetableOsc", module="examples.export_examples", ugen_name="MMMWavetableOsc",
                 params={"num_chans": 1, "interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"}, install=True)
