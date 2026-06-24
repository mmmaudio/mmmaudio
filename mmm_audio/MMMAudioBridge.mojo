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
def PyInit_GrainsBridge() abi("C") -> PythonObject:
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

        return m.finalize()
    except e:
        _ = Error(String("error creating Python Mojo module: " + String(e)))
        abort()

@doc_hidden
@fieldwise_init
struct MMMAudioBridge(Movable, Writable):
    var world: World
    var graph: Grains
    var environment_ptr: UnsafePointer[mut=True, Environment, MutUntrackedOrigin]

    @staticmethod
    def py_init(out self: MMMAudioBridge, args: PythonObject, kwargs: PythonObject) raises:

        args_dict = args[0]

        sample_rate = Float64(py=args_dict["sample_rate"])
        block_size = Int(py=args_dict["block_size"])
        num_in_chans = Int(py=args_dict["num_in_chans"])
        num_out_chans = Int(py=args_dict["num_out_chans"])

        self = Self(sample_rate, block_size, num_in_chans, num_out_chans)

    def __init__(out self, sample_rate: Float64 = 44100.0, block_size: Int = 512, num_in_chans: Int = 12, num_out_chans: Int = 12):
        """Initialize the audio engine with sample rate, block size, and number of channels."""

        self.environment_ptr = alloc[Environment](1)
        self.environment_ptr.init_pointee_move(Environment(block_size, num_in_chans, num_out_chans))

        self.world = alloc[MMMWorld](1) 
        self.world.init_pointee_move(MMMWorld(sample_rate, self.environment_ptr))

        self.graph = Grains(self.world)

    def write_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.environment_ptr[].block_size)

    def write_repr_to(self, mut writer: Some[Writer]):
        writer.write("MMMAudioBridge with sample_rate=", self.world[].sample_rate, ", block_size=", self.environment_ptr[].block_size)

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
        py_self[].environment_ptr[].messenger_manager.update_bool_msg(String(key_vals[0]), Bool(key_vals[1]))

        return PythonObject(None)

    @staticmethod
    def update_bools_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Bool(b) for b in key_vals[1:]]

        py_self[].environment_ptr[].messenger_manager.update_bools_msg(key, values^)
        return PythonObject(None)

    @staticmethod
    def update_float_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].environment_ptr[].messenger_manager.update_float_msg(String(key_vals[0]), Float64(py=key_vals[1]))

        return PythonObject(None)

    @staticmethod
    def update_floats_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Float64(py=f) for f in key_vals[1:]]

        py_self[].environment_ptr[].messenger_manager.update_floats_msg(key, values^)

        return PythonObject(None)

    @staticmethod
    def update_int_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()

        py_self[].environment_ptr[].messenger_manager.update_int_msg(String(key_vals[0]), Int(py=key_vals[1]))

        return PythonObject(None)

    @staticmethod
    def update_ints_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        key = String(key_vals[0])
        values = [Int(py=v) for v in key_vals[1:]]

        py_self[].environment_ptr[].messenger_manager.update_ints_msg(key, values^)

        return PythonObject(None)

    @staticmethod
    def update_trig_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:
        var py_self = py_selfA.downcast_value_ptr[Self]()
        py_self[].environment_ptr[].messenger_manager.update_trig_msg(String(key_vals[0]))

        return PythonObject(None)

    @staticmethod
    def update_trigs_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        key = String(key_vals[0])
        values = [Bool(b) for b in key_vals[1:]]

        py_self[].environment_ptr[].messenger_manager.update_trigs_msg(key, values^)

        return PythonObject(None)

    @staticmethod
    def update_string_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        py_self[].environment_ptr[].messenger_manager.update_string_msg(String(key_vals[0]), String(key_vals[1]))

        return PythonObject(None)

    @staticmethod
    def update_strings_msg(py_selfA: PythonObject, key_vals: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        key = String(key_vals[0])
        texts = [String(s) for s in key_vals[1:]]

        py_self[].environment_ptr[].messenger_manager.update_strings_msg(key, texts^)

        return PythonObject(None)

    def get_audio_samples(mut self, loc_in_buffer: MutUnsafePointer[Float32, ...], mut loc_out_buffer: MutUnsafePointer[Float64, ...]) raises:

        self.environment_ptr[].top_of_block = True
        self.environment_ptr[].messenger_manager.transfer_msgs()
                
        for i in range(self.environment_ptr[].block_size):
            self.environment_ptr[].block_state = i  # Update the block state

            if i == 1:
                self.environment_ptr[].top_of_block = False
                self.environment_ptr[].messenger_manager.empty_msg_dicts()

            if self.environment_ptr[].top_of_block:
                self.environment_ptr[].print_counter += 1
            # fill the sound_in list with the current sample from all inputs
            for j in range(self.environment_ptr[].num_in_chans):
                self.environment_ptr[].sound_in[j] = Float64(loc_in_buffer[i * self.environment_ptr[].num_in_chans + j]) 

            samples = self.graph.next()  # Get the next audio samples from the graph

            # Fill the wire buffer with the sample data
            for j in range(min(self.environment_ptr[].num_out_chans, samples.__len__())):
                loc_out_buffer[i * self.environment_ptr[].num_out_chans + j] = samples[Int(j)]

    @staticmethod
    def next(py_selfA: PythonObject, in_buffer: PythonObject, out_buffer: PythonObject) raises -> PythonObject:

        var py_self = py_selfA.downcast_value_ptr[Self]()

        loc_in_buffer = in_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float32]()

        loc_out_buffer = out_buffer.__array_interface__["data"][0].unsafe_get_as_pointer[DType.float64]()

        # zero the output buffer
        # TODO: is this necessary? aren't they going to be overwritten anyway?
        # if they're not overwritten wouldn't that be a bug?
        for j in range(py_self[].environment_ptr[].num_out_chans):
            for i in range(py_self[].environment_ptr[].block_size):
                loc_out_buffer[i * py_self[].environment_ptr[].num_out_chans + j] = 0.0 

        py_self[0].get_audio_samples(loc_in_buffer, loc_out_buffer)

        return PythonObject(None)
