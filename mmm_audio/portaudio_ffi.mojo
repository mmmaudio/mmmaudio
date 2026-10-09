"""
FFI bindings for PortAudio, loaded at runtime from the libportaudio shared
library.

`pixi install` puts libportaudio in the project's environment and the loader
below finds it there, so no system-wide install is needed - but you have to be
running inside that environment (`pixi run ...` or `pixi shell`). 

The two structs below mirror the C definitions in portaudio.h field for
field. Mojo lays out a `RegisterPassable` struct of C types using the C
layout, padding included, so the offsets match what the C compiler produces:

    PaStreamParameters   device@0  channelCount@4  sampleFormat@8
                         suggestedLatency@16  hostApiSpecificStreamInfo@24
                         (32 bytes)

    PaDeviceInfo         structVersion@0  name@8  hostApi@16
                         maxInputChannels@20  maxOutputChannels@24
                         defaultLowInputLatency@32  defaultLowOutputLatency@40
                         defaultHighInputLatency@48 defaultHighOutputLatency@56
                         defaultSampleRate@64
                         (72 bytes)
"""

from std.ffi import OwnedDLHandle, c_char, c_int, c_ulong
from std.os.env import getenv
from std.origin import MutAnyOrigin, MutUntrackedOrigin
from std.os import abort
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder


# ---------------------------------------------------------------------------
# Constants from portaudio.h.
# ---------------------------------------------------------------------------
comptime PA_NO_ERROR = 0
comptime PA_NO_DEVICE = -1

comptime PA_FLOAT32 = 1  # paFloat32 = 0x00000001
comptime PA_INT16 = 8    # paInt16   = 0x00000008
comptime PA_NO_FLAG = 0

# PaStreamCallbackResult - what your callback returns.
comptime PA_CONTINUE = 0
comptime PA_COMPLETE = 1
comptime PA_ABORT = 2

# ---------------------------------------------------------------------------
# Device selection sentinels used by this module (not PortAudio's).
#
# PortAudio's own paNoDevice is -1, but that's also the natural spelling for
# "just give me the default", so these two are kept distinct.
# ---------------------------------------------------------------------------
comptime PA_DEVICE_DEFAULT = -1  # use the system default for this direction
comptime PA_DEVICE_NONE = -2     # don't open this direction at all


# ---------------------------------------------------------------------------
# Types crossing the C boundary.
# ---------------------------------------------------------------------------

# `PaStream*`. PortAudio never lets you look inside it, so this is just the
# handle's address. Keeping it an Int (rather than a Pointer) sidesteps the
# fact that a Mojo Pointer can't be null, which matters because PortAudio
# hands the stream back through a `PaStream**` out-parameter.
comptime PaStream = Int

# `const PaDeviceInfo*` as returned by Pa_GetDeviceInfo.
comptime PaDeviceInfoPtr = Pointer[PaDeviceInfo, MutUntrackedOrigin]

@fieldwise_init
struct PaStreamParameters(RegisterPassable):
    """Mirrors `PaStreamParameters` in portaudio.h - see the module docstring
    for the required field order and offsets."""

    var device: c_int
    var channel_count: c_int
    var sample_format: c_ulong
    var suggested_latency: Float64
    
    # `void *hostApiSpecificStreamInfo` - must be NULL unless you're using a
    # host-API extension. Typed as Int because a Mojo Pointer can't be null;
    # it's the same 8 bytes in the same place.
    var host_api_specific_stream_info: Int


@fieldwise_init
struct PaDeviceInfo(RegisterPassable):
    """Mirrors `PaDeviceInfo` in portaudio.h - see the module docstring for
    the required field order and offsets."""

    var struct_version: c_int
    # `const char *name`. The const doesn't affect layout; a mutable origin
    # keeps it compatible with String(unsafe_from_utf8_ptr=...).
    var name: Pointer[c_char, MutUntrackedOrigin]
    var host_api: c_int
    var max_input_channels: c_int
    var max_output_channels: c_int
    var default_low_input_latency: Float64
    var default_low_output_latency: Float64
    var default_high_input_latency: Float64
    var default_high_output_latency: Float64
    var default_sample_rate: Float64

