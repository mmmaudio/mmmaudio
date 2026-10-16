from mmm_audio.Oversampling import Downsampler, Upsampler
from mmm_audio.Buffer_Module import SIMDBuffer, Buffer
from mmm_audio.Polyphony import PolyReset
from mmm_audio.constants import *
from mmm_audio.BooleanTests import RisingBoolDetector
from mmm_audio.MMMWorld_Module import TimesOversampling
from std.math import tanh, floor, pi, exp, log, cosh
from mmm_audio.MMMWorld_Module import Interp
from mmm_audio.functions import all_lanes_equal, clip, clip_finite, sign, li2_neg_exp


def bitcrusher[num_chans: SIMDLength](in_samp: MFloat[num_chans], bits: Int) -> MFloat[num_chans]:
    """Simple bitcrusher function that reduces the bit depth of the input signal.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.

    Args:
        in_samp: The input sample to be bitcrushed.
        bits: The number of bits to reduce the signal to.

    Returns:
        The output sample.
    """
    var step = 1.0 / MFloat[num_chans](1 << bits)
    var out_samp = floor(in_samp / step + 0.5) * step

    return out_samp


struct Latch[num_chans: SIMDLength = 1](Copyable, Movable):
    """
    A simple latch that holds the last input sample when a trigger is received.

    Parameters:
        num_chans: The number of channels for SIMD operations.
    """
    var rbd: RisingBoolDetector[Self.num_chans]
    var samp: MFloat[Self.num_chans]

    def __init__(out self):
        """Initialize the Latch."""
        self.samp = MFloat[Self.num_chans](0)
        self.rbd = RisingBoolDetector[Self.num_chans]()

    def next(mut self, in_samp: MFloat[Self.num_chans], trig: MBool[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process the input sample and trigger, returning the latched output sample.

        Args:
            in_samp: The input sample to be latched.
            trig: A boolean trigger signal. When switching from false to true, the latch updates its output to the current input sample.

        Returns:
            The currently latched sample.
        """
        
        var rising_edge = self.rbd.next(trig)
        self.samp = rising_edge.select(in_samp, self.samp)
        return self.samp

# Anti-Derivative Anti-aliasing functions are based on Jatin Chowdhury's python notebook: https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html and chowshapers: https://github.com/Chowdhury-DSP/chowdsp_utils/tree/master/modules/dsp/chowdsp_waveshapers/Waveshapers

# the trait currently doesn't work, but it will once parameters are included in traits

# trait ADAAfuncs[num_chans: SIMDLength = 1](Movable, Copyable):

#     def next_norm[num_chans: SIMDLength](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...

#     def next_AD1[num_chans: SIMDLength](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...
    
#     def next_AD2[num_chans: SIMDLength](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...

struct SoftClipAD[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.none, degree: Int = 3](Copyable, Movable):
    """
    Anti-Derivative Anti-aliasing soft-clipping function.
    
    This struct provides a first or second order anti-aliased `soft clip` function using the Anti-Derivative Anti-aliasing (ADAA) with optional Downsampler. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        degree: The degree of the soft clipping polynomial (must be odd).
    """
    var x1: MFloat[Self.num_chans]
    var x2: MFloat[Self.num_chans]
    var ad2_x1: MFloat[Self.num_chans]
    var d2: MFloat[Self.num_chans]
    var ad2_valid: Bool  # False when ad2_x1/d2 are stale (start, reset, or after 1st-order calls)
    var downsampler: Downsampler[Self.num_chans, Self.ov_samp]
    var upsampler: Upsampler[Self.num_chans, Self.ov_samp]
    var D: Float64
    var norm_factor: Float64
    var inv_norm_factor: Float64
    comptime TOL = 1.0e-5
    comptime TOL2 = 1.0e-3
    comptime MAX_IN: Float64 = 50.0  # beyond the knee the curve is flat, so clamping is inaudible and keeps the 2nd-order ADAA differences well-conditioned
    var G1: Float64
    var G2: Float64
    var initialized: Bool

    def __init__(out self, world: World):
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False
        if Self.ov_samp.times > 2:
            print("SoftClipAD: ov_samp greater than x2 not supported yet. It will not sound good.")
        self.downsampler = Downsampler[Self.num_chans, self.ov_samp](world)
        self.upsampler = Upsampler[Self.num_chans, self.ov_samp](world)
        self.D = Float64(Self.degree // 2 * 2 + 1)  # ensure degree is odd
        self.norm_factor = (self.D - 1) / self.D
        self.inv_norm_factor = 1.0 / self.norm_factor
        self.G1 = 1.0 / (2.0 * (self.norm_factor * self.norm_factor)) - 1.0 / ((self.norm_factor * self.norm_factor) * self.D * (self.D + 1))
        self.G2 = 1.0 / (6.0 * (self.norm_factor * self.norm_factor * self.norm_factor)) - 1.0 / ((self.norm_factor * self.norm_factor * self.norm_factor) * self.D * (self.D + 1) * (self.D + 2))
        self.initialized = False

    @doc_hidden
    @always_inline
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Transfer function: x - x^n/n"""

        var mask: MBool[Self.num_chans] = abs(x*self.norm_factor).gt(1.0)

        var out = ((x * self.norm_factor) - pow(x * self.norm_factor, self.D) / self.D) * self.inv_norm_factor

        out = mask.select(sign(x), out)

        return out

    @doc_hidden
    @always_inline
    def _next_AD1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First antiderivative: x²/2 - x^(n+1) / (n*(n+1))"""
        var mask: MBool[Self.num_chans] = abs(x*self.norm_factor).gt(1.0)

        var outA = x * sign(x) + self.G1 - self.inv_norm_factor

        var out = ((self.norm_factor * (x * x) / 2.0) - (pow(self.norm_factor, self.D) * pow(x, self.D + 1) / (self.D * (self.D + 1.0)))) * self.inv_norm_factor

        return mask.select(outA, out)

    @doc_hidden
    @always_inline
    def _next_AD2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Second antiderivative: x³/6 - x^(n+2) / (n*(n+1)*(n+2))"""
        var mask: MBool[Self.num_chans] = abs(x*self.norm_factor).gt(1.0)

        var outA = ((x * x / 2.0) + self.G2 + (self.inv_norm_factor * self.inv_norm_factor / 2.0) - self.G1 * self.inv_norm_factor) * sign(x) + x * (self.G1 - self.inv_norm_factor)

        var out = ((self.norm_factor * (x * x * x) / 6.0) - (pow(self.norm_factor, self.D) * pow(x, self.D + 2) / (self.D * (self.D + 1.0) * (self.D + 2.0)))) * self.inv_norm_factor

        return mask.select(outA, out)

    @doc_hidden
    @always_inline
    def _next2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the second-order anti-aliased SoftClip. The output is delayed by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased clipped signal.
        """
        if not self.ad2_valid:
            # 1st-order calls only track x1 and x2, so rebuild the 2nd-order state before using it
            self.ad2_x1 = self._next_AD2(self.x1)
            self.d2 = abs(self.x1 - self.x2).lt(Self.TOL2).select(
                self._next_AD1((self.x1 + self.x2) * 0.5),
                (self.ad2_x1 - self._next_AD2(self.x2)) / (self.x1 - self.x2)
            )
            self.ad2_valid = True

        var ad2_x0 = self._next_AD2(x)
        var d1 = abs(x - self.x1).lt(Self.TOL2).select(
            self._next_AD1((x + self.x1) * 0.5),
            (ad2_x0 - self.ad2_x1) / (x - self.x1)
        )

        var x_bar = (x + self.x2) * 0.5
        var delta = x_bar - self.x1
        var fallback = abs(delta).lt(Self.TOL2).select(
            self._next_norm((x_bar + self.x1) * 0.5),
            (2.0 / delta) * (self._next_AD1(x_bar) + (self.ad2_x1 - self._next_AD2(x_bar)) / delta)
        )

        var out = abs(x - self.x2).lt(Self.TOL2).select(fallback, (2.0 / (x - self.x2)) * (d1 - self.d2))

        self.d2 = d1
        self.x2 = self.x1
        self.x1 = x
        self.ad2_x1 = ad2_x0
        return out

    @doc_hidden
    @always_inline
    def _next1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the first-order anti-aliased SoftClip.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased folded signal.
        """
        var mask = abs(x - self.x1).lt(self.TOL)

        var out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x) - self._next_AD1(self.x1)) / (x - self.x1))
        self.x2 = self.x1
        self.x1 = x
        self.ad2_valid = False
        return out

    @doc_hidden
    @always_inline
    def _process[ADAA_Order: Int](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        comptime if ADAA_Order == 1:
            return self._next1(x)
        else:
            return self._next2(x)

    def reset(mut self):
        """Reset the internal state of the SoftClipAD."""
        self.initialized = False
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False

    @always_inline
    def next[ADAA_Order: Int = 1](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Anti-aliased `soft_clip`.

        Computes the first or second order anti-aliased `soft_clip` of `x`. If the ov_samp is greater than 0, oversampling is applied to the processing.

        Parameters:
            ADAA_Order: The order of the anti-derivative anti-aliasing (1 or 2). Second order aliases less, costs more, and delays the output by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `soft_clip` of `x`.
        """
        comptime assert ADAA_Order == 1 or ADAA_Order == 2, "SoftClipAD: ADAA_Order must be 1 or 2."
        var xs = clip_finite(x, Self.MAX_IN)
        # if not self.initialized:
        #     self.x1 = x
        #     self.initialized = True
        #     return self._next_norm(x)

        comptime if Self.ov_samp == TimesOversampling.none:
            return self._process[ADAA_Order](xs)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.ov_samp.times):
                # upsample the input
                x2 = self.upsampler.next(xs, i)
                y = self._process[ADAA_Order](x2)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()

def soft_clip[num_chans: SIMDLength](x: MFloat[num_chans], min_val: MFloat[num_chans] = -1., max_val: MFloat[num_chans] = 1.) -> MFloat[num_chans]:
    """Apply a SuperCollider-style soft clip across a custom range.

    Parameters:
        num_chans: The number of channels for SIMD operations.

    Args:
        x: The input sample to clip.
        min_val: Lower clipping bound.
        max_val: Upper clipping bound.

    Returns:
        The softly clipped output sample.
    """
    var center = (min_val + max_val) / 2.0
    var range = (max_val - min_val) / 2.0
    var normalized = (x - center) / range
    var clipped = normalized / (1.0 + abs(normalized))
    return center + clipped * range

struct HardClipAD[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.none](Copyable, Movable):
    """
    Anti-Derivative Anti-aliasing hard-clipping function.
    
    This struct provides a first or second order anti-aliased version of the `hard_clip` function using the Anti-Derivative Anti-aliasing (ADAA) with optional Downsampler. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """
    var x1: MFloat[Self.num_chans]
    var x2: MFloat[Self.num_chans]
    var ad2_x1: MFloat[Self.num_chans]
    var d2: MFloat[Self.num_chans]
    var ad2_valid: Bool  # False when ad2_x1/d2 are stale (start, reset, or after 1st-order calls)
    var downsampler: Downsampler[Self.num_chans, Self.ov_samp]
    var upsampler: Upsampler[Self.num_chans, Self.ov_samp]
    comptime TOL = 1.0e-5
    comptime TOL2 = 1.0e-3
    comptime MAX_IN: Float64 = 50.0  # beyond the knee the curve is flat, so clamping is inaudible and keeps the 2nd-order ADAA differences well-conditioned
    var initialized: Bool

    def __init__(out self, world: World):
        """Initialize the HardClipAD.
        
        Args:
            world: A pointer to the MMMWorld.
        """
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False
        self.downsampler = Downsampler[Self.num_chans, Self.ov_samp](world)
        self.upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)
        self.initialized = False

    @doc_hidden
    @always_inline
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).lt(1.0)
        return mask.select(x, sign(x))

    @doc_hidden
    @always_inline
    def _next_AD1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).lt(1.0)
        return mask.select(x * x * 0.5, x * sign(x) - 0.5)

    @doc_hidden
    @always_inline
    def _next_AD2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).lt(1.0)

        return mask.select(x * x * x / 6.0, ((x * x * 0.5) + (1.0 / 6.0)) * sign(x) - (x/2))

    @doc_hidden
    @always_inline
    def _next2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the second-order anti-aliased `hard_clip`. The output is delayed by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased clipped signal.
        """
        if not self.ad2_valid:
            # 1st-order calls only track x1 and x2, so rebuild the 2nd-order state before using it
            self.ad2_x1 = self._next_AD2(self.x1)
            self.d2 = abs(self.x1 - self.x2).lt(Self.TOL2).select(
                self._next_AD1((self.x1 + self.x2) * 0.5),
                (self.ad2_x1 - self._next_AD2(self.x2)) / (self.x1 - self.x2)
            )
            self.ad2_valid = True

        var ad2_x0 = self._next_AD2(x)
        var d1 = abs(x - self.x1).lt(Self.TOL2).select(
            self._next_AD1((x + self.x1) * 0.5),
            (ad2_x0 - self.ad2_x1) / (x - self.x1)
        )

        var x_bar = (x + self.x2) * 0.5
        var delta = x_bar - self.x1
        var fallback = abs(delta).lt(Self.TOL2).select(
            self._next_norm((x_bar + self.x1) * 0.5),
            (2.0 / delta) * (self._next_AD1(x_bar) + (self.ad2_x1 - self._next_AD2(x_bar)) / delta)
        )

        var out = abs(x - self.x2).lt(Self.TOL2).select(fallback, (2.0 / (x - self.x2)) * (d1 - self.d2))

        self.d2 = d1
        self.x2 = self.x1
        self.x1 = x
        self.ad2_x1 = ad2_x0
        return out

    @doc_hidden
    @always_inline
    def _next1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x - self.x1).lt(self.TOL)
        var out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x) - self._next_AD1(self.x1)) / (x - self.x1))
        self.x2 = self.x1
        self.x1 = x
        self.ad2_valid = False
        return out

    @doc_hidden
    @always_inline
    def _process[ADAA_Order: Int](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        comptime if ADAA_Order == 1:
            return self._next1(x)
        else:
            return self._next2(x)

    def reset(mut self):
        """Reset the internal state of the HardClipAD."""
        self.initialized = False
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False

    @always_inline
    def next[ADAA_Order: Int = 1](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Anti-aliased `hard_clip`.

        Computes the first or second order anti-aliased `hard_clip` of `x`. If the ov_samp is greater than 0, oversampling is applied to the processing.

        Parameters:
            ADAA_Order: The order of the anti-derivative anti-aliasing (1 or 2). Second order aliases less, costs more, and delays the output by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `hard_clip` of `x`.
        """
        comptime assert ADAA_Order == 1 or ADAA_Order == 2, "HardClipAD: ADAA_Order must be 1 or 2."
        var xs = clip_finite(x, Self.MAX_IN)
        comptime if Self.ov_samp == TimesOversampling.none:
            return self._process[ADAA_Order](xs)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.ov_samp.times):
                # upsample the input
                x2 = self.upsampler.next(xs, i)
                y = self._process[ADAA_Order](x2)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()

struct TanhAD[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.none](Copyable, Movable, PolyReset):
    """Anti-Derivative Anti-aliasing tanh function.
    
    This struct provides a first or second order anti-aliased version of the `tanh` function using the Anti-Derivative Anti-aliasing (ADAA) method with optional Downsampler. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.

    Parameters:
        num_chans: The number of channels for SIMD operations.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """

    var x1: MFloat[Self.num_chans]
    var x2: MFloat[Self.num_chans]
    var ad2_x1: MFloat[Self.num_chans]
    var d2: MFloat[Self.num_chans]
    var ad2_valid: Bool  # False when ad2_x1/d2 are stale (start, reset, or after 1st-order calls)
    comptime TOL = 1.0e-5
    comptime TOL2 = 1.0e-3
    comptime MAX_IN: Float64 = 50.0  # tanh is flat to double precision beyond ~20, so clamping is inaudible and keeps the 2nd-order ADAA differences well-conditioned
    comptime LN2 = 0.6931471805599453
    comptime PI2_24 = pi * pi / 24.0
    var downsampler: Downsampler[Self.num_chans, Self.ov_samp]
    var upsampler: Upsampler[Self.num_chans, Self.ov_samp]
    var initialized: Bool

    def __init__(out self, world: World):
        """Initialize the TanhAD.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False
        self.downsampler = Downsampler[Self.num_chans, Self.ov_samp](world)
        self.upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)
        self.initialized = False

    @doc_hidden
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        return tanh(x)

    @doc_hidden
    def _log_term(self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """ln(1 + e^(-2|x|)), shared by both antiderivatives."""
        return log(1.0 + exp(-2.0 * abs(x)))

    @doc_hidden
    def _next_AD1(self, x: MFloat[Self.num_chans], u: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First antiderivative: |x| + ln(1 + e^(-2|x|)) - ln2, with u = `_log_term(x)`."""
        return abs(x) + u - Self.LN2

    @doc_hidden
    def _next_AD2(self, x: MFloat[Self.num_chans], u: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Second antiderivative: sign(x) * (x²/2 - |x|ln2 + Li2(-e^(-2|x|))/2 + π²/24), with u = `_log_term(x)`."""
        var ax = abs(x)
        return sign(x) * (0.5 * ax * ax - Self.LN2 * ax + 0.5 * li2_neg_exp(u) + Self.PI2_24)

    @doc_hidden
    def _next2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the second-order anti-aliased `tanh` of `x`. The output is delayed by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `tanh` of `x`.
        """
        if not self.ad2_valid:
            # 1st-order calls only track x1 and x2, so rebuild the 2nd-order state before using it
            self.ad2_x1 = self._next_AD2(self.x1, self._log_term(self.x1))
            self.d2 = abs(self.x1 - self.x2).lt(Self.TOL2).select(
                self._next_AD1((self.x1 + self.x2) * 0.5, self._log_term((self.x1 + self.x2) * 0.5)),
                (self.ad2_x1 - self._next_AD2(self.x2, self._log_term(self.x2))) / (self.x1 - self.x2)
            )
            self.ad2_valid = True

        var ad2_x0 = self._next_AD2(x, self._log_term(x))
        var x_mid = (x + self.x1) * 0.5
        var d1 = abs(x - self.x1).lt(Self.TOL2).select(
            self._next_AD1(x_mid, self._log_term(x_mid)),
            (ad2_x0 - self.ad2_x1) / (x - self.x1)
        )

        var x_bar = (x + self.x2) * 0.5
        var delta = x_bar - self.x1
        var u_bar = self._log_term(x_bar) # this calculation of 
        var fallback = abs(delta).lt(Self.TOL2).select(
            self._next_norm((x_bar + self.x1) * 0.5),
            (2.0 / delta) * (self._next_AD1(x_bar, u_bar) + (self.ad2_x1 - self._next_AD2(x_bar, u_bar)) / delta)
        )

        var out = abs(x - self.x2).lt(Self.TOL2).select(fallback, (2.0 / (x - self.x2)) * (d1 - self.d2))

        self.d2 = d1
        self.x2 = self.x1
        self.x1 = x
        self.ad2_x1 = ad2_x0
        return out

    def _next1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the first-order anti-aliased `tanh` of `x`.

        This method should be called iteratively for each sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `tanh` of `x`.
        """
        var mask: MBool[Self.num_chans] = abs(x - self. x1).lt(self.TOL)

        var out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x, self._log_term(x)) - self._next_AD1(self.x1, self._log_term(self.x1))) / (x - self.x1))
        self.x2 = self.x1
        self.x1 = x
        self.ad2_valid = False
        return out
    
    @doc_hidden
    @always_inline
    def _process[ADAA_Order: Int](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        comptime if ADAA_Order == 1:
            return self._next1(x)
        else:
            return self._next2(x)

    def reset(mut self):
        """Reset the internal state of the TanhAD."""
        self.initialized = False
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False
        self.downsampler.reset()
        self.upsampler.reset()

    @always_inline
    def next[ADAA_Order: Int = 1](mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Anti-aliased `tanh`.

        Computes the first or second order anti-aliased `tanh` of `x` using the ADAA method. If the os_index is greater than 0, oversampling is applied to the processing.

        Parameters:
            ADAA_Order: The order of the anti-derivative anti-aliasing (1 or 2). Second order aliases less, costs more, and delays the output by one sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `tanh` of `x`.
        """
        comptime assert ADAA_Order == 1 or ADAA_Order == 2, "TanhAD: ADAA_Order must be 1 or 2."
        var xs = clip_finite(x, Self.MAX_IN)

        comptime if Self.ov_samp == TimesOversampling.none:
            return self._process[ADAA_Order](xs)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.ov_samp.times):
                # upsample the input
                x2 = self.upsampler.next(xs, i)
                y = self._process[ADAA_Order](x2)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()

@doc_hidden
def buchla_cell[num_chans: SIMDLength](sig: MFloat[num_chans], sign: MFloat[num_chans], thresh: MFloat[num_chans], 
               sig_mul1: MFloat[num_chans], sign_mul: MFloat[num_chans], sig_mul2: MFloat[num_chans]) -> MFloat[num_chans]:
    """Implements the Buchla cell function."""
    var mask: MBool[num_chans] = abs(sig).gt(thresh)

    return mask.select((sig * sig_mul1 - (sign * sign_mul)) * sig_mul2, 0.0)

def buchla_wavefolder[num_chans: SIMDLength](input: MFloat[num_chans], var amp: Float64) -> MFloat[num_chans]:
    """Buchla waveshaper.

    Buchla waveshaper implementation as a function. Derived from Virual Analog Buchla 259e Wavefolderby Esqueda, etc. See the BuchlaWavefolder struct for an ADAA version with oversampling.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.

    Args:
        input: Signal in - between 0 and +/-40.
        amp: Amplitude/gain control (1 to 40).
    
    Returns:
        Waveshaped output signal.
    """
    # Generate sine wave at given phase
    amp = clip(amp, 1.0, 40.0)
    var sig = input * amp
    var sig_sign = sign(sig)

    # Apply Buchla cells
    var v1 = buchla_cell(sig, sig_sign, 0.6, 0.8333, 0.5, -12.0)
    var v2 = buchla_cell(sig, sig_sign, 2.994, 0.3768, 1.1281, -27.777)
    var v3 = buchla_cell(sig, sig_sign, 5.46, 0.2829, 1.5446, -21.428)
    var v4 = buchla_cell(sig, sig_sign, 1.8, 0.5743, 1.0338, 17.647)
    var v5 = buchla_cell(sig, sig_sign, 4.08, 0.2673, 1.0907, 36.363)
    var v6 = sig * 5.0
    
    var out = (v1 + v2 + v3) + (v4 + v5 + v6)

    # Scale output
    return tanh(out / amp)

@doc_hidden
struct BuchlaCell[num_chans: SIMDLength = 1](Copyable, Movable):
    var G: Float64       # folder cell "gain"
    var B: Float64       # folder cell "bias"
    var thresh: Float64  # folder cell "threshold"
    var mix: Float64     # folder cell mixing factor
    var Bp: Float64
    var Bpp: Float64
    comptime one_sixth: Float64 = 1.0 / 6.0

    def __init__(out self, G: Float64, B: Float64, thresh: Float64, mix: Float64):
        self.G = G
        self.B = B
        self.thresh = thresh
        self.mix = mix
        self.Bp = 0.5 * G * (thresh*thresh) - B * thresh
        self.Bpp = Self.one_sixth * G * (thresh*thresh*thresh) - 0.5 * B * (thresh*thresh) - thresh * self.Bp

    def func(self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).gt(self.thresh)
        return mask.select(self.G * x - self.B * sign(x), MFloat[Self.num_chans](0.0))

    def func_AD(self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).gt(self.thresh)
        return mask.select(0.5 * self.G * (x * x) - self.B * x * sign(x) - self.Bp, MFloat[Self.num_chans](0.0))

    def func_AD2(self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var sgn = sign(x)
        var mask: MBool[Self.num_chans] = abs(x).gt(self.thresh)
        return mask.select(Self.one_sixth * self.G * (x * x * x) - 0.5 * self.B * (x * x) * sgn - self.Bp * x - self.Bpp * sgn, MFloat[Self.num_chans](0.0))

struct BuchlaWavefolder[num_chans: SIMDLength = 1, ov_samp: TimesOversampling = TimesOversampling.x2](Copyable, Movable):
    """Buchla 259 style Wavefolder.
    
    Buchla 259 style wavefolder implementation with first or second order Anti-Derivative Anti-aliasing (ADAA) and Downsampler. Derived from Virual Analog Buchla 259e Wavefolderby Esqueda, etc. The ADAA technique is based on [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html).
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """
    
    comptime x_mix: Float64 = 5.0
    var cells: List[BuchlaCell[Self.num_chans]]
    comptime TOL: Float64 = 1.0e-5
    comptime TOL2: Float64 = 1.0e-3
    comptime MAX_IN: Float64 = 40.0  # documented input range; keeps the 2nd-order ADAA differences well-conditioned
    var x1: MFloat[Self.num_chans]
    var x2: MFloat[Self.num_chans]
    var ad2_x1: MFloat[Self.num_chans]
    var d2: MFloat[Self.num_chans]
    var ad2_valid: Bool  # False when ad2_x1/d2 are stale (start, reset, or after 1st-order calls)
    var prev_amp: Float64
    var world: World
    var downsampler: Downsampler[Self.num_chans, Self.ov_samp]
    var upsampler: Upsampler[Self.num_chans, Self.ov_samp]

    def __init__(out self, world: World):
        """Initialize the BuchlaWavefolder.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.world = world
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.ad2_x1 = MFloat[Self.num_chans](0.0)
        self.d2 = MFloat[Self.num_chans](0.0)
        self.ad2_valid = False
        self.prev_amp = -1.0  # forces the stored antiderivatives to be rebuilt on the first sample
        # Initialize folder cells
        self.cells = List[BuchlaCell[Self.num_chans]]()
        self.cells.append(BuchlaCell[Self.num_chans](0.8333, 0.5, 0.6, -12.0))
        self.cells.append(BuchlaCell[Self.num_chans](0.3768, 1.1281, 2.994, -27.777))
        self.cells.append(BuchlaCell[Self.num_chans](0.2829, 1.5446, 5.46, -21.428))
        self.cells.append(BuchlaCell[Self.num_chans](0.5743, 1.0338, 1.8, 17.647))
        self.cells.append(BuchlaCell[Self.num_chans](0.2673, 1.0907, 4.08, 36.363))
        self.downsampler = Downsampler[Self.num_chans, Self.ov_samp](world)
        self.upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)

    @doc_hidden
    def _next_norm(self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        var x2 = x * amp
        var y: MFloat[Self.num_chans] = Self.x_mix * x2
        for i in range(len(self.cells)):
            y += self.cells[i].mix * self.cells[i].func(x2)
        return y / amp

    @doc_hidden
    def _next_AD1(self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        var x2 = x * amp
        var y: MFloat[Self.num_chans] = 0.5 * Self.x_mix * (x2 * x2)
        for i in range(len(self.cells)):
            y += self.cells[i].mix * self.cells[i].func_AD(x2)
        return y / (amp * amp)

    @doc_hidden
    def _next_AD2(self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        var x2 = x * amp
        var y: MFloat[Self.num_chans] = (Self.x_mix / 6.0) * (x2 * x2 * x2)
        for i in range(len(self.cells)):
            y += self.cells[i].mix * self.cells[i].func_AD2(x2)
        return y / (amp * amp * amp)

    @doc_hidden
    @always_inline
    def _next2(mut self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        """
        Computes the second-order anti-aliased BuchlaWavefolder. The output is delayed by one sample.

        Args:
            x: The input sample.
            amp: The amplitude/gain control.

        Returns:
            The anti-aliased folded signal.
        """
        var safe_amp = max(amp, 1e-6)

        # amp changes the transfer function, so antiderivatives stored under the old amp no longer match.
        # Rebuild them under the new amp so both sides of each difference come from the same curve.
        # 1st-order calls only track x1 and x2, so the 2nd-order state is stale after them too.
        if safe_amp != self.prev_amp or not self.ad2_valid:
            self.ad2_x1 = self._next_AD2(self.x1, safe_amp)
            self.d2 = abs(self.x1 - self.x2).lt(Self.TOL2).select(
                self._next_AD1((self.x1 + self.x2) * 0.5, safe_amp),
                (self.ad2_x1 - self._next_AD2(self.x2, safe_amp)) / (self.x1 - self.x2)
            )
            self.prev_amp = safe_amp
            self.ad2_valid = True

        var ad2_x0 = self._next_AD2(x, safe_amp)
        var d1 = abs(x - self.x1).lt(Self.TOL2).select(
            self._next_AD1((x + self.x1) * 0.5, safe_amp),
            (ad2_x0 - self.ad2_x1) / (x - self.x1)
        )

        var x_bar = (x + self.x2) * 0.5
        var delta = x_bar - self.x1
        var fallback = abs(delta).lt(Self.TOL2).select(
            self._next_norm((x_bar + self.x1) * 0.5, safe_amp),
            (2.0 / delta) * (self._next_AD1(x_bar, safe_amp) + (self.ad2_x1 - self._next_AD2(x_bar, safe_amp)) / delta)
        )

        var out = abs(x - self.x2).lt(Self.TOL2).select(fallback, (2.0 / (x - self.x2)) * (d1 - self.d2))

        self.d2 = d1
        self.x2 = self.x1
        self.x1 = x
        self.ad2_x1 = ad2_x0
        return out

    @doc_hidden
    @always_inline
    def _next1(mut self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        """
        Computes the first-order anti-aliased BuchlaWavefolder.

        Args:
            x: The input sample.
            amp: The amplitude/gain control.

        Returns:
            The anti-aliased folded signal.
        """
        var safe_amp = max(amp, 1e-6)
    
        var mask = abs(x - self.x1).lt(self.TOL)
        var out = mask.select(
            self._next_norm((x + self.x1) * 0.5, safe_amp), 
            (self._next_AD1(x, safe_amp) - self._next_AD1(self.x1, safe_amp)) / (x - self.x1)
        )
        self.x2 = self.x1
        self.x1 = x
        self.ad2_valid = False
        return out

    @doc_hidden
    @always_inline
    def _process[ADAA_Order: Int](mut self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        comptime if ADAA_Order == 1:
            return self._next1(x, amp)
        else:
            return self._next2(x, amp)

    @always_inline
    def next[ADAA_Order: Int = 1](mut self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        """Anti-aliased BuchlaWavefolder.

        Computes the first or second order anti-aliased BuchlaWavefolder. If the ov_samp is greater than 0, oversampling is applied to the processing.

        Parameters:
            ADAA_Order: The order of the anti-derivative anti-aliasing (1 or 2). Second order aliases less, costs more, and delays the output by one sample.

        Args:
            x: The input sample.
            amp: The amplitude/gain control.

        Returns:
            The anti-aliased folded signal.
        """
        comptime assert ADAA_Order == 1 or ADAA_Order == 2, "BuchlaWavefolder: ADAA_Order must be 1 or 2."
        var xs = clip_finite(x, Self.MAX_IN)
        comptime if Self.ov_samp == TimesOversampling.none:
            return self._process[ADAA_Order](xs, amp)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.ov_samp.times):
                # upsample the input
                x2 = self.upsampler.next(xs, i)
                y = self._process[ADAA_Order](x2, amp)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()

struct WaveShaper[num_chans: SIMDLength = 1, interp: Interp = Interp.linear, times_ov: TimesOversampling = TimesOversampling.none](Copyable, Movable):
    """A waveshaper that reads its transfer function out of a buffer.

    The input is treated as a position along the table: -1 reads the first
    frame, 1 reads the last one, and anything outside that range is clipped
    rather than wrapped. Tables built by SuperCollider's `Signal.chebyFill`
    (and the Mojo `cheby_fill`) are laid out exactly this way, with x running
    from -1 to 1 across all `num_frames` frames.

    A buffer with more than one channel holds more than one transfer function,
    and `dist_frac` crossfades between them.

    Parameters:
        num_chans: The number of channels for SIMD operations.
        interp: The interpolation method to use when reading the table.
        times_ov: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
    """
    var world: World
    var upsampler: Upsampler[Self.num_chans, Self.times_ov]
    var downsampler: Downsampler[Self.num_chans, Self.times_ov]

    def __init__(out self, world: World):
        """Initialize the WaveShaper.

        Args:
            world: A pointer to the MMMWorld.
        """
        comptime assert Self.interp != Interp.sinc, (
            "WaveShaper does not support Interp.sinc. Use Interp.cubic for a smooth curve, and times_ov for anti-aliasing."
        )

        self.world = world
        self.upsampler = Upsampler[Self.num_chans, Self.times_ov](world)
        self.downsampler = Downsampler[Self.num_chans, Self.times_ov](world)

    @doc_hidden
    @always_inline
    def _phase(self, input: MFloat[Self.num_chans], num_frames: Int, num_frames_f64: Float64) -> MFloat[Self.num_chans]:
        """Turn an input sample into the phase that reads the matching frame.

        Scales the input from -1 to 1 into a frame index, and backs it off by 1.5 frames if using lagrange4 interpolation.
        """
        var scale: Float64 = Float64(num_frames - 1) / num_frames_f64 if num_frames > 1 else 0.0
        var f_idx = (0.5 + 0.5 * clip(input, -1.0, 1.0)) * scale

        # lagrange4() centres its kernel at fd = 1.5 + frac, so it reads 1.5
        # frames above the index it is handed. Back that out, holding at 0 so
        # the fractional part never goes negative.
        comptime if Self.interp == Interp.lagrange4:
            f_idx = max(f_idx - 1.5 / num_frames_f64, 0.0)

        return f_idx

    @doc_hidden
    @always_inline
    def _read[simd_chans: SIMDLength](mut self, input: MFloat[Self.num_chans], buffer: SIMDBuffer[simd_chans], dist_frac: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Read one sample per channel out of a SIMDBuffer table."""
        if buffer.num_frames == 0:
            return MFloat[Self.num_chans](0.0)

        var phase = self._phase(input, buffer.num_frames, buffer.num_frames_f64)

        # Where dist_frac lands between the buffer's tables.
        comptime max_chan = Int(simd_chans) - 1
        var chan_fl = Float64(max_chan) * clip(dist_frac, 0.0, 1.0)

        var out = MFloat[Self.num_chans](0.0)
        comptime for out_chan in range(Self.num_chans):
            var sample = buffer.at_phase[Self.interp, False, 0, True](self.world, phase[out_chan])
            var chan0 = clip(Int(chan_fl[out_chan]), 0, max_chan)
            var chan1 = clip(chan0 + 1, 0, max_chan)
            var frac = chan_fl[out_chan] - Float64(chan0)
            out[out_chan] = sample[chan0] * (1.0 - frac) + sample[chan1] * frac

        return out

    @doc_hidden
    @always_inline
    def _read(mut self, input: MFloat[Self.num_chans], buffer: Buffer, dist_frac: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Read one sample per channel out of a Buffer table."""
        if buffer.num_frames == 0 or buffer.num_chans == 0:
            return MFloat[Self.num_chans](0.0)

        var phase = self._phase(input, buffer.num_frames, buffer.num_frames_f64)

        var max_chan = Int(buffer.num_chans) - 1
        var chan_fl = Float64(max_chan) * clip(dist_frac, 0.0, 1.0)

        var out = MFloat[Self.num_chans](0.0)
        comptime for out_chan in range(Self.num_chans):
            var chan0 = clip(Int(chan_fl[out_chan]), 0, max_chan)
            var chan1 = clip(chan0 + 1, 0, max_chan)
            var frac = chan_fl[out_chan] - Float64(chan0)
            var sample0 = buffer.at_phase[Self.interp, False, 0, True](self.world, chan0, phase[out_chan])
            var sample1 = buffer.at_phase[Self.interp, False, 0, True](self.world, chan1, phase[out_chan])
            out[out_chan] = sample0[0] * (1.0 - frac) + sample1[0] * frac

        return out

    @always_inline
    def next[simd_chans: SIMDLength](mut self, input: MFloat[Self.num_chans], buffer: SIMDBuffer[simd_chans], dist_frac: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.0)) -> MFloat[Self.num_chans]:
        """Waveshape the input sample with a transfer function held in a SIMDBuffer.

        Parameters:
            simd_chans: Number of transfer functions stored in the buffer, one per channel.

        Args:
            input: The input sample. Values outside -1 to 1 are clipped.
            buffer: The SIMDBuffer holding the transfer function(s).
            dist_frac: A value between 0 and 1 that picks a transfer function from the buffer's channels, interpolating between neighbours. 0 is the first channel, 1 is the last.

        Returns:
            The waveshaped output sample.
        """
        comptime if Self.times_ov == TimesOversampling.none:
            return self._read(input, buffer, dist_frac)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.times_ov.times):
                x2 = self.upsampler.next(input, i)
                y = self._read(x2, buffer, dist_frac)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], buffer: Buffer, dist_frac: MFloat[Self.num_chans] = MFloat[Self.num_chans](0.0)) -> MFloat[Self.num_chans]:
        """Waveshape the input sample with a transfer function held in a Buffer.

        Args:
            input: The input sample. Values outside -1 to 1 are clipped.
            buffer: The Buffer holding the transfer function(s).
            dist_frac: A value between 0 and 1 that picks a transfer function from the buffer's channels, interpolating between neighbours. 0 is the first channel, 1 is the last.

        Returns:
            The waveshaped output sample.
        """
        comptime if Self.times_ov == TimesOversampling.none:
            return self._read(input, buffer, dist_frac)
        else:
            var x2: MFloat[Self.num_chans]
            var y: MFloat[Self.num_chans]
            comptime for i in range(Self.times_ov.times):
                x2 = self.upsampler.next(input, i)
                y = self._read(x2, buffer, dist_frac)
                self.downsampler.add_sample(y)
            return self.downsampler.get_sample()
