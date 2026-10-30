from mmm_audio.Polyphony import PolyReset
from mmm_audio.constants import *
from mmm_audio.MMMWorld_Module import TimesOversampling
from mmm_audio.Windows_Module import kaiser_window
from std.math import pi, sin, cos, tan, sqrt, log, ceil

@fieldwise_init
struct OversamplingFilter(Equatable, ImplicitlyCopyable):
    """The anti-aliasing filter used by the [Upsampler](Oversampling.md#struct-upsampler) and [Downsampler](Oversampling.md#struct-downsampler).

    Both the IIR and FIR variants are half-band filters run as a cascade of 2x stages, passing everything up to 0.4167 of the sample rate (20 kHz at 48 kHz, 40 kHz at 96 kHz), but never less than 20 kHz, and rejecting aliases by more than 100 dB. Below 48 kHz the 20 kHz floor narrows the transition band, so the filters get longer: at 44.1 kHz the IIR uses one more coefficient in its first stage and the FIR's latency rises to about 40 samples at x2. They differ in how they delay the signal.

    | Filter                  | Notes                                                                 |
    | ----------------------- | --------------------------------------------------------------------- |
    | OversamplingFilter.iir  | Polyphase allpass IIR (default). Very cheap, with only a few samples of latency, but each frequency is delayed by a different amount. |
    | OversamplingFilter.fir  | Linear-phase FIR. Every frequency is delayed by the same amount, but it costs more CPU and has much more latency. |

    The FIR is a "linear phase" filter and thus delays every frequency by the same time, so the shape of the waveform is kept exactly and the whole signal simply arrives later. Since the delay is constant, the phase shift grows in proportion to frequency, hence "linear phase". The IIR delays high frequencies more than low ones. At x2 the Upsampler delays 1.8 samples at low frequencies, 2.2 at 10 kHz and 5.3 at 20 kHz, so partials shift slightly against each other, mostly in the top octave.

    Delay in base-rate samples at 48 kHz and above, Upsampler / Downsampler (a round trip adds both). The Downsampler's is shorter by (times - 1) / times, because each output is taken at the newest sample of its block:

    | Factor | IIR, low frequencies | IIR, 20 kHz | FIR, all frequencies |
    | ------ | -------------------- | ----------- | -------------------- |
    | x2     | 1.8 / 1.3            | 5.3 / 4.8   | 22.5 / 22            |
    | x4     | 2.4 / 1.6            | 5.9 / 5.2   | 25.75 / 25           |
    | x8     | 2.6 / 1.7            | 6.1 / 5.2   | 27.125 / 26.25       |
    | x16    | 2.7 / 1.7            | 6.2 / 5.3   | 27.6875 / 26.75      |

    Use the IIR for an insert, such as a distortion or an oscillator on its own. There, a delay that varies by about 70 µs above 10 kHz is inaudible, and the low latency matters, especially inside a feedback loop.

    Use the FIR when the oversampled signal is combined with a copy that was not oversampled: parallel (wet/dry) distortion, multiband splits,  compression, or anything that is later summed with the dry signal. Delay the dry path by `get_latency()` and the two line up at every frequency. With the IIR no single delay lines up at all frequencies, so mixing causes slight comb filtering in the treble. The FIR is also the choice when something after it depends on exact peak values, such as a clipper or true-peak limiter, or for null tests. Its drawbacks are the latency and pre-ringing: being symmetric, its impulse response rings slightly before a sharp transient as well as after it.
    """
    var value: Int

    comptime iir = OversamplingFilter(0)
    comptime fir = OversamplingFilter(1)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self.value == other.value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

comptime _OS_ATTENUATION = 100.0
"""Stopband attenuation of each half-band stage in dB."""
comptime _OS_FIR_ATTENUATION = 115.0
"""Design attenuation for the FIR stages. The Kaiser length estimate falls up to 10 dB short on these short half-bands, so they are designed for more than `_OS_ATTENUATION` to reach at least what the IIR does."""

