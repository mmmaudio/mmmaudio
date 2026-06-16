from mmm_audio import *
from std.collections import Dict, Set

struct Messenger(Copyable, Movable):
    """Communication between Python and Mojo.
    
    It works by checking for messages sent from Python at the start of each audio block, and updating
    any parameters registered with it accordingly. Each data type has its own `update` function and `notify_update` which will return a Bool indicating whether the parameter was updated.

    For example usage, see the MessengerExample.mojo file in the [Examples](../examples/index.md) folder.
    """

    var namespace: Optional[String]
    var world: World

    var key_dict: Dict[String, String]

    def __init__(out self, world: World, namespace: Optional[String] = None):
        """Initialize the Messenger.

        If a 'namespace' is provided, any messages sent from Python need to be prepended with this name.
        For example, if a Float64 updates with the name 'freq' and this Messenger has the
        namespace 'synth1', then to update the freq value from Python, the user must send 'synth1.freq'.

        Args:
            world: An `World` to the world to check for new messages.
            namespace: A `String` (or by defaut `None`) to declare as the 'namespace' for this Messenger. If a 'namespace' is provided, any messages sent from Python need to be prepended with this name. For example, if a Float64 updates with the name 'freq' and this Messenger has the namespace 'synth1', then to update the freq value from Python, the user must send 'synth1.freq'.
        """

        self.world = world
        self.namespace = namespace
        self.key_dict = Dict[String, String]()


    @doc_hidden
    def get_name_with_namespace(mut self, name: String) raises -> UnsafePointer[mut=False, String, origin_of(self.key_dict)]:
        if not self.key_dict.__contains__(name):
            if self.namespace:
                with_namespace = self.namespace.value() + "." + name
            else:
                with_namespace = name
            self.key_dict[name] = with_namespace

        return UnsafePointer(to=self.key_dict[name]).as_immutable()

    # def get_name_with_namespace(mut self, name: String) raises -> UnsafePointer[mut=False,String, ...]:
    #     if not self.key_dict.__contains__(name):
    #         if self.namespace:
    #             with_namespace = self.namespace.value()+"."+name
    #         else:
    #             with_namespace = name
    #         self.key_dict[name] = with_namespace

    #     return UnsafePointer(to=self.key_dict[name])

    # update Bool
    def update(mut self, name: String, mut param: Bool):
        """Update a Bool variable with a value sent from Python.

        Args:
            name: A `String` to identify the Bool sent from Python.
            param: A `Bool` variable to be updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_bool(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
            except error:
                print("Error occurred while updating bool message. Error: ", error)

    # notify_update Bool
    def notify_update(mut self, name: String, mut param: Bool) -> Bool:
        """Notify and update a Bool variable with a value sent from Python.

        Args:
            name: A `String` to identify the Bool sent from Python.
            param: A `Bool` variable to be updated.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_bool(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
                    return True
            except error:
                print("Error occurred while updating bool message. Error: ", error)
        return False

    # update List[Bool]
    # def update(mut self, name: String, mut param: List[Bool]):
    #     if self.world[].top_of_block():
    #         try:
    #             var opt = self.world[].messenger_manager[].get_bools(self.get_name_with_namespace(name)[])
    #             if opt:
    #                 param = opt.value().copy()
    #         except error:
    #             print("Error occurred while updating bool message. Error: ", error)

    # # notify_update List[Bool]
    # def notify_update(mut self, name: String, mut param: List[Bool]) -> Bool:
    #     if self.world[].top_of_block():
    #         try:
    #             var opt = self.world[].messenger_manager[].get_bools(self.get_name_with_namespace(name)[])
    #             if opt:
    #                 param = opt.value().copy()
    #                 return True
    #         except error:
    #             print("Error occurred while updating bool message. Error: ", error)
    #     return False

    # update Float64
    def update(mut self, name: String, mut param: Float64):
        """Update a Float64 variable with a value sent from Python.

        Args:
            name: A `String` to identify the Float64 sent from Python.
            param: A `Float64` variable to be updated.
        """
        
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_float(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
            except error:
                print("Error occurred while updating float message. Error: ", error)

    # notify_update Float64
    def notify_update(mut self, name: String, mut param: Float64) -> Bool:
        """Notify and update a Float64 variable with a value sent from Python.

        Args:
            name: A `String` to identify the Float64 sent from Python.
            param: A `Float64` variable to be updated.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_float(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
                    return True
            except error:
                print("Error occurred while updating float message. Error: ", error)
        return False

    # update List[Float64]
    def update(mut self, name: String, mut param: List[Float64]):
        """Update a List[Float64] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[Float64] sent from Python.
            param: A `List[Float64]` variable to be updated. The List will be resized to match the incoming data.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_floats(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
            except error:
                print("Error occurred while updating float list message. Error: ", error)

    # notify_update List[Float64]
    def notify_update(mut self, name: String, mut param: List[Float64]) -> Bool:
        """Notify and update a List[Float64] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[Float64] sent from Python.
            param: A `List[Float64]` variable to be updated. The List will be resized to match the incoming data.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_floats(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
                    return True
            except error:
                print("Error occurred while updating float list message. Error: ", error)
        return False

    def update[dtype: DType, num_chans: Int](mut self, name: String, mut param: SIMD[dtype, num_chans]):
        """Update a SIMD[DType.float64] variable with a value sent from Python.

        Parameters:
            dtype: The scalar dtype stored in the SIMD parameter.
            num_chans: Number of SIMD lanes to update.

        Args:
            name: A `String` to identify the SIMD[DType.float64] sent from Python.
            param: A `SIMD[DType.float64]` variable to be updated. The SIMD will *not* be resized to match the incoming data. It is the user's responsibility to ensure the sizes match.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_floats(self.get_name_with_namespace(name)[])
                if opt:
                    for i in range(len(opt.value())):
                        param[i] = Scalar[dtype](opt.value()[i])
            except error:
                print("Error occurred while updating float SIMD message. Error: ", error)

    def notify_update[dtype: DType, num_chans: Int](mut self, name: String, mut param: SIMD[dtype, num_chans]) -> Bool:
        """Notify and update a SIMD[DType.float64] variable with a value sent from Python.

        Parameters:
            dtype: The scalar dtype stored in the SIMD parameter.
            num_chans: Number of SIMD lanes to update.

        Args:
            name: A `String` to identify the SIMD[DType.float64] sent from Python.
            param: A `SIMD[DType.float64]` variable to be updated. The SIMD will *not* be resized to match the incoming data. It is the user's responsibility to ensure the sizes match.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_floats(self.get_name_with_namespace(name)[])
                if opt:
                    for i in range(len(opt.value())):
                        param[i] = Scalar[dtype](opt.value()[i])
                    return True
            except error:
                print("Error occurred while updating float SIMD message. Error: ", error)
        return False

    # update Int
    def update(mut self, name: String, mut param: Int):
        """Update a Int variable with a value sent from Python.

        Args:
            name: A `String` to identify the Int sent from Python.
            param: A `Int` variable to be updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_int(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
            except error:
                print("Error occurred while updating int message. Error: ", error)

    # notify_update Int
    def notify_update(mut self, name: String, mut param: Int) -> Bool:
        """Notify and update a Int variable with a value sent from Python.

        Args:
            name: A `String` to identify the Int sent from Python.
            param: A `Int` variable to be updated.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_int(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
                    return True
            except error:
                print("Error occurred while updating int message. Error: ", error)
        return False

    # update List[Int]
    def update(mut self, name: String, mut param: List[Int]):
        """Update a List[Int] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[Int] sent from Python.
            param: A `List[Int]` variable to be updated. The List will be resized to match the incoming data.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_ints(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
            except error:
                print("Error occurred while updating int list message. Error: ", error)

    # notify_update List[Int]
    def notify_update(mut self, name: String, mut param: List[Int]) -> Bool:
        """Notify and update a List[Int] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[Int] sent from Python.
            param: A `List[Int]` variable to be updated. The List will be resized to match the incoming data.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_ints(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
                    return True
            except error:
                print("Error occurred while updating int list message. Error: ", error)
        return False

    # update String
    def update(mut self, name: String, mut param: String):
        """Update a String variable with a value sent from Python.
        
        Args:
            name: A `String` to identify the String sent from Python.
            param: A `String` variable to be updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_string(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
            except error:
                print("Error occurred while updating text message. Error: ", error)

    # notify_update String
    def notify_update(mut self, name: String, mut param: String) -> Bool:
        """Notify and update a String variable with a value sent from Python.

        Args:
            name: A `String` to identify the String sent from Python.
            param: A `String` variable to be updated.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_string(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value()
                    return True
            except error:
                print("Error occurred while updating text message. Error: ", error)
        return False

    # update List[String]
    def update(mut self, name: String, mut param: List[String]):
        """Update a List[String] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[String] sent from Python.
            param: A `List[String]` variable to be updated. The List will be resized to match the incoming data.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_strings(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
            except error:
                print("Error occurred while updating text message. Error: ", error)
    
    # notify_update List[String]
    def notify_update(mut self, name: String, mut param: List[String]) -> Bool:
        """Notify and update a List[String] variable with a value sent from Python.

        Args:
            name: A `String` to identify the List[String] sent from Python.
            param: A `List[String]` variable to be updated. The List will be resized to match the incoming data.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                var opt = temp[].get_strings(self.get_name_with_namespace(name)[])
                if opt:
                    param = opt.value().copy()
                    return True
            except error:
                print("Error occurred while updating text message. Error: ", error)
        return False

    def notify_trig(mut self, name: String) -> Bool:
        """Get notified if a `send_trig` message was sent under the specified name.

        Args:
            name: A `String` to identify the trigger sent from Python.

        Returns:
            A `Bool` indicating whether a trigger was sent from Python under the specified name.
        """

        if self.world[].top_of_block():
            try:
                temp = self.world[].messenger_manager.value()
                return temp[].get_trig(self.get_name_with_namespace(name)[])
            except error:
                print("Error occurred while updating trig message. Error: ", error)
        return False

@doc_hidden
struct BoolMessage(Movable, Copyable):
    var retrieved: Bool
    var value: Bool

    def __init__(out self, value: Bool):
        self.retrieved = False
        self.value = value

@doc_hidden
struct BoolsMessage(Movable, Copyable):
    var retrieved: Bool
    var value: List[Bool]

    def __init__(out self, value: List[Bool]):
        self.retrieved = False
        self.value = value.copy()

@doc_hidden
struct FloatMessage(Movable, Copyable):
    var retrieved: Bool
    var value: Float64

    def __init__(out self, value: Float64):
        self.retrieved = False
        self.value = value

@doc_hidden
struct FloatsMessage(Movable, Copyable):
    var retrieved: Bool
    var value: List[Float64]

    def __init__(out self, value: List[Float64]):
        self.retrieved = False
        self.value = value.copy()

@doc_hidden
struct IntMessage(Movable, Copyable):
    var retrieved: Bool
    var value: Int

    def __init__(out self, value: Int):
        self.retrieved = False
        self.value = value

@doc_hidden
struct IntsMessage(Movable, Copyable):
    var retrieved: Bool
    var value: List[Int]

    def __init__(out self, value: List[Int]):
        self.retrieved = False
        self.value = value.copy()

@doc_hidden
struct StringMessage(Movable, Copyable):
    var value: String
    var retrieved: Bool

    def __init__(out self, value: String):
        self.value = value.copy()
        self.retrieved = False

@doc_hidden
struct StringsMessage(Movable, Copyable):
    var value: List[String]
    var retrieved: Bool

    def __init__(out self, value: List[String]):
        self.value = value.copy()
        self.retrieved = False

# struct TrigMessage isn't necessary. See MessengerManager for explanation.

@doc_hidden
struct TrigsMessage(Movable, Copyable):
    var retrieved: Bool
    var value: List[Bool]

    def __init__(out self, value: List[Bool]):
        self.retrieved = False
        self.value = value.copy()

@doc_hidden
struct MessengerManager(Movable, Copyable):

    var bool_msg_pool: Dict[String, Bool]
    var bool_msgs: Dict[String, BoolMessage]

    var bools_msg_pool: Dict[String, List[Bool]]
    var bools_msgs: Dict[String, BoolsMessage]

    var float_msg_pool: Dict[String, Float64]
    var float_msgs: Dict[String, FloatMessage]
    
    var floats_msg_pool: Dict[String, List[Float64]]
    var floats_msgs: Dict[String, FloatsMessage]
    
    var int_msg_pool: Dict[String, Int]
    var int_msgs: Dict[String, IntMessage]

    var ints_msg_pool: Dict[String, List[Int]]
    var ints_msgs: Dict[String, IntsMessage]

    var string_msg_pool: Dict[String, String]
    var string_msgs: Dict[String, StringMessage]

    var strings_msg_pool: Dict[String, List[String]]
    var strings_msgs: Dict[String, StringsMessage]

    var trig_msg_pool: Set[String]
    # Rather than making a TrigMessage struct, we only need a Dict:
    # Keys are the "trig names" that have been pooled, the Bools are
    # whether or not they were retrieved this block.
    var trig_msgs: Dict[String, Bool]

    var trigs_msg_pool: Dict[String, List[Bool]]
    var trigs_msgs: Dict[String, TrigsMessage]
    
    def __init__(out self):

        self.bool_msg_pool = Dict[String, Bool]()
        self.bool_msgs = Dict[String, BoolMessage]()

        self.bools_msg_pool = Dict[String, List[Bool]]()
        self.bools_msgs = Dict[String, BoolsMessage]()

        self.float_msg_pool = Dict[String, Float64]()
        self.float_msgs = Dict[String, FloatMessage]()

        self.floats_msg_pool = Dict[String, List[Float64]]()
        self.floats_msgs = Dict[String, FloatsMessage]()

        self.int_msg_pool = Dict[String, Int]()
        self.int_msgs = Dict[String, IntMessage]()
        
        self.ints_msg_pool = Dict[String, List[Int]]()
        self.ints_msgs = Dict[String, IntsMessage]()

        self.string_msg_pool = Dict[String, String]()
        self.string_msgs = Dict[String, StringMessage]()

        self.strings_msg_pool = Dict[String, List[String]]()
        self.strings_msgs = Dict[String, StringsMessage]()

        self.trig_msg_pool = Set[String]()
        self.trig_msgs = Dict[String, Bool]()

        self.trigs_msg_pool = Dict[String, List[Bool]]()
        self.trigs_msgs = Dict[String, TrigsMessage]()

    ##### Bool #####
    @always_inline
    def update_bool_msg(mut self, key: String, value: Bool):
        self.bool_msg_pool[key] = value

    @always_inline
    def update_bools_msg(mut self, key: String, var value: List[Bool]):
        self.bools_msg_pool[key] = value^

    ##### Float #####
    @always_inline
    def update_float_msg(mut self, key: String, value: Float64):
        self.float_msg_pool[key] = value

    @always_inline
    def update_floats_msg(mut self, key: String, var value: List[Float64]):
        self.floats_msg_pool[key] = value^

    ##### Int #####
    @always_inline
    def update_int_msg(mut self, key: String, value: Int):
        self.int_msg_pool[key] = value
    
    @always_inline
    def update_ints_msg(mut self, key: String, var value: List[Int]):
        self.ints_msg_pool[key] = value^

    ##### String #####
    @always_inline
    def update_string_msg(mut self, key: String, value: String):
        self.string_msg_pool[key] = value

    @always_inline
    def update_strings_msg(mut self, key: String, var value: List[String]):
        self.strings_msg_pool[key] = value^

    ##### Trig #####
    @always_inline
    def update_trig_msg(mut self, var key: String):
        self.trig_msg_pool.add(key^)

    @always_inline
    def update_trigs_msg(mut self, key: String, var value: List[Bool]):
        self.trigs_msg_pool[key] = value^

    def transfer_msgs(mut self) raises:

        for bm in self.bool_msg_pool.take_items():
            self.bool_msgs[bm.key] = BoolMessage(bm.value)

        for bsm in self.bools_msg_pool.take_items():
            self.bools_msgs[bsm.key] = BoolsMessage(bsm.value)

        for fm in self.float_msg_pool.take_items():
            self.float_msgs[fm.key] = FloatMessage(fm.value)

        for fsm in self.floats_msg_pool.take_items():
            self.floats_msgs[fsm.key] = FloatsMessage(fsm.value)

        for im in self.int_msg_pool.take_items():
            self.int_msgs[im.key] = IntMessage(im.value)

        for ism in self.ints_msg_pool.take_items():
            self.ints_msgs[ism.key] = IntsMessage(ism.value)

        for sm in self.string_msg_pool.take_items():
            self.string_msgs[sm.key] = StringMessage(sm.value)

        for ssm in self.strings_msg_pool.take_items():
            self.strings_msgs[ssm.key] = StringsMessage(ssm.value)

        for tm in self.trig_msg_pool:
            self.trig_msgs[tm] = False  # Set retrieved Bool to False initially
        # The other pools are Dicts so "take_items()" empties them, but since
        # trig_msg_pool is a Set, we have to clear it manually:
        self.trig_msg_pool.clear() 

        for tsm in self.trigs_msg_pool.take_items():
            self.trigs_msgs[tsm.key] = TrigsMessage(tsm.value)

    # get_* functions retrieve messages from the Dicts *after* they have
    # been transferred from the pools to the Dicts. These functions are called
    # from a graph (likely via a Messenger instance) to get the latest message values.
    @always_inline
    def get_bool(mut self, key: String) raises -> Optional[Bool]:
        if key in self.bool_msgs:
            self.bool_msgs[key].retrieved = True
            return self.bool_msgs[key].value
        return None

    @always_inline
    def get_bools(mut self: Self, key: String) raises-> Optional[List[Bool]]:
        if key in self.bools_msgs:
            self.bools_msgs[key].retrieved = True
            # Copy is ok here because it will only copy when there is a
            # new list for it to use, which should be rare. If the user
            # is, like, streaming lists of tons of values, they should
            # be using a different method, such as loading the data into
            # a buffer ahead of time and reading from that.
            return self.bools_msgs[key].value.copy()
        return None
    
    @always_inline
    def get_float(mut self, key: String) raises -> Optional[Float64]:
        if key in self.float_msgs:
            self.float_msgs[key].retrieved = True
            return self.float_msgs[key].value
        return None

    @always_inline
    def get_floats(mut self: Self, key: String) raises-> Optional[List[Float64]]:
        if key in self.floats_msgs:
            self.floats_msgs[key].retrieved = True
            # Copy is ok here because it will only copy when there is a
            # new list for it to use, which should be rare. If the user
            # is, like, streaming lists of tons of values, they should
            # be using a different method, such as loading the data into
            # a buffer ahead of time and reading from that.
            return self.floats_msgs[key].value.copy()
        return None

    @always_inline
    def get_int(mut self, key: String) raises -> Optional[Int]:
        if key in self.int_msgs:
            self.int_msgs[key].retrieved = True
            return self.int_msgs[key].value
        return None

    @always_inline
    def get_ints(mut self, key: String) raises -> Optional[List[Int]]:
        if key in self.ints_msgs:
            self.ints_msgs[key].retrieved = True
            return self.ints_msgs[key].value.copy()
        return None

    @always_inline
    def get_string(mut self, key: String) raises -> Optional[String]:
        if key in self.string_msgs:
            self.string_msgs[key].retrieved = True
            return self.string_msgs[key].value
        return None

    @always_inline
    def get_strings(mut self, key: String) raises -> Optional[List[String]]:
        if key in self.strings_msgs:
            self.strings_msgs[key].retrieved = True
            return self.strings_msgs[key].value.copy()
        return None

    @always_inline
    def get_trig(mut self, key: String) -> Bool:
        if key in self.trig_msgs:
            self.trig_msgs[key] = True
            return True
        return False

    @always_inline
    def get_trigs(mut self, key: String) raises -> Optional[List[Bool]]:
        if key in self.trigs_msgs:
            self.trigs_msgs[key].retrieved = True
            return self.trigs_msgs[key].value.copy()
        return None

    def empty_msg_dicts(mut self):
        for bool_msg in self.bool_msgs.take_items():
            if not bool_msg.value.retrieved:
                print("Bool message was not retrieved this block:", bool_msg.key)

        for bools_msg in self.bools_msgs.take_items():
            if not bools_msg.value.retrieved:
                print("Bools message was not retrieved this block:", bools_msg.key)

        for float_msg in self.float_msgs.take_items():
            if not float_msg.value.retrieved:
                print("Float message was not retrieved this block:", float_msg.key)

        for floats_msg in self.floats_msgs.take_items():
            if not floats_msg.value.retrieved:
                print("Floats message was not retrieved this block:", floats_msg.key)

        for int_msg in self.int_msgs.take_items():
            if not int_msg.value.retrieved:
                print("Int message was not retrieved this block:", int_msg.key)

        for ints_msg in self.ints_msgs.take_items():
            if not ints_msg.value.retrieved:
                print("Ints message was not retrieved this block:", ints_msg.key)

        for string_msg in self.string_msgs.take_items():
            if not string_msg.value.retrieved:
                print("String message was not retrieved this block:", string_msg.key)
        
        for strings_msg in self.strings_msgs.take_items():
            if not strings_msg.value.retrieved:
                print("Strings message was not retrieved this block:", strings_msg.key)

        for tm in self.trig_msgs.take_items():
            if not tm.value:
                print("Trig message was not retrieved this block:", tm.key)

        for trigs_msg in self.trigs_msgs.take_items():
            if not trigs_msg.value.retrieved:
                print("Trigs message was not retrieved this block:", trigs_msg.key)
