# you should not edit this file
# i don't want it to be in this directory, but it needs to be here due to a mojo compiler bug

from std.atomic import Atomic
from std.ffi import c_int, c_ulong
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder

from std.os import abort
from std.memory import *
from std.memory.alloc import unsafe_alloc
from std.origin import MutAnyOrigin, MutUntrackedOrigin
from std.sys import simd_width_of

from mmm_audio.constants import *
from mmm_audio.MMMWorld_Module import MMMWorld, Environment
from mmm_audio.portaudio_ffi import (
    PortAudio,
    PaStream,
    PA_CONTINUE,
    PA_DEVICE_DEFAULT,
    PA_DEVICE_NONE,
)
from examples.Grains import Grains

# this is needed to make the module importable in Python - so simple!
@doc_hidden
@export
def PyInit_GrainsBridge() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("GrainsBridge")

        # var person_type = mb.add_type[Person]("Person")
        _ = m.add_type[MMMAudioBridge]("MMMAudioBridge").def_py_init[MMMAudioBridge.py_init]()
            .def_method[MMMAudioBridge.next]("next")
            .def_method[MMMAudioBridge.get_config]("get_config")
            .def_method[MMMAudioBridge.open_audio_stream]("open_audio_stream")
            .def_method[MMMAudioBridge.close_audio_stream]("close_audio_stream")
            .def_method[MMMAudioBridge.start_audio]("start_audio")
            .def_method[MMMAudioBridge.stop_audio]("stop_audio")
            .def_method[MMMAudioBridge.set_screen_dims]("set_screen_dims")
            .def_method[MMMAudioBridge.update_mouse_pos]("update_mouse_pos")
            .def_method[MMMAudioBridge.update_bool_msg]("update_bool_msg")
            .def_method[MMMAudioBridge.update_bools_msg]("update_bools_msg")
            .def_method[MMMAudioBridge.update_float_msg]("update_float_msg")
            .def_method[MMMAudioBridge.update_floats_msg]("update_floats_msg")
            .def_method[MMMAudioBridge.update_int_msg]("update_int_msg")
            .def_method[MMMAudioBridge.update_ints_msg]("update_ints_msg")
            .def_method[MMMAudioBridge.update_trig_msg]("update_trig_msg")
            .def_method[MMMAudioBridge.update_trigs_msg]("update_trigs_msg")
            .def_method[MMMAudioBridge.update_string_msg]("update_string_msg")
            .def_method[MMMAudioBridge.update_strings_msg]("update_strings_msg")

        return m.finalize()
    except e:
        _ = Error(String("error creating Python Mojo module: " + String(e)))
        abort()


@doc_hidden
def find_audio_device(
    portaudio: PortAudio, name: String, want_input: Bool
) raises -> Int:
    """Turns a device name into the index `open_stream` wants.

    An empty name means "don't open this direction" and "default" means "let
    PortAudio pick". Anything else matches the first device whose name
    contains it, falling back to the default if nothing matches - the same
    substring match the Python side used to do.
    """
    if name == "":
        return PA_DEVICE_NONE
    if name == "default":
        return PA_DEVICE_DEFAULT

    for device in range(portaudio.device_count()):
        var info = portaudio.device_info(device)
        var channels: Int
        if want_input:
            channels = Int(info[].max_input_channels)
        else:
            channels = Int(info[].max_output_channels)
        if channels > 0 and name in String(unsafe_from_utf8_ptr=info[].name):
            return device

    print("Device '", name, "' not found, using default", sep="")
    return PA_DEVICE_DEFAULT


@doc_hidden
struct SpinLock(Movable):
    """A one-word lock.

    The audio thread only ever `try_acquire`s: waiting on a lock is exactly
    what a real-time thread must not do, so it degrades instead. Everyone
    else can afford to `acquire`.
    """

    var held: Atomic[DType.int64]

    def __init__(out self):
        self.held = Atomic[DType.int64](0)

    def try_acquire(mut self) -> Bool:
        var expected: Int64 = 0
        return self.held.compare_exchange(expected, 1)

    def acquire(mut self):
        while not self.try_acquire():
            pass

    def release(mut self):
        self.held.store(0)


