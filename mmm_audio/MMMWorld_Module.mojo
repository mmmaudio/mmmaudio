from std.python import PythonObject
import std.time
from std.collections import Set
from mmm_audio import *

struct Environment(Movable, Copyable):
    var block_size: Int
    var num_in_chans: Int
    var num_out_chans: Int
    var sound_in: List[Float64]
    var screen_dims: List[Float64]  
    var mouse_x: Float64
    var mouse_y: Float64
    var block_state: Int
    var top_of_block: Bool
    var last_print_time: Float64
    var print_flag: Int
    var last_print_flag: Int
    var print_counter: UInt16

    var osc_buffers: OscBuffers
    var windows: Windows
    var messenger_manager: MessengerManager
    var sinc_interpolator: SincInterpolator[4, 14]

    def __init__(out self, block_size: Int = 64, num_in_chans: Int = 2, num_out_chans: Int = 2):
        self.block_size = block_size
        self.num_in_chans = num_in_chans
        self.num_out_chans = num_out_chans
        self.sound_in = [0.0 for _ in range(num_in_chans)]
        self.screen_dims = [800.0, 600.0]  # Default screen dimensions
        self.mouse_x = 0.0
        self.mouse_y = 0.0
        self.block_state = 0
        self.top_of_block = True
        self.last_print_time = 0.0
        self.print_flag = 0
        self.last_print_flag = 0
        self.print_counter = 0

        self.osc_buffers = OscBuffers()
        self.windows = Windows()
        self.sinc_interpolator = SincInterpolator[4, 14]()
        self.messenger_manager = MessengerManager()

