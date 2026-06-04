from mmm_audio import *

struct WhiteNoise[num_chans: Int = 1](Copyable, Movable):
    """Generate white noise samples.
    
    Parameters:
        num_chans: Number of SIMD channels.
    """
    def __init__(out self):
        """Initialize the WhiteNoise struct."""
        pass  # No initialization needed for white noise

    def next(self, gain: MFloat[Self.num_chans] = MFloat[Self.num_chans](1.0)) -> MFloat[Self.num_chans]:
        """Generate the next white noise sample.

        Args:
            gain: Amplitude scaling factor.
        
        Returns:
            A random value between -gain and gain.
        """
        # Generate random value between -1 and 1, then scale by gain
        return rrand[Self.num_chans](-1.0, 1.0) * gain

struct PinkNoise[num_chans: Int = 1](Copyable, Movable):
    """Generate pink noise samples.

    Uses the [Voss-McCartney algorithm](https://www.firstpr.com.au/dsp/pink-noise/#Voss-McCartney).

    Parameters:
        num_chans: Number of SIMD channels.
    """

    var b0: MFloat[Self.num_chans]
    var b1: MFloat[Self.num_chans]
    var b2: MFloat[Self.num_chans]
    var b3: MFloat[Self.num_chans]
    var b4: MFloat[Self.num_chans]
    var b5: MFloat[Self.num_chans]
    var b6: MFloat[Self.num_chans]

    def __init__(out self):
        """Initialize the PinkNoise struct."""
        self.b0 = MFloat[Self.num_chans](0.0)
        self.b1 = MFloat[Self.num_chans](0.0)
        self.b2 = MFloat[Self.num_chans](0.0)
        self.b3 = MFloat[Self.num_chans](0.0)
        self.b4 = MFloat[Self.num_chans](0.0)
        self.b5 = MFloat[Self.num_chans](0.0)
        self.b6 = MFloat[Self.num_chans](0.0)

    def next(mut self, gain: MFloat[Self.num_chans] = MFloat[Self.num_chans](1.0)) -> MFloat[Self.num_chans]:
        """Generate the next pink noise sample.

        Args:
            gain: Amplitude scaling factor.

        Returns:
            The next pink noise sample scaled by gain.
        """
        # Generate white noise SIMD
        var white = rrand[Self.num_chans](-1.0, 1.0)

        # Filter white noise to get pink noise (Voss-McCartney algorithm)
        self.b0 = self.b0 * 0.99886 + white * 0.0555179
        self.b1 = self.b1 * 0.99332 + white * 0.0750759
        self.b2 = self.b2 * 0.96900 + white * 0.1538520
        self.b3 = self.b3 * 0.86650 + white * 0.3104856
        self.b4 = self.b4 * 0.55000 + white * 0.5329522
        self.b5 = self.b5 * -0.7616 - white * 0.0168980

        # Sum the filtered noise sources
        var pink = self.b0 + self.b1 + self.b2 + self.b3 + self.b4 + self.b5 + self.b6 + white * 0.5362

        # Scale and return the result
        return pink * (gain * 0.125)

struct BrownNoise[num_chans: Int = 1](Copyable, Movable):
    """Generate brown noise samples.

    Parameters:
        num_chans: Number of SIMD channels.
    """

    var last_output: MFloat[Self.num_chans]

    def __init__(out self):
        """Initialize the BrownNoise struct."""
        self.last_output = MFloat[Self.num_chans](0.0)

    def next(mut self, gain: MFloat[Self.num_chans] = MFloat[Self.num_chans](1.0)) -> MFloat[Self.num_chans]:
        """Generate the next brown noise sample.

        Args:
            gain: Amplitude scaling factor.

        Returns:
            The next brown noise sample scaled by gain.
        """
        # Generate white noise SIMD
        var white = rrand[Self.num_chans](-1.0, 1.0)

        # Integrate white noise to get brown noise
        self.last_output += (white - self.last_output) * 0.02
        return self.last_output * gain

