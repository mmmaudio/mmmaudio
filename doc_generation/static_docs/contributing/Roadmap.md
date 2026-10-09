# MMMAudio Roadmap

## 1. Mojo 1.0

MMMAudio is currently aligned with Mojo 1.0. We are going to keep the syntax as stable as we can for the foreseeable future and will only update to new versions of Mojo if it keeps the syntax relatively stable.

## 2. GPU-based dsp

Mojo is designed for GPU and it works on Apple Silicon GPUs. This should allow us to integrate GPU-based dsp, like FFTs, into the codebase.

## 3. Faster Compile Time

Compile time is a bit slow right now. Part of this is that the Mojo compiler doesn't seem to parallelize compilation in Python, and we imagine this will change. Packages also can't be compiled, so everything is compiled each time a graph is compiled. Hopefully there are improvements to this in the coming year.

## 4. Mojo-side I/O Bindings

The audio loop now runs entirely on the Mojo side, on PortAudio's own callback thread, through the FFI bindings in `mmm_audio/portaudio_ffi.mojo`.

## 5. Mojo -> Python Messaging

Currently we have a robust messaging system to send messages from Python to Mojo, but not the other way around. We need to implement this.

## 6. DAW Plugin DSP

Mojo’s Foreign Function Interface (FFI) allows Mojo programs to export functions using a standard ``C'' abi, and this should allow us to export a MMMAudio graph as a Linux shared object file or a Mac dynamic library, ready to expose its messaging api to JUCE, iPlug, or other environment. The MMMAudio Python environment will be able to serve as a testing ground for DSP. Then, when the processing code is ready, it can be compiled and folded into an audio plugin to be used in any DAW or stand-alone system.