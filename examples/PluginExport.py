"""
Build MMMAudio graphs as VST3, CLAP or AU plugins, from Python.

Each `export_plugin` call compiles the graph, generates a JUCE project in
PluginExporter/builds/<graph_name>/ and builds it. The finished plugins are left in PluginExporter/builds/<graph_name>/plugins/, and the call returns their paths.

The first build downloads JUCE (and, for CLAP, clap-juce-extensions) into the
PluginExporter folder, so it takes a few minutes. Later builds are faster.
It needs git and cmake (`pixi add cmake`), and Xcode's command line tools on macOS.

`install=True` copies the plugins into your user plug-in folders: on macOS
~/Library/Audio/Plug-Ins/VST3, .../CLAP and .../Components (AU). Restart or
rescan the host afterwards to see them.

Every plugin accepts MIDI and passes it to the graph as "note_on", "note_off",
"cc", "pitch_bend" and so on, the same messages `MMMAudio.send_midi` sends.
See PluginExporter/export_plugin.py for the details.
"""
from PluginExporter.export_plugin import export_plugin

# ---- build only ----

# The simplest build: a VST3 of the graph, with no parameters or editor.
# This is an effect, with 2 inputs and as many outputs as the graph's next() returns.
export_plugin("FeedbackDelaysGUI", "examples", plugin_type="VST3")

# Give it a GUI script, and its sliders and checkboxes become host automatable
# parameters and a plain plugin editor. The export script translates the GUI into a JUCE editor.
export_plugin("FeedbackDelaysGUI", "examples", plugin_type="VST3", gui_file="examples/FeedbackDelaysGui.py")

# Several plugin types at once. AU can only be built on macOS.
paths = export_plugin("FeedbackDelaysGUI", "examples", plugin_type=["VST3", "AU", "Clap"], gui_file="examples/FeedbackDelaysGui.py")
print(paths)

# An instrument: no audio input, MIDI in. BenjolinExample.py opens MMMAudio with
# in_device=None, which already marks it as an instrument; instrument=True makes it explicit.
export_plugin("BenjolinExample", "examples", plugin_type=["VST3", "AU"], gui_file="examples/BenjolinExample.py", instrument=True)

export_plugin("SuperSaw", "llm", plugin_type=["VST3", "AU", "Clap"], gui_file="llm/SuperSaw.py", instrument=True, build=False)

# Other options:
# - plugin_name: the name the host shows (default: the graph name).
# - num_in / num_out: channel counts, if the defaults are wrong. num_in is the
#   effect's input count and is fixed: the plugin only accepts that many input channels.
# - resources: extra files or folders to bundle. Files the graph names by relative
#   path, like "resources/Shiverer.wav", are found and bundled automatically.
# - config: "Release" (default) or "Debug".
export_plugin("FeedbackDelaysGUI", "examples", plugin_type="VST3", gui_file="examples/FeedbackDelaysGui.py", plugin_name="MMM Feedback Delays", num_in=1, num_out=2)

# ---- build and install ----

# The same calls with install=True also copy the plugins into your plug-in folders.
export_plugin("FeedbackDelaysGUI", "examples", plugin_type=["VST3", "AU"], gui_file="examples/FeedbackDelaysGui.py", install=True)

# MLP_Synth with no gui, but it should package the safetensors and the model into the plugin bundle, so it can run without any extra files.
export_plugin("MLP_Synth2D", "examples.ML_examples", plugin_type=["VST3", "AU", "Clap"], gui_file="examples/ML_examples/MLP_Synth2D.py", install=True, instrument=True)

export_plugin("ManyOscillators", "user_files", plugin_type=["VST3"], install=True, instrument=True)

export_plugin("BenjolinExample", "examples", plugin_type=["VST3", "AU"], gui_file="examples/BenjolinExample.py", install=True)
export_plugin("FDNVerb", "llm", plugin_type=["VST3", "AU", "Clap"], gui_file="llm/FDNVerb.py", install=True)

# The same build from a terminal, in the MMMAudio folder:
# `pixi run python PluginExporter/export_plugin.py --graph_name FeedbackDelaysGUI --package_name examples --plugin_type VST3 AU --gui_file examples/FeedbackDelaysGui.py --install`
