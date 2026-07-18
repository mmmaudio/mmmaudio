from mmm_audio import *
from std.math import exp, sqrt, tan, pi, tanh, ceil, floor

from std.sys import simd_width_of

struct Lag[num_chans: Int = 1](Movable, Copyable):
    """A lag processor that smooths input values over time based on a specified lag time in seconds.

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """

    comptime simd_width = simd_width_of[DType.float64]()
    var sample_rate: Float64
    var lagged: MFloat[Self.num_chans]
    var b1: MFloat[Self.num_chans]
    var lag_time: MFloat[Self.num_chans]
    var input: MFloat[Self.num_chans]

    def __init__(out self, world: World, lag_time: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.02)):
        """Initialize the lag processor with given lag time in seconds.

        Args:
            world: Pointer to the MMMWorld.
            lag_time: SIMD vector specifying lag time in seconds for each channel.
        """
        
        self.sample_rate = world[].sample_rate
        self.lagged = MFloat[Self.num_chans](0.0)
        self.b1 = 0
        self.lag_time = 0
        self.input = MFloat[Self.num_chans](0.0)
        self.set_lag_time(lag_time)

    def __init__(out self, sr: Float64, lag_time: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.02)):
        """Initialize the lag processor with given lag time in seconds.

        Args:
            sr: Sample rate in Hz.
            lag_time: SIMD vector specifying lag time in seconds for each channel.
        """
        
        self.sample_rate = sr
        self.lagged = MFloat[Self.num_chans](0.0)
        self.b1 = 0
        self.lag_time = 0
        self.input = MFloat[Self.num_chans](0.0)
        self.set_lag_time(lag_time)
        
    @always_inline
    def next(mut self, input: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the lag processor.
        
        Args:
            input: Input SIMD vector values.
        
        Returns:
            Output values after applying the lag.
        """

        self.input = input
        self.lagged = self.input + self.b1 * (self.lagged - (self.input))
        self.lagged = sanitize(self.lagged)

        return self.lagged

    @always_inline
    def next(mut self) -> MFloat[Self.num_chans]:
        """Process one sample through the lag processor. This version does not take an input argument and instead uses the last value set in self.input.
        
        Returns:
            Output values after applying the lag.
        """

        self.lagged = self.input + self.b1 * (self.lagged - (self.input))
        self.lagged = sanitize(self.lagged)

        return self.lagged

    @always_inline
    def set_lag_time(mut self, lag: MFloat[Self.num_chans]):
        """Set a new lag time in seconds for each channel.
        
        Args:
            lag: SIMD vector specifying new lag time in seconds for each channel.
        """
        self.lag_time = lag
        self.b1 = exp(-6.907755278982137 / (lag * self.sample_rate))

    
struct Lags[num_lags: Int](Movable, Copyable):
    """A convenience struct for processing a list of lags (which are processed in parallel using SIMD). The number of lags is determined at compile time by the num_lags parameter. The outputs of the lags can be accessed using the [] operator, just like accessing values in a List: `lags[0]`.

    Parameters:
        num_lags: The total number of lags.
    """
    comptime simd_width = simd_width_of[DType.float64]() * 2
    comptime num_simd = Self.num_lags // Self.simd_width + (1 if Self.num_lags % Self.simd_width != 0 else 0)
    var lags : List[Lag[Self.simd_width]]

    def __init__(out self, world: World, lag_time: Float64 = 0.1):
        self.lags = [Lag[Self.simd_width](world, lag_time) for _ in range(Self.num_simd)]

    def __init__(out self, sr: Float64, lag_time: Float64 = 0.1):
        self.lags = [Lag[Self.simd_width](sr, lag_time) for _ in range(Self.num_simd)]

    def next(mut self, vals: Span[MFloat[1], ...]):
        """Process a Span (List or InlineArray) of Floats through the lags.

        Args:
            vals: Input values whose length should match num_lags.
        """
        comptime for i in range(Self.num_simd):
            simd_val = MFloat[Self.simd_width](0.0)
            comptime for j in range(Self.simd_width):
                comptime idx = i * Self.simd_width + j
                comptime if idx < Self.num_lags:
                    simd_val[j] = vals[idx]
            _ = self.lags[i].next(simd_val)

    def next(mut self):
        """Process the lags using the value already stored in the input.
        """
        comptime for i in range(Self.num_simd):
            _ = self.lags[i].next()

    def set_lag_time(mut self, lag: Float64):
        """Set a new lag time in seconds for all lags.

        Args:
            lag: New lag time in seconds.
        """
        for i in range(Self.num_simd):
            self.lags[i].set_lag_time(lag)

    def __getitem__(self, idx: Int) -> Float64:
        simd_index = idx // Self.simd_width
        lane_index = idx % Self.simd_width
        return self.lags[simd_index].lagged[lane_index]

    def __setitem__(mut self, idx: Int, value: Float64):
        simd_index = idx // Self.simd_width
        lane_index = idx % Self.simd_width
        self.lags[simd_index].input[lane_index] = value


struct LagUD[num_chans: Int = 1](Movable, Copyable):
    """A lag processor with separate lag times for rising (up) and falling (down) values.

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """

    var sample_rate: Float64
    var lagged: MFloat[Self.num_chans]
    var b1_up: MFloat[Self.num_chans]
    var b1_down: MFloat[Self.num_chans]
    var lag_up: MFloat[Self.num_chans]
    var lag_down: MFloat[Self.num_chans]
    var input: MFloat[Self.num_chans]

    def __init__(
        out self,
        world: World,
        lag_up: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.1),
        lag_down: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.1),
    ):
        """Initialize the lag processor with separate up/down lag times in seconds.

        Args:
            world: Pointer to the MMMWorld.
            lag_up: SIMD vector specifying lag time in seconds for rising values.
            lag_down: SIMD vector specifying lag time in seconds for falling values.
        """
        self.sample_rate = world[].sample_rate
        self.lagged = MFloat[Self.num_chans](0.0)
        self.b1_up = 0
        self.b1_down = 0
        self.lag_up = 0
        self.lag_down = 0
        self.input = MFloat[Self.num_chans](0.0)
        self.set_lag_times(max(lag_up, 0.001), max(lag_down, 0.001))

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the lag processor.

        Args:
            input: Input SIMD vector values.

        Returns:
            Output values after applying the appropriate lag.
        """
        # Select coefficient based on whether input is greater than current value
        mask = input.gt(self.lagged)
        b1 = mask.select(self.b1_up, self.b1_down)

        self.lagged = input + b1 * (self.lagged - input)
        self.lagged = sanitize(self.lagged)

        return self.lagged

    @always_inline
    def next(mut self) -> MFloat[Self.num_chans]:
        """Process one sample through the lag processor. This version does not take an input argument and instead uses the last value set in self.input.

        Returns:
            Output values after applying the appropriate lag.
        """
        # Select coefficient based on whether input is greater than current value
        mask = self.input.gt(self.lagged)
        b1 = mask.select(self.b1_up, self.b1_down)

        self.lagged = self.input + b1 * (self.lagged - self.input)
        self.lagged = sanitize(self.lagged)

        return self.lagged

    @always_inline
    def set_lag_times(
        mut self,
        lag_up: MFloat[Self.num_chans],
        lag_down: MFloat[Self.num_chans],
    ):
        """Set new lag times in seconds for rising and falling values.

        Args:
            lag_up: SIMD vector specifying lag time in seconds for rising values.
            lag_down: SIMD vector specifying lag time in seconds for falling values.
        """
        self.lag_up = lag_up
        self.lag_down = lag_down
        self.b1_up = exp(-6.907755278982137 / (lag_up * self.sample_rate))
        self.b1_down = exp(-6.907755278982137 / (lag_down * self.sample_rate))

struct LagsUD[num_lags: Int](Movable, Copyable):
    """A convenience struct for processing a list of LagsUD (which are processed in parallel using SIMD). The number of LagsUD is determined at compile time by the num_lags parameter. The outputs of the lags can be accessed using the [] operator, just like accessing values in a List: `lags[0]`.

    Parameters:
        num_lags: The total number of lags.
    """
    comptime simd_width = simd_width_of[DType.float64]() * 2
    comptime num_simd = Self.num_lags // Self.simd_width + (1 if Self.num_lags % Self.simd_width != 0 else 0)
    var lags : List[LagUD[Self.simd_width]]

    def __init__(out self, world: World, lag_up: Float64 = 0.1, lag_down: Float64 = 0.1):
        self.lags = [LagUD[Self.simd_width](world, lag_up, lag_down) for _ in range(Self.num_simd)]

    def next(mut self, vals: Span[MFloat[1], ...]):
        """Process a Span (List or InlineArray) of Floats through the lags.

        Args:
            vals: Input values whose length should match num_lags.
        """
        comptime for i in range(Self.num_simd):
            simd_val = MFloat[Self.simd_width](0.0)
            comptime for j in range(Self.simd_width):
                comptime idx = i * Self.simd_width + j
                comptime if idx < Self.num_lags:
                    simd_val[j] = vals[idx]
            _ = self.lags[i].next(simd_val)

    def next(mut self):
        """Process the lags using the value already stored in the input.
        """
        comptime for i in range(Self.num_simd):
            _ = self.lags[i].next()

    def set_lag_times(mut self, lag_up: Float64, lag_down: Float64):
        """Set new lag times in seconds for all lags.

        Args:
            lag_up: New lag time in seconds for rising values.
            lag_down: New lag time in seconds for falling values.
        """
        for i in range(Self.num_simd):
            self.lags[i].set_lag_times(lag_up, lag_down)

    def __getitem__(self, idx: Int) -> Float64:
        simd_index = idx // Self.simd_width
        lane_index = idx % Self.simd_width
        return self.lags[simd_index].lagged[lane_index]

    def __setitem__(mut self, idx: Int, value: Float64):
        simd_index = idx // Self.simd_width
        lane_index = idx % Self.simd_width
        self.lags[simd_index].input[lane_index] = value

@fieldwise_init
struct FilterType(Equatable, ImplicitlyCopyable):
    """Enumeration of different State Variable Filter modes.

    This makes specifying a filter type more readable. For example,
    to specify a lowpass filter, use `FilterType.lowpass`.

    | Mode          | Value |
    |---------------|-------|
    | lowpass       | 0     |
    | bandpass      | 1     |
    | highpass      | 2     |
    | notch         | 3     |
    | peak          | 4     |
    | bell          | 5     |
    | allpass       | 6     |
    | lowshelf      | 7     |
    | highshelf     | 8     |
    """

    var _value: Int

    comptime lowpass = FilterType(0)
    comptime bandpass = FilterType(1)
    comptime highpass = FilterType(2)
    comptime notch = FilterType(3)
    comptime peak = FilterType(4)
    comptime bell = FilterType(5)
    comptime allpass = FilterType(6)
    comptime lowshelf = FilterType(7)
    comptime highshelf = FilterType(8)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

struct SVF[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """A State Variable Filter struct.

    To use the different modes, see the mode-specific methods: `lpf`, `hpf`, `bpf`, `notch`, `peak`, `bell`, `allpass`, `lowshelf`, and `highshelf`. Each of these methods takes the same parameters: input, frequency, q, and gain_db (for those that use it).

    One can also call the `next` method with a specified `FilterType` to process the input through the desired filter mode.
    
    Implementation from [Andrew Simper](https://cytomic.com/files/dsp/SvfLinearTrapOptimised2.pdf). 
    Translated from Oleg Nesterov's Faust implementation.

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """

    var ic1eq: MFloat[Self.num_chans]  # Internal state 1
    var ic2eq: MFloat[Self.num_chans]  # Internal state 2
    var sample_rate: Float64
    
    def __init__(out self, world: World):
        """Initialize the SVF.
        
        Args:
            world: Pointer to the MMMWorld.
        """
        self.ic1eq = MFloat[Self.num_chans](0.0)
        self.ic2eq = MFloat[Self.num_chans](0.0)
        self.sample_rate = world[].sample_rate

    def reset(mut self):
        """Clears any leftover internal state so the filter starts clean after interruptions or discontinuities in the audio stream.""" 
        self.ic1eq = MFloat[Self.num_chans](0.0)
        self.ic2eq = MFloat[Self.num_chans](0.0)

    @doc_hidden
    @always_inline
    def _compute_coefficients[filter_type: FilterType](self, frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans]) -> Tuple[MFloat[Self.num_chans], MFloat[Self.num_chans], MFloat[Self.num_chans], MFloat[Self.num_chans], MFloat[Self.num_chans]]:
        """Compute filter coefficients based on type and parameters.
        
        Parameters:
            filter_type: The type of filter to compute coefficients for.

        Args:
            frequency: The cutoff/center frequency of the filter.
            q: The resonance of the filter.
            gain_db: The gain in decibels for filters that use it.

        Returns:
            A tuple containing (g, k, mix_a, mix_b, mix_c).
        """
        
        # Compute A (gain factor)
        var A: MFloat[Self.num_chans] = pow(MFloat[Self.num_chans](10.0), gain_db / 40.0)

        # Compute g (frequency warping)
        var base_g = tan(frequency * pi / self.sample_rate)
        var g: MFloat[Self.num_chans]
        comptime if filter_type == FilterType.lowshelf:  # lowshelf
            g = base_g / sqrt(A)
        elif filter_type == FilterType.highshelf:  # highshelf
            g = base_g * sqrt(A)
        else:
            g = base_g
        
        # Compute k (resonance factor)
        var k: MFloat[Self.num_chans]
        comptime if filter_type == FilterType.bell:  # bell
            k = 1.0 / (q * A)
        else:
            k = 1.0 / q
        
        # Get mix coefficients based on filter type
        var mix_coefs = self._get_mix_coefficients[filter_type](k, A)
        
        return (g, k, mix_coefs[0], mix_coefs[1], mix_coefs[2])

    @doc_hidden
    @always_inline
    def _get_mix_coefficients[filter_type: FilterType](self, k: MFloat[Self.num_chans], A: MFloat[Self.num_chans]) -> Tuple[MFloat[Self.num_chans], MFloat[Self.num_chans], MFloat[Self.num_chans]]:
        """Get mixing coefficients for different filter types"""
        
        mc0 = MFloat[Self.num_chans](1.0)
        mc1 = MFloat[Self.num_chans](0.0)
        mc2 = MFloat[Self.num_chans](0.0)

        comptime for i in range(Self.num_chans):
            comptime if filter_type == FilterType.lowpass:    
                mc0[i], mc1[i], mc2[i] = 0.0, 0.0, 1.0
            elif filter_type == FilterType.bandpass:  
                mc0[i], mc1[i], mc2[i] = 0.0, 1.0, 0.0
            elif filter_type == FilterType.highpass:   
                mc0[i], mc1[i], mc2[i] = 1.0, -k[i], -1.0
            elif filter_type == FilterType.peak:   
                mc0[i], mc1[i], mc2[i] = 1.0, -k[i], -2.0
            elif filter_type == FilterType.notch:   
                mc0[i], mc1[i], mc2[i] = 1.0, -k[i], 0.0
            elif filter_type == FilterType.allpass:   
                mc0[i], mc1[i], mc2[i] = 1.0, -2.0*k[i], 0.0
            elif filter_type == FilterType.bell:  
                mc0[i], mc1[i], mc2[i] = 1.0, k[i]*(A[i]*A[i] - 1.0), 0.0
            elif filter_type == FilterType.lowshelf:   
                mc0[i], mc1[i], mc2[i] = 1.0, k[i]*(A[i] - 1.0), A[i]*A[i] - 1.0
            elif filter_type == FilterType.highshelf:    
                mc0[i], mc1[i], mc2[i] = A[i]*A[i], k[i]*(1.0 - A[i])*A[i], 1.0 - A[i]*A[i]
            else:
                mc0[i], mc1[i], mc2[i] = 1.0, 0.0, 0.0  

        return (mc0, mc1, mc2)

    @doc_hidden
    @always_inline
    def next[filter_type: FilterType](mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans] = 0.0) -> MFloat[Self.num_chans]:
        """Process one sample through the SVF filter of the given type.
        
        Parameters:
            filter_type: The type of SVF filter to apply. See `FilterType` struct for options.

        Args:
            input: The next input value to process.
            frequency: The cutoff/center frequency of the filter.
            q: The resonance of the filter.
            gain_db: The gain in decibels for filters that use it.

        Returns:
            The next sample of the filtered output.
        """
        
        var coefs = self._compute_coefficients[filter_type](frequency, q, gain_db)
        var g = coefs[0]
        var k = coefs[1]
        var mix_a = coefs[2]
        var mix_b = coefs[3]
        var mix_c = coefs[4]

        # Compute the tick function
        var denominator = 1.0 + g * (g + k)
        var v1 = (self.ic1eq + g * (input - self.ic2eq)) / denominator
        var v2 = self.ic2eq + g * v1
        
        # Update internal state (2*v1 - ic1eq, 2*v2 - ic2eq)
        self.ic1eq = 2.0 * v1 - self.ic1eq
        self.ic2eq = 2.0 * v2 - self.ic2eq

        self.ic1eq = sanitize(self.ic1eq)
        self.ic2eq = sanitize(self.ic2eq)
        
        # Mix the outputs: mix_a*v0 + mix_b*v1 + mix_c*v2
        var output = mix_a * input + mix_b * v1 + mix_c * v2
        return sanitize(output)
    
    @always_inline
    def lpf(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF lowpass filter. Passes frequencies below the cutoff while attenuating frequencies above it.
        
        Args:
            input: The input signal to process.
            frequency: The cutoff frequency of the lowpass filter.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.lowpass](input, frequency, q)

    @always_inline
    def bpf(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF bandpass filter. Passes a band of frequencies centered at the cutoff while attenuating frequencies above and below.
        
        Args:
            input: The input signal to process.
            frequency: The center frequency of the bandpass filter.
            q: The bandwidth of the filter. Higher numbers == narrower filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.bandpass](input, frequency, q)

    @always_inline
    def hpf(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF highpass filter. Passes frequencies above the cutoff while attenuating frequencies below it.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency of the highpass filter.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.highpass](input, frequency, q)

    @always_inline
    def peak(mut self, input: MFloat[self.num_chans], frequency: MFloat[self.num_chans], q: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """
        Process input through a SVF peak filter. Boosts or cuts a band of frequencies centered at the cutoff by an amount determined by q, leaving frequencies outside the band unaffected.

        Args:
            input: The input signal to process.
            frequency: The center frequency of the peak filter.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.peak](input, frequency, q)

    @always_inline
    def notch(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF notch (band stop) filter. Attenuates a narrow band of frequencies centered at the cutoff while passing all others.

        Args:
            input: The input signal to process.
            frequency: The center frequency of the notch filter.
            q: The resonance of the filter.
        
        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.notch](input, frequency, q)

    @always_inline
    def allpass(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF allpass filter. Passes all frequencies at equal amplitude while shifting their phase relationship around the cutoff frequency.
        
        Args:
            input: The input signal to process.
            frequency: The center frequency of the allpass filter.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.allpass](input, frequency, q)

    @always_inline
    def bell(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF bell (peaking EQ) filter. Boosts or cuts a band of frequencies centered at the cutoff by a specified gain amount, leaving frequencies outside the band unaffected.
        
        Args:
            input: The input signal to process.
            frequency: The center frequency of the bell filter.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.bell](input, frequency, q, gain_db)

    @always_inline
    def lowshelf(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF lowshelf filter. Boosts or cuts all frequencies below the cutoff by a specified gain amount, leaving frequencies above unaffected.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency of the low shelf filter.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.lowshelf](input, frequency, q, gain_db)

    @always_inline
    def highshelf(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process input through a SVF highshelf filter. Boosts or cuts all frequencies above the cutoff by a specified gain amount, leaving frequencies below unaffected.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency of the high shelf filter.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.highshelf](input, frequency, q, gain_db)

struct lpf_LR4[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """A 4th-order [Linkwitz-Riley](https://en.wikipedia.org/wiki/Linkwitz%E2%80%93Riley_filter) lowpass filter.

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """
    var svf1: SVF[Self.num_chans]
    var svf2: SVF[Self.num_chans]
    var q: Float64


    def __init__(out self, world: World):
        """Initialize the 4th-order Linkwitz-Riley lowpass filter.
        
        Args:
            world: Pointer to the MMMWorld.
        """
        self.svf1 = SVF[Self.num_chans](world)
        self.svf2 = SVF[Self.num_chans](world)
        self.q = 1.0 / sqrt(2.0)  # 1/sqrt(2) for Butterworth response

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], frequency: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """A single sample through the 4th order Linkwitz-Riley lowpass filter.
        
        Args:
            input: The input sample to process.
            frequency: The cutoff frequency of the lowpass filter.

        Returns:
            The next sample of the filtered output.
        """
        # First stage
        var cf = self.svf1.lpf(input, frequency, self.q)  # First stage
        # Second stage
        return self.svf2.lpf(cf, frequency, self.q)  # Second stage

    def reset(mut self):
        """Reset the internal state of the 4th-order Linkwitz-Riley lowpass filter."""
        self.svf1.reset()
        self.svf2.reset()

struct OnePole[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """One-pole IIR filter that can be configured as lowpass or highpass. Has three defs: `next`, `lpf`, and `hpf`. The `next` def is the most general, allowing you to specify the filter coefficient directly. The `lpf` and `hpf` defs are convenience methods that calculate the appropriate coefficient based on a given cutoff frequency.

    Parameters:
        num_chans: Number of channels to process in parallel.
    """
    var last_samp: MFloat[Self.num_chans]  # Previous output
    var world: World
    
    def __init__(out self, world: World):
        """Initialize the one-pole filter.

        Args:
            world: Pointer to the MMMWorld.
        """

        self.last_samp = MFloat[Self.num_chans](0.0)
        self.world = world
    
    @doc_hidden
    def next(mut self, input: MFloat[Self.num_chans], coef: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the filter.

        Args:
            input: The input signal to process.
            coef: The filter coefficient.

        Returns:
            The next sample of the filtered output.
        """
        coef2 = clip(coef, -0.999999, 0.999999)
        var output = (1 - abs(coef2)) * input + coef2 * self.last_samp
        self.last_samp = output
        return output

    def lpf(mut self, input: MFloat[Self.num_chans], cutoff_hz: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the one-pole lowpass filter with a given cutoff frequency.

        Args:
            input: The input signal to process.
            cutoff_hz: The cutoff frequency of the lowpass filter.

        Returns:
            The next sample of the filtered output.
        """
        var coef = self.coeff(cutoff_hz)
        return self.next(input, coef)

    def hpf(mut self, input: MFloat[Self.num_chans], cutoff_hz: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the one-pole highpass filter with a given cutoff frequency.

        Args:
            input: The input signal to process.
            cutoff_hz: The cutoff frequency of the highpass filter.

        Returns:
            The next sample of the filtered output.
        """
        return input - self.lpf(input, cutoff_hz)

    @doc_hidden
    def coeff(self, cutoff_hz: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Calculate feedback coefficient from cutoff frequency."""
        return exp(-2.0 * pi * cutoff_hz / self.world[].sample_rate)

    def reset(mut self):
        """Reset the one-pole filter to its initial state."""
        self.last_samp = MFloat[Self.num_chans](0.0)

@doc_hidden
def _time_to_coef[num_chans: Int](time_s: MFloat[num_chans], sample_rate: MFloat[num_chans]) -> MFloat[num_chans]:
    mask0 = time_s.le(0.0)
    val = 1.0 / (time_s * sample_rate)
    mask = val.lt(1.0)
    return mask0.select(1.0, mask.select(val, 1.0))

struct Amplitude[num_chans: Int](Movable, Copyable):
    """An amplitude tracker that smooths the absolute value of an input signal over time based on specified attack and release times.
    
    Parameters:
        num_chans: Number of channels to process in parallel.
    """
    var one_pole: OnePole[Self.num_chans]
    var last_val: MFloat[Self.num_chans]
    var coef_att: MFloat[Self.num_chans]
    var coef_rel: MFloat[Self.num_chans]

    var world: World

    def __init__(out self, world: World, attack_time: MFloat[Self.num_chans] = 0.1, release_time: MFloat[Self.num_chans] = 0.1):
        self.world = world
        self.one_pole = OnePole[Self.num_chans](world)
        self.last_val = MFloat[Self.num_chans](0.0)
        self.coef_att = _time_to_coef(attack_time, self.world[].sample_rate)
        self.coef_rel = _time_to_coef(release_time, self.world[].sample_rate)

    
    def set_params(mut self, attack_time: MFloat[Self.num_chans], release_time: MFloat[Self.num_chans]):
        """Adjust the attack and release time of the Amplitude tracker.

        Args:
            attack_time: Attack time of the Amplitude function.
            release_time: Release time of the Amplitude function.
        """
        
        self.coef_att = _time_to_coef(attack_time, self.world[].sample_rate)
        self.coef_rel = _time_to_coef(release_time, self.world[].sample_rate)
    
    def next(mut self, sample: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the Amplitude tracker.

        Args:
            sample: The input signal to process.

        Returns:
            The next sample of the amplitude-tracked output.
        """

        a_val = abs(sample)
        mask = a_val.gt(self.last_val)
        coef = mask.select(self.coef_att, self.coef_rel)
        self.last_val = self.one_pole.next(a_val, coef)

        return self.last_val

struct Onsets[num_chans: Int = 1](Movable, Copyable):
    """Amplitude-based onset detector. Uses Amplitude instead of an FFT to detect onsets. See SpectralFluxOnsets for an FFT-based onset detector.
    
    Parameters:
        num_chans: Number of channels to process in parallel.
    """
    var amplitude: Amplitude[Self.num_chans]
    var prev_amplitude: MFloat[Self.num_chans]
    var prev_diff: MFloat[Self.num_chans]
    var threshold: MFloat[Self.num_chans]
    var cooldown_samples: Int
    var samples_since_onset: MInt[Self.num_chans]
    var world: World

    def __init__(
        out self,
        world: World,
        attack_time: MFloat[Self.num_chans] = 0.005,
        release_time: MFloat[Self.num_chans] = 0.05,
        threshold: MFloat[Self.num_chans] = 0.1,
        cooldown_time: Float64 = 0.1,
    ):
        """Initialize the onset detector.

        Args:
            world: Pointer to the MMMWorld.
            attack_time: Attack time for amplitude follower (fast for onset detection).
            release_time: Release time for amplitude follower.
            threshold: Amplitude rise threshold to trigger onset.
            cooldown_time: Minimum time between onsets in seconds.
        """
        self.world = world
        self.amplitude = Amplitude[Self.num_chans](world, attack_time, release_time)
        self.prev_amplitude = MFloat[Self.num_chans](0.0)
        self.prev_diff = MFloat[Self.num_chans](0.0)
        self.threshold = threshold
        self.cooldown_samples = Int(world[].sample_rate * cooldown_time)
        self.samples_since_onset = MInt[Self.num_chans](self.cooldown_samples)

    def next(mut self, sample: MFloat[Self.num_chans]) -> MBool[Self.num_chans]:
        """Process one sample and detect onsets.

        Args:
            sample: The input signal to process.

        Returns:
            True if onset detected, False otherwise (per channel).
        """
        var amp = self.amplitude.next(sample)
        
        self.samples_since_onset += 1
        
        var above_threshold = amp.gt(self.threshold)
        var was_below = self.prev_amplitude.le(self.threshold)
        var crossed = above_threshold & was_below
        
        cooldown_passed = self.samples_since_onset.ge(MInt[Self.num_chans](self.cooldown_samples))

        onset = crossed & cooldown_passed

        self.samples_since_onset = onset.select(MInt[Self.num_chans](0), self.samples_since_onset)
        
        self.prev_amplitude = amp
        
        return onset

    def reset(mut self):
        """Reset the onset detector state."""
        self.prev_amplitude = MFloat[Self.num_chans](0.0)
        self.prev_diff = MFloat[Self.num_chans](0.0)
        self.samples_since_onset = MInt[Self.num_chans](self.cooldown_samples)

struct DCTrap[num_chans: Int=1](Movable, Copyable, PolyReset):
    """DC Trap filter.
    
    Implementation from Digital Sound Generation by Beat Frei. The cutoff
    frequency of the highpass filter is fixed to 5 Hz.

    Parameters:
        num_chans: Number of channels to process in parallel.
    """

    var alpha: Float64
    var last_samp: MFloat[Self.num_chans]
    var last_inner: MFloat[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the DC blocker filter.
        
        Args:
            world: Pointer to the MMMWorld.
        """
        self.alpha = 2 * pi * 5.0 / world[].sample_rate  # 5 Hz cutoff frequency
        self.last_samp = MFloat[Self.num_chans](0.0)
        self.last_inner = MFloat[Self.num_chans](0.0)

    def reset(mut self):
        """Reset the DC blocker filter to its initial state."""
        self.last_samp = MFloat[Self.num_chans](0.0)
        self.last_inner = MFloat[Self.num_chans](0.0)

    def next(mut self, input: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the DC blocker filter.
        
        Args:
            input: The input signal to process.

        Returns:
            The next sample of the filtered output.
        """
        self.last_inner = self.last_samp * self.alpha + self.last_inner

        sample = input - self.last_inner
        self.last_samp = sample

        return sample

struct VAOnePole[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """
    One-pole filter based on the Virtual Analog design by 
    Vadim Zavalishin in "The Art of VA Filter Design".
    
    This implementation supports both lowpass and highpass modes.

    Parameters:
        num_chans: Number of channels to process in parallel.
    """

    var last_1: MFloat[Self.num_chans]  # Previous output
    var step_val: Float64
    var nyquist: Float64

    def __init__(out self, world: World):
        """Initialize the VAOnePole filter.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.last_1 = MFloat[Self.num_chans](0.0)
        self.step_val = 1.0 / world[].sample_rate
        self.nyquist = world[].sample_rate * 0.5 - 1e-6

    @always_inline
    def next[filter_type: FilterType = FilterType.lowpass](mut self, input: MFloat[Self.num_chans], freq: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the VA one-pole filter of the specified type.

        Parameters:
            filter_type: The type of filter to apply. Can be `FilterType.lowpass` or `FilterType.highpass`.

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the filter.
        
        Returns:
            The next sample of the filtered output.
        """
        comptime if filter_type == FilterType.lowpass:
            return self.lpf(input, freq)
        elif filter_type == FilterType.highpass:
            return self.hpf(input, freq)
        else:
            print("Unsupported filter type for VAOnePole. Use lowpass or highpass.")
            return input

    @always_inline
    def lpf(mut self, input: MFloat[Self.num_chans], freq: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the VA one-pole lowpass filter.

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the lowpass filter.
        
        Returns:
            The next sample of the filtered output.
        """

        var freq2 = clip(freq, 1e-6, self.nyquist)

        var g =  tan(pi * freq2 * self.step_val)

        var G = g / (1.0 + g)

        var v = (input - self.last_1) * G

        var output = self.last_1 + v
        self.last_1 = sanitize(v + output)
        return sanitize(output)

    @always_inline
    def hpf(mut self, input: MFloat[Self.num_chans], freq: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the VA one-pole highpass filter.

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the highpass filter.
        
        Returns:
            The next sample of the filtered output.
        """
        return input - self.lpf(input, freq)

    def reset(mut self):
        """Clears filter's internal state.""" 
        self.last_1 = MFloat[Self.num_chans](0.0)

struct VAMoogLadder[num_chans: Int = 1, ov_samp: TimesOversampling = TimesOversampling.none](Movable, Copyable, PolyReset):
    """Virtual Analog Moog Ladder Filter.
    
    Implementation based on the Virtual Analog design by Vadim Zavalishin in 
    "The Art of VA Filter Design"

    This implementation supports 4-pole lowpass filtering with optional [oversampler](Downsampler.md).

    Parameters:
        num_chans: Number of channels to process in parallel.
        ov_samp: An [oversampler](MMMWorld.md#struct-timesoversampler) struct to indicate times oversampler.
    """
    var nyquist: Float64
    var step_val: Float64
    var last_1: MFloat[Self.num_chans]
    var last_2: MFloat[Self.num_chans]
    var last_3: MFloat[Self.num_chans]
    var last_4: MFloat[Self.num_chans]
    var downsampler: Downsampler[Self.num_chans, Self.ov_samp]
    var upsampler: Upsampler[Self.num_chans, Self.ov_samp]

    def __init__(out self, world: World):
        """Initialize the VAMoogLadder filter.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.nyquist = world[].sample_rate * 0.5 * Float64(Self.ov_samp.times)
        self.step_val = 1.0 / self.nyquist
        self.last_1 = MFloat[Self.num_chans](0.0)
        self.last_2 = MFloat[Self.num_chans](0.0)
        self.last_3 = MFloat[Self.num_chans](0.0)
        self.last_4 = MFloat[Self.num_chans](0.0)
        self.downsampler = Downsampler[Self.num_chans, Self.ov_samp](world)
        self.upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)

    @doc_hidden
    @always_inline
    def lp4(mut self, sig: MFloat[Self.num_chans], freq: MFloat[Self.num_chans], res: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the 4-pole Moog Ladder lowpass filter.

        Args:
            sig: The input signal to process.
            freq: The cutoff frequency of the lowpass filter.
            res: The resonance of the filter. Values between 0 and 1 are typical, though slightly higher values may work, especially with oversampler. 
        
        Returns:
            The next sample of the filtered output.
        """
        var cf = clip(freq, 0.0, self.nyquist * 0.6)
            
        # k is the feedback coefficient of the entire circuit
        var k = 4.0 * res 

        var compensation = 1.0 + k * Float64(Self.ov_samp.times) * 0.25
        
        var omegaWarp = tan(pi * cf * self.step_val)
        var g = omegaWarp / (1.0 + omegaWarp)
        
        var g4 = g * g * g * g
        var s4 = g * g * g * (self.last_1 * (1 - g)) + g * g * (self.last_2 * (1 - g)) + g * (self.last_3 * (1 - g)) + (self.last_4 * (1 - g))
        
        # internally clips the feedback signal to prevent the filter from blowing up
        mask1: MBool[Self.num_chans] = s4.gt(2.0)
        mask2: MBool[Self.num_chans] = s4.lt(-2.0)

        s4 = mask1.select(
            tanh(s4 - 1.0) + 1.0,
            mask2.select(tanh(s4 + 1.0) - 1.0, s4))

        # input is the incoming signal minus the feedback from the last stage
        var input = (sig - k * s4) / (1.0 + k * g4)

        var v1 = g * (input - self.last_1)
        var lp1 = self.last_1 + v1
        
        var v2 = g * (lp1 - self.last_2)
        var lp2 = self.last_2 + v2
        
        var v3 = g * (lp2 - self.last_3)
        var lp3 = self.last_3 + v3
        
        var v4 = g * (lp3 - self.last_4)
        var lp4 = self.last_4 + v4
        
        self.last_1 = lp1
        self.last_2 = lp2
        self.last_3 = lp3
        self.last_4 = lp4

        return lp4 * compensation
    
    def reset(mut self):
        """Clears filter's internal state.""" 
        self.last_1 = MFloat[Self.num_chans](0.0)
        self.last_2 = MFloat[Self.num_chans](0.0)
        self.last_3 = MFloat[Self.num_chans](0.0)
        self.last_4 = MFloat[Self.num_chans](0.0)

    @always_inline
    def next(mut self, sig: MFloat[Self.num_chans], freq: MFloat[Self.num_chans] = 100, res: MFloat[Self.num_chans] = 0.5) -> MFloat[Self.num_chans]:
        """Process one sample through the Moog Ladder lowpass filter.

        Args:
            sig: The input signal to process.
            freq: The cutoff frequency of the lowpass filter.
            res: The resonance of the filter. Values between 0 and 1 are typical, though slightly higher values may work, especially with oversampler.

        Returns:
            The next sample of the filtered output.
        """
        
        comptime if Self.ov_samp == TimesOversampling.none:
            return self.lp4(sig, freq, res)
        else:
            comptime for i in range(Self.ov_samp.times):
                # upsample the input
                sig2 = self.upsampler.next(sig, i)

                var lp4 = self.lp4(sig2, freq, res)
                comptime if Self.ov_samp == TimesOversampling.none:
                    return lp4
                else:
                    self.downsampler.add_sample(lp4)
            return self.downsampler.get_sample()

struct Reson[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """Resonant filter with lowpass, highpass, and bandpass modes.

    A translation of Julius Smith's Faust implementation of [tf2s (virtual analog) resonant filters](https://github.com/grame-cncm/faustlibraries/blob/6061da8bf2279ae4281333861a3dc6254e9076f9/filters.lib#L2054).
    Copyright (C) 2003-2019 by Julius O. Smith III

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """
    var tf2: tf2[num_chans = Self.num_chans]
    var coeffs: List[MFloat[Self.num_chans]]
    var sample_rate: Float64

    def __init__(out self, world: World):
        """Initialize the Reson filter.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.tf2 = tf2[num_chans = Self.num_chans](world)
        self.coeffs = [MFloat[Self.num_chans](0.0) for _ in range(5)]
        self.sample_rate = world[].sample_rate

    def next[filter_type: FilterType = FilterType.lowpass](mut self, input: MFloat[self.num_chans], freq: MFloat[self.num_chans], q: MFloat[self.num_chans], gain: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Process input through a resonant filter with a give FilterType.

        Parameters:
            filter_type: The type of filter to apply (lowpass, highpass, bandpass).

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the lowpass filter.
            q: The resonance of the filter.
            gain: The output gain (clipped to 0.0-1.0 range).

        Returns:
            The next sample of the filtered output.
        """
        comptime if filter_type == FilterType.lowpass:
            return self.lpf(input, freq, q, gain)
        elif filter_type == FilterType.highpass:
            return self.hpf(input, freq, q, gain)
        elif filter_type == FilterType.bandpass:
            return self.bpf(input, freq, q, gain)
        else:
            print("Unsupported filter type. Returning input unprocessed.")
            return input
        

    @always_inline
    def lpf(mut self, input: MFloat[self.num_chans], freq: MFloat[self.num_chans], q: MFloat[self.num_chans], gain: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Process input through a resonant lowpass filter.

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the lowpass filter.
            q: The resonance of the filter.
            gain: The output gain (clipped to 0.0-1.0 range).

        Returns:
            The next sample of the filtered output.
        """
        var wc = 2*pi*freq
        var a1 = 1/q
        var a0 = 1.0
        var b2 = 0.0
        var b1 = 0.0
        var b0 = clip(gain, 0.0, 1.0)

        b0d, b1d, b2d, a1d, a2d = tf2s[Self.num_chans](b2, b1, b0, a1, a0, wc, self.sample_rate)

        return self.tf2.next(input, b0d, b1d, b2d, a1d, a2d)

    @always_inline
    def hpf(mut self, input: MFloat[self.num_chans], freq: MFloat[self.num_chans], q: MFloat[self.num_chans], gain: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Process input through a resonant highpass filter.

        Args:
            input: The input signal to process.
            freq: The cutoff frequency of the highpass filter.
            q: The resonance of the filter.
            gain: The output gain (clipped to 0.0-1.0 range).

        Returns:
            The next sample of the filtered output.
        """

        return gain*input - self.lpf(input, freq, q, gain)

    @always_inline
    def bpf(mut self, input: MFloat[self.num_chans], freq: MFloat[self.num_chans], q: MFloat[self.num_chans], gain: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Process input through a resonant bandpass filter.

        Args:
            input: The input signal to process.
            freq: The center frequency of the bandpass filter.
            q: The resonance of the filter.
            gain: The output gain (clipped to 0.0-1.0 range).

        Returns:
            The next sample of the filtered output.
        """
        var wc = 2*pi*freq
        var a1 = 1/q
        var a0 = 1.0
        var b2 = 0.0
        var b1 = clip(gain, 0.0, 1.0)
        var b0 = 0.0

        b0d, b1d, b2d, a1d, a2d = tf2s[Self.num_chans](b2, b1, b0, a1, a0, wc, self.sample_rate)

        return self.tf2.next(input, b0d, b1d, b2d, a1d, a2d)

    def reset(mut self):
        """Reset the internal state of the Reson filter."""
        self.tf2.reset()

@doc_hidden
struct FIR[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """Finite Impulse Response (FIR) filter implementation.

    A translation of Julius Smith's Faust implementation of digital filters.
    Copyright (C) 2003-2019 by Julius O. Smith III

    Parameters:
        num_chans: The number of SIMD channels to process.
    """

    var buffer: List[MFloat[Self.num_chans]]
    var index: Int

    def __init__(out self, world: World, num_coeffs: Int):
        """Initialize the FIR.

        Args:
            world: Pointer to the MMMWorld.
            num_coeffs: The number of filter coefficients.
        """
        self.buffer = [MFloat[Self.num_chans](0.0) for _ in range(num_coeffs)]
        self.index = 0

    @always_inline
    def next(mut self: FIR, input: MFloat[self.num_chans], *coeffs: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Compute the next output sample of the FIR filter.

        Args:
            input: The input signal to process.
            coeffs: The filter coefficients.

        Returns:
            The next sample of the filtered output.
        """
        self.buffer[self.index] = input
        var output = MFloat[self.num_chans](0.0)
        for i in range(len(coeffs)):
            output += coeffs[i] * self.buffer[(self.index - i + len(self.buffer)) % len(self.buffer)]
        self.index = (self.index + 1) % len(self.buffer)
        return output

    def reset(mut self):
        """Reset the FIR filter to its initial state."""
        self.buffer = [MFloat[Self.num_chans](0.0) for _ in range(len(self.buffer))]
        self.index = 0

@doc_hidden
struct IIR[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """Infinite Impulse Response (IIR) filter implementation.

    A translation of Julius Smith's Faust implementation of digital filters.
    Copyright (C) 2003-2019 by Julius O. Smith III

    Parameters:
        num_chans: The number of SIMD channels to process.
    """
    var fir1: FIR[Self.num_chans]
    var fir2: FIR[Self.num_chans]
    var fb: MFloat[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the IIR.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.fir1 = FIR[Self.num_chans](world,2)
        self.fir2 = FIR[Self.num_chans](world,3)
        self.fb = MFloat[Self.num_chans](0.0)

    @always_inline
    def next(mut self: IIR, input: MFloat[self.num_chans], *coeffs: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Compute the next output sample of the IIR filter.
        
        Args:
            input: The input signal to process.
            coeffs: The filter coefficients.

        Returns:
            The next sample of the filtered output.
        """
        var temp = input - self.fb
        # calls the parallelized fir function, indicating the size of the simd vector to use
        var output1 = self.fir1.next(temp, coeffs[3], coeffs[4])
        var output2 = self.fir2.next(temp, coeffs[0], coeffs[1], coeffs[2])
        self.fb = output1
        return output2

    def reset(mut self):
        """Reset the IIR filter to its initial state."""
        self.fir1.reset()
        self.fir2.reset()
        self.fb = MFloat[Self.num_chans](0.0)

@doc_hidden
struct tf2[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """Second-order transfer function filter implementation.

    A translation of Julius Smith's Faust implementation of digital filters.
    Copyright (C) 2003-2019 by Julius O. Smith III

    Parameters:
        num_chans: The number of SIMD channels to process.
    """
    var iir: IIR[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the tf2 filter.

        Args:
            world: Pointer to the MMMWorld.
        """
        self.iir = IIR[Self.num_chans](world)

    @always_inline
    def next(mut self: tf2, input: MFloat[self.num_chans], b0d: MFloat[self.num_chans], b1d: MFloat[self.num_chans], b2d: MFloat[self.num_chans], a1d: MFloat[self.num_chans], a2d: MFloat[self.num_chans]) -> MFloat[self.num_chans]:
        """Process one sample through the second-order transfer function filter.

        Args:
            input: The input signal to process.
            b0d: The b0 coefficient.
            b1d: The b1 coefficient.
            b2d: The b2 coefficient.
            a1d: The a1 coefficient.
            a2d: The a2 coefficient.

        Returns:
            The next sample of the filtered output.
        """
        return self.iir.next(input, b0d, b1d, b2d, a1d, a2d)
    
    def reset(mut self):
        """Reset the tf2 filter to its initial state."""
        self.iir.reset()

@doc_hidden
@always_inline
def tf2s[num_chans: Int = 1](b2: MFloat[num_chans], b1: MFloat[num_chans], b0: MFloat[num_chans], a1: MFloat[num_chans], a0: MFloat[num_chans], w1: MFloat[num_chans], sample_rate: Float64) -> Tuple[MFloat[num_chans], MFloat[num_chans], MFloat[num_chans], MFloat[num_chans], MFloat[num_chans]]:
    var c   = 1/tan(w1*0.5/sample_rate) # bilinear-transform scale-factor
    var csq = c*c
    var d   = a0 + a1 * c + csq
    var b0d = (b0 + b1 * c + b2 * csq)/d
    var b1d = 2 * (b0 - b2 * csq)/d
    var b2d = (b0 - b1 * c + b2 * csq)/d
    var a1d = 2 * (a0 - csq)/d
    var a2d = (a0 - a1*c + csq)/d

    return (b0d, b1d, b2d, a1d, a2d)

struct Biquad[num_chans: Int = 1](Movable, Copyable, PolyReset):
    """A Biquad filter struct.

    To use the different modes, see the mode-specific methods.
    
    Based on [Robert Bristow-Johnson's Audio EQ Cookbook](https://webaudio.github.io/Audio-EQ-Cookbook/audio-eq-cookbook.html). 

    Parameters:
        num_chans: Number of SIMD channels to process in parallel.
    """

    # Transposed Direct Form II state
    var s1: MFloat[Self.num_chans]
    var s2: MFloat[Self.num_chans]
    var nyquist: Float64

    var sample_rate: Float64
    
    def __init__(out self, world: World):
        """Initialize the Biquad.
        
        Args:
            world: Pointer to the MMMWorld.
        """
        self.s1 = MFloat[Self.num_chans](0.0)
        self.s2 = MFloat[Self.num_chans](0.0)
        self.sample_rate = world[].sample_rate
        self.nyquist = world[].sample_rate * 0.5

    def reset(mut self):
        """Clears any leftover internal state so the filter starts clean after interruptions or discontinuities in the audio stream.""" 
        self.s1 = MFloat[Self.num_chans](0.0)
        self.s2 = MFloat[Self.num_chans](0.0)

    @doc_hidden
    @always_inline
    def _compute_coefficients[filter_type: FilterType](self, frequency: MFloat[Self.num_chans], q: MFloat[Self.num_chans], gain_db: MFloat[Self.num_chans]) -> Tuple[
        MFloat[Self.num_chans], #b0
        MFloat[Self.num_chans], #b1
        MFloat[Self.num_chans], #b2
        MFloat[Self.num_chans], #a1
        MFloat[Self.num_chans]  #a2
        ]:
        """Compute filter coefficients based on type and parameters.
        
        Parameters:
            filter_type: The type of filter to compute coefficients for.

        Args:
            frequency: The cutoff/center frequency of the filter.
            q: The resonance of the filter.
            gain_db: The gain in decibels for filters that use it.

        Returns:
            A tuple containing (b0, b1, b2, a1, a2).
        """
        
        # Compute A (gain factor)
        var A: MFloat[Self.num_chans] = pow(MFloat[Self.num_chans](10.0), gain_db / 40.0)

        # Compute normalized digital frequency
        var w0: MFloat[Self.num_chans] = 2.0 * pi * frequency / self.sample_rate
        var cosw0: MFloat[Self.num_chans] = cos(w0)
        var sinw0: MFloat[Self.num_chans] = sin(w0)
        
        # Alpha term
        var alpha: MFloat[Self.num_chans] = sinw0 / (2.0 * q)

        # Unnormalized coefficients
        var b0 = MFloat[Self.num_chans](0.0)
        var b1 = MFloat[Self.num_chans](0.0)
        var b2 = MFloat[Self.num_chans](0.0)
        var a0 = MFloat[Self.num_chans](0.0)
        var a1 = MFloat[Self.num_chans](0.0)
        var a2 = MFloat[Self.num_chans](0.0)

        comptime if filter_type == FilterType.lowpass:
            b1 = (1.0 - cosw0) # doing this first saves some calculations
            b0 = b1 * 0.5
            b2 = b0
            a0 = 1 + alpha
            a1 = -2.0 * cosw0
            a2 = 1 - alpha
        elif filter_type == FilterType.highpass:
            b0 = (1.0 + cosw0) * 0.5
            b1 = -(1.0 + cosw0)
            b2 = b0
            a0 = 1 + alpha
            a1 = -2.0 * cosw0
            a2 = 1 - alpha
        elif filter_type == FilterType.bandpass:
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
            a0 = 1 + alpha
            a1 = -2.0 * cosw0
            a2 = 1 - alpha
        elif filter_type == FilterType.notch:
            b0 = 1.0
            b1 = -2.0 * cosw0
            b2 = 1.0
            a0 = 1.0 + alpha
            a1 = b1
            a2 = 1 - alpha
        elif filter_type == FilterType.allpass:
            b0 = 1.0 - alpha
            b1 = -2.0 * cosw0
            b2 = 1.0 + alpha
            a0 = b2
            a1 = b1
            a2 = b0
        elif filter_type == FilterType.bell or filter_type == FilterType.peak:
            b0 = 1.0 + (alpha * A)
            b1 = -2.0 * cosw0
            b2 = 1.0 - (alpha * A)
            a0 = 1.0 + (alpha / A)
            a1 = -2.0 * cosw0
            a2 = 1.0 - (alpha / A)
        elif filter_type == FilterType.lowshelf:
            var Ap1 = A + 1.0
            var Am1 = A - 1.0
            var twoSqrtA = 2.0 * sqrt(A) * alpha
            
            b0 =  A * (Ap1 - Am1 * cosw0 + twoSqrtA)
            b1 =  2.0 * A * (Am1 - Ap1 * cosw0)
            b2 =  A * (Ap1 - Am1 * cosw0 - twoSqrtA)
            a0 =  (Ap1 + Am1 * cosw0 + twoSqrtA)
            a1 =  -2.0 * (Am1 + Ap1 * cosw0)
            a2 =  (Ap1 + Am1 * cosw0 - twoSqrtA)
        elif filter_type == FilterType.highshelf:
            var Ap1 = A + 1.0
            var Am1 = A - 1.0
            var twoSqrtA = 2.0 * sqrt(A) * alpha
            
            b0 = A * (Ap1 + Am1 * cosw0 + twoSqrtA)
            b1 = -2.0 * A * (Am1 + Ap1 * cosw0)
            b2 = A * (Ap1 + Am1 * cosw0 - twoSqrtA)
            a0 = (Ap1 - Am1 * cosw0 + twoSqrtA)
            a1 = 2.0 * (Am1 - Ap1 * cosw0)
            a2 = (Ap1 - Am1 * cosw0 - twoSqrtA)

        # Normalize so a0 == 1
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0
        
        return (b0, b1, b2, a1, a2)

    @doc_hidden
    @always_inline
    def next[filter_type: FilterType](
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans],
        gain_db: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.0)
    ) -> MFloat[Self.num_chans]:
        """Process one sample through the biquad filter of the given type.

        Parameters:
            filter_type: The type of biquad filter to process through. See `FilterType` struct for options.

        Args:
            input: The next input value to process.
            frequency: The cutoff/center frequency of the filter.
            q: The resonance of the filter.
            gain_db: The gain in decibels for filters that use it.

        Returns:
            The next sample of the filtered output.
        """
        f2 = clip(frequency, 0.0, self.nyquist)
        var q2 = max(q, 1e-6)
        var coefs = self._compute_coefficients[filter_type](f2, q2, gain_db)
        var b0 = coefs[0]
        var b1 = coefs[1]
        var b2 = coefs[2]
        var a1 = coefs[3]
        var a2 = coefs[4]

        var y = sanitize(b0 * input + self.s1)
        self.s1 = sanitize(b1 * input - a1 * y + self.s2)
        self.s2 = sanitize(b2 * input - a2 * y)
        return y
    
    @always_inline
    def lpf(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad lowpass filter. Passes frequencies below the cutoff while attenuating frequencies above it.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.lowpass](input, frequency, q)

    @always_inline
    def hpf(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad highpass filter. Passes frequencies above the cutoff while attenuating frequencies below it.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.highpass](input, frequency, q)

    @always_inline
    def bpf(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad bandpass filter. Passes a band of frequencies centered at the cutoff while attenuating frequencies above and below.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The bandwidth of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.bandpass](input, frequency, q)

    @always_inline
    def notch(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad notch (band stop) filter. Attenuates a narrow band of frequencies centered at the cutoff while passing all others.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.notch](input, frequency, q)

    @always_inline
    def allpass(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad allpass filter. Passes all frequencies at equal amplitude while shifting their phase relationship around the cutoff frequency.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.allpass](input, frequency, q)

    @always_inline
    def bell(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans],
        gain_db: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad bell (peaking EQ) filter. Boosts or cuts a band of frequencies centered at the cutoff by a specified gain amount, leaving frequencies outside the band unaffected.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.bell](input, frequency, q, gain_db)

    @always_inline
    def lowshelf(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans],
        gain_db: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad lowshelf filter. Boosts or cuts all frequencies below the cutoff by a specified gain amount, leaving frequencies above unaffected.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.lowshelf](input, frequency, q, gain_db)

    @always_inline
    def highshelf(
        mut self,
        input: MFloat[Self.num_chans],
        frequency: MFloat[Self.num_chans],
        q: MFloat[Self.num_chans],
        gain_db: MFloat[Self.num_chans]
    ) -> MFloat[Self.num_chans]:
        """
        Process input through a biquad highshelf filter. Boosts or cuts all frequencies above the cutoff by a specified gain amount, leaving frequencies below unaffected.

        Args:
            input: The input signal to process.
            frequency: The cutoff frequency in Hz.
            q: The resonance of the filter.
            gain_db: The amount to boost/cut around the cutoff.

        Returns:
            The next sample of the filtered output.
        """
        return self.next[FilterType.highshelf](input, frequency, q, gain_db)

struct MedianFilter(Movable, Copyable, PolyReset):
    """A simple median filter for scalar samples.

    The window size is forced to be odd and at least 1.
    """
    var size: Int
    var buffer: List[Float64]
    var sorted: List[Float64]
    var index: Int
    var filled_count: Int

    def __init__(out self, size: Int = 5):
        self.size = size
        if self.size < 1:
            self.size = 1
        if (self.size % 2) == 0:
            self.size += 1
        self.buffer = List[Float64](length=self.size, fill=0.0)
        self.sorted = List[Float64](length=self.size, fill=0.0)
        self.index = 0
        self.filled_count = 0

    def process_sample(mut self, value: Float64) -> Float64:
        self.buffer[self.index] = value
        self.index = (self.index + 1) % self.size
        if self.filled_count < self.size:
            self.filled_count += 1

        for i in range(self.filled_count):
            self.sorted[i] = self.buffer[i]

        for i in range(1, self.filled_count):
            var key = self.sorted[i]
            var j = i - 1
            while j >= 0 and self.sorted[j] > key:
                self.sorted[j + 1] = self.sorted[j]
                j -= 1
            self.sorted[j + 1] = key

        return self.sorted[self.filled_count // 2]

    def reset(mut self):
        """Reset the median filter to its initial state."""
        for i in range(self.size):
            self.buffer[i] = 0.0
            self.sorted[i] = 0.0
        self.index = 0
        self.filled_count = 0