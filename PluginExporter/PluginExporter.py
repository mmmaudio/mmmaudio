"""
Build MMMAudio graphs as VST3, CLAP or AU plugins, from Python.

Each `export_plugin` call compiles the graph, generates a JUCE project in
PluginExporter/builds/<name>/ and builds it, where <name> is plugin_name (by default
the graph_name). The finished plugins are left in PluginExporter/builds/<name>/plugins/,
and the call returns their paths.

The first build downloads JUCE (and, for CLAP, clap-juce-extensions) into the
PluginExporter folder, so it takes a few minutes. Later builds are faster.
It needs git and cmake (cmake should be installed via pixi).

macOS requires Xcode's command line tools.

Linux requires a C++ compiler and JUCE's development packages before building plugins.
On Debian/Ubuntu:

    sudo apt update
    sudo apt install g++ libasound2-dev libjack-jackd2-dev libfreetype-dev \
        libfontconfig1-dev libx11-dev libxcomposite-dev libxcursor-dev libxext-dev \
        libxinerama-dev libxrandr-dev libxrender-dev libxi-dev

It also needs patchelf (`pixi add patchelf` or `sudo apt install patchelf`), so the
bundled Mojo libraries load from the plugin rather than from the pixi environment.
Without it the export prints a warning, and the plugin may only work on the machine
that exported it.

`install=True` copies the plugins into your user plug-in folders: on macOS
~/Library/Audio/Plug-Ins/VST3, .../CLAP and .../Components (AU). Restart or
rescan the host afterwards to see them.

The folder created in the builds/ directory is a JUCE project with all necessary files, so it can be moved to a new location, and you can edit it and build it yourself. Instructions on how to build it with CMake on the command line are in the README.md in that folder. To work on it in Xcode, generate an Xcode project from that folder with `cmake -S . -B build-xcode -G Xcode` and open build-xcode/<name>.xcodeproj.

Every plugin accepts MIDI and passes it to the graph as "note_on", "note_off",
"cc", "pitch_bend" and so on, the same messages `MMMAudio.send_midi` sends.
See PluginExporter/export_plugin.py for the details.
"""
from PluginExporter.export_plugin import export_plugin

# ---- export the JUCE project only (into the PluginExporter/builds/ directory), without building the plugin ----

export_plugin("FM4", "examples", plugin_type=["Clap"], gui_file="examples/FM4.py", instrument=True, build=False)

# ---- build only ----

# The simplest build: a VST3 of the graph, with no parameters or editor.
# This is an effect, with 2 inputs and as many outputs as the graph's next() returns.
export_plugin("ManyOscillators", "examples", plugin_type="VST3", instrument=True)

# Give it a GUI script, and its sliders and checkboxes become host automatable
# parameters and a plain plugin editor. The export script translates the GUI into a JUCE editor.
export_plugin("FeedbackDelaysGUI", "examples", plugin_type="VST3", gui_file="examples/FeedbackDelaysGui.py")

# if the gui_file has not gui elements, it will build a plugin with no parameters and no editor, but it will still be automatable by the host.
export_plugin("MidiKeyboard", "examples", plugin_type="VST3", gui_file="examples/MidiKeyboard.py", instrument=True, install=True)


# Several plugin types at once. AU can only be built on macOS.
paths = export_plugin("FeedbackDelaysGUI", "examples", plugin_type=["VST3", "AU", "Clap"], gui_file="examples/FeedbackDelaysGui.py")
print(paths)

# An instrument: no audio input, MIDI in. BenjolinExample.py opens MMMAudio with
# in_device=None, which already marks it as an instrument; instrument=True makes it explicit.
export_plugin("BenjolinExample", "examples", plugin_type=["VST3", "AU"], gui_file="examples/BenjolinExample.py", instrument=True)


# ---- build and install ----

# MLP_Synth with 2D Slider. It will package the safetensors and the model into the plugin bundle, so it can run without any extra files.
export_plugin("MLP_Synth2D", "examples.ML_examples", plugin_type=["VST3", "AU", "Clap"], gui_file="examples/ML_examples/MLP_Synth2D.py", install=True, instrument=True)

export_plugin("BenjolinExample", "examples", plugin_type=["VST3", "AU"], gui_file="examples/BenjolinExample.py", install=True)

# if you have an 8 channel graph and set num_out to 8, it will build a plugin with 8 outputs. These will run in the DAW as an 8 channel process.
export_plugin("PanAzExample", "examples", plugin_type=["Clap"], install=True, num_out=8)