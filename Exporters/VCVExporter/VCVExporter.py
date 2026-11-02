"""
Build MMMAudio graphs as VCV Rack plugins, from Python.

Each `export_vcv` call compiles the graph, writes a Rack plugin project to
Exporters/VCVExporter/builds/Mojo<version>/<Name>/ and builds it, where <Name> is the
module's name (by default the graph_name). The finished plugin folder is left in
builds/Mojo<version>/<Name>/dist/MMMAudio-<Name>/, and the call returns its path.
`install=True` copies it into Rack's plugins folder; `install_dir="..."` installs
somewhere else instead. Then restart Rack.

The module has num_in audio inputs (what the graph reads with sound_in) and num_out
audio outputs. The GUI script's sliders become knobs and its buttons become buttons.

The first build downloads the Rack SDK into the VCVExporter folder. It needs make, and
on macOS Xcode's command line tools.

See Exporters/VCVExporter/README.md.
"""
from Exporters.VCVExporter.export_vcv import export_vcv, export_struct_vcv

# ---- write the project only (into Exporters/VCVExporter/builds/Mojo<version>/), without building it ----

export_vcv("FM4", "examples", gui_file="examples/FM4.py", build=False)

# ---- build and install ----

# The GUI's 16 sliders become knobs, and its randomize button turns them.
export_vcv("FM4", "examples", gui_file="examples/FM4.py", install=True)
export_vcv("BenjolinExample", "examples", gui_file="examples/BenjolinExample.py", module_name="Benjolin",
           install=True)

# A graph that reads sound_in is an effect: a stereo reverb with two inputs and two outputs.
export_vcv("DattorroReverbExample", "examples", gui_file="examples/DattorroReverbExample.py",
           module_name="Dattorro", in_labels=["L", "R"], out_labels=["L", "R"], install=True)

# Four audio inputs, and no added latency beyond one sample. The None keeps the default name, IN 4.
export_vcv("QuadRingMod", "examples.export_examples", num_in=4, block_size=1,
           in_labels=["car L", "mod L", "car R", None], out_labels=["L", "R"], install=True)

# ---- exporting a single struct ----

# The arguments of a struct's next() become input jacks, and its result output jacks.
# Each Float64 message it reads gets a knob that sends -1 to 1.
# Kick808_S maps its knobs with linexp and linlin, so they show Hz, seconds and semitones.
export_struct_vcv("Kick808_S", module="llm.Kick808", module_name="Kick808", install=True)
# The bare circuit in llm/Kick808.mojo, without knobs: a trig jack in, the drum out.
export_struct_vcv("BridgedT808", module="llm.Kick808", in_labels=["trig"],
                  out_labels=["out"], install=True)

# A two channel sine oscillator: jacks for freq 1 and 2 (100 Hz while unplugged), phase_offset 1
# and 2, and trig.
export_struct_vcv("Osc", module_name="MMMOsc2", params={"num_chans": 2}, install=True)

# Only the first 5 of a struct's 8 output channels get jacks.
# export_struct_vcv("MyStruct", module="my_package", num_outputs=5)