struct MMMWorld(Movable, Copyable):
    """The MMMWorld struct holds global audio processing parameters and state.

    In pretty much all usage, don't edit this struct.
    """
    var sample_rate: Float64
    var environment_ptr: Optional[UnsafePointer[mut=True, Environment, MutUntrackedOrigin]]

    def windows(self) -> ref[self.environment_ptr.value()[].windows] Windows:
        """Returns a reference to the Windows struct for accessing predefined windows.

        Returns:
            A reference to the Windows struct.
        """
        return self.environment_ptr.value()[].windows

    def sinc_interpolator(self) -> ref[self.environment_ptr.value()[].sinc_interpolator] SincInterpolator[4, 14]:
        """Returns a reference to the SincInterpolator struct for performing sinc interpolation.

        Returns:
            A reference to the SincInterpolator struct.
        """
        return self.environment_ptr.value()[].sinc_interpolator

    def osc_buffers(self) -> ref[self.environment_ptr.value()[].osc_buffers] OscBuffers:
        """Returns a reference to the OscBuffers struct for accessing oscillator buffers.

        Returns:
            A reference to the OscBuffers struct.
        """
        return self.environment_ptr.value()[].osc_buffers

    def messenger_manager(self) -> ref[self.environment_ptr.value()[].messenger_manager] MessengerManager:
        """Returns a reference to the MessengerManager struct for managing messages.

        Returns:
            A reference to the MessengerManager struct.
        """
        return self.environment_ptr.value()[].messenger_manager

    def __init__(out self, sample_rate: Float64,
        environment_ptr: Optional[UnsafePointer[mut=True, Environment, MutUntrackedOrigin]] = None,
    ):
        """Initializes the MMMWorld struct.

        Args:
            sample_rate: The audio sample rate.
            environment_ptr: A pointer to the Environment struct, which holds information about the current audio block and input buffers.
        """
        
        self.sample_rate = sample_rate
        self.environment_ptr = environment_ptr

        print("MMMWorld initialized with sample rate:", self.sample_rate)
        if self.environment_ptr != None:
            print("Environment pointer is set.")
        else:
            print("Environment pointer is not set.")


    def mouse_x(self) -> Float64:
        """Returns the current mouse x position as a value between 0.0 and 1.0.
        
        Returns:
            The current mouse x position as a value between 0.0 and 1.0.
        """
        if self.environment_ptr:
            return self.environment_ptr.value()[].mouse_x
        
        print("Warning: Environment pointer is None. Returning default mouse_x value of 0.0.")
        return 0.0

    def mouse_y(self) -> Float64:
        """Returns the current mouse y position as a value between 0.0 and 1.0.
        
        Returns:
            The current mouse y position as a value between 0.0 and 1.0.
        """
        if self.environment_ptr:
            return self.environment_ptr.value()[].mouse_y
        
        print("Warning: Environment pointer is None. Returning default mouse_y value of 0.0.")
        return 0.0

    def top_of_block(self) -> Bool:
        """Returns true if the current sample is the first sample of the audio block.
        
        Returns:
            True if the current sample is the first sample of the audio block, false otherwise.
        """
        if self.environment_ptr:
            return self.environment_ptr.value()[].top_of_block

        print("Warning: Environment pointer is None. Returning default top_of_block value of False.")
        return False
    
    def block_state(self) -> Int:
        """Returns the block state.
        
        Returns:
            An integer that increments by 1 at the start of each audio block. Resets to 0 after reaching 2^31 - 1.
        """
        if self.environment_ptr:
            return self.environment_ptr.value()[].block_state

        print("Warning: Environment pointer is None. Returning default block_state value of 0.")
        return 0

    def num_in_chans(self) -> Int:
        """Returns the number of input channels.
        
        Returns:
            The number of input channels.
        """
        if self.environment_ptr:
            return self.environment_ptr.value()[].num_in_chans

        print("Warning: Environment pointer is None. Returning default num_in_chans value of 0.")
        return 0

    def num_out_chans(self) -> Int:
        """Returns the number of output channels.
        
        Returns:
            The number of output channels.
        """

        if self.environment_ptr:
            return self.environment_ptr.value()[].num_out_chans

        print("Warning: Environment pointer is None. Returning default num_out_chans value of 0.")
        return 0

    def sound_in(self, chan: Int) -> Float64:
        """Returns the input sample value for a given channel.

        Args:
            chan: The input channel to read from. Must be less than num_in_chans.
        
        Returns:
            The input sample value for the given channel.
        """

        if self.environment_ptr:
            return self.environment_ptr.value()[].sound_in[chan]

        print("Warning: Environment pointer is None. Returning default sound_in value of 0.0.")
        return 0.0

    @always_inline
    def print[*Ts: Writable](self, *values: *Ts, n_blocks: UInt16 = 10, sep: StringSlice[StaticConstantOrigin] = " ", end: StringSlice[StaticConstantOrigin] = "\n") -> None:
        """Print values to the console at the top of the audio block every n_blocks.

        Parameters:
            Ts: Types of the values to print. Can be of any type that implements Mojo's `Writable` trait. This parameter is inferred by the values passed to the function. The user doesn't need to specify it.

        Args:
            values: Values to print. Can be of any type that implements Mojo's `Writable` trait. This is a "variadic" argument meaning that the user can pass in any number of values (not as a list, just as comma separated arguments).
            n_blocks: Number of audio blocks between prints. Must be specified using the keyword argument.
            sep: Separator string between values. Must be specified using the keyword argument.
            end: End string to print after all values. Must be specified using the keyword argument.
        """
        
        if self.environment_ptr:
            if self.environment_ptr.value()[].top_of_block and self.environment_ptr.value()[].print_counter % n_blocks == 0:
                comptime for i in range(values.__len__()):
                    print(values[i], end=sep if i < values.__len__() - 1 else end)
        else:
            print("Warning: Environment pointer is None. Cannot print values.")

    def create_subworld(self, times_ov_samp: TimesOversampling = TimesOversampling.none) -> UnsafePointer[MMMWorld, MutUntrackedOrigin]:
        """Create another MMMWorld instance using a different TimesOversampling.

        This is mostly used to create an oversampled subworld with a higher sample rate based on the main world.

        Args:
            times_ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.

        Returns:
            A pointer to the newly created MMMWorld struct.
        """
        new_world = alloc[MMMWorld](1) 
        new_world.init_pointee_move(MMMWorld(
            sample_rate=self.sample_rate * Float64(times_ov_samp.times), 
            environment_ptr = self.environment_ptr
        ))

        return new_world