struct Downsampler[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.none, filter_type: OversamplingFilter = OversamplingFilter.iir](Movable, Copyable, PolyReset):
    """A struct that collects `times_oversampling` samples and then downsamples them using a cascade of half-band low-pass filters. Add a sample for each oversampling iteration with `add_sample()`, then get the downsampled output with `get_sample()`. VERY IMPORTANT, when initializing this struct, use the main world, not the oversampled subworld. The Downsampler exists outside of the oversampled subworld!

    Parameters:
        num_chans: Number of channels for the downsampling buffer.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        filter_type: An [OversamplingFilter](Oversampling.md#struct-oversamplingfilter) to choose the low-latency IIR (default) or linear-phase FIR filter.
    """

    var buffer: Array[MFloat[Self.num_chans], Self.ov_samp.times]  # Buffer for oversampled values
    var counter: Int
    var filter: HalfbandFilter[Self.num_chans, Self.ov_samp, Self.filter_type]

    def __init__(out self, world: World):
        """Initialize the Downsampler struct.

        Args:
            world: Pointer to the MMMWorld instance. VERY IMPORTANT to use the main world, not the oversampled subworld, for this struct.
        """
        self.buffer = Array[MFloat[Self.num_chans], Self.ov_samp.times](fill=MFloat[Self.num_chans](0.0))
        self.counter = 0
        self.filter = HalfbandFilter[Self.num_chans, Self.ov_samp, Self.filter_type](world[].sample_rate)

    @always_inline
    def add_sample(mut self, sample: MFloat[Self.num_chans]):
        """Add a sample to the oversampling buffer.

        Args:
            sample: The sample to add to the buffer.
        """
        self.buffer[self.counter] = sample
        self.counter += 1

    @always_inline
    def get_sample(mut self) -> MFloat[Self.num_chans]:
        """Get the next sample from a filled oversampling buffer.

        Returns:
            The downsampled output sample.
        """
        self.counter = 0
        return self.filter.down(self.buffer)

    def get_latency(self) -> Float64:
        """How far the output lags the input with the FIR filter, the same at every frequency. Delay a dry signal by this much to line it up with the oversampled one. Only available with `OversamplingFilter.fir`, since the IIR's delay depends on frequency (see [OversamplingFilter](Oversampling.md#struct-oversamplingfilter)).

        Returns:
            The delay in samples at the base sample rate. It can be fractional (e.g. 25 at x4).
        """
        # each output is taken at the newest sample of its block, which sits (times - 1) / times
        # of a base sample after the block's start, so it lags the filter by that much less
        return self.filter.get_latency() - Float64(Self.ov_samp.times - 1) / Float64(Self.ov_samp.times)

    def reset(mut self):
        """Reset the internal state of the downsampler."""
        self.filter.reset()
        self.counter = 0

struct Upsampler[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.x2, filter_type: OversamplingFilter = OversamplingFilter.iir](Movable, Copyable, PolyReset):
    """A struct that upsamples the input signal by the specified factor using a cascade of half-band low-pass filters.

    Parameters:
        num_chans: Number of channels for the upsampler.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        filter_type: An [OversamplingFilter](Oversampling.md#struct-oversamplingfilter) to choose the low-latency IIR (default) or linear-phase FIR filter.
    """
    var buffer: Array[MFloat[Self.num_chans], Self.ov_samp.times]
    var filter: HalfbandFilter[Self.num_chans, Self.ov_samp, Self.filter_type]

    def __init__(out self, world: World):
        """Initialize the Upsampler.

        Args:
            world: Pointer to the MMMWorld instance. VERY IMPORTANT to use the main world, not the oversampled subworld, since the filters are designed from its sample rate.
        """
        self.buffer = Array[MFloat[Self.num_chans], Self.ov_samp.times](fill=MFloat[Self.num_chans](0.0))
        self.filter = HalfbandFilter[Self.num_chans, Self.ov_samp, Self.filter_type](world[].sample_rate)

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], i: Int) -> MFloat[Self.num_chans]:
        """Process one sample through the upsampler. Pass in the same sample `times_oversampling` times, once for each oversampling iteration. The whole oversampled block is computed from the sample given when `i == 0`; later calls return the rest of the block.

        Args:
            input: The input signal to process.
            i: The iterator for the oversampling loop. Should range from 0 to (times_oversampling - 1).

        Returns:
            The next sample of the upsampled output.
        """
        comptime if Self.ov_samp.times == 1:
            return input
        if i == 0:
            self.filter.up(input, self.buffer)
        return self.buffer[i]

    def get_latency(self) -> Float64:
        """How far the output lags the input with the FIR filter, the same at every frequency. Delay a dry signal by this much to line it up with the oversampled one. Only available with `OversamplingFilter.fir`, since the IIR's delay depends on frequency (see [OversamplingFilter](Oversampling.md#struct-oversamplingfilter)).

        Returns:
            The delay in samples at the base sample rate. It can be fractional (e.g. 25.75 at x4).
        """
        return self.filter.get_latency()

    def reset(mut self):
        """Reset the internal state of the upsampler."""
        self.filter.reset()

