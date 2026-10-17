# PluginExporter

Turns an MMMAudio graph into a VST3, CLAP or AU plugin. If you give it the
graph's Qt GUI script, the GUI's controls become host-automatable parameters and
a JUCE editor that you can restyle by hand.

The export writes a self-contained JUCE CMake project for each plugin to
`builds/<name>/`, and usually builds it and installs it too.

## Requirements

- The MMMAudio pixi environment, with `cmake` added (`pixi add cmake`)
- git
- macOS: Xcode's command line tools
- Linux: a C++ compiler, JUCE's development packages, and `patchelf`. Each exported
  project's README lists the apt packages.

The first export downloads JUCE (and, for CLAP, clap-juce-extensions) into this
folder, which takes a few minutes. Later exports reuse it.

## Export a plugin

Run from the MMMAudio folder:

```sh
pixi run python PluginExporter/export_plugin.py \
    --graph_name FM4 --package_name examples \
    --plugin_type VST3 AU CLAP \
    --gui_file examples/FM4.py \
    --instrument
```

Or from Python, also from the MMMAudio folder:

```python
from PluginExporter.export_plugin import export_plugin

export_plugin("FM4", "examples", plugin_type=["VST3", "AU", "CLAP"],
              gui_file="examples/FM4.py", instrument=True)
```

`PluginExporter/PluginExporter.py` has more examples.

The finished plugins are left in `builds/<name>/plugins/`. Add `--install` (or
`install=True`) to also copy them into your plug-in folders, then restart or rescan
your host.

| Option | What it does |
|---|---|
| `--graph_name` | The graph's struct and `.mojo` file name, as for `MMMAudio` (required). |
| `--package_name` | The folder holding the graph (default `examples`). |
| `--plugin_type` | Any of `VST3`, `CLAP`, `AU` (default `VST3`). AU is macOS only. |
| `--gui_file` | The graph's Qt GUI script. Without it the plugin has no parameters and an empty editor. |
| `--plugin_name` | The name the host shows (default: the graph name). This is also the folder name in `builds/`. |
| `--instrument` / `--effect` | Instrument (no audio input) or effect. By default this comes from the GUI script: `in_device=None` means instrument. |
| `--num_in` | An effect's input channels. By default the GUI script's `num_input_channels`, capped at 2 (or 2 without a GUI script); pass it for more. An instrument always has 0. |
| `--num_out` | Output channels. By default the N in the graph's `next() -> MFloat[N]`, then the GUI script's `num_output_channels`, then 2. |
| `--resources` | Extra files or folders to put inside the plugin. Files the graph names by relative path, like `"resources/Shiverer.wav"`, are found automatically. |
| `--install` | Copy the plugins into your user plug-in folders. |
| `--no_build` | Only write the project, without building it (see below). |
| `--reset_editor` | Regenerate the editor from the GUI script, discarding your edits to it. |
| `--config` | `Release` (default) or `Debug`. |

### What the export does

1. Compiles the graph and the plugin bridge (`MMMAudioPluginBridge.mojo`) into shared
   libraries.
2. If `--gui_file` is given, runs the script against stand-ins for PySide6 and
   MMMAudio (`gui_tracer.py`) to find its controls. Nothing is shown and no audio
   starts. The result is saved as `builds/<name>/gui_spec.json`.
3. Writes the JUCE project to `builds/<name>/`.
4. Configures and builds it with CMake, using the local JUCE copy.
5. Copies the plugins to `builds/<name>/plugins/` and, with `--install`, into your
   plug-in folders.

### GUI scripts

The tracer understands these widgets:

| Qt widget | Becomes |
|---|---|
| `QSlider`, `QDial`, `QSpinBox`, `QDoubleSpinBox`, MMMAudio `Handle` | A slider parameter |
| `QCheckBox`, `QRadioButton`, checkable `QPushButton` | An on/off parameter |
| `QComboBox` | A choice parameter |
| MMMAudio `Slider2D` | An XY pad |
| `QPushButton` | A button that sends its messages |
| A button that opens a `QFileDialog` | A file picker |
| `QLabel`, `QGroupBox` titles | Labels |
| `QVBoxLayout`, `QHBoxLayout`, `QGridLayout`, `QFormLayout` | Rows and columns |

Anything it can't translate is reported as a `GUI warning` during the export.

### MIDI

Every plugin, instrument or effect, accepts MIDI and forwards it to the graph as Int
list messages:

| Message | Contents |
|---|---|
| `note_on` / `note_off` | `[note, velocity, channel]` |
| `cc` | `[controller, value, channel]` |
| `pitch_bend` | `[value, channel]` |
| `poly_aftertouch` | `[note, pressure, channel]` |
| `channel_pressure` | `[pressure, channel]` |
| `program_change` | `[program, channel]` |

`MMMAudio.send_midi` sends the same messages, so a graph behaves the same with a MIDI
device in Python and as a plugin.

## The project folder

Each export creates `builds/<name>/`, a self-contained CMake project:

| Path | What it is | Replaced on re-export? |
|---|---|---|
| `Source/` | The editor (`PluginEditor.h/.cpp`). Yours to edit. | Only if unedited, or with `--reset_editor` |
| `mmm_plugin/` | The processor, the editor's controls (`MMMWidgets.h`) and `bundle_plugin.py` | Yes |
| `bundle/` | The compiled Mojo libraries, plus files the graph loads | Yes |
| `MMMPluginSpec.h` | Parameters and setup messages, translated from the GUI | Yes |
| `CMakeLists.txt`, `README.md` | The build, and its instructions | Yes |
| `build/`, `plugins/` | CMake's build folder, and the finished plugins | Rebuilt |

