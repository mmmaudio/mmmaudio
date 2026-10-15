# This file is used to compile an audio graphinto its own shared library (in the 
# `mmm_python/graph_bridge.py`). It is then loaded by the prebuilt audio engine. 
# The library exports these two C functions:
#
#   mmm_graph_new(world_addr) -> graph_addr
#   mmm_graph_block(graph_addr, env_addr, in_addr, out_addr)
#
# `in_addr` is interleaved float32 input, `out_addr` interleaved float64 output,
# both `block_size` frames long.

from std.ffi import OwnedDLHandle
from std.origin import MutUntrackedOrigin

from mmm_audio.constants import *
from mmm_audio.MMMWorld_Module import Environment

# these are both standard C function declarations, with different arguments and return types. 
comptime GraphNewFn = def(Int) abi("C") thin -> Int #the function signature graph creation function
comptime GraphBlockDef = def(Int, Int, Int, Int) abi("C") thin -> None #the function signature for the graph block processing function

@doc_hidden
def _c_function_lookup[T: ImplicitlyCopyable](dy_lib: OwnedDLHandle, func_name: String) raises -> T:
    """Look up `func_name` in `dy_lib` as a C function of type `T`. This will return one of the two functions defined above.
    
    Parameters:
        T: The type of the C function to look up. Must be a function type with `abi("C")` and `thin`.

    Args:
        dy_lib: The shared library to look up the function in.
        func_name: The name of the function to look up.

    Returns:
        A callable of type `T` that calls the C function.
    """
    var symbol = dy_lib.get_symbol[NoneType](func_name)
    if not symbol:
        raise Error("missing symbol " + func_name)
    var address = Int(symbol.value())
    return Pointer(to=address).unsafe_bitcast[T]()[]


struct C_GraphHandle(Movable):
    """The audio engine's handle on the compiled dynamic library made by compiling the audio graph."""

    var dy_lib: OwnedDLHandle
    var graph_addr: Int
    var block_fn: GraphBlockDef

    def __init__(out self, path: String, world: World) raises:
        self.dy_lib = OwnedDLHandle(path)
        print(path)
        # get the two C functions we need from the library
        var new_fn = _c_function_lookup[GraphNewFn](self.dy_lib, "mmm_graph_new")
        self.block_fn = _c_function_lookup[GraphBlockDef](self.dy_lib, "mmm_graph_block")
        self.graph_addr = new_fn(Int(world))
        if self.graph_addr == 0:
            raise Error("could not create the graph in " + path)

    @always_inline
    def run_block(self, env_addr: Int, in_addr: Int, out_addr: Int):
        self.block_fn(self.graph_addr, env_addr, in_addr, out_addr)


struct GraphBlock:
    """Per-sample bookkeeping for one audio block, used inside a graph library.

    The generated `mmm_graph_block` does the following for each frame of the block:
    1. calls `process_single_sample(i)` to get the next input sample from the input buffer
    2. calls the graph's `next()` function
    3. calls `write(i, samples)` to write the output sample to the output buffer for each frame of the block.
    """

    var environment: MutPointer[Environment, MutUntrackedOrigin]
    var in_buf: MutPointer[Float32, MutUntrackedOrigin]
    var out_buf: MutPointer[Float64, MutUntrackedOrigin]
    var block_size: Int
    var num_in_chans: Int
    var num_out_chans: Int

    def __init__(out self, env_addr: Int, in_buf_addr: Int, out_buf_addr: Int):
        """Create the GraphBlock.

        Args:
            env_addr: Address of the World's Environment.
            in_buf_addr: Address of the input audio buffer.
            out_buf_addr: Address of the output audio buffer.
        """

        self.environment = MutPointer[Environment, MutUntrackedOrigin](unsafe_from_address=env_addr)
        self.in_buf = MutPointer[Float32, MutUntrackedOrigin](unsafe_from_address=in_buf_addr)
        self.out_buf = MutPointer[Float64, MutUntrackedOrigin](unsafe_from_address=out_buf_addr)
        self.block_size = self.environment[].block_size
        self.num_in_chans = self.environment[].num_in_chans
        self.num_out_chans = self.environment[].num_out_chans
        self.environment[].top_of_block = True

    @always_inline
    def process_single_sample(mut self, i: Int, mut env: Environment):
        env.block_state = i
        env.sample_count += 1

        if env.top_of_block:
            env.print_counter += 1

        # fill the sound_in list with the current sample from all inputs
        var in_offset = i * self.num_in_chans
        for j in range(self.num_in_chans):
            env.sound_in[j] = Float64(self.in_buf[unsafe_offset=in_offset + j])

    @always_inline
    def clear_messages(mut self, i: Int, mut env: Environment):
        if i == 0:
            env.messenger_manager.empty_msg_dicts()
        elif i == 1:
            env.top_of_block = False
            
    @always_inline
    def write_to_outbuf[N: SIMDLength](mut self, i: Int, samples: MFloat[N]):
        var out_offset = i * self.num_out_chans
        for j in range(min(self.num_out_chans, N)):
            self.out_buf[unsafe_offset=out_offset + j] = samples[j]
