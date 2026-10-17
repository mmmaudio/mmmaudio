"""A C ABI front end for the MMMAudio engine, for use inside an audio plugin (VST3, CLAP, AU...).

This is `MMMAudioBridge` without PortAudio and without Python: the plugin host
owns the audio device and calls `mmm_plugin_next` from its process callback,
and the plugin's UI/main thread sends the same messages `MMMAudio.py` sends.

The graph is loaded at runtime from its own shared library, exactly as the
Python engine does (see `mmm_audio/Graph_Module.mojo` and
`mmm_python/graph_bridge.py`, which builds `<Graph>Graph.hash-*.so`).

Build:

    mojo build PluginExporter/MMMAudioPluginBridge.mojo \\
        --emit shared-lib -o libMMMAudioPlugin.so -I .

Every exported function takes the handle returned by `mmm_plugin_new` first.
Pointers are passed as plain addresses (`intptr_t` / `void*` on the C side),
strings as NUL-terminated UTF-8, and arrays as pointer + count. See
`MMMAudioPluginBridge.h` for the C declarations.

Audio buffers are interleaved: frame `i`, channel `c` lives at
`buffer[i * num_chans + c]`. Input is `float`, output is `float`.

Threading: the `mmm_plugin_send_*` functions may be called from any thread
while audio runs. Messages are picked up at the start of the next block the
audio thread renders. `mmm_plugin_set_sample_rate` / `mmm_plugin_set_block_size`
may also be called while audio runs; `mmm_plugin_next` puts out silence for
any block it would otherwise have to wait for them.
"""

from std.atomic import Atomic
from std.ffi import c_char, c_int
from std.os import setenv
from std.memory import *
from std.sys import size_of
from std.memory.alloc import unsafe_alloc
from std.origin import MutUntrackedOrigin

from mmm_audio.constants import *
from mmm_audio.MMMWorld_Module import MMMWorld, Environment
from mmm_audio.Graph_Module import C_GraphHandle


comptime MMM_OK: c_int = 0
comptime MMM_ERROR: c_int = -1


@doc_hidden
struct SpinLock(Movable):
    """A one-word lock.

    The audio thread only ever `try_acquire`s: waiting on a lock is exactly
    what a real-time thread must not do, so it degrades instead. Everyone
    else can afford to `acquire`.
    """

    var held: Atomic[Int64]

    def __init__(out self):
        self.held = Atomic[Int64](0)

    def try_acquire(mut self) -> Bool:
        var expected: Int64 = 0
        return self.held.compare_exchange(expected, 1)

    def acquire(mut self):
        while not self.try_acquire():
            pass

    def release(mut self):
        self.held.store(0)


