from mmm_audio import *

struct Oversampling[num_chans: Int = 1, ov_samp: TimesOversampling = TimesOversampling.none](Movable, Copyable, PolyReset):
    """A struct that collects ` times_oversampling` samples and then downsamples them using a low-pass filter. Add a sample for each oversampling iteration with `add_sample()`, then get the downsampled output with `get_sample()`.

    Parameters:
        num_chans: Number of channels for the oversampling buffer.
        ov_samp: An [oversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """

    var buffer: InlineArray[MFloat[Self.num_chans], Self.ov_samp.times]  # Buffer for oversampled values
    var counter: Int
    var lpf: OS_LPF4[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the Oversampling struct.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.lpf = OS_LPF4[self.num_chans](world)
        self.buffer = InlineArray[MFloat[Self.num_chans], Self.ov_samp.times](fill=MFloat[Self.num_chans](0.0))
        self.counter = 0
        self.lpf.set_sample_rate(world[].sample_rate * MFloat[1](Self.ov_samp.times))
        
        self.lpf.set_cutoff(0.48 * world[].sample_rate)

    @always_inline
    def add_sample(mut self, sample: MFloat[self.num_chans]):
        """Add a sample to the oversampling buffer.
        
        Args:
            sample: The sample to add to the buffer.
        """
        self.buffer[self.counter] = sample
        self.counter += 1

    @always_inline
    def get_sample(mut self) -> MFloat[self.num_chans]:
        """Get the next sample from a filled oversampling buffer.

        Returns:
            The downsampled output sample.
        """
        out = MFloat[self.num_chans](0.0)
        if self.counter > 1:
            for i in range(Self.ov_samp.times):
                out = self.lpf.next(self.buffer[i]) # Lowpass filter each sample
        else:
            out = self.buffer[0]
        self.counter = 0
        return out

    def reset(mut self):
        """Reset the internal state of the upsampler."""
        self.lpf.reset()
        
struct Upsampler[num_chans: Int = 1, ov_samp: TimesOversampling = TimesOversampling.x2](Movable, Copyable, PolyReset):
    """A struct that upsamples the input signal by the specified factor using a low-pass filter.

    Parameters:
        num_chans: Number of channels for the upsampler.
        ov_samp: An [oversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """
    var lpf: OS_LPF4[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the Upsampler.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.lpf = OS_LPF4[Self.num_chans](world)
        self.lpf.set_sample_rate(world[].sample_rate * MFloat[1](Self.ov_samp.times))
        self.lpf.set_cutoff(0.5 * world[].sample_rate)

    @always_inline
    def next(mut self, input: MFloat[self.num_chans], i: Int) -> MFloat[self.num_chans]:
        """Process one sample through the upsampler. Pass in the same sample `times_oversampling` times, once for each oversampling iteration. The algorithm will use the first sample given and fill the buffer with zeroes for the subsequent samples.

        Args:
            input: The input signal to process.
            i: The iterator for the oversampling loop. Should range from 0 to (times_oversampling - 1).

        Returns:
            The next sample of the upsampled output.
        """
        if i == 0:
            return self.lpf.next(input) * MFloat[1](Self.ov_samp.times)
        else:
            return self.lpf.next(MFloat[Self.num_chans](0.0)) * MFloat[1](Self.ov_samp.times)

    def reset(mut self):
        """Reset the internal state of the upsampler."""
        self.lpf.reset()

struct OS_LPF[num_chans: Int = 1](Movable, Copyable):
    """A simple 2nd-order low-pass filter for oversampling applications. Does not allow changing cutoff frequency on the fly to avoid that calculation each sample.
    
    Parameters:
        num_chans: Number of channels for the filter.
    """
    var sample_rate: Float64
    var b0: Float64
    var b1: Float64
    var b2: Float64
    var a1: Float64
    var a2: Float64
    var z1: MFloat[Self.num_chans]
    var z2: MFloat[Self.num_chans]
    comptime INV_SQRT2 = 0.7071067811865475

    def __init__(out self, world: World):
        """Initialize the oversampling low-pass filter.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.sample_rate = world[].sample_rate
        self.b0 = 1.0
        self.b1 = 0.0
        self.b2 = 0.0
        self.a1 = 0.0
        self.a2 = 0.0
        self.z1 = MFloat[Self.num_chans](0.0)
        self.z2 = MFloat[Self.num_chans](0.0)

    def set_sample_rate(mut self, sr: Float64):
        """Set the sample rate for the filter.

        Args:
            sr: The sample rate in Hz.
        """
        self.sample_rate = sr

    def set_cutoff(mut self, fc: Float64):
        """Set the cutoff frequency for the low-pass filter.

        Args:
            fc: The cutoff frequency in Hz.
        """
        var w0 = 2.0 * pi * fc / self.sample_rate
        var cw = cos(w0)
        var sw = sin(w0)
        var Q = self.INV_SQRT2
        var alpha = sw / (2.0 * Q)

        var b0 = (1.0 - cw) * 0.5
        var b1 = 1.0 - cw
        var b2 = (1.0 - cw) * 0.5
        var a0 = 1.0 + alpha
        var a1 = -2.0 * cw
        var a2 = 1.0 - alpha

        # normalize so a0 = 1 (unity DC preserved)
        b0 /= a0
        b1 /= a0
        b2 /= a0
        a1 /= a0
        a2 /= a0

        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2

    @always_inline
    def next(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the 2nd-order low-pass filter.
        
        Args:
            x: The input signal to process.

        Returns:
            The filtered output sample.
        """
        var y = self.b0 * x + self.z1
        self.z1 = self.b1 * x - self.a1 * y + self.z2
        self.z2 = self.b2 * x - self.a2 * y
        return y

    def reset(mut self):
        """Reset the internal state of the low-pass filter."""
        self.z1 = MFloat[Self.num_chans](0.0)
        self.z2 = MFloat[Self.num_chans](0.0)

struct OS_LPF4[num_chans: Int = 1](Movable, Copyable):
    """A 4th-order low-pass filter for oversampling applications, implemented as two cascaded 2nd-order sections.
    
    Parameters:
        num_chans: Number of channels for the filter with fixed cutoff frequency.
    """
    var os_lpf1: OS_LPF[Self.num_chans]
    var os_lpf2: OS_LPF[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the 4th order oversampling low-pass filter.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.os_lpf1 = OS_LPF[Self.num_chans](world)
        self.os_lpf2 = OS_LPF[Self.num_chans](world)
    def set_sample_rate(mut self, sr: Float64):
        self.os_lpf1.set_sample_rate(sr)
        self.os_lpf2.set_sample_rate(sr)
    
    def set_cutoff(mut self, fc: Float64):
        self.os_lpf1.set_cutoff(fc)
        self.os_lpf2.set_cutoff(fc)

    @always_inline
    def next(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the 4th-order low-pass filter with fixed cutoff frequency.
        
        Args:
            x: The input signal to process.

        Returns:
            The filtered output sample.
        """
        
        var y = self.os_lpf1.next(x)
        y = self.os_lpf2.next(y)
        return y

    def reset(mut self):
        """Reset the internal state of the 4th-order low-pass filter."""
        self.os_lpf1.reset()
        self.os_lpf2.reset()

# Library Code:

trait Oversamplable(Movable, Copyable):

    def uses_external_oversampling(mut self, times_oversampling: TimesOversampling):...

trait Nextable(Movable, Copyable, ImplicitlyDestructible):

    def next(mut self, input: MFloat[1]) -> MFloat[1]:...

struct Oversampler[T:Nextable, times_oversampling: TimesOversampling = TimesOversampling.x2](Movable,Copyable):
    var oversampling: Oversampling[ov_samp=Self.times_oversampling]
    var user_nextable: Self.T

    def __init__(out self, world: World, var user_nextable: Self.T):
        self.oversampling = Oversampling[ov_samp=Self.times_oversampling](world)
        self.user_nextable = user_nextable^

        types = reflect[Self.T]().field_types()
        r = reflect[Self.T]()
        comptime for i in range(reflect[Self.T]().field_count()):
            comptime if conforms_to(types[i], Oversamplable):
                ref ovs = r.field_ref[i](self.user_nextable)
                ovs.uses_external_oversampling(Self.times_oversampling)


    def next(mut self, input: MFloat[1]) -> MFloat[1]:
        for _ in range(Self.times_oversampling.times):
            self.oversampling.add_sample(self.user_nextable.next(input))
        return self.oversampling.get_sample()
        
# User Code:

struct GraphIWantToOversample(Nextable):
    var osc: Osc[]

    def __init__(out self, world: World):
        self.osc = Osc(world)

    def next(mut self, input: MFloat[1]) -> MFloat[1]:
        return self.osc.next()

struct MySynth(Copyable, Movable):
    var ovsr: Oversampler[GraphIWantToOversample, TimesOversampling.x4]

    def __init__(out self, world: World):
        self.ovsr = Oversampler[GraphIWantToOversample, TimesOversampling.x4](world, GraphIWantToOversample(world))

    def next(mut self, input: MFloat[1]) -> MFloat[1]:
        return self.ovsr.next(input)
