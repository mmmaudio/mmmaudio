# you should not edit this file
# i don't want it to be in this directory, but it needs to be here due to a mojo compiler bug

from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from std.os import abort
from std.memory import *

from mmm_audio import *
from examples.Grains import Grains

# this is needed to make the module importable in Python - so simple!
@doc_hidden
@export
def PyInit_GrainsBridge() -> PythonObject:
    try:
        var m = PythonModuleBuilder("GrainsBridge")

        # var person_type = mb.add_type[Person]("Person")
        _ = m.add_type[MMMAudioBridge]("MMMAudioBridge").def_py_init[MMMAudioBridge.py_init]()
            .def_method[MMMAudioBridge.next]("next")
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
            .def_method[MMMAudioBridge.set_channel_count]("set_channel_count")  

        return m.finalize()
    except e:
        _ = Error(String("error creating Python Mojo module: " + String(e)))
        abort()


@fieldwise_init
struct MMMAudioBridge(Movable, Writable):
    var world: World
    var graph: Grains  # The audio graph instance
    var osc_buffers: Optional[UnsafePointer[mut=True, OscBuffers, MutExternalOrigin]] 
    var windows: Optional[UnsafePointer[mut=True, Windows, MutExternalOrigin]]
    var messenger_manager: Optional[UnsafePointer[mut=True, MessengerManager, MutExternalOrigin]] 

    # def(args: PythonObject, kwargs: PythonObject) raises -> MMMAudioBridge
    @staticmethod
    def py_init(out self: MMMAudioBridge, args: PythonObject, kwargs: PythonObject) raises:

        var sample_rate = Float64(py=args[0])
        var block_size: Int = Int(py=args[1])

        var num_out_chans: Int = 2
        var num_in_chans: Int = 2

        # right now if you try to read args[3], shit gets really weird

        self = Self(sample_rate, block_size, num_in_chans, num_out_chans)  # Initialize with sample rate, block size, and number of channels

    def __init__(out self, sample_rate: Float64 = 44100.0, block_size: Int = 512, num_in_chans: Int = 12, num_out_chans: Int = 12):
        """Initialize the audio engine with sample rate, block size, and number of channels."""

        self.osc_buffers = alloc[OscBuffers](1)
        self.osc_buffers.value().init_pointee_move(OscBuffers())
        self.windows = alloc[Windows](1)
        self.windows.value().init_pointee_move(Windows())

        self.messenger_manager = alloc[MessengerManager](1)
        self.messenger_manager.value().init_pointee_move(MessengerManager())

        self.world = alloc[MMMWorld](1) 
        self.world.init_pointee_move(MMMWorld(sample_rate, block_size, num_in_chans, num_out_chans, self.osc_buffers, self.windows, self.messenger_manager))

        self.graph = Grains(self.world)

    def write_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.world[].block_size)

    def write_repr_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.world[].block_size)

    @staticmethod
    def set_channel_count(py_selfA: PythonObject, args: PythonObject) raises -> PythonObject:
        var num_in_chans = Int(py=args[0])
        var num_out_chans = Int(py=args[1])
        print("set_channel_count:", num_in_chans, num_out_chans)
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[0].world[].set_channel_count(num_in_chans, num_out_chans)
    
        return None # PythonObject(None)

    @staticmethod
    def set_screen_dims(py_selfA: PythonObject, dims: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[0].world[].screen_dims = [Float64(py=dims[0]), Float64(py=dims[1])]  # Set the screen size in the MMMWorld instance

        return PythonObject(None) 

    @staticmethod
    def update_mouse_pos(py_selfA: PythonObject, pos: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[0].world[].mouse_x = Float64(py=pos[0])
        py_self[0].world[].mouse_y = Float64(py=pos[1])

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def to_float64(py_float: PythonObject) raises -> Float64:
        return Float64(py=py_float)

    @staticmethod
    def update_bool_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        temp = py_self[0].messenger_manager.value()
        temp[].update_bool_msg(String(key_vals[0]), Bool(key_vals[1]))

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_bools_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Bool(b) for b in key_vals[1:]]

        temp = py_self[0].messenger_manager.value()
        temp[].update_bools_msg(key, values^)
        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_float_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        temp = py_self[0].messenger_manager.value()
        temp[].update_float_msg(String(key_vals[0]), Float64(py=key_vals[1]))

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_floats_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Float64(py=f) for f in key_vals[1:]]

        temp = py_self[0].messenger_manager.value()
        temp[].update_floats_msg(key, values^)

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_int_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        temp = py_self[0].messenger_manager.value()
        temp[].update_int_msg(String(key_vals[0]), Int(py=key_vals[1]))

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_ints_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Int(py=v) for v in key_vals[1:]]

        temp = py_self[0].messenger_manager.value()
        temp[].update_ints_msg(key, values^)

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_trig_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        temp = py_self[0].messenger_manager.value()
        temp[].update_trig_msg(String(key_vals[0]))

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_trigs_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        key = String(key_vals[0])
        values = [Bool(b) for b in key_vals[1:]]

        temp = py_self[0].messenger_manager.value()
        temp[].update_trigs_msg(key, values^)

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_string_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        temp = py_self[0].messenger_manager.value()
        temp[].update_string_msg(String(key_vals[0]), String(key_vals[1]))

        return PythonObject(None)  # Return a PythonObject wrapping None

    @staticmethod
    def update_strings_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        key = String(key_vals[0])
        texts = [String(s) for s in key_vals[1:]]

        temp = py_self[0].messenger_manager.value()
        temp[].update_strings_msg(key, texts^)

        return PythonObject(None)  # Return a PythonObject wrapping None

    def get_audio_samples(mut self, loc_in_buffer: MutUnsafePointer[Float32, ...], mut loc_out_buffer: MutUnsafePointer[Float64, ...]) raises:

        self.world[].top_of_block = True
        temp = self.messenger_manager.value()
        temp[].transfer_msgs()
                
        for i in range(self.world[].block_size):
            self.world[].block_state = i  # Update the block state

            if i == 1:
                self.world[].top_of_block = False
                temp[].empty_msg_dicts()

            if self.world[].top_of_block:
                self.world[].print_counter += 1
            # fill the sound_in list with the current sample from all inputs
            for j in range(self.world[].num_in_chans):
                self.world[].sound_in[j] = Float64(loc_in_buffer[i * self.world[].num_in_chans + j]) 

            samples = self.graph.next()  # Get the next audio samples from the graph

            # Fill the wire buffer with the sample data
            for j in range(min(self.world[].num_out_chans, samples.__len__())):
                loc_out_buffer[i * self.world[].num_out_chans + j] = samples[Int(j)]
    @staticmethod
    def next(py_selfA: PythonObject, in_buffer: PythonObject, out_buffer: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        loc_in_buffer = in_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float32]()

        loc_out_buffer = out_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float64]()

        # zero the output buffer
        for j in range(py_self[0].world[].num_out_chans):
            for i in range(py_self[0].world[].block_size):
                loc_out_buffer[i * py_self[0].world[].num_out_chans + j] = 0.0 

        py_self[0].get_audio_samples(loc_in_buffer, loc_out_buffer)  

        return PythonObject(None)  # Return a PythonObject wrapping the float value

