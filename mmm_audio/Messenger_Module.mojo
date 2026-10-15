from mmm_audio.constants import *
from std.collections import Dict, Set
from std.sys import size_of
from std.utils.coord import CoordLike
from std.origin import MutUntrackedOrigin


trait WorldIsMessagable:
    """A World is Messagable if it implements these functions. This allows different types of worlds to be passed into the Messenger to be communicated with.

    `MMMWorld` implements this, and so can the world of another project built to use the Messenger.
    """

    def messenger_manager_ptr(self) -> MutPointer[MessengerManager, MutUntrackedOrigin]:
        """The `MessengerManager` that Python's messages are delivered to.
        
        Returns:
            A mutable pointer to the MessengerManager.
        """
        ...

    def top_of_block_ptr(self) -> MutPointer[Bool, MutUntrackedOrigin]:
        """The flag that is true while the first sample of a block (or the frame) is processed. Messages are only read while it is set to True.

        Returns:
            A mutable pointer to the top_of_block value.
        """
        ...


struct Messenger(Copyable, Movable):
    """Communication between Python and Mojo.
    
    It works by checking for messages sent from Python at the start of each audio block (or frame, for
    a world other than `MMMWorld` - see `WorldIsMessagable`), and updating
    any parameters registered with it accordingly. Each data type has its own `update` function and `notify_update` which will return a Bool indicating whether the parameter was updated.

    For example usage, see the MessengerExample.mojo file in the [Examples](../examples/index.md) folder.
    """

    var namespace: Optional[String]
    var _messenger_manager: MutPointer[MessengerManager, MutUntrackedOrigin]
    var _top_of_block: MutPointer[Bool, MutUntrackedOrigin]

    var key_dict: Dict[String, String]

    def __init__[W: WorldIsMessagable](out self, world: Pointer[mut=True, W, MutUntrackedOrigin], namespace: Optional[String] = None):
        """Initialize the Messenger. If a 'namespace' is provided, any messages sent from Python need to be prepended with this name. For example, if a Float64 updates with the name 'freq' and this Messenger has the namespace 'synth1', then to update the freq value from Python, the user must send 'synth1.freq'.

        Parameters:
            W: A trait that defines a World that is Messageable. MMMAudio's World conforms to this trait.

        Args:
            world: The `World` that the struct will check for new messages (any world that implements `WorldIsMessagable`, which in MMMAudio is `World`).
            namespace: A `String` (or by defaut `None`) to declare as the 'namespace' for this Messenger. If a 'namespace' is provided, any messages sent from Python need to be prepended with this name. For example, if a Float64 updates with the name 'freq' and this Messenger has the namespace 'synth1', then to update the freq value from Python, the user must send 'synth1.freq'.
        """

        self._messenger_manager = world[].messenger_manager_ptr()
        self._top_of_block = world[].top_of_block_ptr()
        self.namespace = namespace
        self.key_dict = Dict[String, String]()


    @doc_hidden
    def get_name_with_namespace(mut self, name: String) raises -> Pointer[mut=False, String, origin_of(self.key_dict[name])]:
        if not self.key_dict.__contains__(name):
            var with_namespace = self.namespace.value() + "." + name if self.namespace else name
            self.key_dict[name] = with_namespace

        return Pointer(to=self.key_dict[name])


    def update[T: Copyable & Deinitable, //](mut self, name: String, mut param: T):
        """Update a variable with a value sent from Python.

        If several messages were sent under `name` since the last block, `param` gets the last one. To get all of
        them, in order, use `update_all`.

        The message type comes from the type of `param`:

        - `Float64` is set by `send_float`, `Int` by `send_int`, `Bool` by `send_bool` and `String` by `send_string`.
        - `List[Float64]`, `List[Int]`, `List[Bool]` and `List[String]` are set by `send_floats`, `send_ints`,
          `send_bools` and `send_strings`. The List is resized to match the incoming data.
        - Any other `SIMD` (such as `MFloat[2]` or `Float32`) is set lane by lane by `send_floats`. The SIMD is
          *not* resized: lanes beyond the values sent keep their value, and extra values are ignored.

        Parameters:
            T: The type of `param`, inferred.

        Args:
            name: A `String` to identify the value sent from Python.
            param: The variable to be updated.
        """
        _ = self.notify_update(name, param)

    def notify_update[T: Copyable & Deinitable, //](mut self, name: String, mut param: T) -> Bool:
        """Notify and update a variable with a value sent from Python.

        The message type comes from the type of `param`, as described in `update`.

        Parameters:
            T: The type of `param`, inferred.

        Args:
            name: A `String` to identify the value sent from Python.
            param: The variable to be updated.

        Returns:
            A `Bool` indicating whether the parameter was updated.
        """
        if self._top_of_block[]:
            try:
                ref manager = self._messenger_manager[]
                return manager._update_param(self.get_name_with_namespace(name)[], param)
            except error:
                print("Error occurred while updating message '", name, "'. Error: ", error)
        return False

    def notify_trig(mut self, name: String) -> Bool:
        """Get notified if a `send_trig` message was sent under the specified name.

        Args:
            name: A `String` to identify the trigger sent from Python.

        Returns:
            A `Bool` indicating whether a trigger was sent from Python under the specified name.
        """

        if self._top_of_block[]:
            try:
                ref temp = self._messenger_manager[]
                return temp.get_trig(self.get_name_with_namespace(name)[])
            except error:
                print("Error occurred while updating trig message. Error: ", error)
        return False


    def notify_address_callback[T: Copyable & Deinitable, //, call_back: def(T) capturing -> None](mut self, name: String) -> Bool:
        """
        Get notified if a message is received and execute a provided callback function with its value.

        The message type comes from the callback's argument type, which can be `Float64`, `Int`,
        `Bool`, `String`, `List[Float64]`, `List[Int]`, `List[Bool]` or `List[String]`. For example,
        a callback taking a `List[Float64]` responds to `send_floats` from Python, and one taking
        an `Int` responds to `send_int`.

        Parameters:
            T: The callback's argument type, inferred from `call_back`.
            call_back: A callback function that takes the message value as its argument.

        Args:
            name: A `String` to identify the message sent from Python.

        Returns:
            A `Bool` indicating whether a message was sent from Python under the specified name.
        """
        if self._top_of_block[]:
            try:
                ref manager = self._messenger_manager[]
                var opt = manager._get_message[T](self.get_name_with_namespace(name)[])
                if opt:
                    call_back(opt.value())
                    return True
            except error:
                print("Error occurred while handling callback message. Error: ", error)
        return False

    def address_callback[T: Copyable & Deinitable, //, call_back: def(T) capturing -> None](mut self, name: String):
        """
        Executes a given callback function with a value sent from Python.

        The message type comes from the callback's argument type, which can be `Float64`, `Int`,
        `Bool`, `String`, `List[Float64]`, `List[Int]`, `List[Bool]` or `List[String]`. For example,
        a callback taking a `List[Float64]` responds to `send_floats` from Python, and one taking
        an `Int` responds to `send_int`.

        Parameters:
            T: The callback's argument type, inferred from `call_back`.
            call_back: A callback function that takes the message value as its argument.

        Args:
            name: A `String` to identify the message sent from Python.
        """
        _ = self.notify_address_callback[call_back](name)

    def update_all[T: Copyable & Deinitable, //](mut self, name: String, mut param: List[T]):
        """Update a List with every value sent from Python under `name` since the last block, in the order they were received.

        Where `update` only keeps the last message, this keeps all of them, so messages sent in quick succession
        (such as several `note_on`s within one block) aren't lost. The element type of `param` chooses the message
        type the same way the type of `param` does in `update`: a `List[Float64]` collects `send_float` messages,
        a `List[List[Int]]` collects `send_ints` messages, a `List[MFloat[2]]` collects `send_floats` messages
        lane by lane, and so on.

        If nothing was sent, `param` keeps its previous contents (use `notify_update_all` to know if it changed).

        Parameters:
            T: The type of each element of `param`, inferred.

        Args:
            name: A `String` to identify the values sent from Python.
            param: The List to be replaced with the values received, oldest first.
        """
        _ = self.notify_update_all(name, param)

    def notify_update_all[T: Copyable & Deinitable, //](mut self, name: String, mut param: List[T]) -> Bool:
        """Notify and update a List with every value sent from Python under `name` since the last block, in the order they were received.

        The message type comes from the element type of `param`, as described in `update_all`.

        Parameters:
            T: The type of each element of `param`, inferred.

        Args:
            name: A `String` to identify the values sent from Python.
            param: The List to be replaced with the values received, oldest first.

        Returns:
            A `Bool` indicating whether the List was updated.
        """
        if self._top_of_block[]:
            try:
                ref manager = self._messenger_manager[]
                return manager._update_param_all(self.get_name_with_namespace(name)[], param)
            except error:
                print("Error occurred while updating message '", name, "'. Error: ", error)
        return False

    def notify_address_callback_all[T: Copyable & Deinitable, //, call_back: def(List[T]) capturing -> None](mut self, name: String) -> Bool:
        """
        Get notified if any messages are received and execute a provided callback function with all of their values, in the order they were received.

        The message type comes from the element type of the callback's argument. For example, a callback
        taking a `List[List[Int]]` responds to `send_ints` from Python, and one taking a `List[Float64]`
        responds to `send_float`. The callback is called once per block, with every value sent that block.

        Parameters:
            T: The type of each element of the callback's argument, inferred from `call_back`.
            call_back: A callback function that takes a List of the message values as its argument.

        Args:
            name: A `String` to identify the messages sent from Python.

        Returns:
            A `Bool` indicating whether any messages were sent from Python under the specified name.
        """
        if self._top_of_block[]:
            try:
                ref manager = self._messenger_manager[]
                var opt = manager._get_messages[T](self.get_name_with_namespace(name)[])
                if opt:
                    call_back(opt.value())
                    return True
            except error:
                print("Error occurred while handling callback message. Error: ", error)
        return False

    def address_callback_all[T: Copyable & Deinitable, //, call_back: def(List[T]) capturing -> None](mut self, name: String):
        """
        Executes a given callback function with every value sent from Python under `name` since the last block, in the order they were received.

        The message type comes from the element type of the callback's argument, as described in `notify_address_callback_all`.

        Parameters:
            T: The type of each element of the callback's argument, inferred from `call_back`.
            call_back: A callback function that takes a List of the message values as its argument.

        Args:
            name: A `String` to identify the messages sent from Python.
        """
        _ = self.notify_address_callback_all[call_back](name)

@doc_hidden
struct Message[T: Copyable & Deinitable](Movable, Copyable):
    """Every value sent under one name since the last block, in the order they were received."""
    var retrieved: Bool
    var values: List[Self.T]

    def __init__(out self, var values: List[Self.T]):
        self.retrieved = False
        self.values = values^

@doc_hidden
@always_inline
def _pool_msg[T: Copyable & Deinitable](mut pool: Dict[String, List[T]], key: String, var value: T):
    pool.setdefault(key, List[T]()).append(value^)

@doc_hidden
def _transfer_pool[T: Copyable & Deinitable](mut pool: Dict[String, List[T]], mut msgs: Dict[String, Message[T]]):
    for entry in pool.take_items():
        msgs[entry.key] = Message[T](entry.value.copy())

@doc_hidden
@always_inline
def _get_last[T: Copyable & Deinitable](mut msgs: Dict[String, Message[T]], key: String) raises -> Optional[T]:
    if key in msgs:
        ref msg = msgs[key]
        msg.retrieved = True
        return msg.values[len(msg.values) - 1].copy()
    return None

@doc_hidden
@always_inline
def _get_all[T: Copyable & Deinitable](mut msgs: Dict[String, Message[T]], key: String) raises -> Optional[List[T]]:
    if key in msgs:
        ref msg = msgs[key]
        msg.retrieved = True
        # Copy is ok here because it will only copy when there are new
        # messages for it to use, which should be rare. If the user
        # is, like, streaming lists of tons of values, they should
        # be using a different method, such as loading the data into
        # a buffer ahead of time and reading from that.
        return msg.values.copy()
    return None

@doc_hidden
def _is_midi_msg(key: String) -> Bool:
    """The messages sent for MIDI by the plugins and MMMAudio.send_midi. A graph often only reads some of them, so they don't warn when they aren't retrieved."""
    return (key == "note_on" or key == "note_off" or key == "cc" or key == "pitch_bend"
        or key == "poly_aftertouch" or key == "channel_pressure" or key == "program_change")

@doc_hidden
def _empty_msgs[T: Copyable & Deinitable](mut msgs: Dict[String, Message[T]], kind: String):
    for msg in msgs.take_items():
        if not msg.value.retrieved and not _is_midi_msg(msg.key):
            print(kind, "message was not retrieved this block:", msg.key)

@doc_hidden
struct MessengerManager(Movable, Copyable):
    """Pools the messages Python sends and hands them to the graph a block at a time.

    Each `*_msg_pool` keeps every value sent under a name, in the order received, until
    `transfer_msgs` moves them into the matching `*_msgs` Dict for the next block. The
    plain getters (`_get_message`) give the last value sent; `_get_messages` gives all of them.
    """

    var bool_msg_pool: Dict[String, List[Bool]]
    var bool_msgs: Dict[String, Message[Bool]]

    var bools_msg_pool: Dict[String, List[List[Bool]]]
    var bools_msgs: Dict[String, Message[List[Bool]]]

    var float_msg_pool: Dict[String, List[Float64]]
    var float_msgs: Dict[String, Message[Float64]]
    
    var floats_msg_pool: Dict[String, List[List[Float64]]]
    var floats_msgs: Dict[String, Message[List[Float64]]]
    
    var int_msg_pool: Dict[String, List[Int]]
    var int_msgs: Dict[String, Message[Int]]

    var ints_msg_pool: Dict[String, List[List[Int]]]
    var ints_msgs: Dict[String, Message[List[Int]]]

    var string_msg_pool: Dict[String, List[String]]
    var string_msgs: Dict[String, Message[String]]

    var strings_msg_pool: Dict[String, List[List[String]]]
    var strings_msgs: Dict[String, Message[List[String]]]

    var trig_msg_pool: Set[String]
    # Rather than making a Message for trigs, we only need a Dict:
    # Keys are the "trig names" that have been pooled, the Bools are
    # whether or not they were retrieved this block.
    var trig_msgs: Dict[String, Bool]

    var trigs_msg_pool: Dict[String, List[List[Bool]]]
    var trigs_msgs: Dict[String, Message[List[Bool]]]
    
    def __init__(out self):

        self.bool_msg_pool = Dict[String, List[Bool]]()
        self.bool_msgs = Dict[String, Message[Bool]]()

        self.bools_msg_pool = Dict[String, List[List[Bool]]]()
        self.bools_msgs = Dict[String, Message[List[Bool]]]()

        self.float_msg_pool = Dict[String, List[Float64]]()
        self.float_msgs = Dict[String, Message[Float64]]()

        self.floats_msg_pool = Dict[String, List[List[Float64]]]()
        self.floats_msgs = Dict[String, Message[List[Float64]]]()

        self.int_msg_pool = Dict[String, List[Int]]()
        self.int_msgs = Dict[String, Message[Int]]()
        
        self.ints_msg_pool = Dict[String, List[List[Int]]]()
        self.ints_msgs = Dict[String, Message[List[Int]]]()

        self.string_msg_pool = Dict[String, List[String]]()
        self.string_msgs = Dict[String, Message[String]]()

        self.strings_msg_pool = Dict[String, List[List[String]]]()
        self.strings_msgs = Dict[String, Message[List[String]]]()

        self.trig_msg_pool = Set[String]()
        self.trig_msgs = Dict[String, Bool]()

        self.trigs_msg_pool = Dict[String, List[List[Bool]]]()
        self.trigs_msgs = Dict[String, Message[List[Bool]]]()

    # update_*_msg functions are called from Python (via the bridge). Each one
    # appends to the pool, so several messages sent to the same name before
    # the next block are all kept, in order.

    ##### Bool #####
    @always_inline
    def update_bool_msg(mut self, key: String, value: Bool):
        _pool_msg(self.bool_msg_pool, key, value)

    @always_inline
    def update_bools_msg(mut self, key: String, var value: List[Bool]):
        _pool_msg(self.bools_msg_pool, key, value^)

    ##### Float #####
    @always_inline
    def update_float_msg(mut self, key: String, value: Float64):
        _pool_msg(self.float_msg_pool, key, value)

    @always_inline
    def update_floats_msg(mut self, key: String, var value: List[Float64]):
        _pool_msg(self.floats_msg_pool, key, value^)

    ##### Int #####
    @always_inline
    def update_int_msg(mut self, key: String, value: Int):
        _pool_msg(self.int_msg_pool, key, value)
    
    @always_inline
    def update_ints_msg(mut self, key: String, var value: List[Int]):
        _pool_msg(self.ints_msg_pool, key, value^)

    ##### String #####
    @always_inline
    def update_string_msg(mut self, key: String, value: String):
        _pool_msg(self.string_msg_pool, key, value)

    @always_inline
    def update_strings_msg(mut self, key: String, var value: List[String]):
        _pool_msg(self.strings_msg_pool, key, value^)

    ##### Trig #####
    @always_inline
    def update_trig_msg(mut self, var key: String):
        self.trig_msg_pool.add(key^)

    @always_inline
    def update_trigs_msg(mut self, key: String, var value: List[Bool]):
        _pool_msg(self.trigs_msg_pool, key, value^)

    def transfer_msgs(mut self) raises:
        _transfer_pool(self.bool_msg_pool, self.bool_msgs)
        _transfer_pool(self.bools_msg_pool, self.bools_msgs)
        _transfer_pool(self.float_msg_pool, self.float_msgs)
        _transfer_pool(self.floats_msg_pool, self.floats_msgs)
        _transfer_pool(self.int_msg_pool, self.int_msgs)
        _transfer_pool(self.ints_msg_pool, self.ints_msgs)
        _transfer_pool(self.string_msg_pool, self.string_msgs)
        _transfer_pool(self.strings_msg_pool, self.strings_msgs)

        for tm in self.trig_msg_pool:
            self.trig_msgs[tm] = False  # Set retrieved Bool to False initially
        # The other pools are Dicts so "take_items()" empties them, but since
        # trig_msg_pool is a Set, we have to clear it manually:
        self.trig_msg_pool.clear() 

        _transfer_pool(self.trigs_msg_pool, self.trigs_msgs)

    @doc_hidden
    def _update_param[T: Copyable & Deinitable](mut self, key: String, mut param: T) raises -> Bool:
        """Set `param` from the last message of its type sent under `key`, as described in `Messenger.update`.

        Parameters:
            T: The type of `param`.

        Args:
            key: The full (namespaced) message name.
            param: The variable to be updated.

        Returns:
            True if a message was sent under `key` and `param` was updated.

        Raises:
            Error: If the manager fails to look up the message.
        """
        comptime if reflect[T].base_name() == "SIMD" and conforms_to(T, CoordLike):
            # SIMD conforms to CoordLike
            comptime dtype = T.DTYPE
            comptime width = size_of[T]() // size_of[Scalar[dtype]]()
            # single-lane SIMD types (e.g. MFloat[1]) are treated as scalars, so we can use the same getters as for non-SIMD types.
            comptime if T == Float64:
                var opt = self._get_message[Float64](key)
                if opt:
                    param = rebind[T](opt.value()).copy()
                    return True
            elif T == Int:
                var opt = self._get_message[Int](key)
                if opt:
                    param = rebind[T](opt.value()).copy()
                    return True
            else:
                # multi-lane SIMD types (e.g. MFloat[2], MFloat[4]) are treated as lists, so we go through and set the values one by one from the list of floats sent from Python.
                var opt = self._get_message[List[Float64]](key)
                if opt:
                    var v = rebind[SIMD[dtype, width]](param)
                    ref values = opt.value()
                    for i in range(min(len(values), width)):
                        v[i] = Scalar[dtype](values[i])
                    param = rebind[T](v).copy()
                    return True
            return False
        else:
            # non-SIMD types, like Lists of Float64 or Int: just use the _get_message function to retrieve the value and update param.
            var opt = self._get_message[T](key)
            if opt:
                param = opt.value().copy()
                return True
            return False

    @doc_hidden
    def _update_param_all[T: Copyable & Deinitable](mut self, key: String, mut param: List[T]) raises -> Bool:
        """Set `param` to every message of type `T` sent under `key`, as described in `Messenger.update_all`.

        Parameters:
            T: The type of each element of `param`.

        Args:
            key: The full (namespaced) message name.
            param: The List to be filled, oldest message first.

        Returns:
            True if at least one message was sent under `key` and `param` was updated.

        Raises:
            Error: If the manager fails to look up the messages.
        """
        comptime if reflect[T].base_name() == "SIMD" and conforms_to(T, CoordLike):
            comptime dtype = T.DTYPE
            comptime width = size_of[T]() // size_of[Scalar[dtype]]()
            comptime if T == Float64:
                var opt = self._get_messages[Float64](key)
                if opt:
                    param = rebind[List[T]](opt.value()).copy()
                    return True
            elif T == Int:
                var opt = self._get_messages[Int](key)
                if opt:
                    param = rebind[List[T]](opt.value()).copy()
                    return True
            else:
                # multi-lane SIMD types are set lane by lane from each list of floats, as in _update_param.
                # Lanes a message doesn't reach keep their value from the message before it (or, for the
                # first message, from the last element already in param).
                var opt = self._get_messages[List[Float64]](key)
                if opt:
                    var v = SIMD[dtype, width](0)
                    if len(param) > 0:
                        v = rebind[SIMD[dtype, width]](param[len(param) - 1])
                    var result = List[T](capacity=len(opt.value()))
                    for values in opt.value():
                        for i in range(min(len(values), width)):
                            v[i] = Scalar[dtype](values[i])
                        result.append(rebind[T](v).copy())
                    param = result^
                    return True
            return False
        else:
            var opt = self._get_messages[T](key)
            if opt:
                param = opt.value().copy()
                return True
            return False

    @doc_hidden
    def _get_message[T: Copyable & Deinitable](mut self, key: String) raises -> Optional[T]:
        """Get the last message of type `T` sent under `key`, choosing the Dict for `T` at compile time.

        Parameters:
            T: One of the message types listed in `Messenger.address_callback`.

        Args:
            key: The full (namespaced) message name.

        Returns:
            The value, if a message of type `T` was sent under `key`.

        Raises:
            Error: If the manager fails to look up the message.
        """
        comptime if T == Float64:
            return rebind[Optional[T]](_get_last(self.float_msgs, key)).copy()
        elif T == Int:
            return rebind[Optional[T]](_get_last(self.int_msgs, key)).copy()
        elif T == Bool:
            return rebind[Optional[T]](_get_last(self.bool_msgs, key)).copy()
        elif T == String:
            return rebind[Optional[T]](_get_last(self.string_msgs, key)).copy()
        elif T == List[Float64]:
            return rebind[Optional[T]](_get_last(self.floats_msgs, key)).copy()
        elif T == List[Int]:
            return rebind[Optional[T]](_get_last(self.ints_msgs, key)).copy()
        elif T == List[Bool]:
            return rebind[Optional[T]](_get_last(self.bools_msgs, key)).copy()
        elif T == List[String]:
            return rebind[Optional[T]](_get_last(self.strings_msgs, key)).copy()
        else:
            comptime assert False, "Messenger messages must be Float64, Int, Bool, String, List[Float64], List[Int], List[Bool] or List[String]"

    @doc_hidden
    def _get_messages[T: Copyable & Deinitable](mut self, key: String) raises -> Optional[List[T]]:
        """Get every message of type `T` sent under `key`, oldest first, choosing the Dict for `T` at compile time.

        Parameters:
            T: One of the message types listed in `Messenger.address_callback`.

        Args:
            key: The full (namespaced) message name.

        Returns:
            The values, if at least one message of type `T` was sent under `key`.

        Raises:
            Error: If the manager fails to look up the messages.
        """
        comptime if T == Float64:
            return rebind[Optional[List[T]]](_get_all(self.float_msgs, key)).copy()
        elif T == Int:
            return rebind[Optional[List[T]]](_get_all(self.int_msgs, key)).copy()
        elif T == Bool:
            return rebind[Optional[List[T]]](_get_all(self.bool_msgs, key)).copy()
        elif T == String:
            return rebind[Optional[List[T]]](_get_all(self.string_msgs, key)).copy()
        elif T == List[Float64]:
            return rebind[Optional[List[T]]](_get_all(self.floats_msgs, key)).copy()
        elif T == List[Int]:
            return rebind[Optional[List[T]]](_get_all(self.ints_msgs, key)).copy()
        elif T == List[Bool]:
            return rebind[Optional[List[T]]](_get_all(self.bools_msgs, key)).copy()
        elif T == List[String]:
            return rebind[Optional[List[T]]](_get_all(self.strings_msgs, key)).copy()
        else:
            comptime assert False, "Messenger messages must be Float64, Int, Bool, String, List[Float64], List[Int], List[Bool] or List[String]"

    @always_inline
    def get_trig(mut self, key: String) -> Bool:
        if key in self.trig_msgs:
            self.trig_msgs[key] = True
            return True
        return False

    @always_inline
    def get_trigs(mut self, key: String) raises -> Optional[List[Bool]]:
        return _get_last(self.trigs_msgs, key)

    def empty_msg_dicts(mut self):
        _empty_msgs(self.bool_msgs, "Bool")
        _empty_msgs(self.bools_msgs, "Bools")
        _empty_msgs(self.float_msgs, "Float")
        _empty_msgs(self.floats_msgs, "Floats")
        _empty_msgs(self.int_msgs, "Int")
        _empty_msgs(self.ints_msgs, "Ints")
        _empty_msgs(self.string_msgs, "String")
        _empty_msgs(self.strings_msgs, "Strings")

        for tm in self.trig_msgs.take_items():
            if not tm.value:
                print("Trig message was not retrieved this block:", tm.key)

        _empty_msgs(self.trigs_msgs, "Trigs")