@doc_hidden
struct AudioState(Movable):
    """The handshake between PortAudio's thread and the Python-facing methods.

    The callback reaches the bridge through a raw address, entirely outside
    Mojo's ownership tracking and without holding the GIL, so everything both
    sides touch has to go through these atomics.

    The two locks are kept apart so the audio thread never has to wait for
    either. `pools` is held for a Dict write at a time, so missing it costs
    one block of message latency. `graph` is only ever held by offline
    rendering, so missing it means `next` is running and a block of silence
    is the right answer.
    """

    var active: Atomic[DType.int64]
    var pools: SpinLock
    var graph: SpinLock

    def __init__(out self):
        self.active = Atomic[DType.int64](0)
        self.pools = SpinLock()
        self.graph = SpinLock()


@doc_hidden
def audio_callback(
    p_input: Int,
    p_output: Int,
    frame_count: c_ulong,
    p_time_info: Int,
    status_flags: c_ulong,
    p_user_data: Int,
) abi("C") -> c_int:
    """PortAudio's stream callback, running on its real-time thread.

    `p_user_data` is the address of the `MMMAudioBridge` living inside the
    Python object - see `open_audio_stream`. Being a thin `abi("C")` function
    it can't capture and it can't raise, so the address is the only way in and
    an error can only be printed.
    """
    if p_user_data == 0:
        return c_int(PA_CONTINUE)

    var bridge = MutPointer[MMMAudioBridge, MutAnyOrigin](
        unsafe_from_address=p_user_data
    )
    try:
        bridge[].fill_output_buffer(p_input, p_output, Int(frame_count))
    except error:
        print("Error in audio callback: ", error)

    return c_int(PA_CONTINUE)


