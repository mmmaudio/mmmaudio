from mmm_audio.constants import *
from mmm_audio.functions import *
from mmm_audio.Buffer_Module import Buffer
from mmm_audio.MMMWorld_Module import WindowType
from mmm_audio.FFTProcess_Module import FFTProcessable
from mmm_audio.ML.Analysis import GetFloat64Featurable
from mmm_audio.ML.MBufAnalysisBridge import MBufAnalysis
from std.complex import *
import std.math as Math
from std.sys import size_of, simd_width_of
from std.random import random_float64

@doc_hidden
def log2_int(n: Int) -> Int:
    """Compute log base 2 of an integer (assuming n is power of 2)."""
    var result = 0
    var temp = n
    while temp > 1:
        temp >>= 1
        result += 1
    return result

@doc_hidden
@always_inline
def _to_polar[nc: SIMDLength](
    result: List[ComplexSIMD[DType.float64, nc]],
    mut mags: List[MFloat[nc]],
    mut phases: List[MFloat[nc]],
    count: Int,
):
    """Convert the first `count` complex bins of `result` into magnitude/phase pairs."""
    var n = min(count, min(len(mags), len(phases)))
    var src = result.unsafe_ptr()
    var dst_mag = mags.unsafe_ptr()
    var dst_phase = phases.unsafe_ptr()

    var i = 0
    comptime if nc == 1:
        # A mono bin is a single Float64, so a run of bins can share one wide atan2.
        # Multi-channel bins are already SIMD vectors and get the same win per bin below.
        comptime assert size_of[ComplexSIMD[DType.float64, 1]]() == 2 * size_of[Float64](),
            "the deinterleaved load below assumes ComplexSIMD is a bare (re, im) pair"
        comptime BINS = 4
        var src_f = src.unsafe_bitcast[Float64]()
        var mag_f = dst_mag.unsafe_bitcast[Float64]()
        var phase_f = dst_phase.unsafe_bitcast[Float64]()
        while i + BINS <= n:
            # result stores each bin as (re, im), so split the run back into two vectors
            var parts = src_f.unsafe_load[width = 2 * BINS](2 * i).deinterleave()
            var re = parts[0]
            var im = parts[1]
            mag_f.unsafe_store(i, Math.sqrt(re * re + im * im))
            phase_f.unsafe_store(i, fast_atan2(im, re))
            i += BINS

    for k in range(i, n):
        var bin = src[unsafe_offset=k]
        dst_mag[unsafe_offset=k] = bin.norm()
        dst_phase[unsafe_offset=k] = fast_atan2(bin.im, bin.re)


@doc_hidden
@always_inline
def _from_polar[nc: SIMDLength](
    mags: List[MFloat[nc]],
    phases: List[MFloat[nc]],
    mut result: List[ComplexSIMD[DType.float64, nc]],
    count: Int,
):
    """Convert the first `count` magnitude/phase pairs back into complex bins."""
    var n = min(count, min(len(mags), len(phases)))
    var src_mag = mags.unsafe_ptr()
    var src_phase = phases.unsafe_ptr()
    var dst = result.unsafe_ptr()

    var k = 0
    comptime if nc == 1:
        # A mono bin is a single Float64, so a run of bins can share one wide sincos.
        # Multi-channel bins are already SIMD vectors and get the same win per bin below.
        comptime assert size_of[ComplexSIMD[DType.float64, 1]]() == 2 * size_of[Float64](),
            "the interleaved store below assumes ComplexSIMD is a bare (re, im) pair"
        comptime BINS = 4
        var mag_f = src_mag.unsafe_bitcast[Float64]()
        var phase_f = src_phase.unsafe_bitcast[Float64]()
        var dst_f = dst.unsafe_bitcast[Float64]()
        while k + BINS <= n:
            var mag = mag_f.unsafe_load[width=BINS](k)
            var trig = sincos(phase_f.unsafe_load[width=BINS](k))
            # result stores each bin as (re, im), so lane-interleave the two halves
            dst_f.unsafe_store(2 * k, (mag * trig[1]).interleave(mag * trig[0]))
            k += BINS

    for i in range(k, n):
        var mag = src_mag[unsafe_offset=i]
        var trig = sincos(src_phase[unsafe_offset=i])
        dst[unsafe_offset=i] = ComplexSIMD[DType.float64, nc](mag * trig[1], mag * trig[0])


