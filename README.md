### MMMAudio(MMMAudioMeans Mojo) Audio 

MMMAudio is a Mojo/Python environment for sound synthesis which uses Mojo for real-time audio processing and Python as a scripting control language. It runs on Mac and Linux, including Raspberry Pi (on Ubuntu). It kind of works on Windows through wsl.

MMMAudio is a highly efficient synthesis system that uses parallelized SIMD operations for maximum efficiency on CPUs. 

Writing dsp code in Mojo is straight-forward and the feedback loop of being able to quickly compile the entire project in a few seconds to test is faster than making externals in SC/max/pd. 

## Getting Started

[See the Getting Started guide](https://spluta.github.io/MMMAudio/getting_started/).

A link to the online documentation is found here: [https://spluta.github.io/MMMAudio/](https://spluta.github.io/MMMAudio/)

See "Documentation Generation" on how to build this locally.

## Program structure

MMMAudio takes advantage of Mojo/Python interoperation compiled directly within a Python project. MMMAudio uses Mojo for all audio processing and Python as the scripting language that controls the audio engine. We take advantage of being part of the Python ecosystem, using Python libraries like numpy, scipy, pyaudio, supriya-midi, hidapi, and pythonosc to facilitate interaction with the audio engine.

MMMAudio currently runs one audio graph at a time. The audio graph is composed of Synths and the Synths are composed of UGens.

A basic program structure may look like this:
```
Graph
|
-- Synth
   |
   -- UGen
   -- UGen
   -- UGen
   Synth
   |
   -- UGen
   -- UGen
```

At the current time, the struct that represents the Graph has to conform to 3 rules:

1) It has to have a next() function with no arguments other than self.

2) It has to have the same name as the file that it is in, so the struct/Graph FeedbackDelays has to be in the file FeedbackDelays.mojo. 

3) It has to be in a Mojo package that is in the MMMAudio directory. This means it is in a folder that contains an __init__.mojo file. That file can be empty, but it has to be there.

When we create a MMMAudio instance, we need to specify the graph we are compiling and the package (folder) where it resides:

mmm_audio = MMMAudio(blocksize=128, num_input_channels=12, num_output_channels=2, in_device=in_device, out_device=out_device, graph_name="Record", package_name="examples")

This means that we are running the "Record" graph from the Record.mojo file in the examples folder. 

If there are any questions about this, look at the examples folder, which contains an empty __init__.mojo file and all of the examples conform to this pattern.

See `User Directories` below on how to make your own mojo package.

## Running Examples

For more information on running examples see [Examples Index](https://spluta.github.io/MMMAudio/examples/).
``.

## VS Code + pixi: run Python line-by-line with Shift+Enter

If you want to use [pixi](https://pixi.prefix.dev/latest/) as the environment manager and be able to press `Shift+Enter` in a `.py` file to execute the current line/selection in REPL mode, use these settings:

- In workspace `.vscode/settings.json`:
   - `python.defaultInterpreterPath`: `${workspaceFolder}/.pixi/envs/default/bin/python`
   - `python.terminal.activateEnvironment`: `false`
   - `python.REPL.sendToNativeREPL`: `false`
- In VS Code keybindings, map `shift+enter` to `python.execSelectionInTerminal` for Python editors.

## User Directories

You can make your own directory for your projects. 

It can have any name.

It must exist inside the MMMAudio directory. 

Make sure this directory contains an empty `__init__.mojo`. Otherwise, the mojo compiler we not be able to see the directory or its contents.

When loading MMMAudio in your project's python file, use the following syntax:

mmm_audio = MMMAudio(128, graph_name="MyProject", package_name="the_folder_I_made")

MMMAudio will look in the 'the_folder_I_made' directory for the necessary files to execute your script.

If you would like to contribute to MMMAudio, git will not track a user-created directory or any of the files therein.

When you pull a new version, it will not overwrite the files in your user-created directories.

## Roadmap

See the [Roadmap](https://spluta.github.io/MMMAudio/contributing/Roadmap) to see where MMMAudio is headed next.

## ICMC Paper

Check out our ICMC Paper on MMMAudio [here](https://github.com/spluta/MMMAudio/blob/main/resources/MMMAudioPaperICMC2026.pdf).

## Documentation Generation

For information on the documentation generation see [Documentation Generation](https://spluta.github.io/MMMAudio/contributing/documentation/).

## Credits

Created by Sam Pluta and Ted Moore.

This repository includes a recording of "Shiverer" by Eric Wubbels as the default sample. This was performed by Eric Wubbels and Erin Lesser and recorded by Jeff Snyder.
