# SCExporter

Turns an MMMAudio graph into a SuperCollider UGen. The graph's audio inputs become the
UGen's audio-rate inputs, and the values you would send it from Python with `send_float`,
`send_int` and `send_bool` (sliders, check boxes and so on) become control-rate inputs.
Any other message, like a string or a list, is sent to a running Synth with a unit command.

The export writes a CMake project to `builds/Mojo<version>/<Name>/` (e.g.
`builds/Mojo1.1.0/FM4/`), builds it, and usually installs it too. It uses the same engine interface as the
[PluginExporter](../PluginExporter/README.md) (`MMMAudioPluginBridge.mojo`).

## Requirements

- The MMMAudio pixi environment, with `cmake` added (`pixi add cmake`)
- git
- macOS: Xcode's command line tools. Linux: a C++ compiler and `patchelf` (Linux is untested)
- SuperCollider (tested with 3.14)

The first export downloads SuperCollider's plug-in headers (a few MB) into this folder.
Later exports reuse them. To use a SuperCollider source folder you already have, pass
`--sc_path` or set `SC_PATH`.

## Export a UGen

Run from the MMMAudio folder:

```sh
pixi run python Exporters/SCExporter/export_sc.py \
    --graph_name FM4 --package_name examples \
    --gui_file examples/FM4.py --install
```

Or from Python, also from the MMMAudio folder:

```python
from Exporters.SCExporter.export_sc import export_sc

export_sc("FM4", "examples", gui_file="examples/FM4.py", install=True)
```

`Exporters/SCExporter/SCExporter.py` has more examples.

`--install` copies the extension into `MMMAudio/` in your user Extensions folder
(`Platform.userExtensionDir`), creating that folder if it isn't there, so all exported
UGens are kept together. `--install_dir` (`install_dir=` in Python) installs into another
folder instead. Then recompile the class library and reboot the server.