struct MMMAudioPluginBridge(Movable):
    """The engine state behind one plugin instance.

    It lives on the heap for its whole life, and its address is the opaque
    handle the C side holds on to.
    """

    var world: World
    var environment_ptr: Pointer[mut=True, Environment, MutUntrackedOrigin]
    var graph: C_GraphHandle
    var graph_lib: String

    # The largest number of frames the graph renders in one call. Longer
    # host buffers are rendered as several blocks; shorter ones as one.
    var block_size: Int

    # `pools` guards the message pools, `graph` the graph and the scratch
    # buffers - see `AudioState` in MMMAudioBridge.mojo for why they are apart.
    var pools: SpinLock
    var graph_lock: SpinLock

    # The graph writes float64; the host wants float32. `silent_in` stands in
    # for a null input buffer.
    var silent_in: MutPointer[Float32, MutUntrackedOrigin]
    var out_scratch: MutPointer[Float64, MutUntrackedOrigin]

    def __init__(
        out self,
        graph_lib: String,
        sample_rate: Float64,
        block_size: Int,
        num_in_chans: Int,
        num_out_chans: Int,
    ) raises:
        """Load the graph from `graph_lib` and build it at `sample_rate`.

        Args:
            graph_lib: Path to the graph's compiled shared library.
            sample_rate: The host's sample rate.
            block_size: The most frames the graph renders per call.
            num_in_chans: Number of interleaved input channels.
            num_out_chans: Number of interleaved output channels.

        Raises:
            If the block size or sample rate is invalid, or the graph can't be loaded.
        """
        if block_size < 1:
            raise Error("block_size must be at least 1")
        if sample_rate <= 0.0:
            raise Error("sample_rate must be positive")

        self.graph_lib = graph_lib
        self.block_size = block_size

        self.environment_ptr = unsafe_alloc[Environment](1)
        self.environment_ptr.unsafe_write(
            Environment(block_size, num_in_chans, num_out_chans)
        )

        self.world = unsafe_alloc[MMMWorld](1)
        self.world.unsafe_write(MMMWorld(sample_rate, self.environment_ptr))

        self.graph = C_GraphHandle(graph_lib, self.world)

        self.pools = SpinLock()
        self.graph_lock = SpinLock()

        self.silent_in = unsafe_alloc[Float32](1)
        self.out_scratch = unsafe_alloc[Float64](1)
        self._alloc_scratch()

    def __deinit__(deinit self):
        self.silent_in.unsafe_free()
        self.out_scratch.unsafe_free()
        _ = self.world.unsafe_take_pointee()
        self.world.unsafe_free()
        _ = self.environment_ptr.unsafe_take_pointee()
        self.environment_ptr.unsafe_free()

    def _alloc_scratch(mut self):
        """(Re)allocate the scratch buffers for the current block size."""
        ref env = self.environment_ptr[]
        self.silent_in.unsafe_free()
        self.out_scratch.unsafe_free()

        var in_len = max(self.block_size * env.num_in_chans, 1)
        self.silent_in = unsafe_alloc[Float32](in_len)
        unsafe_memset_zero(self.silent_in, in_len)

        self.out_scratch = unsafe_alloc[Float64](
            max(self.block_size * env.num_out_chans, 1)
        )

    # ---- configuration ---------------------------------------------------

    def set_sample_rate(mut self, sample_rate: Float64) raises:
        """Change the sample rate and rebuild the graph at it.

        Graphs size delays, buffers and coefficients from the sample rate when
        they are constructed, so the graph is built again from its library.
        Its state (phases, delay contents...) starts over, as it would when a
        host re-prepares a plugin.

        Args:
            sample_rate: The new sample rate.

        Raises:
            If the rate isn't positive or the graph can't be rebuilt.
        """
        if sample_rate <= 0.0:
            raise Error("sample_rate must be positive")
        if sample_rate == self.world[].sample_rate:
            return

        self.graph_lock.acquire()
        try:
            self.world[].sample_rate = sample_rate
            self.world[].sample_dur_seconds = 1.0 / sample_rate
            # The library exports no destructor, so the old graph object is
            # leaked; this only happens when the host changes rate.
            self.graph = C_GraphHandle(self.graph_lib, self.world)
        finally:
            self.graph_lock.release()

    def set_block_size(mut self, block_size: Int) raises:
        """Change the most frames the graph renders per call.

        Args:
            block_size: The new block size, at least 1.

        Raises:
            If `block_size` is less than 1.
        """
        if block_size < 1:
            raise Error("block_size must be at least 1")
        if block_size == self.block_size:
            return

        self.graph_lock.acquire()
        self.block_size = block_size
        self.environment_ptr[].block_size = block_size
        self._alloc_scratch()
        self.graph_lock.release()

    # ---- messages --------------------------------------------------------

    def transfer_msgs_if_free(mut self) raises:
        """Move queued messages into the graph's view, unless a sender is
        mid-write - then they arrive a block later instead of the audio thread
        waiting on it.

        Raises:
            If transferring the messages fails.
        """
        if self.pools.try_acquire():
            try:
                self.environment_ptr[].messenger_manager.transfer_msgs()
            finally:
                self.pools.release()

    # ---- audio -----------------------------------------------------------

    def process(mut self, in_addr: Int, out_addr: Int, frames: Int) raises:
        """Render `frames` frames from the interleaved float32 input at
        `in_addr` into the interleaved float32 output at `out_addr`.

        `in_addr` may be 0 for silent input. Buffers longer than `block_size`
        are rendered as consecutive blocks.

        Args:
            in_addr: Address of `frames * num_in_chans` floats, or 0.
            out_addr: Address of `frames * num_out_chans` floats.
            frames: Number of frames to render.

        Raises:
            If transferring messages fails.
        """
        if out_addr == 0 or frames <= 0:
            return

        ref env = self.environment_ptr[]
        var num_in = env.num_in_chans
        var num_out = env.num_out_chans

        var out_buffer = MutPointer[Float32, MutUntrackedOrigin](
            unsafe_from_address=out_addr
        )

        # Only reconfiguration ever holds the graph lock; silence beats
        # waiting for it on the audio thread.
        if not self.graph_lock.try_acquire():
            unsafe_memset_zero(out_buffer, frames * num_out)
            return

        try:
            var done = 0
            while done < frames:
                var n = min(self.block_size, frames - done)

                var block_in = Int(self.silent_in)
                if in_addr != 0 and num_in > 0:
                    block_in = in_addr + done * num_in * size_of[Float32]()

                self.transfer_msgs_if_free()

                # GraphBlock renders `env.block_size` frames, so a short block
                # (a host's partial buffer, or `next1`) just shortens it.
                env.block_size = n
                unsafe_memset_zero(self.out_scratch, n * num_out)
                self.graph.run_block(
                    Int(self.environment_ptr), block_in, Int(self.out_scratch)
                )

                var dst = out_buffer.unsafe_offset(done * num_out)
                for i in range(n * num_out):
                    dst[unsafe_offset=i] = Float32(self.out_scratch[unsafe_offset=i])

                done += n
        finally:
            env.block_size = self.block_size
            self.graph_lock.release()


