from std.math import log2, floor, pi, iota
from std.random import random_float64, random_ui64
from mmm_audio.constants import *
from mmm_audio.functions import _splitmix64, _GOLDEN64, rrand, exprand, clip
from mmm_audio.BooleanTests import RisingBoolDetector

struct SIMDRand[N: SIMDLength = 1](Copyable, Movable):
    """A xorshift64 generator that advances every SIMD lane in one step.

    `std.random` has no vector generator: `random_float64` and friends return one scalar per
    call and cost about 23ns each, so filling an N lane vector from them costs N calls. This
    keeps one independent xorshift64 stream per lane in a single SIMD register, so a whole
    vector costs roughly 1.7ns however wide it is.

    Unlike [rrand](#rrand) it carries state, so it has to be owned by whatever is generating
    the samples. That is the point: no call into the global generator per sample.

    The generator is fine for audio noise and better than the LCGs common in DSP code, but
    xorshift64 does fail parts of BigCrush. Use `std.random` where randomness quality is
    load bearing, such as dither for mastering.

    Parameters:
        N: Number of SIMD lanes, one independent stream each.
    """

    var state: SIMD[DType.uint64, Self.N]
    """One xorshift64 state word per lane. Never zero, which is the generator's fixed point."""

    def __init__(out self):
        """Seed from the global generator, so separate instances decorrelate.

        Seeding goes through `std.random`, so `seed()` still makes a run reproducible.
        """
        self = Self(random_ui64(0, 0xFFFFFFFFFFFFFFFF))

    def __init__(out self, seed: UInt64):
        """Seed deterministically from one 64-bit value.

        Args:
            seed: The base seed. Lanes are spaced apart from it and mixed, so nearby seeds
                do not produce related streams.
        """
        var s = _splitmix64(
            SIMD[DType.uint64, Self.N](seed) + iota[DType.uint64, Self.N]() * _GOLDEN64
        )
        # xorshift64 is stuck at zero forever, so no lane may start there
        self.state = s.eq(0).select(SIMD[DType.uint64, Self.N](_GOLDEN64), s)

    @always_inline
    def bits(mut self) -> SIMD[DType.uint64, Self.N]:
        """Advance every lane one xorshift64 step.

        Returns:
            A vector of uniformly distributed 64-bit values.
        """
        var x = self.state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        self.state = x
        return x

    @always_inline
    def uniform(mut self) -> MFloat[Self.N]:
        """Draw a vector of uniform values in [0, 1). Inclusive of 0.0, exclusive of 1.0.

        Returns:
            One value per lane.
        """
        # The top 52 bits become the mantissa of a double that already reads 1.0
        return MFloat[Self.N](from_bits=(self.bits() >> 12) | 0x3FF0000000000000) - 1.0

    @always_inline
    def bipolar(mut self) -> MFloat[Self.N]:
        """Draw a vector of uniform values in [-1, 1), the usual range for audio noise. Inclusive of -1.0, exclusive of 1.0.

        Returns:
            One value per lane.
        """
        # Same trick against an exponent that reads 2.0, giving [2, 4) before the shift down
        return MFloat[Self.N](from_bits=(self.bits() >> 12) | 0x4000000000000000) - 3.0

    @always_inline
    def range(mut self, min: MFloat[Self.N], max: MFloat[Self.N]) -> MFloat[Self.N]:
        """Draw a vector of uniform values in [min, max). Inclusive of min, exclusive of max.

        Args:
            min: The lower bound, per lane.
            max: The upper bound, per lane.

        Returns:
            One value per lane.
        """
        return min + (max - min) * self.uniform()

struct WhiteNoise[num_chans: SIMDLength = 1](Copyable, Movable):
    """Generate white noise samples.
    
    Parameters:
        num_chans: Number of SIMD channels.
    """
    var rng: SIMDRand[Self.num_chans]
    """The generator's own state, so a sample costs no call into the global generator."""

    def __init__(out self):
        """Initialize the WhiteNoise struct, seeding it from the global generator."""
        self.rng = SIMDRand[Self.num_chans]()

    def next(mut self, gain: MFloat[Self.num_chans] = MFloat[Self.num_chans](1.0)) -> MFloat[Self.num_chans]:
        """Generate the next white noise sample.

        Args:
            gain: Amplitude scaling factor.
        
        Returns:
            A random value between -gain and gain.
        """

        return self.rng.bipolar() * gain

struct PinkNoise[num_chans: SIMDLength = 1](Copyable, Movable):
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
        var white = rrand(MFloat[Self.num_chans](-1.0), MFloat[Self.num_chans](1.0))

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

struct BrownNoise[num_chans: SIMDLength = 1](Copyable, Movable):
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
        var white = rrand(MFloat[Self.num_chans](-1.0), MFloat[Self.num_chans](1.0))

        # Integrate white noise to get brown noise
        self.last_output += (white - self.last_output) * 0.02
        return self.last_output * gain

struct TExpRand[num_chans: SIMDLength = 1](Copyable, Movable):
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
            self.stored_output = exprand(min, max)
            self.is_initialized = True
            return self.stored_output
        
        var rising_edge: MBool[Self.num_chans] = trig & ~self.last_trig
        var randi = exprand(min, max)
        comptime for i in range(Self.num_chans):
            if rising_edge[i]:
                self.stored_output[i] = randi[i]
        self.last_trig = trig
        return self.stored_output

struct TRand[num_chans: SIMDLength = 1](Copyable, Movable):
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

        var rising_edge: MBool[Self.num_chans] = trig & ~self.last_trig
        comptime for i in range(Self.num_chans):
            if rising_edge[i]:
                self.stored_output[i] = random_float64(min[i], max[i])
        self.last_trig = trig
        return self.stored_output

struct LFSRNoise[num_chans: SIMDLength = 1](Copyable, Movable):
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