def _load_portaudio(library_path: String) raises -> OwnedDLHandle:
    """Finds and loads libportaudio.

    The search list follows pyaudio's setup.py, which looks in
    /usr/local/lib, /usr/lib and /opt/homebrew/lib for a library named
    `portaudio`. Since we're loading at runtime rather than linking, the
    versioned SONAMEs and a bare name (letting the dynamic loader search
    DYLD_/LD_LIBRARY_PATH and the default paths) are tried too.
    """
    var candidates = List[String]()

    if library_path != "":
        candidates.append(library_path)

    var prefix = getenv("CONDA_PREFIX")
    if prefix != "":
        candidates.append(prefix + "/lib/libportaudio.dylib")
        candidates.append(prefix + "/lib/libportaudio.so.2")
        candidates.append(prefix + "/lib/libportaudio.so")
        candidates.append(prefix + "/Library/bin/portaudio.dll")

    # /usr/local/lib - Homebrew on Intel macOS, and manual installs
    candidates.append("/usr/local/lib/libportaudio.dylib")
    candidates.append("/usr/local/lib/libportaudio.2.dylib")
    candidates.append("/usr/local/lib/libportaudio.so.2")
    candidates.append("/usr/local/lib/libportaudio.so")

    # /usr/lib - distro packages
    candidates.append("/usr/lib/libportaudio.dylib")
    candidates.append("/usr/lib/libportaudio.so.2")
    candidates.append("/usr/lib/libportaudio.so")

    # /opt/homebrew/lib - Homebrew on Apple Silicon
    candidates.append("/opt/homebrew/lib/libportaudio.dylib")
    candidates.append("/opt/homebrew/lib/libportaudio.2.dylib")

    # Debian/Ubuntu multiarch
    candidates.append("/usr/lib/x86_64-linux-gnu/libportaudio.so.2")
    candidates.append("/usr/lib/aarch64-linux-gnu/libportaudio.so.2")

    # Let the dynamic loader search its own paths
    candidates.append("libportaudio.dylib")
    candidates.append("libportaudio.so.2")
    candidates.append("libportaudio.so")

    # Windows - this very much needs to be tested
    # Windows portaudio is user installed, so it is probably in Program Files
    candidates.append("portaudio.dll")
    candidates.append("libportaudio.dll")
    candidates.append("libportaudio-2.dll")

    # Common manual install locations
    candidates.append(r"C:\Program Files\PortAudio\bin\portaudio.dll")
    candidates.append(r"C:\Program Files\PortAudio\bin\libportaudio.dll")
    candidates.append(r"C:\Program Files\PortAudio\bin\libportaudio-2.dll")

    for candidate in candidates:
        try:
            return OwnedDLHandle(String(candidate))
        except:
            continue

    raise Error(
        "could not find libportaudio. MMMAudio gets it from its pixi"
        " environment, so run this with `pixi run ...` or from a `pixi shell`"
        " in the MMMAudio directory (after `pixi install`) - a uv/venv or"
        " system python will not have it. "
    )