struct TExpRand[num_chans: Int = 1](Copyable, Movable):
    """Generate exponentially distributed random value upon receiving a trigger.

    Parameters:
        num_chans: Number of SIMD channels.
    """

    var stored_output: MFloat[Self.num_chans]
    var last_trig: MBool[Self.num_chans]
    var is_initialized: Bool

    def __init__(out self):
        """Initialize the TExpRand struct."""
        self.stored_output = MFloat[Self.num_chans](0.0)
        self.last_trig = MBool[Self.num_chans](fill=False)
        self.is_initialized = False

    def next(mut self, min: MFloat[Self.num_chans], max: MFloat[Self.num_chans], trig: MBool[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Output the exponentially distributed random value.

        The value is repeated until a new trigger is received, at which point a new value is generated.
        And that new value is repeated until the next trigger, and so on.
        
        Args:
            min: Minimum value for the random value.
            max: Maximum value for the random value.
            trig: Trigger to generate a new value.

        Returns:
            The exponentially distributed random value.
        """
        
        if not self.is_initialized: 
            comptime for i in range(Self.num_chans):
                self.stored_output[i] = exprand(min[i], max[i])
            self.is_initialized = True
            return self.stored_output
        
        rising_edge: MBool[Self.num_chans] = trig & ~self.last_trig
        comptime for i in range(Self.num_chans):
            if rising_edge[i]:
                self.stored_output[i] = exprand(min[i], max[i])
        self.last_trig = trig
        return self.stored_output

struct TRand[num_chans: Int = 1](Copyable, Movable):
     """Generate uniformly distributed random value upon receiving a trigger.

    Parameters:
        num_chans: Number of SIMD channels.
    """

    var stored_output: MFloat[Self.num_chans]
    var last_trig: MBool[Self.num_chans]
    var is_initialized: Bool

    def __init__(out self):
        """Initialize the TRand struct."""
        self.stored_output = MFloat[Self.num_chans](0.0)
        self.last_trig = MBool[Self.num_chans](fill=False)
        self.is_initialized = False

    def next(mut self, min: MFloat[Self.num_chans], max: MFloat[Self.num_chans], trig: MBool[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Output uniformly distributed random value.

        The value is repeated until a new trigger is received, at which point a new value is generated.
        And that new value is repeated until the next trigger, and so on.

        Args:
            min: Minimum value for the random value.
            max: Maximum value for the random value.
            trig: Trigger to generate a new value.

        Returns:
            The uniformly distributed random value.
        """

        if not self.is_initialized: 
            comptime for i in range(Self.num_chans):
                self.stored_output[i] = random_float64(min[i], max[i])
            self.is_initialized = True
            return self.stored_output

        rising_edge: MBool[Self.num_chans] = trig & ~self.last_trig
        comptime for i in range(Self.num_chans):
            if rising_edge[i]:
                self.stored_output[i] = random_float64(min[i], max[i])
        self.last_trig = trig
        return self.stored_output

struct LFSRNoise[num_chans: Int = 1](Copyable, Movable):
    """Generate noise using a Linear Feedback Shift Register (LFSR).

    Based on [Josiah Sytsma's LFSR implementation](https://www.mjsyts.com/development/lfsr-noise-part-3).
    
    Parameters:
        num_chans: Number of SIMD channels.
    """

    var world:                  World
    var state:                  MInt[Self.num_chans]
    var width:                  MInt[Self.num_chans]
    var mask:                   MInt[Self.num_chans]
    var phase:                  MFloat[Self.num_chans]
    var freq_mul:               Float64
    var rising_bool_detector:   RisingBoolDetector[Self.num_chans]
    var top_freq:               Float64

    def __init__(out self, world: World):
        self.world                = world
        self.freq_mul             = 1.0 / world[].sample_rate
        self.top_freq             = world[].sample_rate / 2.0
        self.state                = MInt[Self.num_chans](1)
        self.phase                = MFloat[Self.num_chans](0.0)
        self.width                = MInt[Self.num_chans](0)
        self.mask                 = MInt[Self.num_chans](0)
        self.rising_bool_detector = RisingBoolDetector[Self.num_chans]()

    def set_oversampling(mut self, times_oversampling: TimesOversampling):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: An [oversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        """
        self.freq_mul = TimesOversampling.get_freq_mul(self.world, times_oversampling)

    @doc_hidden
    @always_inline
    def step(mut self):
        self.state = self.state.eq(0).select(MInt[Self.num_chans](1), self.state)
        var lsb0 = self.state & 1
        var lsb1 = (self.state >> 1) & 1
        var fb   = lsb0 ^ lsb1
        self.state = (self.state >> 1) | (fb << (self.width - 1))
        self.state &= self.mask

    @always_inline
    def next(mut self, freq: MFloat[Self.num_chans] = 1.0, width: MInt[Self.num_chans] = 15, trig: Bool = False) -> MFloat[Self.num_chans]:
        """Generate the next LFSR noise sample.

        Args:
            freq: Frequency at which to step the LFSR in Hz.
            width: Width of the LFSR in bits (3-32).
            trig: Trigger signal to reset state when switching from False to True.

        Returns:
            The next LFSR noise sample.
        """
        self.width = clip(width, MInt[Self.num_chans](3), MInt[Self.num_chans](32))
        self.mask = (self.width.eq(32)).select(
            MInt[Self.num_chans](0xFFFFFFFF),
            (MInt[Self.num_chans](1) << self.width) - 1
        )
        var trig_mask = MBool[Self.num_chans](fill=trig)
        var resets = self.rising_bool_detector.next(trig_mask)
        var clamped_freq = clip(freq, MFloat[Self.num_chans](0.0), MFloat[Self.num_chans](self.top_freq))
        var incremented_phase = self.phase + (clamped_freq * self.freq_mul)
        var wrapped: MBool[Self.num_chans] = incremented_phase.ge(1.0)
        var old_state = self.state
        self.step()
        self.state = wrapped.select(self.state, old_state)
        self.phase = wrapped.select(incremented_phase - 1.0, incremented_phase)
        self.state = resets.select(MInt[Self.num_chans](1), self.state)
        self.phase = resets.select(MFloat[Self.num_chans](0.0), self.phase)
        var out = (self.state & 1).cast[DType.float64]() * 2.0 - 1.0
        return out