The project doesn't need the MMMAudio repository to build. You can copy or move it
anywhere (delete its `build/` folder first). If you don't point it at local copies,
CMake downloads JUCE and clap-juce-extensions on the first configure.

## Build and install with CMake

You can build any project folder with CMake directly, for example after editing its
editor or after an export with `--no_build`. Run from `builds/<name>/`. The project's
own `README.md` has the exact commands for that plugin.

Configure. This is needed once per `build/` folder; the export has already done it unless
you used `--no_build`:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
```

To use the copies in this folder instead of downloading them, add
`-DMMM_JUCE_DIR=<this folder>/JUCE` and, for CLAP,
`-DMMM_CLAP_DIR=<this folder>/clap-juce-extensions`.

Build. The targets are `<name>_VST3`, `<name>_AU` and `<name>_CLAP`:

```sh
cmake --build build --config Release --parallel --target FM4_VST3 FM4_AU FM4_CLAP
```

The plugins appear in `build/<name>_artefacts/Release/`. After building each one,
CMake copies the Mojo libraries into it.

Install:

```sh
cmake --install build --config Release --component plugin
```

Keep `--component plugin`. Without it, CMake also runs JUCE's own install rules,
which try to copy JUCE into `/usr/local` and fail.

Inside the MMMAudio repository, prefix these commands with `pixi run` to use the pixi
environment's CMake. Outside it, any CMake 3.28 or newer works.

| Format | Installed to |
|---|---|
| VST3 | `~/Library/Audio/Plug-Ins/VST3` (macOS), `~/.vst3` (Linux) |
| CLAP | `~/Library/Audio/Plug-Ins/CLAP` (macOS), `~/.clap` (Linux) |
| AU | `~/Library/Audio/Plug-Ins/Components` |

## Customizing the editor

The editor in `Source/` is plain JUCE code generated from the Qt GUI (`editor_codegen.py`):

- **Controls:** each control is a named member, e.g.
  `mmm::SliderRow freqSlider { plugin.apvts, "freq", "freq Hz" };`. It attaches to
  its parameter by ID, so you can restyle or move it without changing what it controls.
- **Layout:** `resized()` places each control with explicit `setBounds` calls.
- **Look:** the `lookAndFeel` member restyles every control at once. Replace it with
  your own `juce::LookAndFeel_V4` subclass.
- **Extra code:** other `.cpp` files you add to `Source/` are compiled. Images and
  fonts in `Source/assets/` are available through `BinaryData` (`#include "BinaryData.h"`).

After editing, either build with CMake or re-export. The export only regenerates the
editor while it still matches what it last generated, so your edits survive a
re-export. Use `--reset_editor` to start over from the GUI.

A kept editor won't show controls you later add to the Qt GUI. The parameters still
reach the host; add the controls to the editor yourself, or use `--reset_editor`.

## When to re-export and when to just build

| You changed | Do |
|---|---|
| The editor in `Source/` | Build with CMake (or re-export) |
| The Mojo graph, or anything it imports | Re-export |
| The Qt GUI script (parameters, layout) | Re-export (with `--reset_editor` if the editor has been edited) |
| A file the graph loads (samples, etc.) | Re-export |

Each export gives the plugin a new version (`0.1.<n>`), so hosts reload its
parameters instead of using a cached copy.

## Troubleshooting

- **A fix to the exporter doesn't seem to apply.** In a Python session or notebook
  that imported `export_plugin` before you changed it, the old code is still loaded.
  Restart the session, or use the command-line export.
- **`file INSTALL cannot make directory "/usr/local/include/JUCE-..."`**: add
  `--component plugin` to `cmake --install`.
- **The host doesn't see a new AU.** `--install` and `cmake --install` restart macOS's
  AU registration service (`AudioComponentRegistrar`). If the host still has the old
  version, restart the host.
- **The editor shows "could not load ..." or "could not create the MMMAudio graph
  from ..."**: the plugin couldn't load its Mojo libraries or graph. Check that
  `Contents/Frameworks` (macOS) or the `<name>_mmm` folder (Linux) is inside the plugin
  and holds them. If you built with CMake, a `bundle_plugin:` line should have appeared
  for each format. On Linux, also check that `patchelf` was installed when you exported.
- **A plugin built on one machine won't load on another.** The Mojo libraries are
  native code, so export on each OS and CPU architecture you want to support.

## Files in this folder

| File | Role |
|---|---|
| `export_plugin.py` | The exporter (command line and `export_plugin()`) |
| `gui_tracer.py` | Translates a Qt GUI script into `gui_spec.json` |
| `editor_codegen.py` | Writes the editor's C++ from that spec |
| `bundle_plugin.py` | Copies the Mojo libraries into a built plugin (copied into every project) |
| `juce_template/` | The processor and controls (copied into every project as `mmm_plugin/`) |
| `MMMAudioPluginBridge.mojo`, `.h` | The engine's C interface, which the plugin calls |
| `JUCE/`, `clap-juce-extensions/` | Local copies, downloaded on first use |
| `builds/` | One project per exported plugin |