struct PortAudio:
    """Loads libportaudio and calls into it.

    `__init__` calls Pa_Initialize; call `terminate()` when you're done.
    """

    # The handle to the loaded libportaudio. 
    var lib: OwnedDLHandle

    def __init__(out self, library_path: String = "") raises:
        """Loads libportaudio and initializes PortAudio.

        Args:
            library_path: Full path to the library. Empty means search the
                usual locations.

        Raises:
            If the library can't be found or Pa_Initialize fails.
        """
        self.lib = _load_portaudio(library_path)

        var error = Int(self.lib.call["Pa_Initialize", c_int]())
        if error != PA_NO_ERROR:
            raise Error("Pa_Initialize failed: " + self.error_text(error))

    def terminate(self) raises:
        """Pa_Terminate. Call this once you've closed your streams.

        Raises:
            If Pa_Terminate fails.
        """
        var error = Int(self.lib.call["Pa_Terminate", c_int]())
        if error != PA_NO_ERROR:
            raise Error("Pa_Terminate failed: " + self.error_text(error))

    def error_text(self, error: Int) raises -> String:
        """Human-readable text for a PaError code.

        Args:
            error: A PaError code returned by any PortAudio call.

        Returns:
            The message PortAudio gives for that code.

        Raises:
            If the call into PortAudio fails.
        """
        var message = self.lib.call[
            "Pa_GetErrorText", Pointer[c_char, MutUntrackedOrigin]
        ](c_int(error))
        return String(unsafe_from_utf8_ptr=message)

    # -- devices ------------------------------------------------------------

    def device_count(self) raises -> Int:
        """Pa_GetDeviceCount.

        Returns:
            How many devices PortAudio can see.

        Raises:
            If Pa_GetDeviceCount fails.
        """
        var count = Int(self.lib.call["Pa_GetDeviceCount", c_int]())
        if count < 0:
            raise Error("Pa_GetDeviceCount failed: " + self.error_text(count))
        return count

    def default_output_device(self) raises -> Int:
        """Pa_GetDefaultOutputDevice.

        Returns:
            The default output device's index, or PA_NO_DEVICE.

        Raises:
            If the call into PortAudio fails.
        """
        return Int(self.lib.call["Pa_GetDefaultOutputDevice", c_int]())

    def default_input_device(self) raises -> Int:
        """Pa_GetDefaultInputDevice.

        Returns:
            The default input device's index, or PA_NO_DEVICE.

        Raises:
            If the call into PortAudio fails.
        """
        return Int(self.lib.call["Pa_GetDefaultInputDevice", c_int]())

    def device_info(self, device: Int) raises -> PaDeviceInfoPtr:
        """Pa_GetDeviceInfo.

        Args:
            device: A device index below `device_count`.

        Returns:
            A pointer to PortAudio's own PaDeviceInfo for that device.

        Raises:
            If the index isn't a valid device.
        """
        var info = self.lib.call[
            "Pa_GetDeviceInfo", Optional[PaDeviceInfoPtr]
        ](c_int(device))
        if not info:
            raise Error("no such device index: " + String(device))
        return info.value()

    def device_name(self, device: Int) raises -> String:
        """The name PortAudio reports for a device.

        Args:
            device: A device index below `device_count`.

        Returns:
            The device's name.

        Raises:
            If the index isn't a valid device.
        """
        return String(unsafe_from_utf8_ptr=self.device_info(device)[].name)

    def resolve_input_device(self, device: Int) raises -> Int:
        """Turns PA_DEVICE_DEFAULT into a real index. Passes PA_DEVICE_NONE
        through untouched.

        Args:
            device: An index, PA_DEVICE_DEFAULT, or PA_DEVICE_NONE.

        Returns:
            A real device index, or PA_DEVICE_NONE.

        Raises:
            If PA_DEVICE_DEFAULT was asked for and there is no default
            input device.
        """
        if device == PA_DEVICE_NONE:
            return PA_DEVICE_NONE
        if device != PA_DEVICE_DEFAULT:
            return device

        var resolved = self.default_input_device()
        if resolved == PA_NO_DEVICE:
            raise Error("no default input device is available")
        return resolved

    def resolve_output_device(self, device: Int) raises -> Int:
        """Turns PA_DEVICE_DEFAULT into a real index. Passes PA_DEVICE_NONE
        through untouched.

        Args:
            device: An index, PA_DEVICE_DEFAULT, or PA_DEVICE_NONE.

        Returns:
            A real device index, or PA_DEVICE_NONE.

        Raises:
            If PA_DEVICE_DEFAULT was asked for and there is no default
            output device.
        """
        if device == PA_DEVICE_NONE:
            return PA_DEVICE_NONE
        if device != PA_DEVICE_DEFAULT:
            return device

        var resolved = self.default_output_device()
        if resolved == PA_NO_DEVICE:
            raise Error("no default output device is available")
        return resolved

    def _print_device(
        self, device: Int, channels: Int, is_default: Bool
    ) raises:
        var info = self.device_info(device)
        print(
            "  [",
            device,
            "] ",
            String(unsafe_from_utf8_ptr=info[].name),
            " - ",
            channels,
            " ch, ",
            info[].default_sample_rate,
            " Hz",
            "  (default)" if is_default else "",
            sep="",
        )

    def list_devices(self) raises:
        """Prints the input and output devices, with the indices
        `open_stream` expects.

        A device that does both shows up in both lists under the same index.

        Raises:
            If PortAudio can't be queried for its devices.
        """
        var count = self.device_count()
        var default_input = self.default_input_device()
        var default_output = self.default_output_device()

        print("Input devices:")
        var input_count = 0
        for device in range(count):
            var channels = Int(self.device_info(device)[].max_input_channels)
            if channels > 0:
                self._print_device(device, channels, device == default_input)
                input_count += 1
        if input_count == 0:
            print("  (none found)")

        print("Output devices:")
        var output_count = 0
        for device in range(count):
            var channels = Int(self.device_info(device)[].max_output_channels)
            if channels > 0:
                self._print_device(device, channels, device == default_output)
                output_count += 1
        if output_count == 0:
            print("  (none found)")

    # -- sample rate --------------------------------------------------------

    def stream_sample_rate(
        self, input_device: Int, output_device: Int
    ) raises -> Float64:
        """The sample rate a stream on these devices will run at.

        The rate isn't chosen by the caller - it comes from the devices
        themselves (PortAudio's `defaultSampleRate`). For a duplex stream
        both devices have to agree, otherwise there's no single rate the
        stream could run at and this raises.

        Args:
            input_device: Index, PA_DEVICE_DEFAULT, or PA_DEVICE_NONE.
            output_device: Index, PA_DEVICE_DEFAULT, or PA_DEVICE_NONE.

        Returns:
            The rate in Hz a stream on these devices will run at.

        Raises:
            If neither direction has a device, or if a duplex pair disagrees
            on its rate.
        """
        var input = self.resolve_input_device(input_device)
        var output = self.resolve_output_device(output_device)

        if input == PA_DEVICE_NONE and output == PA_DEVICE_NONE:
            raise Error("a stream needs an input device, an output device, or both")

        if input == PA_DEVICE_NONE:
            return self.device_info(output)[].default_sample_rate

        if output == PA_DEVICE_NONE:
            return self.device_info(input)[].default_sample_rate

        var input_rate = self.device_info(input)[].default_sample_rate
        var output_rate = self.device_info(output)[].default_sample_rate
        if input_rate != output_rate:
            for _ in range(5):
                print("Sample rate mismatch!")
                print("")
            raise Error(
                "input and output devices disagree on sample rate!"
            )

        return input_rate

    # -- streams ------------------------------------------------------------

    def _stream_parameters(
        self,
        device: Int,
        channels: Int,
        is_input: Bool,
        block_size: Int,
        sample_rate: Float64,
    ) raises -> PaStreamParameters:
        var info = self.device_info(device)

        var available: Int
        if is_input:
            available = Int(info[].max_input_channels)
        else:
            available = Int(info[].max_output_channels)

        if channels <= 0:
            raise Error("channel count must be at least 1")
        if channels > available:
            var direction = String("input") if is_input else String("output")
            raise Error(
                "'"
                + self.device_name(device)
                + "' supports at most "
                + String(available)
                + " "
                + direction
                + " channels, but "
                + String(channels)
                + " were requested"
            )

        # This suggests a desired latency to the device. The device may or may not be able to achieve that latency, but it will try.
        var latency = Float64(block_size) / sample_rate

        return PaStreamParameters(
            device=c_int(device),
            channel_count=c_int(channels),
            sample_format=c_ulong(PA_FLOAT32),
            suggested_latency=latency,
            host_api_specific_stream_info=0,
        )

    def open_stream[
        Callback: AnyType, //
    ](
        self,
        input_device: Int,
        output_device: Int,
        input_channels: Int,
        output_channels: Int,
        block_size: Int,
        callback: Callback,
        user_data: Int = 0,
    ) raises -> PaStream:
        """Opens a float32 stream: input, output, or both.

        The sample rate isn't a parameter - it's taken from the devices via
        `stream_sample_rate`, which raises if a duplex pair disagrees.

        Args:
            input_device: Index from `list_devices`, PA_DEVICE_DEFAULT, or
                PA_DEVICE_NONE for an output-only stream.
            output_device: Index from `list_devices`, PA_DEVICE_DEFAULT, or
                PA_DEVICE_NONE for an input-only stream.
            input_channels: Ignored when there's no input device.
            output_channels: Ignored when there's no output device.
            block_size: Frames per callback (PortAudio's framesPerBuffer).
                It's also what the stream asks the device for as its
                hardware buffer size, by way of suggestedLatency - see
                `_stream_parameters`.
            callback: A thin abi("C") function with the shape documented
                above.
            user_data: An address handed back to the callback as its
                `p_user_data` argument. 0 means NULL. A thin callback can't
                capture, so this is how it reaches the state it works on.

        Returns:
            The open stream, to hand to `start`, `stop` and `close`.

        Raises:
            If the devices can't supply the requested channels, if a duplex
            pair disagrees on its sample rate, or if Pa_OpenStream fails.
        """
        var input = self.resolve_input_device(input_device)
        var output = self.resolve_output_device(output_device)
        var sample_rate = self.stream_sample_rate(input, output)

        # PortAudio wants a NULL parameters pointer for a direction that
        # isn't in use, and a Mojo Pointer can't be null - hence one call per
        # combination, passing Int(0) for the unused side.
        var stream: PaStream = 0
        var error: Int

        if input != PA_DEVICE_NONE and output != PA_DEVICE_NONE:
            var input_parameters = self._stream_parameters(
                input, input_channels, True, block_size, sample_rate
            )
            var output_parameters = self._stream_parameters(
                output, output_channels, False, block_size, sample_rate
            )
            error = Int(
                self.lib.call["Pa_OpenStream", c_int](
                    Pointer(to=stream),
                    Pointer(to=input_parameters),
                    Pointer(to=output_parameters),
                    sample_rate,
                    c_ulong(block_size),
                    c_ulong(PA_NO_FLAG),
                    callback,
                    user_data,
                )
            )
        elif output != PA_DEVICE_NONE:
            var output_parameters = self._stream_parameters(
                output, output_channels, False, block_size, sample_rate
            )
            error = Int(
                self.lib.call["Pa_OpenStream", c_int](
                    Pointer(to=stream),
                    Int(0),  # inputParameters = NULL
                    Pointer(to=output_parameters),
                    sample_rate,
                    c_ulong(block_size),
                    c_ulong(PA_NO_FLAG),
                    callback,
                    user_data,
                )
            )
        else:
            var input_parameters = self._stream_parameters(
                input, input_channels, True, block_size, sample_rate
            )
            error = Int(
                self.lib.call["Pa_OpenStream", c_int](
                    Pointer(to=stream),
                    Pointer(to=input_parameters),
                    Int(0),  # outputParameters = NULL
                    sample_rate,
                    c_ulong(block_size),
                    c_ulong(PA_NO_FLAG),
                    callback,
                    user_data,
                )
            )

        if error != PA_NO_ERROR:
            raise Error("Pa_OpenStream failed: " + self.error_text(error))
        if stream == 0:
            raise Error("Pa_OpenStream returned no stream")

        return stream

    def open_output_stream[
        Callback: AnyType, //
    ](
        self,
        device: Int,
        channels: Int,
        block_size: Int,
        callback: Callback,
        user_data: Int = 0,
    ) raises -> PaStream:
        """Convenience wrapper: an output-only stream.

        Args:
            device: Index from `list_devices`, or PA_DEVICE_DEFAULT.
            channels: Output channels to open.
            block_size: Frames per callback.
            callback: A thin abi("C") function with the shape documented above.
            user_data: An address handed back to the callback.

        Returns:
            The open stream.

        Raises:
            If the stream can't be opened.
        """
        return self.open_stream(
            PA_DEVICE_NONE, device, 0, channels, block_size, callback, user_data
        )

    def open_input_stream[
        Callback: AnyType, //
    ](
        self,
        device: Int,
        channels: Int,
        block_size: Int,
        callback: Callback,
        user_data: Int = 0,
    ) raises -> PaStream:
        """Convenience wrapper: an input-only stream.

        Args:
            device: Index from `list_devices`, or PA_DEVICE_DEFAULT.
            channels: Input channels to open.
            block_size: Frames per callback.
            callback: A thin abi("C") function with the shape documented above.
            user_data: An address handed back to the callback.

        Returns:
            The open stream.

        Raises:
            If the stream can't be opened.
        """
        return self.open_stream(
            device, PA_DEVICE_NONE, channels, 0, block_size, callback, user_data
        )

    def start(self, stream: PaStream) raises:
        """Starts the stream; the callback begins firing.

        Args:
            stream: A stream from `open_stream`.

        Raises:
            If Pa_StartStream fails.
        """
        var error = Int(self.lib.call["Pa_StartStream", c_int](stream))
        if error != PA_NO_ERROR:
            raise Error("Pa_StartStream failed: " + self.error_text(error))

    def stop(self, stream: PaStream) raises:
        """Stops the stream, waiting for buffered audio to play out.

        Args:
            stream: A stream from `open_stream`.

        Raises:
            If Pa_StopStream fails.
        """
        var error = Int(self.lib.call["Pa_StopStream", c_int](stream))
        if error != PA_NO_ERROR:
            raise Error("Pa_StopStream failed: " + self.error_text(error))

    def close(self, stream: PaStream) raises:
        """Closes the stream and frees its resources.

        Args:
            stream: A stream from `open_stream`.

        Raises:
            If Pa_CloseStream fails.
        """
        var error = Int(self.lib.call["Pa_CloseStream", c_int](stream))
        if error != PA_NO_ERROR:
            raise Error("Pa_CloseStream failed: " + self.error_text(error))

    def is_stream_active(self, stream: PaStream) raises -> Bool:
        """True while the stream is playing or recording.

        Handy as the condition of a "run until stopped" loop - and using
        `self` each time round the loop is what keeps this PortAudio handle
        alive for as long as the audio thread needs it. See the note in
        noise_portaudio.mojo.

        Args:
            stream: A stream from `open_stream`.

        Returns:
            True while the stream is playing or recording.

        Raises:
            If Pa_IsStreamActive fails.
        """
        var result = Int(self.lib.call["Pa_IsStreamActive", c_int](stream))
        if result < 0:
            raise Error("Pa_IsStreamActive failed: " + self.error_text(result))
        return result == 1