# ---- C ABI -----------------------------------------------------------------


@always_inline
def _bridge(handle: Int) -> MutPointer[MMMAudioPluginBridge, MutUntrackedOrigin]:
    return MutPointer[MMMAudioPluginBridge, MutUntrackedOrigin](
        unsafe_from_address=handle
    )


@always_inline
def _c_string(addr: Int) -> String:
    return String(
        unsafe_from_utf8_ptr=MutPointer[c_char, MutUntrackedOrigin](
            unsafe_from_address=addr
        )
    )


@export
def mmm_plugin_new(
    graph_lib: Int,
    sample_rate: Float64,
    block_size: Int,
    num_in_chans: Int,
    num_out_chans: Int,
) abi("C") -> Int:
    """Create an engine running the graph in a compiled graph library.

    Args:
        graph_lib: Address of a C string: the graph library's path.
        sample_rate: The host's sample rate.
        block_size: The most frames rendered per graph block.
        num_in_chans: Number of interleaved input channels.
        num_out_chans: Number of interleaved output channels.

    Returns:
        The engine's handle, or 0 on failure.
    """
    if graph_lib == 0:
        return 0
    try:
        var bridge = unsafe_alloc[MMMAudioPluginBridge](1)
        bridge.unsafe_write(
            MMMAudioPluginBridge(
                _c_string(graph_lib),
                sample_rate,
                block_size,
                num_in_chans,
                num_out_chans,
            )
        )
        return Int(bridge)
    except e:
        print("mmm_plugin_new: ", e)
        return 0


@export
def mmm_plugin_set_resource_dir(path: Int) abi("C"):
    """Where relative file paths in graphs (`"resources/Shiverer.wav"`) are
    looked up when they don't exist from the working directory. Sets the
    process-wide `MMM_RESOURCE_DIR`, so call it before `mmm_plugin_new` or
    `mmm_plugin_set_sample_rate` (which build the graph).

    Args:
        path: Address of a C string: the resource folder.
    """
    if path == 0:
        return
    _ = setenv("MMM_RESOURCE_DIR", _c_string(path))