UGens are grouped by the Mojo version they were built with: the install puts the UGen in
`MMMAudio/Mojo<version>/<Name>/`. The Mojo runtime libraries are the same for every UGen
built with the same Mojo version, so they share one copy, in
`MMMAudio/Mojo<version>/shared_libraries/`, which the install creates or updates. See
[The extension folder](#the-extension-folder). Without `--install`, the finished extension
is in `builds/Mojo<version>/<Name>/extension/<Name>/` and the runtime in
`builds/Mojo<version>/shared_libraries/`; copy them into your Extensions folder in that
layout.

| Option | What it does |
|---|---|
| `--graph_name` | The graph's struct and `.mojo` file name, as for `MMMAudio` (required). |
| `--package_name` | The folder holding the graph (default: the GUI script's `package_name`, else `examples`). |
| `--gui_file` | The graph's Qt GUI script. Its controls become control-rate inputs. |
| `--ugen_name` | The UGen's class name (default: the graph name, capitalized). This is also the folder name in `builds/Mojo<version>/`. |
| `--instrument` / `--effect` | No audio inputs, or audio inputs. By default, a graph that never calls `sound_in` is an instrument. |
| `--num_in` | An effect's audio inputs. By default the GUI script's `num_input_channels`, capped at 2 (or 2 without a GUI script). |
| `--num_out` | Outputs. By default the N in the graph's `next() -> MFloat[N]`, then the GUI script's `num_output_channels`, then 2. |
| `--resources` | Extra files or folders to bundle. Files the graph names by relative path, like `"resources/Shiverer.wav"`, are found automatically. |
| `--install` | Copy the extension into the `MMMAudio` folder of your user Extensions folder (creating it if needed), as `Mojo<version>/<Name>/`, replacing earlier copies (also ones built with other Mojo versions), and the Mojo runtime into `Mojo<version>/shared_libraries/`. |
| `--install_dir` | Install into this folder instead of `Extensions/MMMAudio` (implies `--install`). |
| `--no_build` | Only write the project, without building it. |
| `--sc_path` | A SuperCollider source folder to take the plug-in headers from. |
| `--config` | `Release` (default) or `Debug`. |

## Export a single struct

`export_struct_sc` turns one MMMAudio struct, like `Osc` or `Freeverb`, into a UGen. The
arguments of the struct's `next` method become the UGen's `.ar` arguments, in the same
order and with the same defaults, all at audio rate (numbers and control-rate signals are
made audio rate). What `next` returns is the output.

```python
from Exporters.SCExporter.export_sc import export_struct_sc

export_struct_sc("Osc")        # MMMOsc.ar(freq: 100, phase_offset: 0, trig: 0)
export_struct_sc("Freeverb")   # MMMFreeverb.ar(input, room_size: 0, lp_comb_lpfreq: 1000, added_space: 0)
```

```sh
pixi run python Exporters/SCExporter/export_sc.py --struct Freeverb --install
```

- The UGen is called `MMM<Struct>` unless you pass `ugen_name`, since SuperCollider has
  its own `Osc`, `Line`, `Phasor` and so on. For a method other than `next`, the method's
  name is added: `MMMOscNextBasicWaveforms`.
- `method` runs another method of the struct instead of `next`, e.g.
  `method="next_basic_waveforms"` (`--method next_basic_waveforms`).
- The struct's parameters and the method's have their default values. Set them, as Mojo
  code, with `params` and `method_params`. A parameter pack takes a list.

  ```python
  export_struct_sc("Osc", ugen_name="MMMOscSinc",
                   params={"interp": "Interp.sinc", "ov_samp": "TimesOversampling.x2"})
  export_struct_sc("Osc", ugen_name="MMMOscSaw", method_params={"osc_type": "OscType.saw"})
  export_struct_sc("Osc", method="next_basic_waveforms",
                   method_params={"osc_types": ["OscType.sine", "OscType.saw", "OscType.square"]})
  ```

  On the command line: `--params interp=Interp.sinc ov_samp=TimesOversampling.x2`, and
  `--method_params osc_types=OscType.sine,OscType.saw,OscType.square`. The help file lists
  every parameter's value.
- An `MFloat[N]`, `MBool[N]` or `MInt[N]` argument takes N channels; a `Float64`, `Bool` or
  `Int` takes one. A `Bool` is true above 0. A one-channel argument given an array expands
  into several UGens, as usual: `MMMOsc.ar([440, 660])`. What the method returns sets the
  outputs: `next_all_basic_waveforms` returns an `MFloat[4]`, so it has 4.
- A struct from outside `mmm_audio`: `module="examples.export_examples"` (a package) or
  `module="llm.test_export.QuadRingMod"` (a file). `__init__` arguments without a default:
  `init_args={"max_delay": "1.0"}`, as Mojo code.
- A struct with its own `Messenger` reads messages, sent to a running Synth with the class
  methods. `examples/export_examples/WavetableOsc.mojo` loads a wavetable this way:
  `MMMWavetableOsc.sendString(x, "load_wavetable", path)`. The help file lists the
  messages.
- The export writes a small graph that runs the struct to `struct_graphs/`, and exports
  that.

## Using the UGen

The export prints the UGen's inputs. Each UGen has a help file, which lists them with their
ranges and has an example (select the class name and press Cmd-D, or Ctrl-D on Linux).
The generated class (`Classes/<Name>.sc`) lists them too.

```supercollider
(
SynthDef(\fm4, { |out = 0, osc0_freq = 100, osc0_mula = 0|
	Out.ar(out, FM4.ar(osc0_freq: osc0_freq, osc0_mula: osc0_mula));
}).add;
)
x = Synth(\fm4);
x.set(\osc0_freq, 300);
```

An effect takes its audio first: `PitchShiftExample.ar(SoundIn.ar([0, 1]), pitch_shift: 2)`.
A mono signal into a 2-input UGen is used for both inputs.

### Inputs

| Input | Rate | Comes from |
|---|---|---|
| `in` (effects only) | audio | The graph's `world[].sound_in(i)` |
| A slider (`QSlider`, `Handle`...) | control | Sends its value as a float, int or bool, as the GUI does |
| A check box or combo box | control | Its state number: 0 or 1, or the item's index. It sends what the GUI sends for that state |
| A button | control | A trigger: sends the button's messages when it goes from 0 or less to above 0 |
| An XY pad | control | One input each for x and y, sent together as the list the GUI sends |
| A `Float64`, `Int` or `Bool` the graph reads with `Messenger.update` | control | Sent as that type |
| A `Messenger.notify_trig` | control | A trigger |

Controls are read once per block and only sent to the graph when they change. The ones
from the graph itself are those the GUI doesn't already send, so a graph without a GUI
script still gets a control for each value it reads. Their defaults are the values the
graph sets in `__init__`, or the value the GUI script sends on setup. Keys of a Messenger
with a namespace written in the code (`Messenger(self.world, "synth1")`) get it as a prefix
(`synth1_freq`); a namespace only known when the graph runs can't be followed, and the
export notes the keys it skipped.

### Messages

The class sends any message to a running Synth, the same ones `MMMAudio.py` sends:

```supercollider
FM4.sendFloat(x, "key", 1.5);
FM4.sendFloats(x, "key", [1, 2, 3]);
FM4.sendInt(x, "key", 3);         // also sendInts
FM4.sendBool(x, "key", true);     // also sendBools
FM4.sendTrig(x, "key");           // also sendTrigs
FM4.sendString(x, "key", "~/sounds/a.wav".standardizePath);
FM4.sendStrings(x, "key", ["a", "b"]);
```

These are unit commands: `/u_cmd nodeID ugenIndex "float" "key" 1.5`, and so on for
`floats`, `int`, `ints`, `bool`, `bools`, `trig`, `trigs`, `string` and `strings`. The
class finds the UGen's index from the SynthDef, for SynthDefs built in this session or added
with `.add`. If a SynthDef holds more than one of the same UGen, give each an `id`
(`FM4.ar(id: \left)`) and pass it along: `FM4.sendFloat(x, "key", 1.5, id: \left)`.

A message under the same name as a control input is overwritten by that input when the
graph is first built, and whenever the input changes.

The export lists the messages it couldn't make into inputs (strings, lists, file pickers)
as notes, and they are repeated at the top of the class file.

### Timing

Building a graph allocates memory and may load files, so each Synth builds its graph on the
server's non-real-time thread, and outputs silence until it is ready. Freeing it, and the
send methods, go through the same thread, in order, so a message sent right after
`Synth(...)` reaches the new graph. A graph that loads a large sound file can take a moment.

Every Synth gets its own graph, built at the server's sample rate and block size.

## The project folder

Each export creates `builds/Mojo<version>/<Name>/`, a CMake project. It is built against
the Mojo runtime libraries in `builds/Mojo<version>/shared_libraries/`, which the exports
with that Mojo version share:

| Path | What it is |
|---|---|
| `src/` | The UGen's C++ (`MMMUGen.cpp`), and `MMMSCSpec.h`, which describes this graph |
| `sc/` | The class (`Classes/<Name>.sc`) and its help file (`HelpSource/Classes/<Name>.schelp`) |
| `bundle/` | The compiled Mojo graph and its engine (`libMMMAudioPluginBridge`), plus files the graph loads |
| `CMakeLists.txt`, `README.md` | The build, and its instructions |
| `build/`, `extension/` | CMake's build folder, and the finished extension |

Everything is replaced on re-export. To build it yourself, from `builds/Mojo<version>/<Name>/`:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
cmake --install build --config Release   # into Extensions/MMMAudio/, runtime included
```

Without `-DSC_PATH=...`, the configure step downloads SuperCollider's headers. To move the
project, take `shared_libraries/` along, or point `-DMMM_SHARED_LIBS=...` at it. Changes to the
Mojo graph, the GUI script or files the graph loads need a new export.

## The extension folder

```
Extensions/MMMAudio/
  Mojo1.1.0/                           every UGen built with Mojo 1.1.0
    FM4/
      FM4.scx                          the UGen (FM4.so on Linux)
      Classes/FM4.sc                   its class
      HelpSource/Classes/FM4.schelp    its help file, with an example
      ignore/                          the Mojo graph and its engine
        resources/                     files the graph loads by relative path
    shared_libraries/                  the Mojo runtime they share
      libKGENCompilerRTShared.1.1.0.dylib   ...and so on
  Mojo1.2.0.dev2026101905/             UGens built with another Mojo version
    QuadRingMod/
    shared_libraries/
```

Each UGen loads the runtime from `../shared_libraries/`, so a UGen and its
`shared_libraries` folder have to stay in the same `Mojo<version>` folder. The runtime
libraries' names carry the Mojo version (`libKGENCompilerRTShared.1.1.0.dylib` on macOS,
`libKGENCompilerRTShared.so.1.1.0` on Linux), so UGens built with different Mojo versions
can run in one server, each with its own runtime. SuperCollider skips folders named
`ignore`, so the server doesn't try to load the graph libraries as plug-ins; it only loads
`.scx` files on macOS and `.so` files on Linux, so the versioned runtime names are safe in
`shared_libraries`.

A UGen is only installed once: installing it removes any copy built with another Mojo
version, since SuperCollider can't have two classes with the same name.

## Troubleshooting

- **`<Name>: could not load the Mojo runtime library ...`** when the server boots: the
  `shared_libraries` folder isn't beside the UGen's folder. Install with `--install`, or
  copy `builds/Mojo<version>/shared_libraries/` there.
- **`<Name>: could not load ...`** (anything else): the UGen's `ignore` folder is missing or
  incomplete. Re-export, and copy the whole extension folder.
- **The UGen outputs silence and the server posts `could not build the MMMAudio graph`**:
  the graph raised an error while being built, often a file it couldn't find. Pass it with
  `--resources`.
- **A fix to the exporter doesn't seem to apply.** In a Python session that imported
  `export_sc` before you changed it, the old code is still loaded. Restart the session.
- **A UGen built on one machine won't load on another.** The Mojo libraries are native
  code, so export on each OS and CPU architecture you want to support.

## Files in this folder

| File | Role |
|---|---|
| `export_sc.py` | The exporter (command line and `export_sc()`) |
| `sc_template/` | The UGen's C++, copied into every project as `src/` |
| `SCExporter.py` | Examples |
| `struct_graphs/` | The graphs `export_struct_sc` writes to run a struct |
| `supercollider/` | SuperCollider's headers, downloaded on first use |
| `builds/` | `Mojo<version>/`: one project per exported UGen, and `shared_libraries/`, the Mojo runtime |