def list_audio_devices() raises -> PythonObject:
    """Prints the available input and output audio devices.

    Initializes PortAudio, prints both lists, and terminates it again, so
    it's self-contained - call it any time from Python.

    Returns:
        Python's None.

    Raises:
        If PortAudio can't be loaded or queried.
    """
    var portaudio = PortAudio()
    portaudio.list_devices()
    portaudio.terminate()
    return Python.none()


def get_audio_devices() raises -> PythonObject:
    """The audio devices PortAudio can see, as a pair of Python dicts.

    Both dicts map a device index - the same index `open_stream` takes - to
    `[name, max_channels, sample_rate]`. A device that does both input and
    output appears in both under the same index.

    Initializes PortAudio and terminates it again, so it's self-contained -
    call it any time from Python.

    Returns:
        A `(in_devices, out_devices)` tuple of dicts.

    Raises:
        If PortAudio can't be loaded or queried.
    """
    var portaudio = PortAudio()
    var in_devices = Python.dict()
    var out_devices = Python.dict()

    for device in range(portaudio.device_count()):
        var info = portaudio.device_info(device)
        var name = String(unsafe_from_utf8_ptr=info[].name)
        var max_in = Int(info[].max_input_channels)
        var max_out = Int(info[].max_output_channels)
        var rate = info[].default_sample_rate

        if max_in > 0:
            in_devices[device] = Python.list(name, max_in, rate)
        if max_out > 0:
            out_devices[device] = Python.list(name, max_out, rate)

    portaudio.terminate()
    return Python.tuple(in_devices, out_devices)


@export
def PyInit_portaudio_ffi() abi("C") -> PythonObject:
    """These are the functions that Mojo exposes to Python.

    Returns:
        The built module.
    """
    try:
        var module = PythonModuleBuilder("portaudio_ffi")
        module.def_function[list_audio_devices](
            "list_audio_devices",
            docstring="Print the available input and output audio devices.",
        )
        module.def_function[get_audio_devices](
            "get_audio_devices",
            docstring=(
                "Return (in_devices, out_devices), each a dict mapping device"
                " index to [name, max_channels, sample_rate]."
            ),
        )
        return module.finalize()
    except error:
        abort(
            String("error creating Python module 'portaudio_ffi': ", error)
        )
