from mmm_audio import *
from std.math import tanh, floor, pi, exp, log, cosh

def bitcrusher[num_chans: Int](in_samp: MFloat[num_chans], bits: Int) -> MFloat[num_chans]:
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


struct Latch[num_chans: Int = 1](Copyable, Movable):
    """
    A simple latch that holds the last input sample when a trigger is received.

    Parameters:
        num_chans: The number of channels for SIMD operations.
    """
    var samp: MFloat[Self.num_chans]
    var last_trig: MBool[Self.num_chans]

    def __init__(out self):
        """Initialize the Latch."""
        self.samp = MFloat[Self.num_chans](0)
        self.last_trig = MBool[Self.num_chans](False)

    def next(mut self, in_samp: MFloat[Self.num_chans], trig: MBool[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Process the input sample and trigger, returning the latched output sample.

        Args:
            in_samp: The input sample to be latched.
            trig: A boolean trigger signal. When switching from false to true, the latch updates its output to the current input sample.

        Returns:
            The currently latched sample.
        """
        
        rising_edge: MBool[Self.num_chans] = trig & ~self.last_trig
        self.samp = rising_edge.select(in_samp, self.samp)
        self.last_trig = trig
        return self.samp

# Anti-Derivative Anti-aliasing functions are based on Jatin Chowdhury's python notebook: https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html and chowshapers: https://github.com/Chowdhury-DSP/chowdsp_utils/tree/master/modules/dsp/chowdsp_waveshapers/Waveshapers

# the trait currently doesn't work, but it will once parameters are included in traits

# trait ADAAfuncs[num_chans: Int = 1](Movable, Copyable):

#     def next_norm[num_chans: Int](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...

#     def next_AD1[num_chans: Int](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...
    
#     def next_AD2[num_chans: Int](mut self, input: MFloat[num_chans]) -> MFloat[num_chans]:
#         ...

# [TODO] implement 2nd order ADAA versions of hard clip, soft clip, tanh
# [TODO] implement a parameter in the .next functions to choose between none, and 1st and 2nd order ADAA

struct SoftClipAD[num_chans: Int = 1, os_index: Int = 0, degree: Int = 3](Copyable, Movable):
    """
    Anti-Derivative Anti-aliasing soft-clipping function.
    
    This struct provides first order anti-aliased `soft clip` function using the Anti-Derivative Anti-aliasing (ADAA) with optional Oversampling. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        os_index: The oversampling index (0 = no oversampling, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x).
        degree: The degree of the soft clipping polynomial (must be odd).
    """
    comptime times_oversampling = 2 ** Self.os_index    
    var x1: MFloat[Self.num_chans]
    var oversampling: Oversampling[Self.num_chans, Self.times_oversampling]
    var upsampler: Upsampler[Self.num_chans, Self.times_oversampling]
    var D: Float64
    var norm_factor: Float64
    var inv_norm_factor: Float64
    comptime TOL = 1.0e-5
    var G1: Float64

    def __init__(out self, world: World):
        self.x1 = MFloat[Self.num_chans](0.0)
        if Self.os_index > 1:
            print("SoftClipAD: os_index greater than 1 not supported yet. It will not sound good.")
        self.oversampling = Oversampling[Self.num_chans, Self.times_oversampling](world)
        self.upsampler = Upsampler[Self.num_chans, 2 ** Self.os_index](world)
        self.D = Float64(Self.degree // 2 * 2 + 1)  # ensure degree is odd
        self.norm_factor = (self.D - 1) / self.D
        self.inv_norm_factor = 1.0 / self.norm_factor
        self.G1 = 1.0 / (2.0 * (self.norm_factor * self.norm_factor)) - 1.0 / ((self.norm_factor * self.norm_factor) * self.D * (self.D + 1))

    @doc_hidden
    @always_inline
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Transfer function: x - x^n/n"""

        mask: MBool[Self.num_chans] = abs(x*self.norm_factor).gt(1.0)

        out = ((x * self.norm_factor) - pow(x * self.norm_factor, self.D) / self.D) * self.inv_norm_factor

        out = mask.select(sign(x), out)

        return out

    @doc_hidden
    @always_inline
    def _next_AD1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First antiderivative: x²/2 - x^(n+1) / (n*(n+1))"""
        mask: MBool[Self.num_chans] = abs(x*self.norm_factor).gt(1.0)

        outA = x * sign(x) + self.G1 - self.inv_norm_factor

        out = ((self.norm_factor * (x * x) / 2.0) - (pow(self.norm_factor, self.D) * pow(x, self.D + 1) / (self.D * (self.D + 1.0)))) * self.inv_norm_factor

        return mask.select(outA, out)

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
        mask = abs(x - self.x1).lt(self.TOL)

        out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x) - self._next_AD1(self.x1)) / (x - self.x1))
        self.x1 = x
        return out

    @always_inline
    def next(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First-order anti-aliased `hard_clip`.

        Computes the first-order anti-aliased `hard_clip` of `x`. If the os_index is greater than 0, oversampling is applied to the processing.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `soft_clip` of `x`.
        """
        comptime if Self.os_index == 0:
            return self._next1(x)
        else:
            comptime for i in range(self.times_oversampling):
                # upsample the input
                x2 = self.upsampler.next(x, i)
                y = self._next1(x2)
                self.oversampling.add_sample(y)
            return self.oversampling.get_sample()

def soft_clip[num_chans: Int](x: MFloat[num_chans], min_val: MFloat[num_chans] = -1., max_val: MFloat[num_chans] = 1.) -> MFloat[num_chans]:
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

struct HardClipAD[num_chans: Int = 1, os_index: Int = 0](Copyable, Movable):
    """
    Anti-Derivative Anti-aliasing hard-clipping function.
    
    This struct provides a first order anti-aliased version of the `hard_clip` function using the Anti-Derivative Anti-aliasing (ADAA) with optional Oversampling. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        os_index: The oversampling index (0 = no oversampling, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x).
    """
    var x1: MFloat[Self.num_chans]
    var x2: MFloat[Self.num_chans]
    var oversampling: Oversampling[Self.num_chans, 2 ** Self.os_index]
    var upsampler: Upsampler[Self.num_chans, 2 ** Self.os_index]
    comptime TOL = 1.0e-5

    def __init__(out self, world: World):
        """Initialize the HardClipAD.
        
        Args:
            world: A pointer to the MMMWorld.
        """
        self.x1 = MFloat[Self.num_chans](0.0)
        self.x2 = MFloat[Self.num_chans](0.0)
        self.oversampling = Oversampling[Self.num_chans, 2 ** Self.os_index](world)
        self.upsampler = Upsampler[Self.num_chans, 2 ** Self.os_index](world)

    @doc_hidden
    @always_inline
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        mask: MBool[Self.num_chans] = abs(x).lt(1.0)
        return mask.select(x, sign(x))

    @doc_hidden
    @always_inline
    def _next_AD1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        mask: MBool[Self.num_chans] = abs(x).lt(1.0)
        return mask.select(x * x * 0.5, x * sign(x) - 0.5)

    @doc_hidden
    @always_inline
    def _next_AD2(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        mask: MBool[Self.num_chans] = abs(x).lt(1.0)

        return mask.select(x * x * x / 6.0, ((x * x * 0.5) + (1.0 / 6.0)) * sign(x) - (x/2))

    @doc_hidden
    @always_inline
    def _calcD(mut self, x0: MFloat[Self.num_chans], x1: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:

        mask: MBool[Self.num_chans] = abs(x0 - x1).lt(self.TOL)

        return mask.select(
            self._next_AD1((x0 + x1) * 0.5),
            (self._next_AD2(x0) - self._next_AD2(x0) - self._next_AD2(x1)) / (x0 - x1)
        )

    @doc_hidden
    @always_inline
    def _fallback(mut self, x0: MFloat[Self.num_chans], x2: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        x_bar = (x0 + x2) * 0.5
        delta = x_bar - x0

        mask: MBool[Self.num_chans] = abs(delta).lt(self.TOL)  # Changed to abs(delta)
        return mask.select(
            self._next_norm((x_bar + x0) * 0.5),
            (2.0 / delta) * (self._next_AD1(x_bar) + (self._next_AD2(x0) - self._next_AD2(x_bar)) / delta)
        )

    @doc_hidden
    @always_inline
    def _next1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        mask: MBool[Self.num_chans] = abs(x - self. x1).lt(self.TOL)
        out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x) - self._next_AD1(self.x1)) / (x - self.x1))
        self.x1 = x
        return out

    @always_inline
    def next(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First-order anti-aliased `hard_clip`.

        Computes the first-order anti-aliased `hard_clip` of `x`. If the os_index is greater than 0, oversampling is applied to the processing.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `hard_clip` of `x`.
        """
        comptime if Self.os_index == 0:
            return self._next1(x)
        else:
            comptime times_oversampling = 2 ** Self.os_index
            comptime for i in range(times_oversampling):
                # upsample the input
                x2 = self.upsampler.next(x, i)
                y = self._next1(x2)
                self.oversampling.add_sample(y)
            return self.oversampling.get_sample()
    
struct TanhAD[num_chans: Int = 1, os_index: Int = 0](Copyable, Movable):
    """Anti-Derivative Anti-aliasing first order tanh function.
    
    This struct provides a first order anti-aliased version of the `tanh` function using the Anti-Derivative Anti-aliasing (ADAA) method with optional Oversampling. See [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html) for more details on how this works.

    Parameters:
        num_chans: The number of channels for SIMD operations.
        os_index: The oversampling index (0 = no oversampling, 1 = 2x, 2 = 4x, etc.).
    """

    var x1: MFloat[Self.num_chans]
    comptime TOL = 1.0e-5
    var oversampling: Oversampling[Self.num_chans, 2 ** Self.os_index]
    var upsampler: Upsampler[Self.num_chans, 2 ** Self.os_index]

    def __init__(out self, world: World):
        """Initialize the TanhAD.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.x1 = MFloat[Self.num_chans](0.0)
        self.oversampling = Oversampling[Self.num_chans, 2 ** Self.os_index](world)
        self.upsampler = Upsampler[Self.num_chans, 2 ** Self.os_index](world)

    @doc_hidden
    def _next_norm(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        return tanh(x)

    @doc_hidden
    def _next_AD1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        return log (cosh (x))

    def _next1(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """
        Computes the first-order anti-aliased `tanh` of `x`.

        This method should be called iteratively for each sample.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `tanh` of `x`.
        """
        mask: MBool[Self.num_chans] = abs(x - self. x1).lt(self.TOL)

        out = mask.select(self._next_norm((x + self.x1) * 0.5), (self._next_AD1(x) - self._next_AD1(self.x1)) / (x - self.x1))
        self.x1 = x
        return out
    
    @always_inline
    def next(mut self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """First-order anti-aliased `hard_clip`.

        Computes the first-order anti-aliased `hard_clip` of `x` using the ADAA method. If the os_index is greater than 0, oversampling is applied to the processing.

        Args:
            x: The input sample.

        Returns:
            The anti-aliased `hard_clip` of `x`.
        """
        comptime if Self.os_index == 0:
            return self._next1(x)
        else:
            comptime times_oversampling = 2 ** Self.os_index
            comptime for i in range(times_oversampling):
                # upsample the input
                x2 = self.upsampler.next(x, i)
                y = self._next1(x2)
                self.oversampling.add_sample(y)
            return self.oversampling.get_sample()

@doc_hidden
def buchla_cell[num_chans: Int](sig: MFloat[num_chans], sign: MFloat[num_chans], thresh: MFloat[num_chans], 
               sig_mul1: MFloat[num_chans], sign_mul: MFloat[num_chans], sig_mul2: MFloat[num_chans]) -> MFloat[num_chans]:
    """Implements the Buchla cell function."""
    var mask: MBool[num_chans] = abs(sig).gt(thresh)

    return mask.select((sig * sig_mul1 - (sign * sign_mul)) * sig_mul2, 0.0)

def buchla_wavefolder[num_chans: Int](input: MFloat[num_chans], var amp: Float64) -> MFloat[num_chans]:
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
    
    out = (v1 + v2 + v3) + (v4 + v5 + v6)

    # Scale output
    return tanh(out / amp)

@doc_hidden
struct BuchlaCell[num_chans: Int = 1](Copyable, Movable):
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
        mask: MBool[Self.num_chans] = abs(x).gt(self.thresh)
        return mask.select(self.G * x - self.B * sign(x), MFloat[Self.num_chans](0.0))

    def func_AD(self, x: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        var mask: MBool[Self.num_chans] = abs(x).gt(self.thresh)
        return mask.select(0.5 * self.G * (x * x) - self.B * x * sign(x) - self.Bp, MFloat[Self.num_chans](0.0))

    # def func_AD2(self, x: Float64) -> Float64:
    #     var sgn = sign(x)
    #     if abs(x) > self.thresh:
    #         return (Self.one_sixth * self.G * (x * x * x) 
    #                 - 0.5 * self.B * (x * x) * sgn 
    #                 - self.Bp * x 
    #                 - self.Bpp * sgn)
    #     return 0.0

struct BuchlaWavefolder[num_chans: Int = 1, os_index: Int = 1](Copyable, Movable):
    """Buchla 259 style Wavefolder.
    
    Buchla 259 style wavefolder implementation with Anti-Derivative Anti-aliasing (ADAA) and Oversampling. Derived from Virual Analog Buchla 259e Wavefolderby Esqueda, etc. The ADAA technique is based on [Practical Considerations for Antiderivative Anti-aliasing (Chowdhury)](https://ccrma.stanford.edu/~jatin/Notebooks/adaa.html).
    
    Parameters:
        num_chans: The number of channels for SIMD operations.
        os_index: The oversampling index (0 = no oversampling, 1 = 2x, 2 = 4x, etc.).
    """
    
    comptime x_mix: Float64 = 5.0
    var cells: List[BuchlaCell[Self.num_chans]]
    comptime TOL: Float64 = 1.0e-5
    var x1: MFloat[Self.num_chans]
    var world: World
    var oversampling: Oversampling[Self.num_chans, 2 ** Self.os_index]
    var upsampler: Upsampler[Self.num_chans, 2 ** Self.os_index]

    def __init__(out self, world: World):
        """Initialize the BuchlaWavefolder.

        Args:
            world: A pointer to the MMMWorld.
        """
        self.world = world
        self.x1 = MFloat[Self.num_chans](0.0)
        # Initialize folder cells
        self.cells = List[BuchlaCell[Self.num_chans]]()
        self.cells.append(BuchlaCell[Self.num_chans](0.8333, 0.5, 0.6, -12.0))
        self.cells.append(BuchlaCell[Self.num_chans](0.3768, 1.1281, 2.994, -27.777))
        self.cells.append(BuchlaCell[Self.num_chans](0.2829, 1.5446, 5.46, -21.428))
        self.cells.append(BuchlaCell[Self.num_chans](0.5743, 1.0338, 1.8, 17.647))
        self.cells.append(BuchlaCell[Self.num_chans](0.2673, 1.0907, 4.08, 36.363))
        self.oversampling = Oversampling[Self.num_chans, 2 ** Self.os_index](world)
        self.upsampler = Upsampler[Self.num_chans, 2 ** Self.os_index](world)

    @doc_hidden
    def _next_norm(self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        x2 = x * amp
        var y: MFloat[Self.num_chans] = Self.x_mix * x2
        for i in range(len(self.cells)):
            y += self.cells[i].mix * self.cells[i].func(x2)
        return y / amp

    @doc_hidden
    def _next_AD1(self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        x2 = x * amp
        var y: MFloat[Self.num_chans] = 0.5 * Self.x_mix * (x2 * x2)
        for i in range(len(self.cells)):
            y += self.cells[i].mix * self.cells[i].func_AD(x2)
        return y / (amp * amp)

    # def _wave_func_AD2(self, x: Float64, amp: Float64) -> Float64:
    #     x2 = x * amp
    #     var y: Float64 = (Self.x_mix / 6.0) * (x2 * x2 * x2)
    #     for i in range(len(self.cells)):
    #         y += self.cells[i].mix * self.cells[i].func_AD2(x2)
    #     return y
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
        safe_amp = max(amp, 1e-6)
    
        mask = abs(x - self.x1).lt(self.TOL)
        out = mask.select(
            self._next_norm((x + self.x1) * 0.5, safe_amp), 
            (self._next_AD1(x, safe_amp) - self._next_AD1(self.x1, safe_amp)) / (x - self.x1)
        )
        self.x1 = x
        return out

    @always_inline
    def next(mut self, x: MFloat[Self.num_chans], amp: Float64) -> MFloat[Self.num_chans]:
        """First-order anti-aliased BuchlaWavefolder.

        Computes the first-order anti-aliased BuchlaWavefolder. If the os_index is greater than 0, oversampling is applied to the processing.

        Args:
            x: The input sample.
            amp: The amplitude/gain control.

        Returns:
            The anti-aliased `hard_clip` of `x`.
        """
        comptime if Self.os_index == 0:
            return self._next1(x, amp)
        else:
            comptime times_oversampling = 2 ** Self.os_index
            comptime for i in range(times_oversampling):
                # upsample the input
                x2 = self.upsampler.next(x, i)
                y = self._next1(x2, amp)
                self.oversampling.add_sample(y)
            return self.oversampling.get_sample()