struct HalfbandFilter[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.x2, filter_type: OversamplingFilter = OversamplingFilter.iir](Movable, Copyable):
    """A cascade of [HalfbandStage](Oversampling.md#struct-halfbandstage)s, one per doubling, that converts between the base rate and `ov_samp.times` times the base rate a block at a time. Used by the [Upsampler](Oversampling.md#struct-upsampler) and [Downsampler](Oversampling.md#struct-downsampler); an instance should be used for only one direction, since the stages hold filter state.

    Later stages in the filter run at a higher rate and thus have fewer coefficients.

    Parameters:
        num_chans: Number of channels processed in parallel.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        filter_type: An [OversamplingFilter](Oversampling.md#struct-oversamplingfilter) to choose IIR or FIR.
    """
    var stages: List[HalfbandStage[Self.num_chans, Self.filter_type]]
    """One 2x stage per doubling. `stages[0]` runs between the base rate and 2x, the last one at the highest rate."""
    var scratch: Array[MFloat[Self.num_chans], Self.ov_samp.times]
    """Intermediate block for `up()`, so each stage reads its input in time order."""

    def __init__(out self, sample_rate: Float64):
        """Design one half-band stage per doubling up to `ov_samp.times`.

        Args:
            sample_rate: The base sample rate in Hz. The passband is 0.4167 of it, but at least 20 kHz (see [OversamplingFilter](Oversampling.md#struct-oversamplingfilter)).
        """
        self.stages = List[HalfbandStage[Self.num_chans, Self.filter_type]]()
        self.scratch = Array[MFloat[Self.num_chans], Self.ov_samp.times](fill=MFloat[Self.num_chans](0.0))
        # top of the passband as a fraction of the base rate: 0.4167 of it (20 kHz at 48 kHz), at least 20 kHz,
        # but capped at 20 kHz at 44.1 kHz so lower rates don't push the band toward Nyquist
        var base_passband = min(max(20000.0 / sample_rate, 20.0 / 48.0), 20.0 / 44.1)
        var n = 2
        while n <= Self.ov_samp.times:
            # passband edge, normalized to this stage's high rate
            var passband = base_passband / Float64(n)
            self.stages.append(HalfbandStage[Self.num_chans, Self.filter_type](0.5 - 2.0 * passband))
            n *= 2

    @always_inline
    def up(mut self, input: MFloat[Self.num_chans], mut block: Array[MFloat[Self.num_chans], Self.ov_samp.times]):
        """Upsample one base-rate sample into a block of `ov_samp.times` high-rate samples, running the stages from the base rate upward.

        Args:
            input: The base-rate input sample.
            block: Receives the high-rate samples, in time order.
        """
        comptime if Self.ov_samp.times == 1:
            block[0] = input
            return
        # each stage doubles the block and must see its input in time order, so stages
        # alternate between `scratch` and `block`, arranged so the last one writes `block`;
        # unrolled at compile time, since the stage count and block sizes are known
        comptime n_stages = _n_stages(Self.ov_samp.times)
        var out0 = MFloat[Self.num_chans](0.0)
        var out1 = MFloat[Self.num_chans](0.0)
        comptime for s in range(n_stages):
            comptime n = 1 << s
            comptime to_block = (n_stages - 1 - s) % 2 == 0
            comptime for j in range(n):
                var x: MFloat[Self.num_chans]
                comptime if s == 0:
                    x = input
                elif to_block:
                    x = self.scratch[j]
                else:
                    x = block[j]
                self.stages[s].up(x, out0, out1)
                comptime if to_block:
                    block[2 * j] = out0
                    block[2 * j + 1] = out1
                else:
                    self.scratch[2 * j] = out0
                    self.scratch[2 * j + 1] = out1

    @always_inline
    def down(mut self, mut block: Array[MFloat[Self.num_chans], Self.ov_samp.times]) -> MFloat[Self.num_chans]:
        """Downsample a block of `ov_samp.times` high-rate samples into one base-rate sample, running the stages from the highest rate down. The block is overwritten.

        Args:
            block: The high-rate samples, in time order.

        Returns:
            The base-rate output sample.
        """
        # halve the block in place, from the highest-rate stage down to the base rate;
        # unrolled at compile time, since the stage count and block sizes are known
        comptime n_stages = _n_stages(Self.ov_samp.times)
        comptime for k in range(n_stages):
            comptime s = n_stages - 1 - k
            comptime n = Self.ov_samp.times >> (k + 1)
            comptime for j in range(n):
                block[j] = self.stages[s].down(block[2 * j], block[2 * j + 1])
        return block[0]

    def get_latency(self) -> Float64:
        """Total delay of the FIR cascade, the same at every frequency. Only available with `OversamplingFilter.fir`.

        Returns:
            The delay in samples at the base sample rate. Stage `s` runs at `2^(s + 1)` times the base rate, so its delay counts for that much less.
        """
        comptime assert Self.filter_type == OversamplingFilter.fir, "get_latency() is only available with OversamplingFilter.fir"
        var total: Float64 = 0.0
        var rate: Float64 = 2.0
        for s in range(len(self.stages)):
            total += self.stages[s].get_latency() / rate
            rate *= 2.0
        return total

    def reset(mut self):
        """Clear the filter state of every stage."""
        for ref stage in self.stages:
            stage.reset()