@export
def mmm_plugin_free(handle: Int) abi("C"):
    """Destroy an engine made by `mmm_plugin_new`.

    Args:
        handle: The engine.
    """
    if handle == 0:
        return
    var bridge = _bridge(handle)
    _ = bridge.unsafe_take_pointee()
    bridge.unsafe_free()


@export
def mmm_plugin_set_sample_rate(handle: Int, sample_rate: Float64) abi("C") -> c_int:
    """Set the sample rate, rebuilding the graph if it changed.

    Args:
        handle: The engine.
        sample_rate: The new sample rate.

    Returns:
        0 on success, -1 on failure.
    """
    if handle == 0:
        return MMM_ERROR
    try:
        _bridge(handle)[].set_sample_rate(sample_rate)
        return MMM_OK
    except e:
        print("mmm_plugin_set_sample_rate: ", e)
        return MMM_ERROR


@export
def mmm_plugin_set_block_size(handle: Int, block_size: Int) abi("C") -> c_int:
    """Set the most frames rendered per graph block.

    Args:
        handle: The engine.
        block_size: The new block size.

    Returns:
        0 on success, -1 on failure.
    """
    if handle == 0:
        return MMM_ERROR
    try:
        _bridge(handle)[].set_block_size(block_size)
        return MMM_OK
    except e:
        print("mmm_plugin_set_block_size: ", e)
        return MMM_ERROR


@export
def mmm_plugin_get_sample_rate(handle: Int) abi("C") -> Float64:
    if handle == 0:
        return 0.0
    return _bridge(handle)[].world[].sample_rate


@export
def mmm_plugin_get_block_size(handle: Int) abi("C") -> Int:
    if handle == 0:
        return 0
    return _bridge(handle)[].block_size


@export
def mmm_plugin_get_num_in_chans(handle: Int) abi("C") -> Int:
    if handle == 0:
        return 0
    return _bridge(handle)[].environment_ptr[].num_in_chans


@export
def mmm_plugin_get_num_out_chans(handle: Int) abi("C") -> Int:
    if handle == 0:
        return 0
    return _bridge(handle)[].environment_ptr[].num_out_chans


@export
def mmm_plugin_next(handle: Int, in_buffer: Int, out_buffer: Int, frames: Int) abi("C") -> c_int:
    """Render `frames` frames.

    Args:
        handle: The engine.
        in_buffer: Address of interleaved floats, `num_in_chans` wide (or 0).
        out_buffer: Address of interleaved floats, `num_out_chans` wide.
        frames: Number of frames.

    Returns:
        0 on success, -1 on failure.
    """
    if handle == 0:
        return MMM_ERROR
    try:
        _bridge(handle)[].process(in_buffer, out_buffer, frames)
        return MMM_OK
    except e:
        print("mmm_plugin_next: ", e)
        return MMM_ERROR


@export
def mmm_plugin_next1(handle: Int, in_frame: Int, out_frame: Int) abi("C") -> c_int:
    """Render a single frame. Messages are picked up on every call.

    Args:
        handle: The engine.
        in_frame: Address of `num_in_chans` floats (or 0).
        out_frame: Address of `num_out_chans` floats.

    Returns:
        0 on success, -1 on failure.
    """
    return mmm_plugin_next(handle, in_frame, out_frame, 1)


# ---- messages (the same set MMMAudio.py sends) ------------------------------
# Each copies its arguments, so the caller's memory may be reused on return.


@export
def mmm_plugin_send_bool(handle: Int, key: Int, value: c_int) abi("C"):
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_bool_msg(k, value != 0)
    b.pools.release()


@export
def mmm_plugin_send_bools(handle: Int, key: Int, values: Int, count: Int) abi("C"):
    """Send a list message.

    Args:
        handle: The engine.
        key: Address of a C string: the message name.
        values: Address of `count` bytes, each 0 (false) or non-zero (true).
        count: Number of values.
    """
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    var src = MutPointer[UInt8, MutUntrackedOrigin](unsafe_from_address=values)
    var vals = List[Bool](capacity=count)
    for i in range(count):
        vals.append(src[unsafe_offset=i] != 0)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_bools_msg(k, vals^)
    b.pools.release()