@doc_hidden
@fieldwise_init
struct MMMAudioBridge(Movable, Writable):
    var world: World
    var graph: Grains
    var environment_ptr: Pointer[mut=True, Environment, MutUntrackedOrigin]

    var portaudio_ptr: Pointer[mut=True, PortAudio, MutUntrackedOrigin]
    var audio_state_ptr: Pointer[mut=True, AudioState, MutUntrackedOrigin]

    # PortAudio hands the audio thread interleaved float32; the graph writes
    # float64. These two scratch buffers bridge the gap once per block, and
    # `silent_in` doubles as the input for an output-only stream.
    var silent_in: MutPointer[Float32, MutUntrackedOrigin]
    var out_scratch: MutPointer[Float64, MutUntrackedOrigin]

    var input_device: Int
    var output_device: Int
    var in_device_name: String
    var out_device_name: String
    var stream: PaStream  # 0 until open_audio_stream is called

    # Lanes per step of the float64 -> float32 clip on the way out.
    comptime simd_width = simd_width_of[DType.float64]() * 4

    @staticmethod
    def py_init(out self: MMMAudioBridge, args: PythonObject, kwargs: PythonObject) raises:

        var args_dict = args[0]

        var block_size = Int(py=args_dict["block_size"])
        var num_in_chans = Int(py=args_dict["num_in_chans"])
        var num_out_chans = Int(py=args_dict["num_out_chans"])
        var in_device = String(args_dict["in_device"])
        var out_device = String(args_dict["out_device"])

        self = Self(block_size, num_in_chans, num_out_chans, in_device, out_device)

    def __init__(out self, block_size: Int = 512, num_in_chans: Int = 12, num_out_chans: Int = 12, in_device: String = "default", out_device: String = "default") raises:
        """Initialize the audio engine with block size, channel counts and devices.

        The sample rate isn't a parameter: it comes from the devices
        themselves, and the requested channel counts are clamped to what the
        devices actually have. Pass an empty device name to leave that
        direction closed.
        """

        self.portaudio_ptr = unsafe_alloc[PortAudio](1)
        self.portaudio_ptr.unsafe_write(PortAudio())
        ref portaudio = self.portaudio_ptr[]

        self.input_device = portaudio.resolve_input_device(
            find_audio_device(portaudio, in_device, True)
        )
        self.output_device = portaudio.resolve_output_device(
            find_audio_device(portaudio, out_device, False)
        )

        var in_chans = 0
        self.in_device_name = String("None")
        if self.input_device != PA_DEVICE_NONE:
            var info = portaudio.device_info(self.input_device)
            in_chans = min(num_in_chans, Int(info[].max_input_channels))
            self.in_device_name = String(unsafe_from_utf8_ptr=info[].name)

        var out_chans = 0
        self.out_device_name = String("None")
        if self.output_device != PA_DEVICE_NONE:
            var info = portaudio.device_info(self.output_device)
            out_chans = min(num_out_chans, Int(info[].max_output_channels))
            self.out_device_name = String(unsafe_from_utf8_ptr=info[].name)

        # With no device at all there's no stream to run and no rate to take
        # one from, but the graph can still be rendered offline via `next`.
        var sample_rate: Float64 = 48000.0
        if self.input_device != PA_DEVICE_NONE or self.output_device != PA_DEVICE_NONE:
            sample_rate = portaudio.stream_sample_rate(
                self.input_device, self.output_device
            )

        self.environment_ptr = unsafe_alloc[Environment](1)
        self.environment_ptr.unsafe_write(Environment(block_size, in_chans, out_chans))

        self.world = unsafe_alloc[MMMWorld](1)
        self.world.unsafe_write(MMMWorld(sample_rate, self.environment_ptr))

        self.graph = Grains(self.world)

        self.audio_state_ptr = unsafe_alloc[AudioState](1)
        self.audio_state_ptr.unsafe_write(AudioState())

        self.silent_in = unsafe_alloc[Float32](max(block_size * in_chans, 1))
        for i in range(block_size * in_chans):
            self.silent_in[unsafe_offset=i] = 0.0

        self.out_scratch = unsafe_alloc[Float64](max(block_size * out_chans, 1))

        self.stream = 0

    def write_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.environment_ptr[].block_size)

    def write_repr_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.environment_ptr[].block_size)

    @staticmethod
    def get_config(py_selfA: PythonObject) raises -> PythonObject:
        """What the devices settled on, for the Python side to report."""
        var py_self = py_selfA.downcast_value_ptr[Self]()

        var config = Python.dict()
        config["sample_rate"] = py_self[].world[].sample_rate
        config["block_size"] = py_self[].environment_ptr[].block_size
        config["num_in_chans"] = py_self[].environment_ptr[].num_in_chans
        config["num_out_chans"] = py_self[].environment_ptr[].num_out_chans
        config["in_device"] = py_self[].in_device_name
        config["out_device"] = py_self[].out_device_name

        return config

    @staticmethod
    def open_audio_stream(py_selfA: PythonObject) raises -> PythonObject:
        """Open the PortAudio stream and let its callback start firing.

        The callback runs the graph only once `start_audio` has been called;
        until then it just writes silence, which is how the stream can stay
        open across start/stop without reopening the device.

        The bridge's address is handed to PortAudio as the callback's user
        data. It's taken from the Python object, which is where the bridge
        lives for good once `py_init` has moved it there.
        """
        var py_self = py_selfA.downcast_value_ptr[Self]()

        if py_self[].stream != 0:
            return PythonObject(None)
        if py_self[].output_device == PA_DEVICE_NONE and py_self[].input_device == PA_DEVICE_NONE:
            return PythonObject(None)

        ref env = py_self[].environment_ptr[]
        py_self[].stream = py_self[].portaudio_ptr[].open_stream(
            py_self[].input_device,
            py_self[].output_device,
            env.num_in_chans,
            env.num_out_chans,
            env.block_size,
            audio_callback,
            Int(py_self),
        )
        py_self[].portaudio_ptr[].start(py_self[].stream)

        return PythonObject(None)

    @staticmethod
    def close_audio_stream(py_selfA: PythonObject) raises -> PythonObject:
        """Stop the graph, then stop and close the stream."""
        var py_self = py_selfA.downcast_value_ptr[Self]()

        py_self[].audio_state_ptr[].active.store(0)
        if py_self[].stream != 0:
            py_self[].portaudio_ptr[].stop(py_self[].stream)
            py_self[].portaudio_ptr[].close(py_self[].stream)
            py_self[].stream = 0

        return PythonObject(None)

    @staticmethod
    def start_audio(py_selfA: PythonObject) raises -> PythonObject:
        """Start running the graph in the open stream's callback."""
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].audio_state_ptr[].active.store(1)

        return PythonObject(None)

    @staticmethod
    def stop_audio(py_selfA: PythonObject) raises -> PythonObject:
        """Go back to writing silence, leaving the stream open."""
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].audio_state_ptr[].active.store(0)

        return PythonObject(None)

    @staticmethod
    def set_screen_dims(py_selfA: PythonObject, dims: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].environment_ptr[].screen_dims = [Float64(py=dims[0]), Float64(py=dims[1])]  # Set the screen size in the MMMWorld instance

        return PythonObject(None)

    @staticmethod
    def update_mouse_pos(py_selfA: PythonObject, pos: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].environment_ptr[].mouse_x = Float64(py=pos[0])
        py_self[].environment_ptr[].mouse_y = Float64(py=pos[1])

        return PythonObject(None)

    @staticmethod
    def to_float64(py_float: PythonObject) raises -> Float64:
        return Float64(py=py_float)

    @staticmethod
    def update_bool_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_bool_msg(String(key_vals[0]), Bool(key_vals[1]))
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_bools_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        var key = String(key_vals[0])
        var values = [Bool(b) for b in key_vals[1:]]

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_bools_msg(key, values^)
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_float_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_float_msg(String(key_vals[0]), Float64(py=key_vals[1]))
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_floats_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        var key = String(key_vals[0])
        var values = [Float64(py=f) for f in key_vals[1:]]

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_floats_msg(key, values^)
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_int_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_int_msg(String(key_vals[0]), Int(py=key_vals[1]))
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_ints_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        var key = String(key_vals[0])
        var values = [Int(py=v) for v in key_vals[1:]]

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_ints_msg(key, values^)
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_trig_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_trig_msg(String(key_vals[0]))
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_trigs_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        var key = String(key_vals[0])
        var values = [Bool(b) for b in key_vals[1:]]

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_trigs_msg(key, values^)
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_string_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_string_msg(String(key_vals[0]), String(key_vals[1]))
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    @staticmethod
    def update_strings_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        var key = String(key_vals[0])
        var texts = [String(s) for s in key_vals[1:]]

        py_self[].audio_state_ptr[].pools.acquire()
        try:
            py_self[].environment_ptr[].messenger_manager.update_strings_msg(key, texts^)
        finally:
            py_self[].audio_state_ptr[].pools.release()

        return PythonObject(None)

    def get_audio_samples(mut self, loc_in_buffer: MutPointer[Float32, ...], mut loc_out_buffer: MutPointer[Float64, ...]) raises:
        # making this a reference is very efficient
        ref env = self.environment_ptr[]
        var block_size = env.block_size
        var num_in = env.num_in_chans
        var num_out = env.num_out_chans

        env.top_of_block = True

        for i in range(block_size):
            env.block_state = i  # Update the block state

            if i == 1:
                env.top_of_block = False
                env.messenger_manager.empty_msg_dicts()

            if env.top_of_block:
                env.print_counter += 1
            # fill the sound_in list with the current sample from all inputs
            var in_offset = i * num_in
            for j in range(num_in):
                env.sound_in[j] = Float64(loc_in_buffer[unsafe_offset=in_offset + j])

            var samples = self.graph.next()  # Get the next audio samples from the graph

            # Fill the wire buffer with the sample data
            var out_offset = i * num_out
            for j in range(min(num_out, samples.__len__())):
                loc_out_buffer[unsafe_offset=out_offset + j] = samples[Int(j)]

    def transfer_msgs_if_free(mut self) raises:
        """Drain whatever Python has queued into the message pools.

        If Python is mid-write the pools are left alone and their messages
        arrive a block later. Waiting here would put someone else's Dict
        insert on the audio thread's critical path, which is the one thing it
        can't afford.
        """
        if self.audio_state_ptr[].pools.try_acquire():
            try:
                self.environment_ptr[].messenger_manager.transfer_msgs()
            finally:
                self.audio_state_ptr[].pools.release()

    def fill_output_buffer(mut self, p_input: Int, p_output: Int, frames: Int) raises:
        """Run one block of the graph into PortAudio's output buffer.

        Both PortAudio buffers are interleaved float32 while the graph works
        in float64, so the block goes through `out_scratch` and is clipped and
        narrowed on the way out - the clip the Python callback used to apply
        with numpy, done in one SIMD pass instead of three array allocations.
        """
        ref env = self.environment_ptr[]
        var num_out = env.num_out_chans
        var block_size = env.block_size

        if p_output == 0 or num_out == 0:
            return

        var out_buffer = MutPointer[Float32, MutUntrackedOrigin](
            unsafe_from_address=p_output
        )

        if self.audio_state_ptr[].active.load() == 0:
            unsafe_memset_zero(out_buffer, frames * num_out)
            return

        self.transfer_msgs_if_free()

        # Only offline rendering ever holds the graph lock, so failing to take
        # it means `next` is running right now; a block of silence beats
        # either racing it or spinning here until it's done.
        if not self.audio_state_ptr[].graph.try_acquire():
            unsafe_memset_zero(out_buffer, frames * num_out)
            return

        # PortAudio honors framesPerBuffer, so `frames` should be the block size
        var frames_to_render = min(frames, block_size)

        var in_buffer = MutPointer[Float32, MutUntrackedOrigin](
            unsafe_from_address=Int(self.silent_in)
        )
        if p_input != 0 and env.num_in_chans > 0 and frames >= block_size:
            in_buffer = MutPointer[Float32, MutUntrackedOrigin](
                unsafe_from_address=p_input
            )

        var scratch = self.out_scratch
        try:
            unsafe_memset_zero(scratch, block_size * num_out)
            self.get_audio_samples(in_buffer, scratch)
        finally:
            self.audio_state_ptr[].graph.release()

        var rendered = frames_to_render * num_out
        var i = 0
        while i + Self.simd_width <= rendered:
            out_buffer.unsafe_store(
                i,
                scratch.unsafe_load[width = Self.simd_width](i)
                .clamp(-1.0, 1.0)
                .cast[DType.float32](),
            )
            i += Self.simd_width
        while i < rendered:
            out_buffer[unsafe_offset=i] = Float32(
                scratch[unsafe_offset=i].clamp(-1.0, 1.0)
            )
            i += 1

        if rendered < frames * num_out:
            unsafe_memset_zero(
                out_buffer.unsafe_offset(rendered),
                frames * num_out - rendered,
            )

    @staticmethod
    def next(py_selfA: PythonObject, in_buffer: PythonObject, out_buffer: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        var loc_in_buffer = in_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float32]()

        var loc_out_buffer = out_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float64]()

        unsafe_memset_zero(
            loc_out_buffer,
            py_self[].environment_ptr[].block_size
            * py_self[].environment_ptr[].num_out_chans,
        )

        # Held for the whole render, which is what keeps the audio thread from
        # rendering the same graph at the same time - it sees the lock taken
        # and puts out silence instead.
        py_self[].audio_state_ptr[].graph.acquire()
        try:
            py_self[].audio_state_ptr[].pools.acquire()
            try:
                py_self[].environment_ptr[].messenger_manager.transfer_msgs()
            finally:
                py_self[].audio_state_ptr[].pools.release()

            py_self[unsafe_offset=0].get_audio_samples(loc_in_buffer, loc_out_buffer)
        finally:
            py_self[].audio_state_ptr[].graph.release()

        return PythonObject(None)
