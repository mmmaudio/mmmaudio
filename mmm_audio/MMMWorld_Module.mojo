from std.python import PythonObject
import std.time
from std.collections import Set
from mmm_audio import *

struct MMMWorld(Movable, Copyable):
    """The MMMWorld struct holds global audio processing parameters and state.

    In pretty much all usage, don't edit this struct.
    """
    var sample_rate: Float64
    var block_size: Int
    var osc_buffers: Optional[UnsafePointer[mut=True, OscBuffers, MutExternalOrigin]]
    # windows
    var windows: Optional[UnsafePointer[mut=True, Windows, MutExternalOrigin]]
    var messenger_manager: Optional[UnsafePointer[mut=True, MessengerManager, MutExternalOrigin]]
    
    var num_in_chans: Int
    var num_out_chans: Int

    var sound_in: List[Float64]

    var screen_dims: List[Float64]  

    var mouse_x: Float64
    var mouse_y: Float64

    var block_state: Int
    var top_of_block: Bool


    var sinc_interpolator: SincInterpolator[4, 14]

    var last_print_time: Float64
    var print_flag: Int
    var last_print_flag: Int

    var print_counter: UInt16

    def __init__(out self, sample_rate: Float64, 
        block_size: Int = 128, 
        num_in_chans: Int = 2, 
        num_out_chans: Int = 2, 
        osc_buffers_ptr: Optional[UnsafePointer[OscBuffers, MutExternalOrigin]] = None, 
        windows_ptr: Optional[UnsafePointer[Windows, MutExternalOrigin]] = None, 
        messenger_manager_ptr: Optional[UnsafePointer[MessengerManager, MutExternalOrigin]] = None
    ):
        """Initializes the MMMWorld struct.

        Args:
            sample_rate: The audio sample rate.
            block_size: The audio block size.
            num_in_chans: The number of input channels.
            num_out_chans: The number of output channels.
            osc_buffers_ptr: A pointer to the OscBuffers struct, which holds precomputed oscillator waveforms.
            windows_ptr: A pointer to the Windows struct, which holds precomputed window functions.
            messenger_manager_ptr: A pointer to the MessengerManager struct.
        """
        
        self.sample_rate = sample_rate
        self.block_size = block_size
        self.top_of_block = False
        self.num_in_chans = num_in_chans
        self.num_out_chans = num_out_chans
        self.sound_in = List[Float64]()
        for _ in range(self.num_in_chans):
            self.sound_in.append(0.0)  # Initialize input buffer with zeros

        self.osc_buffers = osc_buffers_ptr
        self.windows = windows_ptr

        self.mouse_x = 0.0
        self.mouse_y = 0.0
        self.screen_dims = [1000.0, 1000.0]

        self.block_state = 0

        self.last_print_time = 0.0
        self.print_flag = 0
        self.last_print_flag = 0

        self.messenger_manager = messenger_manager_ptr

        self.print_counter = 0

        self.sinc_interpolator = SincInterpolator[4,14]()

        print("MMMWorld initialized with sample rate:", self.sample_rate, "and block size:", self.block_size)

    def set_channel_count(mut self, num_in_chans: Int, num_out_chans: Int):
        """Sets the number of input and output channels.

        Args:
            num_in_chans: The number of input channels.
            num_out_chans: The number of output channels.
        """
        self.num_in_chans = num_in_chans
        self.num_out_chans = num_out_chans
        self.sound_in = List[Float64]()
        for _ in range(self.num_in_chans):
            self.sound_in.append(0.0)  # Reinitialize input buffer with zeros

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
        
        if self.top_of_block:
            if self.print_counter % n_blocks == 0:
                comptime for i in range(values.__len__()):
                    print(values[i], end=sep if i < values.__len__() - 1 else end)

# Enum-like structs for selecting settings
# ========================================
# once Mojo has enums, these will probably be converted to enums

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
        """Get the frequency multiplier for a given oversampling setting."""
        return (1.0 /  world[].sample_rate) / Float64(ov_samp.times)