struct RealFFT[num_chans: SIMDLength = 1](Copyable, Movable):
    """Real-valued FFT implementation using Cooley-Tukey algorithm.

    If you're looking to create an FFT-based FX, look to the [FFTProcessable](FFTProcess.md/#trait-fftprocessable)
    trait used in conjunction with [FFTProcess](FFTProcess.md/#struct-fftprocess) instead. This struct is a 
    lower-level implementation that provides
    FFT and inverse FFT on fixed windows of real values. [FFTProcessable](FFTProcess.md/#trait-fftprocessable) structs will enable you to 
    send audio samples (such as in a custom struct's `.next()` `def`) *into* and *out of* 
    an FFT, doing some manipulation of the magnitudes and phases in between. ([FFTProcess](FFTProcess.md/#struct-fftprocess)
    has this RealFFT struct inside of it.)

    Both the forward and the inverse transform pack the `window_size` real samples into a
    `window_size // 2` point complex transform, so a window costs half of what a full complex
    FFT of the same size would. `result` therefore holds only the `window_size // 2 + 1` unique
    bins of the spectrum; the mirrored upper half is implied by conjugate symmetry.

    Parameters:
        num_chans: Number of channels for SIMD processing.
    """
    comptime Complex = ComplexSIMD[DType.float64, Self.num_chans]

    var result: List[Self.Complex]
    var half: List[Self.Complex]
    var mags: List[MFloat[Self.num_chans]]
    var phases: List[MFloat[Self.num_chans]]
    var bit_reverse_lut: List[Int]
    var tw_re: List[Float64]
    var tw_im: List[Float64]
    var unpack_re: List[Float64]
    var unpack_im: List[Float64]
    var log_n: Int
    var scale: Float64
    var window_size: Int
    var half_size: Int

    def __init__(out self, window_size: Int):
        """Initialize the RealFFT struct.
        
        All internal buffers and lookup tables are set up here based on the Parameters.

        Args:
            window_size: FFT window size in samples.

        """
        self.window_size = window_size
        self.half_size = window_size // 2
        self.log_n = log2_int(self.half_size)
        # the packed transform is half_size points long, so the inverse normalises by 1/half_size
        self.scale = 1.0 / Float64(self.half_size)

        self.result = List[Self.Complex](length=self.half_size + 1, fill=Self.Complex(0.0, 0.0))
        self.half = List[Self.Complex](length=self.half_size, fill=Self.Complex(0.0, 0.0))
        self.mags = List[MFloat[Self.num_chans]](length=self.half_size + 1, fill=MFloat[Self.num_chans](0.0))
        self.phases = List[MFloat[Self.num_chans]](length=self.half_size + 1, fill=MFloat[Self.num_chans](0.0))

        # Butterfly twiddles
        self.tw_re = List[Float64](capacity=self.half_size)
        self.tw_im = List[Float64](capacity=self.half_size)
        for stage in range(1, self.log_n + 1):
            var m = 1 << stage
            for j in range(m >> 1):
                var angle = -2.0 * Math.pi * Float64(j) / Float64(m)
                var sin_a, cos_a = sincos(angle)  # sincos returns (sin, cos), in that order
                self.tw_re.append(cos_a)
                self.tw_im.append(sin_a)

        # exp(-2*pi*i*k/window_size), used to split the packed transform back into even/odd halves
        self.unpack_re = List[Float64](capacity=self.half_size)
        self.unpack_im = List[Float64](capacity=self.half_size)
        for k in range(self.half_size):
            var sin_a, cos_a = sincos(-2.0 * Math.pi * Float64(k) / Float64(window_size))
            self.unpack_re.append(cos_a)
            self.unpack_im.append(sin_a)

        self.bit_reverse_lut = List[Int](capacity=self.half_size)
        for i in range(self.half_size):
            self.bit_reverse_lut.append(self.bit_reverse(i, self.log_n))

    @doc_hidden
    def bit_reverse(self,num: Int, bits: Int) -> Int:
        """Reverse the bits of a number."""
        var result = 0
        var n = num
        for _ in range(bits):
            result = (result << 1) | (n & 1)
            n >>= 1
        return result

    def fft(mut self, input: List[MFloat[Self.num_chans]]):
        """Compute the FFT of the input real-valued samples.
        
        The resulting magnitudes and phases are stored in the internal `mags` and `phases` lists.
        
        Args:
            input: The input real-valued samples to transform. This can be a List of SIMD vectors for multi-channel processing or a List of Float64 for single-channel processing.
        """
        self._compute_fft(input)
        _to_polar(self.result, self.mags, self.phases, self.half_size + 1)

    def fft(mut self, input: List[MFloat[Self.num_chans]], mut mags: List[MFloat[Self.num_chans]], mut phases: List[MFloat[Self.num_chans]]):
        """Compute the FFT of the input real-valued samples.
        
        The resulting magnitudes and phases are stored in the provided lists.
        
        Args:
            input: The input real-valued samples to transform. This can be a List of SIMD vectors for multi-channel processing or a List of Float64 for single-channel processing.
            mags: A mutable list to store the magnitudes of the FFT result.
            phases: A mutable list to store the phases of the FFT result.
        """
        self._compute_fft(input)
        _to_polar(self.result, mags, phases, self.half_size + 1)

    @doc_hidden
    @always_inline
    def _butterflies[inverse: Bool](mut self):
        """In-place radix-2 Cooley-Tukey passes over `half`, which is already bit-reversed."""
        var buf = self.half.unsafe_ptr()
        var twr = self.tw_re.unsafe_ptr()
        var twi = self.tw_im.unsafe_ptr()
        for stage in range(1, self.log_n + 1):
            var m = 1 << stage
            var half_m = m >> 1
            var offset = half_m - 1
            for k in range(0, self.half_size, m):
                for j in range(half_m):
                    var w_im = twi[unsafe_offset=offset + j]
                    comptime if inverse:
                        w_im = -w_im
                    var w = Self.Complex(twr[unsafe_offset=offset + j], w_im)

                    var idx1 = k + j
                    var idx2 = idx1 + half_m

                    var t = w * buf[unsafe_offset=idx2]
                    var u = buf[unsafe_offset=idx1]

                    buf[unsafe_offset=idx1] = u + t
                    buf[unsafe_offset=idx2] = u - t

    @doc_hidden
    def _compute_fft(mut self, input: List[MFloat[Self.num_chans]]):
        # The loops below index the raw buffers, so bail out rather than run off the end
        if self.half_size < 1 or len(input) < self.window_size:
            return

        # Treat the real window as half_size complex points, z[i] = x[2i] + i*x[2i+1],
        # scattered straight into bit-reversed order.
        var buf = self.half.unsafe_ptr()
        var brev = self.bit_reverse_lut.unsafe_ptr()
        var src = input.unsafe_ptr()
        for i in range(self.half_size):
            buf[unsafe_offset=brev[unsafe_offset=i]] = Self.Complex(
                src[unsafe_offset=2 * i], src[unsafe_offset=2 * i + 1]
            )

        self._butterflies[inverse=False]()

        # Split the packed transform G into the even/odd spectra and recombine them.
        # G[0] is real in both parts, giving the DC and Nyquist bins directly.
        var spectrum = self.result.unsafe_ptr()
        var upr = self.unpack_re.unsafe_ptr()
        var upi = self.unpack_im.unsafe_ptr()

        var g0 = buf[unsafe_offset=0]
        spectrum[unsafe_offset=0] = Self.Complex(g0.re + g0.im, MFloat[Self.num_chans](0.0))
        spectrum[unsafe_offset=self.half_size] = Self.Complex(g0.re - g0.im, MFloat[Self.num_chans](0.0))

        for k in range(1, self.half_size):
            var gk = buf[unsafe_offset=k]
            var gc = buf[unsafe_offset=self.half_size - k].conj()

            var even = (gk + gc) * 0.5
            var odd = (gk - gc) * Self.Complex(0.0, -0.5)
            var twiddle = Self.Complex(upr[unsafe_offset=k], upi[unsafe_offset=k])

            spectrum[unsafe_offset=k] = even + odd * twiddle

    def ifft(mut self, mut output: List[MFloat[Self.num_chans]]):
        """Compute the inverse FFT using the internal magnitudes and phases.
        
        The output real-valued samples are written to the provided output list.

        Args:
            output: A mutable list to store the output real-valued samples.
        """
        _from_polar(self.mags, self.phases, self.result, self.half_size + 1)
        self._compute_inverse_fft(output)

    def ifft(mut self, mags: List[MFloat[Self.num_chans]], phases: List[MFloat[Self.num_chans]], mut output: List[MFloat[Self.num_chans]]):
        """Compute the inverse FFT using the provided magnitudes and phases.
        
        The output real-valued samples are written to the provided output list.

        Args:
            mags: A list of magnitudes for the inverse FFT.
            phases: A list of phases for the inverse FFT.
            output: A mutable list to store the output real-valued samples.
        """
        _from_polar(mags, phases, self.result, self.half_size + 1)
        self._compute_inverse_fft(output)

    @doc_hidden
    def _compute_inverse_fft(mut self, mut output: List[MFloat[Self.num_chans]]):
        if self.half_size < 1:
            return

        # Fold the half-spectrum back into half_size complex points -- the exact inverse of the
        # split done at the end of _compute_fft -- so the inverse costs the same as the forward.
        var buf = self.half.unsafe_ptr()
        var brev = self.bit_reverse_lut.unsafe_ptr()
        var spectrum = self.result.unsafe_ptr()
        var upr = self.unpack_re.unsafe_ptr()
        var upi = self.unpack_im.unsafe_ptr()

        var dc = spectrum[unsafe_offset=0].re
        var nyquist = spectrum[unsafe_offset=self.half_size].re
        buf[unsafe_offset=brev[unsafe_offset=0]] = Self.Complex(
            (dc + nyquist) * 0.5, (dc - nyquist) * 0.5
        )

        for k in range(1, self.half_size):
            var xk = spectrum[unsafe_offset=k]
            var xc = spectrum[unsafe_offset=self.half_size - k].conj()

            var even = (xk + xc) * 0.5
            # (xk - xc) * 0.5 is W_N^k * odd[k], so undo the rotation with the conjugate twiddle
            var odd = (xk - xc) * 0.5 * Self.Complex(upr[unsafe_offset=k], -upi[unsafe_offset=k])

            # G[k] = even[k] + i*odd[k]
            buf[unsafe_offset=brev[unsafe_offset=k]] = Self.Complex(
                even.re - odd.im, even.im + odd.re
            )

        self._butterflies[inverse=True]()

        # z[i] carries the even samples in its real part and the odd samples in its imaginary part
        var n = min(self.half_size, len(output) // 2)
        var dst = output.unsafe_ptr()
        for i in range(n):
            var z = buf[unsafe_offset=i]
            dst[unsafe_offset=2 * i] = z.re * self.scale
            dst[unsafe_offset=2 * i + 1] = z.im * self.scale
    
    @staticmethod
    def fft_frequencies(sr: Float64, n_fft: Int, min_bin: Int = 0, num_bins: Int = -1) -> List[Float64]:
        """Compute the FFT bin center frequencies.

        This implementation is based on Librosa's eponymous [function](https://librosa.org/doc/main/generated/librosa.fft_frequencies.html).

        Args:
            sr: The sample rate of the audio signal.
            n_fft: The size of the FFT.
            min_bin: The minimum FFT bin index to include.
            num_bins: The number of FFT bins to include. Defaults to all bins from min_bin to n_fft//2.

        Returns:
            A List of Float64 representing the center frequencies of each FFT bin.
        """
        var nyquist_bin = n_fft // 2
        var min_b = max(min_bin, 0)
        var max_possible = nyquist_bin - min_b + 1
        var count = num_bins
        if count < 0 or count > max_possible:
            count = max_possible
        if count <= 0:
            return List[Float64]()
        var binHz = sr / Float64(n_fft)
        var freqs = List[Float64](length=count, fill=0.0)
        var dst = freqs.unsafe_ptr()

        # The bin index is just a ramp, so build it with iota and write a whole vector at a
        # time. Four native vectors per store keeps the loop from being latency bound.
        comptime BINS = 4 * simd_width_of[DType.float64]()
        var i = 0
        while i + BINS <= count:
            dst.unsafe_store(
                i, (Math.iota[DType.float64, BINS]() + Float64(min_b + i)) * binHz
            )
            i += BINS

        for k in range(i, count):
            dst[unsafe_offset=k] = Float64(min_b + k) * binHz
        return freqs^

    @staticmethod
    def buf_analysis(buf: Buffer, chan: Int,start_frame: Int, var num_frames: Int, window_size: Int, hop_size: Int, window_type: WindowType = WindowType.hann) -> Tuple[List[List[Float64]], List[List[Float64]]]:
        """Compute the Short-Time Fourier Transform (STFT) of a buffer.

        Args:
            buf: The input audio buffer to analyze.
            chan: The channel index to analyze from the buffer.
            start_frame: The starting frame index in the buffer to begin analysis.
            num_frames: The number of frames to analyze from the starting frame.
            window_size: The size of the FFT window.
            hop_size: The hop size between successive windows.
            window_type: The type of window to apply to each frame before computing the FFT.

        Returns:
            A tuple containing two lists of lists of Float64 representing the magnitudes and phases of the STFT for each frame and frequency bin.
        """
        var fftanalysis = FFTAnalysis()
        try:
            var magsphss = MBufAnalysis.fft_process(fftanalysis,buf,chan,start_frame,num_frames,window_size,hop_size,window_type=window_type)
            var nframes = len(magsphss)
            var nmags = len(magsphss[0]) // 2
            var mags = List[List[Float64]](length=nframes, fill=List[Float64](length=nmags, fill=0.0))
            var phss = List[List[Float64]](length=nframes, fill=List[Float64](length=nmags, fill=0.0))
            for frame_idx, frame in enumerate(magsphss):
                for i in range(nmags):
                    mags[frame_idx][i] = frame[i]
                    phss[frame_idx][i] = frame[nmags + i]
            return mags^, phss^
        except e:
            abort(String(e))

@doc_hidden
struct FFTAnalysis(FFTProcessable, GetFloat64Featurable):
    var mags: List[Float64]
    var phss: List[Float64]

    def __init__(out self):
        self.mags = List[Float64]()
        self.phss = List[Float64]()

    def next_frame(mut self, mags: List[Float64], phases: List[Float64]):
        self.mags = mags.copy()
        self.phss = phases.copy()
    
    def get_features(self) -> List[Float64]:
        var nmags = len(self.mags)
        var features = List[Float64](length=nmags * 2, fill=0.0)
        for i in range(nmags):
            features[i] = self.mags[i]
        for i in range(nmags):
            features[nmags + i] = self.phss[i]
        return features^


@doc_hidden
struct HeapItem(Copyable, Movable, ImplicitlyCopyable):
    """A heap item storing (priority, index) pair for max heap."""
    var priority: Float64
    var index: Int

    def __init__(out self, priority: Float64, index: Int):
        self.priority = priority
        self.index = index

    def __lt__(self, other: Self) -> Bool:
        return self.priority < other.priority

    def __le__(self, other: Self) -> Bool:
        return self.priority <= other.priority

    def __gt__(self, other: Self) -> Bool:
        return self.priority > other.priority

    def __ge__(self, other: Self) -> Bool:
        return self.priority >= other.priority

    def __eq__(self, other: Self) -> Bool:
        return self.priority == other.priority and self.index == other.index

    def __ne__(self, other: Self) -> Bool:
        return not (self == other)


@doc_hidden
struct MaxHeap(Copyable, Movable):
    """Simple max heap implementation for RTPGHI."""
    var items: List[HeapItem]

    def __init__(out self):
        self.items = List[HeapItem]()

    def __init__(out self, capacity: Int):
        self.items = List[HeapItem]()
        self.items.reserve(capacity)

    def clear(mut self):
        self.items.clear()

    def size(self) -> Int:
        return len(self.items)

    def push(mut self, item: HeapItem):
        """Push an item onto the heap."""
        self.items.append(item)
        self._bubble_up(len(self.items) - 1)

    def pop(mut self) -> HeapItem:
        """Pop the maximum item from the heap."""
        var result = self.items[0]
        var last = self.items.pop()
        if len(self.items) > 0:
            self.items[0] = last
            self._bubble_down(0)
        return result

    def _bubble_up(mut self, idx: Int):
        """Move item up to maintain heap property."""
        var current = idx
        while current > 0:
            var parent = (current - 1) // 2
            if self.items[current].priority > self.items[parent].priority:
                var temp = self.items[current]
                self.items[current] = self.items[parent]
                self.items[parent] = temp
                current = parent
            else:
                break

    def _bubble_down(mut self, idx: Int):
        """Move item down to maintain heap property."""
        var current = idx
        var size = len(self.items)
        
        while True:
            var largest = current
            var left = 2 * current + 1
            var right = 2 * current + 2
            
            if left < size and self.items[left].priority > self.items[largest].priority:
                largest = left
            
            if right < size and self.items[right].priority > self.items[largest].priority:
                largest = right
            
            if largest != current:
                var temp = self.items[current]
                self.items[current] = self.items[largest]
                self.items[largest] = temp
                current = largest
            else:
                break


struct RTPGHI(Copyable, Movable):
    """Real-Time Phase Gradient Heap Integration for spectrogram inversion.

    Based on: Zdenek Prusa and Peter L. Soendergaard,
    "Real-time spectrogram inversion using phase gradient heap integration"
    Proceedings of DAFX 2016

    This implementation uses one look-ahead frame for best quality.
    The algorithm reconstructs phase for frame n-1 using magnitude information
    from frames n-2, n-1, and n.
    
    The `process_frame` method automatically delays the output magnitudes to match
    the reconstructed phases, so both outputs correspond to the same frame (n-1).
    """
    comptime EPSILON: Float64 = 1e-10
    comptime LOG_EPSILON: Float64 = log(1e-10)

    var bins: Int
    var fft_size: Int
    var hop_size: Int
    var gamma: Float64
    
    # State buffers (3 frames of history)
    var log_mag_n_minus_2: List[Float64]  # Frame n-2
    var log_mag_n_minus_1: List[Float64]  # Frame n-1 (frame being reconstructed)
    var log_mag_n: List[Float64]          # Frame n (current/look-ahead frame)
    
    # Linear magnitude buffer for output (frame n-1)
    var mag_n_minus_1: List[Float64]
    var output_mags: List[Float64]
    
    var phase_n_minus_2: List[Float64]    # Reconstructed phase for frame n-2
    var phase_n_minus_1: List[Float64]    # Reconstructed phase for frame n-1
    
    # Phase gradients for frame n-1
    var phi_t_n_minus_2: List[Float64]    # Time gradient at n-2
    var phi_t_n_minus_1: List[Float64]    # Time gradient at n-1
    var phi_omega_n_minus_1: List[Float64] # Frequency gradient at n-1
    
    # Working buffers
    var todo: List[Bool]
    var phase_estimate: List[Float64]
    var heap: MaxHeap
    
    var frame_count: Int

    def __init__(out self, fft_size: Int, hop_size: Int):
        """Initialize RTPGHI with FFT size and hop size.
        
        Args:
            fft_size: The FFT size (window size).
            hop_size: The hop size between frames.
        """
        self.fft_size = fft_size
        self.hop_size = hop_size
        self.bins = fft_size // 2 + 1
        
        # Gamma for Hann window (from paper Table 1)
        # gamma = C_g * len(g)^2 where C_g = 0.25645 for Hann
        self.gamma = 0.25645 * Float64(fft_size * fft_size)
        
        # Initialize state buffers
        self.log_mag_n_minus_2 = List[Float64](length=self.bins, fill=Self.LOG_EPSILON)
        self.log_mag_n_minus_1 = List[Float64](length=self.bins, fill=Self.LOG_EPSILON)
        self.log_mag_n = List[Float64](length=self.bins, fill=Self.LOG_EPSILON)
        
        # Linear magnitude buffer for delayed output
        self.mag_n_minus_1 = List[Float64](length=self.bins, fill=0.0)
        self.output_mags = List[Float64](length=self.bins, fill=0.0)
        
        self.phase_n_minus_2 = List[Float64](length=self.bins, fill=0.0)
        self.phase_n_minus_1 = List[Float64](length=self.bins, fill=0.0)
        
        self.phi_t_n_minus_2 = List[Float64](length=self.bins, fill=0.0)
        self.phi_t_n_minus_1 = List[Float64](length=self.bins, fill=0.0)
        self.phi_omega_n_minus_1 = List[Float64](length=self.bins, fill=0.0)
        
        # Working buffers
        self.todo = List[Bool](length=self.bins, fill=False)
        self.phase_estimate = List[Float64](length=self.bins, fill=0.0)
        self.heap = MaxHeap(self.bins * 2)
        
        self.frame_count = 0
        
        # Pre-compute initial phase gradients
        _compute_phi_t(self.log_mag_n_minus_2, self.phi_t_n_minus_2, self.fft_size, self.hop_size, self.gamma)

    def reset(mut self):
        """Reset the RTPGHI state."""
        for i in range(self.bins):
            self.log_mag_n_minus_2[i] = Self.LOG_EPSILON
            self.log_mag_n_minus_1[i] = Self.LOG_EPSILON
            self.log_mag_n[i] = Self.LOG_EPSILON
            self.mag_n_minus_1[i] = 0.0
            self.phase_n_minus_2[i] = 0.0
            self.phase_n_minus_1[i] = 0.0
            self.phi_t_n_minus_2[i] = 0.0
            self.phi_t_n_minus_1[i] = 0.0
            self.phi_omega_n_minus_1[i] = 0.0
        self.frame_count = 0

    def process_frame(
        mut self,
        mut magnitudes: List[Float64],
        mut phases: List[Float64],
        tolerance: Float64 = 1e-6
    ):
        """Process a magnitude spectrum frame and output matched magnitudes and phases.
        
        This function takes the current frame's magnitudes as input and outputs
        the previous frame's magnitudes along with their reconstructed phases.
        Both outputs correspond to frame n-1, ensuring they are properly synchronized.
        
        Due to the one-frame look-ahead requirement, the first call will output
        zeros for both magnitudes and phases.
        
        Args:
            magnitudes: On input, the magnitude spectrum for frame n (bins elements).
                       On output, the magnitude spectrum for frame n-1.
            phases: Output phase spectrum for frame n-1 (bins elements, radians).
            tolerance: Relative magnitude threshold for phase reconstruction.
        """
        
        for i in range(self.bins):
            # Store the previous frame's linear magnitudes for output before shifting
            # (these are the magnitudes that correspond to the phases we'll compute)
            self.output_mags[i] = self.mag_n_minus_1[i]  # Store n-1 mags for output
            
            # Shift the frame buffers
            # n-2 <- n-1, n-1 <- n, n <- new input
            self.log_mag_n_minus_2[i] = self.log_mag_n_minus_1[i]
            self.log_mag_n_minus_1[i] = self.log_mag_n[i]
            # Compute log magnitude for new frame, with floor for numerical stability
            self.log_mag_n[i] = Math.log(max(magnitudes[i], Self.EPSILON))
        
        # Shift linear magnitude buffer (store current input for next frame's output)
        for i in range(self.bins):
            self.mag_n_minus_1[i] = magnitudes[i]
        
        # Shift phase estimates
        for i in range(self.bins):
            self.phase_n_minus_2[i] = self.phase_n_minus_1[i]
        
        # Shift time gradients
        for i in range(self.bins):
            self.phi_t_n_minus_2[i] = self.phi_t_n_minus_1[i]
        
        # Compute new gradients for frame n-1 (the frame we're reconstructing)
        _compute_phi_t(self.log_mag_n_minus_1, self.phi_t_n_minus_1, self.fft_size, self.hop_size, self.gamma)
        _compute_phi_omega(
            self.log_mag_n_minus_2,
            self.log_mag_n,
            self.phi_omega_n_minus_1,
            self.fft_size,
            self.hop_size,
            self.gamma
        )
        
        self.frame_count += 1
        
        # Need at least 2 frames to start producing valid output
        if self.frame_count < 2:
            # Output zeros for both magnitudes and phases for the first frame
            for i in range(self.bins):
                magnitudes[i] = 0.0
                phases[i] = 0.0
            return
        
        # Output the delayed magnitudes (frame n-1)
        for i in range(self.bins):
            magnitudes[i] = self.output_mags[i]
        
        # Compute absolute tolerance based on max log magnitude
        var max_log_mag = self.log_mag_n_minus_1[0]
        var max_log_mag_prev = self.log_mag_n_minus_2[0]
        for i in range(1, self.bins):
            if self.log_mag_n_minus_1[i] > max_log_mag:
                max_log_mag = self.log_mag_n_minus_1[i]
            if self.log_mag_n_minus_2[i] > max_log_mag_prev:
                max_log_mag_prev = self.log_mag_n_minus_2[i]
        
        var abs_tol = Math.log(tolerance) + max(max_log_mag, max_log_mag_prev)
        
        # Initialize: mark bins above tolerance as needing processing
        var num_todo = 0
        for i in range(self.bins):
            var needs_processing = self.log_mag_n_minus_1[i] > abs_tol
            self.todo[i] = needs_processing
            if needs_processing:
                num_todo += 1
            # Initialize with random phase for bins below tolerance
            self.phase_estimate[i] = random_float64(-Math.pi, Math.pi)
        
        # Initialize heap with bins from frame n-2 (previous reconstructed frame)
        self.heap.clear()
        for i in range(self.bins):
            if self.log_mag_n_minus_2[i] > abs_tol:
                # Use negative indices for previous frame bins
                # Positive indices (0 to bins-1) for current frame bins
                self.heap.push(HeapItem(self.log_mag_n_minus_2[i], -(i + 1)))
        
        # Heap integration algorithm (Algorithm 1 from paper)
        while num_todo > 0 and self.heap.size() > 0:
            var item = self.heap.pop()
            var idx = item.index
            
            if idx < 0:
                # This is from the previous frame (n-2)
                # Propagate to current frame (n-1) in time direction
                var m = -(idx + 1)  # Convert back to bin index
                
                if self.todo[m]:
                    # Equation from paper line 11:
                    # φ(m,n) = φ(m,n-1) + 0.5*(φ_t(m,n-1) + φ_t(m,n))
                    self.phase_estimate[m] = (
                        self.phase_n_minus_2[m] +
                        0.5 * (self.phi_t_n_minus_2[m] + self.phi_t_n_minus_1[m])
                    )
                    self.todo[m] = False
                    num_todo -= 1
                    # Add to heap for frequency propagation
                    self.heap.push(HeapItem(self.log_mag_n_minus_1[m], m))
            else:
                # This is from current frame (n-1)
                # Propagate to neighbors in frequency direction
                var m = idx
                
                # Propagate to higher frequency neighbor (m+1)
                if m < self.bins - 1 and self.todo[m + 1]:
                    # Equation from paper line 18:
                    # φ(m+1,n) = φ(m,n) + 0.5*(φ_ω(m,n) + φ_ω(m+1,n))
                    self.phase_estimate[m + 1] = (
                        self.phase_estimate[m] +
                        0.5 * (self.phi_omega_n_minus_1[m] + self.phi_omega_n_minus_1[m + 1])
                    )
                    self.todo[m + 1] = False
                    num_todo -= 1
                    self.heap.push(HeapItem(self.log_mag_n_minus_1[m + 1], m + 1))
                
                # Propagate to lower frequency neighbor (m-1)
                if m > 0 and self.todo[m - 1]:
                    # Equation from paper line 23:
                    # φ(m-1,n) = φ(m,n) - 0.5*(φ_ω(m,n) + φ_ω(m-1,n))
                    self.phase_estimate[m - 1] = (
                        self.phase_estimate[m] -
                        0.5 * (self.phi_omega_n_minus_1[m] + self.phi_omega_n_minus_1[m - 1])
                    )
                    self.todo[m - 1] = False
                    num_todo -= 1
                    self.heap.push(HeapItem(self.log_mag_n_minus_1[m - 1], m - 1))
        
        # Store the reconstructed phase for next iteration and output
        for i in range(self.bins):
            self.phase_n_minus_1[i] = self.phase_estimate[i]
            phases[i] = self.phase_estimate[i]


@doc_hidden
def _compute_phi_t(log_mag: List[Float64], mut phi_t: List[Float64], fft_size: Int, hop_size: Int, gamma: Float64):
    """Compute phase time gradient using frequency derivative of log-magnitude.
    
    From paper equation (14):
    φ_t(m,n) = (aM)/(2γ) * (s_log(m+1,n) - s_log(m-1,n)) + 2πam/M
    
    where m is frequency bin, a is hop_size, M is fft_size, γ is gamma.
    """
    var bins = fft_size // 2 + 1
    var a = Float64(hop_size)
    var M = Float64(fft_size)
    var coef = (a * M) / (2.0 * gamma)
    
    # DC bin (m=0): set derivative to 0, keep only the constant term
    phi_t[0] = 0.0
    
    # Middle bins: centered difference for frequency derivative
    for m in range(1, bins - 1):
        var freq_deriv = 0.5 * (log_mag[m + 1] - log_mag[m - 1])
        var constant_term = Math.tau * a * Float64(m) / M
        phi_t[m] = coef * freq_deriv + constant_term
    
    # Nyquist bin: use one-sided difference
    var m_last = bins - 1
    var freq_deriv_last = log_mag[m_last] - log_mag[m_last - 1]
    var constant_term_last = Math.tau * a * Float64(m_last) / M
    phi_t[m_last] = coef * freq_deriv_last + constant_term_last


@doc_hidden
def _compute_phi_omega(
    log_mag_prev: List[Float64],
    log_mag_next: List[Float64],
    mut phi_omega: List[Float64],
    fft_size: Int,
    hop_size: Int,
    gamma: Float64
):
    """Compute phase frequency gradient using time derivative of log-magnitude.
    
    From paper equation (13):
    φ_ω(m,n) = -γ/(2aM) * (s_log(m,n+1) - s_log(m,n-1))
    
    Uses centered difference across frames n-1 and n+1 to get derivative at n.
    """
    var a = Float64(hop_size)
    var M = Float64(fft_size)
    var coef = -gamma / (2.0 * a * M)
    
    for m in range(fft_size // 2 + 1):
        var time_deriv = 0.5 * (log_mag_next[m] - log_mag_prev[m])
        phi_omega[m] = coef * time_deriv