@export
def mmm_plugin_send_float(handle: Int, key: Int, value: Float64) abi("C"):
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_float_msg(k, value)
    b.pools.release()


@export
def mmm_plugin_send_floats(handle: Int, key: Int, values: Int, count: Int) abi("C"):
    """Send a list message.

    Args:
        handle: The engine.
        key: Address of a C string: the message name.
        values: Address of `count` doubles.
        count: Number of values.
    """
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    var src = MutPointer[Float64, MutUntrackedOrigin](unsafe_from_address=values)
    var vals = List[Float64](capacity=count)
    for i in range(count):
        vals.append(src[unsafe_offset=i])
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_floats_msg(k, vals^)
    b.pools.release()


@export
def mmm_plugin_send_int(handle: Int, key: Int, value: Int64) abi("C"):
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_int_msg(k, Int(value))
    b.pools.release()


@export
def mmm_plugin_send_ints(handle: Int, key: Int, values: Int, count: Int) abi("C"):
    """Send a list message.

    Args:
        handle: The engine.
        key: Address of a C string: the message name.
        values: Address of `count` int64s.
        count: Number of values.
    """
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    var src = MutPointer[Int64, MutUntrackedOrigin](unsafe_from_address=values)
    var vals = List[Int](capacity=count)
    for i in range(count):
        vals.append(Int(src[unsafe_offset=i]))
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_ints_msg(k, vals^)
    b.pools.release()


@export
def mmm_plugin_send_trig(handle: Int, key: Int) abi("C"):
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_trig_msg(k^)
    b.pools.release()


@export
def mmm_plugin_send_trigs(handle: Int, key: Int, values: Int, count: Int) abi("C"):
    """Send a list message.

    Args:
        handle: The engine.
        key: Address of a C string: the message name.
        values: Address of `count` bytes, each 0 (no trigger) or non-zero.
        count: Number of values.
    """
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    var src = MutPointer[UInt8, MutUntrackedOrigin](unsafe_from_address=values)
    var vals = List[Bool](capacity=count)
    for i in range(count):
        vals.append(src[unsafe_offset=i] != 0)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_trigs_msg(k, vals^)
    b.pools.release()


@export
def mmm_plugin_send_string(handle: Int, key: Int, value: Int) abi("C"):
    if handle == 0 or key == 0 or value == 0:
        return
    var k = _c_string(key)
    var v = _c_string(value)
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_string_msg(k, v)
    b.pools.release()


@export
def mmm_plugin_send_strings(handle: Int, key: Int, values: Int, count: Int) abi("C"):
    """Send a list message.

    Args:
        handle: The engine.
        key: Address of a C string: the message name.
        values: Address of `count` C string addresses (`const char* const*`).
        count: Number of values.
    """
    if handle == 0 or key == 0:
        return
    var k = _c_string(key)
    var src = MutPointer[Int, MutUntrackedOrigin](unsafe_from_address=values)
    var vals = List[String](capacity=count)
    for i in range(count):
        var addr = src[unsafe_offset=i]
        vals.append(_c_string(addr) if addr != 0 else String())
    ref b = _bridge(handle)[]
    b.pools.acquire()
    b.environment_ptr[].messenger_manager.update_strings_msg(k, vals^)
    b.pools.release()


@export
def mmm_plugin_update_mouse_pos(handle: Int, x: Float64, y: Float64) abi("C"):
    if handle == 0:
        return
    ref env = _bridge(handle)[].environment_ptr[]
    env.mouse_x = x
    env.mouse_y = y


@export
def mmm_plugin_set_screen_dims(handle: Int, width: Float64, height: Float64) abi("C"):
    if handle == 0:
        return
    # Written in place so the audio thread never sees the List reallocated.
    ref dims = _bridge(handle)[].environment_ptr[].screen_dims
    dims[0] = width
    dims[1] = height