@fieldwise_init
struct Interp(Equatable, ImplicitlyCopyable):
    """Interpolation types for use in various UGens.

    Specify an interpolation type by typing it explicitly.

    | Interpolation Type | Notes                                       |
    | ------------------ | ------------------------------------------- |
    | Interp.none        |                                             |
    | Interp.linear      |                                             |
    | Interp.quad        |                                             |
    | Interp.cubic       |                                             |
    | Interp.lagrange4   |                                             |
    | Interp.sinc        | Should only be used with oscillators        |
    
    """
    var _value: Int

    comptime none = Interp(0)
    comptime linear = Interp(1)
    comptime quad = Interp(2)
    comptime cubic = Interp(3)
    comptime lagrange4 = Interp(4)
    comptime sinc = Interp(5)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

@fieldwise_init
struct WindowType(Equatable, ImplicitlyCopyable):
    """Window types for predefined windows found in world[].windows.

    Specify a window type by typing it explicitly.

    | Window Type         | 
    | ------------------- |
    | WindowType.none     | 
    | WindowType.rect     | 
    | WindowType.hann     | 
    | WindowType.hamming  | 
    | WindowType.blackman | 
    | WindowType.kaiser   | 
    | WindowType.sine     | 
    | WindowType.tri      | 
    | WindowType.pan2     | 
    | WindowType.gaussian | 
    | WindowType.user_defined |
    """

    var _value: Int

    comptime none = WindowType(0)
    comptime rect = WindowType(1)
    comptime hann = WindowType(2)
    comptime hamming = WindowType(3)
    comptime blackman = WindowType(4)
    comptime kaiser = WindowType(5)
    comptime sine = WindowType(6)
    comptime tri = WindowType(7)
    comptime pan2 = WindowType(8)
    comptime gaussian = WindowType(9)
    comptime user_defined = WindowType(10)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

@fieldwise_init
struct OscType(Equatable, ImplicitlyCopyable, Intable):
    """Oscillator types for selecting waveform types.

    Specify an oscillator type by typing it explicitly.
    For example, to specify a sine, one could use the number `0`, 
    but it is clearer to type `OscType.sine`.

    | Oscillator Type              | Value |
    | ---------------------------- | ----- |
    | OscType.sine                 | 0     |
    | OscType.triangle             | 1     |
    | OscType.saw                  | 2     |
    | OscType.square               | 3     |
    """
    var _value: Int

    comptime sine: OscType = OscType(0)
    comptime triangle: OscType = OscType(1)
    comptime saw: OscType = OscType(2)
    comptime square: OscType = OscType(3)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    @doc_hidden
    def __int__(self) -> Int:
        return self._value

@fieldwise_init
struct TimesOversampling(Equatable, ImplicitlyCopyable):
    var times: Int

    comptime none = TimesOversampling(1)
    comptime x2 = TimesOversampling(2)
    comptime x4 = TimesOversampling(4)
    comptime x8 = TimesOversampling(8)
    comptime x16 = TimesOversampling(16)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self.times == other.times

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    @staticmethod
    def get_freq_mul(world: World, ov_samp: TimesOversampling) -> Float64:
        """Get the frequency multiplier for a given oversampling setting.
        
        Args:
            world: A pointer to the MMMWorld instance, used to access the sample rate.
            ov_samp: A TimesOversampling struct to use for computing the frequency multiplier.
        
        Returns:
            The frequency multiplier corresponding to the oversampling setting.
        """
        return (1.0 /  world[].sample_rate) / Float64(ov_samp.times)