def _n_stages(times: Int) -> Int:
    """Number of 2x stages for an oversampling factor (log2 of `times`)."""
    var n = 0
    var t = times
    while t > 1:
        t //= 2
        n += 1
    return n

struct HalfbandStage[num_chans: SIMDLength = 1, filter_type: OversamplingFilter = OversamplingFilter.iir](Movable, Copyable):
    """One 2x up- or downsampling stage of a half-band low-pass filter, cutting off at a quarter of the high rate. Chained by a [HalfbandFilter](Oversampling.md#struct-halfbandfilter); an instance should be used for only one direction.

    The IIR version is two parallel chains of first-order allpass sections (de Soras' HIIR design), each running at the low rate. The FIR version is a Kaiser-windowed linear-phase half-band whose every other tap is zero, run polyphase so only the nonzero taps are computed.

    Parameters:
        num_chans: Number of channels processed in parallel.
        filter_type: An [OversamplingFilter](Oversampling.md#struct-oversamplingfilter) to choose IIR or FIR.
    """
    # IIR
    var coefs: List[Float64]
    """Allpass coefficients. Even indices form the first chain, odd indices the second."""
    var x1: List[MFloat[Self.num_chans]]
    var y1: List[MFloat[Self.num_chans]]
    # FIR
    var taps: List[Float64]
    """First half of the nonzero side taps (the filter is symmetric)."""
    var half: Int
    var hist: List[MFloat[Self.num_chans]]
    """History of the filtered branch, stored twice (frames `[k]` and `[k + size]`) so any window is contiguous."""
    var delayed: List[MFloat[Self.num_chans]]
    """History of the branch that only sees the center tap (downsampling only)."""
    var size: Int
    var mask: Int
    var write: Int

    def __init__(out self, transition: Float64):
        """Design the filter.

        Args:
            transition: Width of the transition band, normalized to the high rate. The band is centered on a quarter of the high rate.
        """
        self.coefs = List[Float64]()
        self.x1 = List[MFloat[Self.num_chans]]()
        self.y1 = List[MFloat[Self.num_chans]]()
        self.taps = List[Float64]()
        self.half = 0
        self.hist = List[MFloat[Self.num_chans]]()
        self.delayed = List[MFloat[Self.num_chans]]()
        self.size = 1
        self.mask = 0
        self.write = 0

        comptime if Self.filter_type == OversamplingFilter.iir:
            self.coefs = _hiir_coefs(_OS_ATTENUATION, transition)
            self.x1 = List[MFloat[Self.num_chans]](length=len(self.coefs), fill=MFloat[Self.num_chans](0.0))
            self.y1 = List[MFloat[Self.num_chans]](length=len(self.coefs), fill=MFloat[Self.num_chans](0.0))
        else:
            # Kaiser length estimate, rounded up to 4k - 1 so the end taps are nonzero
            var n_est = Int(ceil((_OS_FIR_ATTENUATION - 8.0) / (2.285 * 2.0 * pi * transition))) + 1
            var k = (n_est + 4) // 4
            var n_taps = 4 * k - 1
            var center = 2 * k - 1
            var window = kaiser_window(n_taps, 0.1102 * (_OS_FIR_ATTENUATION - 8.7))
            var sum: Float64 = 0.0
            for j in range(k):
                # nonzero side taps sit at even indices, an odd distance from the center
                var t = Float64(2 * j - center)
                var h = sin(pi * t * 0.5) / (pi * t) * window[2 * j]
                self.taps.append(h)
                sum += 2.0 * h
            # side taps sum to 0.5 and the center tap is 0.5, so DC gain is exactly 1
            for j in range(k):
                self.taps[j] *= 0.5 / sum
            self.half = k
            while self.size < 2 * k + 1:
                self.size *= 2
            self.mask = self.size - 1
            self.hist = List[MFloat[Self.num_chans]](length=2 * self.size, fill=MFloat[Self.num_chans](0.0))
            self.delayed = List[MFloat[Self.num_chans]](length=self.size, fill=MFloat[Self.num_chans](0.0))

    def get_latency(self) -> Float64:
        """Delay of the FIR filter, which is the distance from its first tap to its center. Only available with `OversamplingFilter.fir`.

        Returns:
            The delay in samples at this stage's high rate.
        """
        comptime assert Self.filter_type == OversamplingFilter.fir, "HalfbandStage.get_latency() is only available with OversamplingFilter.fir"
        return Float64(2 * self.half - 1)

    def reset(mut self):
        """Clear the filter state."""
        for i in range(len(self.x1)):
            self.x1[i] = MFloat[Self.num_chans](0.0)
            self.y1[i] = MFloat[Self.num_chans](0.0)
        for i in range(len(self.hist)):
            self.hist[i] = MFloat[Self.num_chans](0.0)
        for i in range(len(self.delayed)):
            self.delayed[i] = MFloat[Self.num_chans](0.0)
        self.write = 0

    @always_inline
    def _allpass_chains(mut self, mut s0: MFloat[Self.num_chans], mut s1: MFloat[Self.num_chans]):
        """Run `s0` through the even-indexed allpass chain and `s1` through the odd one."""
        var n = len(self.coefs)
        var c = self.coefs.unsafe_ptr()
        var x1 = self.x1.unsafe_ptr()
        var y1 = self.y1.unsafe_ptr()
        var i = 0
        while i + 1 < n:
            var t0 = (s0 - y1[unsafe_offset=i]) * c[unsafe_offset=i] + x1[unsafe_offset=i]
            var t1 = (s1 - y1[unsafe_offset=i + 1]) * c[unsafe_offset=i + 1] + x1[unsafe_offset=i + 1]
            x1[unsafe_offset=i] = s0
            x1[unsafe_offset=i + 1] = s1
            y1[unsafe_offset=i] = t0
            y1[unsafe_offset=i + 1] = t1
            s0 = t0
            s1 = t1
            i += 2
        if i < n:
            var t0 = (s0 - y1[unsafe_offset=i]) * c[unsafe_offset=i] + x1[unsafe_offset=i]
            x1[unsafe_offset=i] = s0
            y1[unsafe_offset=i] = t0
            s0 = t0

    @always_inline
    def _push(mut self, x: MFloat[Self.num_chans]):
        self.write = (self.write + 1) & self.mask
        self.hist[self.write] = x
        self.hist[self.write + self.size] = x

    @always_inline
    def _side_taps(self) -> MFloat[Self.num_chans]:
        """Dot product of the side taps with the filtered branch history, folded on its symmetry."""
        var n = 2 * self.half - 1
        var start = (self.write - n) & self.mask  # oldest frame of the window
        var taps = self.taps.unsafe_ptr()
        var hist = self.hist.unsafe_ptr()
        var acc = MFloat[Self.num_chans](0.0)
        for j in range(self.half):
            acc += taps[unsafe_offset=j] * (hist[unsafe_offset=start + j] + hist[unsafe_offset=start + n - j])
        return acc

    @always_inline
    def down(mut self, older: MFloat[Self.num_chans], newer: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Filter two consecutive high-rate samples into one low-rate sample.

        Args:
            older: The first of the two samples.
            newer: The second of the two samples.

        Returns:
            The low-rate output sample.
        """
        comptime if Self.filter_type == OversamplingFilter.iir:
            var s0 = newer
            var s1 = older
            self._allpass_chains(s0, s1)
            return 0.5 * (s0 + s1)
        else:
            self._push(newer)
            self.delayed[self.write] = older
            return self._side_taps() + 0.5 * self.delayed[(self.write - self.half + 1) & self.mask]

    @always_inline
    def up(mut self, x: MFloat[Self.num_chans], mut out0: MFloat[Self.num_chans], mut out1: MFloat[Self.num_chans]):
        """Turn one low-rate sample into two consecutive high-rate samples.

        Args:
            x: The low-rate input sample.
            out0: Receives the first high-rate sample.
            out1: Receives the second high-rate sample.
        """
        comptime if Self.filter_type == OversamplingFilter.iir:
            out0 = x
            out1 = x
            self._allpass_chains(out0, out1)
        else:
            self._push(x)
            out0 = 2.0 * self._side_taps()
            out1 = self.hist[(self.write - self.half + 1) & self.mask]

def _hiir_coefs(attenuation: Float64, transition: Float64) -> List[Float64]:
    """Allpass coefficients for a polyphase IIR half-band (Laurent de Soras, HIIR), using the fewest coefficients that reach `attenuation` dB over the given `transition` width."""
    var k = tan((1.0 - transition * 2.0) * pi / 4.0)
    k *= k
    var kksqrt = (1.0 - k * k) ** 0.25
    var e = 0.5 * (1.0 - kksqrt) / (1.0 + kksqrt)
    var e4 = e * e * e * e
    var q = e * (1.0 + e4 * (2.0 + e4 * (15.0 + 150.0 * e4)))

    var attn_p2 = 10.0 ** (-attenuation / 10.0)
    var a = attn_p2 / (1.0 - attn_p2)
    var order = Int(ceil(log(a * a / 16.0) / log(q)))
    if order % 2 == 0:
        order += 1
    if order < 3:
        order = 3

    var coefs = List[Float64]()
    for index in range((order - 1) // 2):
        var c = Float64(index + 1)
        var num = _hiir_acc_num(q, order, c) * q ** 0.25
        var den = _hiir_acc_den(q, order, c) + 0.5
        var ww = num / den
        var wwsq = ww * ww
        var x = sqrt((1.0 - wwsq * k) * (1.0 - wwsq / k)) / (1.0 + wwsq)
        coefs.append((1.0 - x) / (1.0 + x))
    return coefs^

def _hiir_acc_num(q: Float64, order: Int, c: Float64) -> Float64:
    var acc: Float64 = 0.0
    var sign: Float64 = 1.0
    var i = 0
    while True:
        var term = q ** Float64(i * (i + 1)) * sin(Float64(i * 2 + 1) * c * pi / Float64(order)) * sign
        acc += term
        sign = -sign
        i += 1
        if abs(term) <= 1e-100:
            break
    return acc

def _hiir_acc_den(q: Float64, order: Int, c: Float64) -> Float64:
    var acc: Float64 = 0.0
    var sign: Float64 = -1.0
    var i = 1
    while True:
        var term = q ** Float64(i * i) * cos(Float64(i * 2) * c * pi / Float64(order)) * sign
        acc += term
        sign = -sign
        i += 1
        if abs(term) <= 1e-100:
            break
    return acc
