# VCVExporter

Turns an MMMAudio graph or struct into a VCV Rack plugin with one module.

> **Beta, and vibe coded.** LLMs wrote most of this exporter, and it may change without warning.
> See [the Exporters README](../README.md#vibe-coded-and-in-beta).

The module has `num_in` audio inputs, which the graph reads with `world[].sound_in(i)`,
and `num_out` audio outputs. The graph's Qt GUI script becomes its panel: sliders become
knobs and buttons become buttons.

The export writes a Rack plugin project to `builds/Mojo<version>/<Name>/` (e.g.
`builds/Mojo1.1.0/FM4/`), builds it, and optionally installs it. It uses the same engine
interface as the [PluginExporter](../PluginExporter/README.md) and the
[SCExporter](../SCExporter/README.md) (`MMMAudioPluginBridge.mojo`).

## Requirements

- The MMMAudio pixi environment
- `make` and a C++ compiler. macOS: Xcode's command line tools. Linux: `g++` and `patchelf`
  (Linux is untested)
- VCV Rack 2 (tested with 2.6.6)

The first export downloads the Rack SDK (about 8 MB) into `src/`. Later exports reuse
it. To use a Rack SDK you already have, pass `--rack_sdk` or set `RACK_DIR`.

## Export a module

Run from the MMMAudio folder:

```sh
pixi run python Exporters/VCVExporter/export_vcv.py \
    --graph_name FM4 --package_name examples \
    --gui_file examples/FM4.py --install
```

Or from Python, also from the MMMAudio folder:

```python
from Exporters.VCVExporter.export_vcv import export_vcv

export_vcv("FM4", "examples", gui_file="examples/FM4.py", install=True)
```

`Exporters/VCVExporter/VCVExporter.py` has more examples.

`--install` copies the plugin into Rack's plugins folder
(`~/Library/Application Support/Rack2/plugins-mac-arm64/` on an Apple Silicon Mac,
`~/.local/share/Rack2/plugins-lin-x64/` on Linux), replacing an earlier copy. Then restart
Rack: it only loads plugins when it starts. The module is in the browser under the brand
MMMAudio. Without `--install`, the finished plugin is in
`builds/Mojo<version>/<Name>/dist/MMMAudio-<Name>/`; copy that folder into the plugins folder.

| Option | What it does |
|---|---|
| `--graph_name` | The graph's struct and `.mojo` file name, as for `MMMAudio` (required, unless you use `--struct`). |
| `--package_name` | The folder holding the graph (default: the GUI script's `package_name`, else `examples`). |
| `--gui_file` | The graph's Qt GUI script. Its sliders and buttons become the module's knobs and buttons. |
| `--module_name` | The module's name (default: the graph name). The plugin is `MMMAudio-<module_name>`, and this is also the folder name in `builds/Mojo<version>/`. |
| `--instrument` / `--effect` | No audio inputs, or audio inputs. By default, a graph that never calls `sound_in` is an instrument. |
| `--num_in` | An effect's audio inputs. By default the GUI script's `num_input_channels`, capped at 2 (or 2 without a GUI script). |
| `--num_out` | Audio outputs. By default the N in the graph's `next() -> MFloat[N]`, then the GUI script's `num_output_channels`, then 2. |
| `--in_labels` | Names for the audio inputs, in order, like `--in_labels L R`. `None` keeps an input's default name (`IN 1`, `IN 2`, ...; `IN` for a single input), and so do inputs past the end of the list. From Python, pass a list, with `None` for a default. |
| `--out_labels` | Names for the audio outputs, as for `--in_labels` (`OUT 1`, ...). |
| `--resources` | Extra files or folders to bundle. Files the graph names by relative path, like `"resources/Shiverer.wav"`, are found automatically. |
| `--block_size` | Samples per graph block, which is also the module's latency: 1, 4, 16, 32 (default) or 64. It can be changed in the module's menu. |
| `--install` | Copy the plugin into Rack's plugins folder, replacing an earlier copy. |
| `--install_dir` | Install into this folder instead (implies `--install`). |
| `--no_build` | Only write the project, without building it. |
| `--rack_sdk` | A Rack SDK folder to build with. |

## Export a struct

`export_struct_vcv` builds one MMMAudio struct, like `Osc` or a struct of your own, as a
module, as the SCExporter's `export_struct_sc` does for SuperCollider:

```python
from Exporters.VCVExporter.export_vcv import export_struct_vcv

export_struct_vcv("BridgedT808", module="llm.Kick808", module_name="Kick808")
```

or `pixi run python Exporters/VCVExporter/export_vcv.py --struct BridgedT808 --module llm.Kick808`.

- **Inputs:** each argument of the struct's `next` (or `method`) becomes input jacks, in
  order: one for a `Float64`, `Bool` or `Int`, N for an `MFloat[N]`, `MBool[N]` or
  `MInt[N]`. A jack is named after its argument (`pitch 1`, `pitch 2` for an
  `MFloat[2]`). ±5 V is ±1 to the struct, and a `Bool` is true above 0 V. While nothing
  is plugged in, the argument gets its default value (`freq: Float64 = 440.0` gets 440),
  or 0.
- **Outputs:** the method's result, one jack per channel. `num_outputs` keeps only the
  first few: 5 of an `MFloat[8]`.
- **Knobs:** each `Float64` message the struct reads with its own `Messenger` gets a knob
  that sends -1 to 1, so scale the value in the struct. If the struct maps the variable
  the message fills with `linlin`, `linexp` or `lincurve` and plain numbers, like
  `linexp(self.knob_freq + freq, -1.0, 1.0, 20.0, 200.0)`, the knob shows the mapped value
  (20 to 200 Hz here), and you can type one in; it still sends -1 to 1, so it adds to an
  input jack as the struct adds them. A `Bool` message gets a latching
  button and a trig (`notify_trig`) a button. `Int`, `String` and list messages are left
  out. The knobs send their values when the graph is built, so they replace the struct's
  own starting values.
- **Labels:** `in_labels` and `out_labels` rename the jacks, as for a graph.

| Option | What it does |
|---|---|
| `--struct` | The struct to export, instead of `--graph_name`. |
| `--module` | The Mojo package or module that defines it, as you would import it (default `mmm_audio`). |
| `--module_name` | The module's name (default: the struct's, plus the method's for a method other than `next`). |
| `--method` | The method to run each sample (default `next`). |
| `--params` | Values for the struct's parameters, as Mojo code: `--params num_chans=2 interp=Interp.sinc`. |
| `--method_params` | Values for the method's parameters: `--method_params osc_type=OscType.saw`. A parameter pack takes a comma-separated list. |
| `--init_args` | Mojo expressions for `__init__` arguments without a default. |
| `--num_outputs` | Output jacks for only the first this many of the result's channels. |
| `--in_labels`, `--out_labels`, `--block_size`, `--install`, `--install_dir`, `--no_build`, `--rack_sdk` | As for a graph. |

The struct is run by a small graph the export writes to `src/struct_graphs/`.

## The module

The export prints the module's knobs and buttons. Hover over one in Rack to see its full
name and value.

| In the GUI | In Rack |
|---|---|
| A slider (`Handle`) | A knob over the same range, with the same curve. A slider that sends an int snaps to whole numbers. |
| A push button | A button. It sends the button's messages when pressed. |
| A button that randomizes or sets sliders | A button that turns those knobs. |
| A check box or checkable button | A latching button. |
| A combo box | A knob with one step per item, which shows the item's name. |
| An XY pad | Two knobs, x and y, plus a button if pressing the pad sends a message. |
| A file picker | Left out: a module can't open a file dialog. |

Controls are placed in the order they appear in the GUI, in rows, with the audio inputs
and then the outputs at the bottom of the panel. The panel is as wide as it needs to be.

Knobs and buttons are read once per block and sent to the graph when they change, as the
GUI would send them. The GUI script's setup messages are sent when the graph is built.
Without a GUI script the module has no knobs or buttons.

A jack's label on the panel shows the first 7 characters of its name; hover over it to
see the whole name.

Rack's audio is ±5 V and MMMAudio's is ±1, so inputs are divided by 5 and outputs
multiplied by 5. The ports are mono: a polyphonic cable gives its first channel.

### Block size and latency

Rack runs a module one sample at a time. The module collects samples and runs the graph
on a block of them, so its output is `block size` samples behind its input. A smaller
block lowers the latency and uses more CPU. Choose 1 to 64 samples in the module's
right-click menu; the choice is saved with the patch. The default is 32, or `--block_size`.

Changing Rack's sample rate rebuilds the graph at the new rate, with the knobs' current
values.

## The project folder

Each export creates `builds/Mojo<version>/<Name>/`:

| | |
|---|---|
| `src/` | The module's C++ (`MMMModule.cpp`), and `MMMVCVSpec.h`, which describes this graph and its panel |
| `res/` | The panel's background, light and dark |
| `bundle/` | The compiled Mojo graph, its engine and the Mojo runtime, plus files the graph loads |
| `plugin.json`, `Makefile`, `README.md` | The plugin's manifest, the build, and its instructions |
| `dist/MMMAudio-<Name>/` | The finished plugin folder |

Everything is replaced on re-export. To rebuild it yourself, see the project's README.md.

## The plugin folder

```
plugins-mac-arm64/
  MMMAudio-FM4/
    plugin.dylib          the module (plugin.so on Linux)
    plugin.json
    res/FM4.svg           its panel, and FM4-dark.svg
    bundle/
      libs/               the Mojo graph, its engine, and the Mojo runtime
      resources/          files the graph loads by relative path
```

Each plugin carries its own copy of the Mojo runtime (about 3 MB). The runtime libraries'
names carry the Mojo version (`libKGENCompilerRTShared.1.1.0.dylib`), so plugins built with
different Mojo versions can run in one Rack.

## Troubleshooting

- **The module's menu says the Mojo libraries didn't load, or the graph didn't build.**
  Rack's `log.txt` (in `~/Library/Application Support/Rack2/` or `~/.local/share/Rack2/`)
  says why. A graph that can't find a file it loads needs `--resources`.
- **A re-exported module still behaves as before.** Restart Rack: it doesn't reload plugins.
- **A plugin built on one machine won't load on another.** The Mojo libraries are native
  code, so export on each OS and CPU architecture you want to support.

## Files in this folder

| File | Role |
|---|---|
| `export_vcv.py` | The exporter (command line, `export_vcv()` and `export_struct_vcv()`) |
| `src/vcv_template/` | The module's C++, copied into every project as `src/` |
| `VCVExporter.py` | Examples of how to export graphs from Python |
| `src/Rack-SDK-<version>-<platform>/` | The Rack SDK, downloaded on first use |
| `src/struct_graphs/` | The graphs that run exported structs, written by `export_struct_vcv` |
| `builds/` | `Mojo<version>/`: one project per exported module |
