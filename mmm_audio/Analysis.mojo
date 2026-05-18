from mmm_audio import *
from std.math import ceil, floor, log2, log, exp, sqrt, cos, pi
from std.math import sqrt

@always_inline
@doc_hidden
def parabolic_refine(prev: Float64, cur: Float64, next: Float64) -> Tuple[Float64, Float64]:
    denom = prev - 2.0 * cur + next
    if abs(denom) < 1e-12:
        return (0.0, cur)
    p = 0.5 * (prev - next) / denom
    refined_val = cur - 0.25 * (prev - next) * p
    return (p, refined_val)

@always_inline
@doc_hidden
def spectral_amp_prepare(
    mags: List[Float64],
    sample_rate: Float64,
    min_freq: Float64,
    max_freq: Float64,
    log_freq: Bool,
    power_mag: Bool,
    mut amp: List[Float64],
    mut amp_sum: Float64,
    mut max_amp: Float64,
    mut min_bin: Int,
    mut max_bin: Int,
    mut bin_hz: Float64,
) -> Bool:
    var n_bins = len(mags)

    var max_f = max_freq
    if max_f < 0.0:
        max_f = sample_rate / 2.0
    max_f = min(max_f, sample_rate / 2.0)

    var fft_size = (n_bins - 1) * 2
    bin_hz = sample_rate / Float64(fft_size)

    min_bin = Int(ceil(min_freq / bin_hz))
    max_bin = Int(floor(max_f / bin_hz))
    min_bin = max(min_bin, 0)
    max_bin = min(max_bin, n_bins - 1)

    if log_freq and min_bin == 0:
        min_bin = 1

    var size = max_bin - min_bin

    amp = List[Float64](length=size, fill=0.0)
    amp_sum = 0.0
    max_amp = 0.0
    var eps: Float64 = 1.0e-12
    for i in range(size):
        var bin = min_bin + i
        var v = max(mags[bin], eps)
        if power_mag:
            v = v * v
        amp[i] = v
        amp_sum += v
        if v > max_amp:
            max_amp = v

    return True

@always_inline
@doc_hidden
def spectral_freqs_prepare(
    min_bin: Int,
    max_bin: Int,
    bin_hz: Float64,
    log_freq: Bool,
    mut freqs: List[Float64],
):
    var size = max_bin - min_bin
    if size <= 0:
        freqs = List[Float64]()
        return

    var nyquist_bin = max(max_bin, 1)
    var n_fft = nyquist_bin * 2
    var sr = bin_hz * Float64(n_fft)
    freqs = RealFFT.fft_frequencies(sr=sr, n_fft=n_fft, min_bin=min_bin, num_bins=size)

    if log_freq:
        for i in range(size):
            freqs[i] = 69.0 + 12.0 * log2(freqs[i] / 440.0)

    return

trait GetFloat64Featurable:
    def get_features(self) -> List[Float64]:...

struct YIN(BufferedProcessable,GetFloat64Featurable):
    """Monophonic Frequency ('F0') Detection using the YIN algorithm (FFT-based, O(N log N) version)."""
    var pitch: Float64
    var confidence: Float64
    var sample_rate: Float64
    var fft: RealFFT[]
    var fft_input: List[Float64]
    var fft_power_mags: List[Float64]
    var fft_zero_phases: List[Float64]
    var acf_real: List[Float64]
    var yin_buffer: List[Float64]
    var yin_values: List[Float64]
    var window_size: Int
    var min_freq: Float64
    var max_freq: Float64

    def __init__(out self, sr: Float64, window_size: Int = 1024, min_freq: Float64 = 20.0, max_freq: Float64 = 20000.0):
        """Initialize the YIN pitch detector.

        Args:
            sr: The sample rate from the MMMWorld.
            window_size: The size of the analysis window in samples.
            min_freq: The minimum frequency to consider for pitch detection.
            max_freq: The maximum frequency to consider for pitch detection.

        Returns:
            An initialized YIN struct.
        """

        self.window_size = window_size
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.pitch = 0.0
        self.confidence = 0.0
        self.sample_rate = sr
        self.fft = RealFFT(window_size * 2)
        self.fft_input = List[Float64](length=window_size * 2, fill=0.0)
        self.fft_power_mags = List[Float64](length=window_size + 1, fill=0.0)
        self.fft_zero_phases = List[Float64](length=window_size + 1, fill=0.0)
        self.acf_real = List[Float64](length=window_size * 2, fill=0.0)
        self.yin_buffer = List[Float64](length=window_size, fill=0.0)
        self.yin_values = List[Float64](length=window_size, fill=0.0)
    
    def get_features(self) -> List[Float64]:
        """Return the current pitch and confidence as a List of Float64."""
        return [self.pitch, self.confidence]

    def next_window(mut self, mut frame: List[Float64]):
        """Compute the YIN pitch estimate for the given frame of audio samples.

        Args:
            frame: The input audio frame of size `window_size`. This List gets passed from [BufferedProcess](BufferedProcess.md).
        """

        # 1. Prepare input for FFT (Zero padding)
        for i in range(len(frame)):
            self.fft_input[i] = frame[i]
        for i in range(len(frame), len(self.fft_input)):
            self.fft_input[i] = 0.0
        
        # 2. FFT
        self.fft.fft(self.fft_input)
        
        # 3. Power Spectrum (Mags^2)
        # We use a separate buffer for power mags so we preserve fft_mags for external use
        for i in range(len(self.fft.mags)):
            self.fft_power_mags[i] = self.fft.mags[i] * self.fft.mags[i]
            
        # 4. IFFT -> Autocorrelation
        # Use zero phases for autocorrelation
        self.fft.ifft(self.fft_power_mags, self.fft_zero_phases, self.acf_real)
        
        # 5. Compute Difference Function
        var total_energy = self.acf_real[0]
        
        var running_sum = 0.0
        for i in range(len(frame)):
            running_sum += frame[i] * frame[i]
            self.yin_buffer[i] = running_sum
            
        self.yin_values[0] = 1.0 
        
        for tau in range(1, len(frame)):
             var term1 = self.yin_buffer[len(frame) - 1 - tau]
             var term2 = total_energy
             if tau > 0:
                 term2 -= self.yin_buffer[tau - 1]
             var term3 = 2.0 * self.acf_real[tau]
             
             self.yin_values[tau] = term1 + term2 - term3

        # cumulative mean normalized difference function
        var tmp_sum: Float64 = 0.0
        for i in range(1, len(frame)):
            raw_val = self.yin_values[i]
            tmp_sum += raw_val
            if tmp_sum != 0.0:
                self.yin_values[i] = raw_val * (Float64(i) / tmp_sum)
            else:
                self.yin_values[i] = 1.0

        var local_pitch = 0.0
        var local_conf = 0.0
        if tmp_sum > 0.0:
            var high_freq = self.max_freq if self.max_freq > 0.0 else 1.0
            var low_freq = self.min_freq if self.min_freq > 0.0 else 1.0
            
            var min_bin = Int((self.sample_rate / high_freq) + 0.5)
            var max_bin = Int((self.sample_rate / low_freq) + 0.5)

            # Clamp min_bin
            if min_bin < 1:
                min_bin = 1

            # Clamp max_bin
            var safe_limit = len(frame) // 2
            if max_bin > safe_limit:
                max_bin = safe_limit

            if max_bin > min_bin:
                var best_tau = -1
                var best_val = 1.0
                var threshold: Float64 = 0.1
                var tau = min_bin
                while tau < max_bin:
                    var val = self.yin_values[tau]
                    if val < threshold:
                        while tau + 1 < max_bin and self.yin_values[tau + 1] < val:
                            tau += 1
                            val = self.yin_values[tau]
                        best_tau = tau
                        best_val = val
                        break
                    if val < best_val:
                        best_tau = tau
                        best_val = val
                    tau += 1

                if best_tau > 0:
                    var refined_idx = Float64(best_tau)
                    if best_tau > 0 and best_tau < len(frame) - 1:
                        var prev = self.yin_values[best_tau - 1]
                        var cur = self.yin_values[best_tau]
                        var nxt = self.yin_values[best_tau + 1]
                        var (offset, refined_val) = parabolic_refine(prev, cur, nxt)
                        refined_idx += offset
                        best_val = refined_val

                    if refined_idx > 0.0:
                        local_pitch = self.sample_rate / refined_idx
                        local_conf = max(1.0 - best_val, 0.0)
                        local_conf = min(local_conf, 1.0)

        self.pitch = local_pitch
        self.confidence = local_conf

struct SpectralCentroid(FFTProcessable, GetFloat64Featurable):
    """Spectral Centroid analysis.

    Based on the [Peeters (2003)](http://recherche.ircam.fr/anasyn/peeters/ARTICLES/Peeters_2003_cuidadoaudiofeatures.pdf)
    """

    var sr: Float64
    var centroid: Float64
    var min_freq: Float64
    var max_freq: Float64
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral centroid value as a List of Float64."""
        return [self.centroid]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, power_mag: Bool = False):
        """Initialize the Spectral Centroid analyzer.
        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider when computing the spectral centroid.
            max_freq: The maximum frequency to consider when computing the spectral centroid.
            power_mag: Whether to use power magnitudes (mags^2) instead of linear magnitudes when computing the centroid.
        
        Returns:
            An initialized SpectralCentroid struct.
        """
        self.sr = sr
        self.centroid = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral centroid for a given FFT analysis.

        This function is to be used by FFTProcess if SpectralCentroid is passed as the "process".

        Args:
            mags: The input magnitudes as a List of Float64.
            phases: The input phases as a List of Float64.
        """
        self.centroid = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, power_mag: Bool = False) -> Float64:
        """Compute the spectral centroid for the given magnitudes of an FFT frame.

        This static method is useful when there is an FFT already computed, perhaps as 
        part of a custom struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.

        Args:
            mags: The input magnitudes as a List of Float64.
            sample_rate: The sample rate of the audio signal.
            min_freq: The minimum frequency to consider when computing the spectral centroid.
            max_freq: The maximum frequency to consider when computing the spectral centroid.
            power_mag: Whether to use power magnitudes (mags^2) instead of linear magnitudes when computing the centroid.

        Returns:
            Float64. The spectral centroid value.
        """
        var amp = List[Float64]()
        var freqs = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            False,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0
        spectral_freqs_prepare(min_bin, max_bin, bin_hz, False, freqs)

        var centroid: Float64 = 0.0
        for i in range(len(amp)):
            centroid += amp[i] * freqs[i]
        return centroid / amp_sum

struct SpectralSpread(FFTProcessable, GetFloat64Featurable):
    """Spectral Spread analysis."""

    var sr: Float64
    var spread: Float64
    var min_freq: Float64
    var max_freq: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral spread value as a List of Float64."""
        return [self.spread]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Spread analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.spread = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral spread for a given FFT analysis."""
        self.spread = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.log_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False) -> Float64:
        var amp = List[Float64]()
        var freqs = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0
        spectral_freqs_prepare(min_bin, max_bin, bin_hz, log_freq, freqs)

        var centroid: Float64 = 0.0
        for i in range(len(amp)):
            centroid += amp[i] * freqs[i]
        centroid /= amp_sum

        var variance: Float64 = 0.0
        for i in range(len(amp)):
            var diff = freqs[i] - centroid
            variance += amp[i] * diff * diff
        variance /= amp_sum

        return sqrt(max(variance, 0.0))

struct SpectralSkewness(FFTProcessable, GetFloat64Featurable):
    """Spectral Skewness analysis."""

    var sr: Float64
    var skewness: Float64
    var min_freq: Float64
    var max_freq: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral skewness value as a List of Float64."""
        return [self.skewness]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Skewness analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.skewness = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral skewness for a given FFT analysis."""
        self.skewness = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.log_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False) -> Float64:
        var amp = List[Float64]()
        var freqs = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0
        spectral_freqs_prepare(min_bin, max_bin, bin_hz, log_freq, freqs)

        var centroid: Float64 = 0.0
        for i in range(len(amp)):
            centroid += amp[i] * freqs[i]
        centroid /= amp_sum

        var variance: Float64 = 0.0
        for i in range(len(amp)):
            var diff = freqs[i] - centroid
            variance += amp[i] * diff * diff
        variance /= amp_sum

        if variance <= 0.0:
            return 0.0

        var denom3 = variance * sqrt(variance) * amp_sum
        var acc3: Float64 = 0.0
        for i in range(len(amp)):
            var diff = freqs[i] - centroid
            var diff2 = diff * diff
            acc3 += amp[i] * diff2 * diff
        return acc3 / denom3

struct SpectralKurtosis(FFTProcessable, GetFloat64Featurable):
    """Spectral Kurtosis analysis."""

    var sr: Float64
    var kurtosis: Float64
    var min_freq: Float64
    var max_freq: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral kurtosis value as a List of Float64."""
        return [self.kurtosis]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Kurtosis analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.kurtosis = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral kurtosis for a given FFT analysis."""
        self.kurtosis = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.log_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False) -> Float64:
        var amp = List[Float64]()
        var freqs = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0
        spectral_freqs_prepare(min_bin, max_bin, bin_hz, log_freq, freqs)

        var centroid: Float64 = 0.0
        for i in range(len(amp)):
            centroid += amp[i] * freqs[i]
        centroid /= amp_sum

        var variance: Float64 = 0.0
        for i in range(len(amp)):
            var diff = freqs[i] - centroid
            variance += amp[i] * diff * diff
        variance /= amp_sum

        if variance <= 0.0:
            return 0.0

        var denom4 = variance * variance * amp_sum
        var acc4: Float64 = 0.0
        for i in range(len(amp)):
            var diff = freqs[i] - centroid
            var diff2 = diff * diff
            acc4 += amp[i] * diff2 * diff2
        return acc4 / denom4

struct SpectralRolloff(FFTProcessable, GetFloat64Featurable):
    """Spectral Rolloff analysis."""

    var sr: Float64
    var rolloff: Float64
    var min_freq: Float64
    var max_freq: Float64
    var rolloff_target: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral rolloff value as a List of Float64."""
        return [self.rolloff]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, rolloff_target: Float64 = 95.0, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Rolloff analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            rolloff_target: Percentage of spectral energy for rolloff.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.rolloff = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.rolloff_target = rolloff_target
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral rolloff for a given FFT analysis."""
        self.rolloff = self.from_mags(
            mags,
            self.sr,
            self.min_freq,
            self.max_freq,
            self.rolloff_target,
            self.log_freq,
            self.power_mag,
        )

    @staticmethod
    def from_mags(
        mags: List[Float64],
        sample_rate: Float64,
        min_freq: Float64 = 20,
        max_freq: Float64 = 20000,
        rolloff_target: Float64 = 95.0,
        log_freq: Bool = False,
        power_mag: Bool = False,
    ) -> Float64:
        var amp = List[Float64]()
        var freqs = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0
        spectral_freqs_prepare(min_bin, max_bin, bin_hz, log_freq, freqs)

        var rolloff: Float64 = 0.0
        var cum_sum: Float64 = 0.0
        var target = amp_sum * rolloff_target / 100.0
        for i in range(len(amp)):
            cum_sum += amp[i]
            if cum_sum >= target:
                if i == 0:
                    rolloff = freqs[0]
                else:
                    rolloff = freqs[i] - (freqs[i] - freqs[i - 1]) * (cum_sum - target) / amp[i]
                break
        return rolloff

struct SpectralFlatness(FFTProcessable, GetFloat64Featurable):
    """Spectral Flatness analysis."""

    var sr: Float64
    var flatness: Float64
    var min_freq: Float64
    var max_freq: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral flatness value (dB) as a List of Float64."""
        return [self.flatness]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Flatness analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.flatness = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral flatness for a given FFT analysis."""
        self.flatness = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.log_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False) -> Float64:
        var amp = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0

        var eps: Float64 = 1.0e-12
        var amp_mean = amp_sum / Float64(len(amp))
        var sum_log: Float64 = 0.0
        for i in range(len(amp)):
            sum_log += log(max(amp[i], eps))
        var flatness = exp(sum_log / Float64(len(amp))) / max(amp_mean, eps)
        return 20.0 * log(max(flatness, eps)) / log(10.0)

struct SpectralCrest(FFTProcessable, GetFloat64Featurable):
    """Spectral Crest analysis."""

    var sr: Float64
    var crest: Float64
    var min_freq: Float64
    var max_freq: Float64
    var log_freq: Bool
    var power_mag: Bool

    def get_features(self) -> List[Float64]:
        """Return the current spectral crest value (dB) as a List of Float64."""
        return [self.crest]

    def __init__(out self, sr: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False):
        """Initialize the Spectral Crest analyzer.

        Args:
            sr: The sample rate from the MMMWorld.
            min_freq: The minimum frequency to consider.
            max_freq: The maximum frequency to consider.
            log_freq: Whether to use log-frequency (MIDI) bins.
            power_mag: Whether to use power magnitudes (mags^2).
        """
        self.sr = sr
        self.crest = 0.0
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.log_freq = log_freq
        self.power_mag = power_mag

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the spectral crest for a given FFT analysis."""
        self.crest = self.from_mags(mags, self.sr, self.min_freq, self.max_freq, self.log_freq, self.power_mag)

    @staticmethod
    def from_mags(mags: List[Float64], sample_rate: Float64, min_freq: Float64 = 20, max_freq: Float64 = 20000, log_freq: Bool = False, power_mag: Bool = False) -> Float64:
        var amp = List[Float64]()
        var amp_sum: Float64 = 0.0
        var max_amp: Float64 = 0.0
        var min_bin: Int = 0
        var max_bin: Int = 0
        var bin_hz: Float64 = 0.0
        if not spectral_amp_prepare(
            mags,
            sample_rate,
            min_freq,
            max_freq,
            log_freq,
            power_mag,
            amp,
            amp_sum,
            max_amp,
            min_bin,
            max_bin,
            bin_hz,
        ):
            return 0.0

        var eps: Float64 = 1.0e-12
        var amp_mean = amp_sum / Float64(len(amp))
        var crest = max_amp / max(amp_mean, eps)
        return 20.0 * log(max(crest, eps)) / log(10.0)

struct RMS(BufferedProcessable, GetFloat64Featurable):
    """Root Mean Square (RMS) amplitude analysis.
    """
    var rms: Float64

    def get_features(self) -> List[Float64]:
        """Return the current RMS value as a List of Float64."""
        return [self.rms]

    def __init__(out self):
        """Initialize the RMS analyzer."""
        self.rms = 0.0

    def next_window(mut self, mut input: List[Float64]):
        """Compute the RMS for the given window of audio samples.

        This function is to be used with a [BufferedProcess](BufferedProcess.md/#struct-bufferedprocess).

        Args:
            input: The input audio frame of samples. This List gets passed from [BufferedProcess](BufferedProcess.md/#struct-bufferedprocess).
        
        The computed RMS value is stored in self.rms.
        """
        self.rms = self.from_window(input)

    @staticmethod
    def from_window(mut frame: List[Float64]) -> Float64:
        """Compute the RMS for the given window of audio samples.

        This static method is useful when there is an audio frame already available, perhaps
        as part of a custom struct that implements the [BufferedProcessable](BufferedProcess.md/#trait-bufferedprocessable) trait.

        Args:
            frame: The input audio frame of samples.
        
        Returns:
            Float64. The computed RMS value.
        """
        sum_sq: Float64 = 0.0
        for v in frame:
            sum_sq += v * v
        return sqrt(sum_sq / Float64(len(frame)))

struct MelBands(FFTProcessable, GetFloat64Featurable):
    """Mel Bands analysis.

    This implementation follows the approach used in the [Librosa](https://librosa.org/) library. 
    """

    var sr: Float64
    var weights: List[List[Float64]]
    var bands: List[Float64]
    var num_bands: Int
    var min_freq: Float64
    var max_freq: Float64
    var fft_size: Int
    var power: Float64

    def get_features(self) -> List[Float64]:
        """Return the current mel band values as a List of Float64."""
        return self.bands.copy()

    def __init__(out self, sr: Float64, num_bands: Int = 40, min_freq: Float64 = 20.0, max_freq: Float64 = 20000.0, fft_size: Int = 1024, power: Float64 = 2.0):
        """Initialize the Mel Bands analyzer.
        
        Args:
            sr: The sample rate from the MMMWorld.
            num_bands: The number of mel bands to compute.
            min_freq: The minimum frequency (in Hz) to consider when computing the mel bands.
            max_freq: The maximum frequency (in Hz) to consider when computing the mel bands.
            fft_size: The size of the FFT being used to compute the mel bands.
            power: Exponent applied to magnitudes before mel filtering (librosa default is 2.0 for power).
        
        Returns:
            An initialized MelBands struct.
        """
        
        self.sr = sr
        self.num_bands = num_bands
        self.min_freq = min_freq
        self.max_freq = max_freq
        self.fft_size = fft_size
        self.power = power

        self.weights = List[List[Float64]](length=self.num_bands,fill=List[Float64](length=(self.fft_size // 2) + 1, fill=0.0))
        self.bands = List[Float64](length=self.num_bands, fill=0.0)
        self.make_weights()

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the mel bands for a given FFT analysis.

        This function is to be used by FFTProcess if MelBands is passed as the "process".

        Nothing is returned from this function, but the computed mel band values are stored in self.bands.

        Args:
            mags: The input magnitudes as a List of Float64.
            phases: The input phases as a List of Float64.
        """
        self.from_mags(mags)

    def from_mags(mut self, ref mags: List[Float64]):
        """Compute the mel bands for a given list of magnitudes.

        This function is useful when there is an FFT already computed, perhaps as 
        part of a custom struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.

        Args:
            mags: The input magnitudes as a List of Float64.
        """
        for i in range(self.num_bands):
            band_energy: Float64 = 0.0
            for j in range(len(mags)):
                var mag_val: Float64
                if self.power == 1.0:
                    mag_val = mags[j]
                elif self.power == 2.0:
                    mag_val = mags[j] * mags[j]
                else:
                    mag_val = mags[j] ** self.power
                band_energy += self.weights[i][j] * mag_val
            self.bands[i] = band_energy
    
    @doc_hidden
    def make_weights(mut self):
        """Compute the mel filter bank weights."""

        fftfreqs = RealFFT.fft_frequencies(sr=self.sr, n_fft=self.fft_size)

        # 'Center freqs' of mel bands - uniformly spaced between limits
        mel_f = MelBands.mel_frequencies(self.num_bands + 2, fmin=self.min_freq, fmax=self.max_freq)

        fdiff = diff(mel_f)
        ramps = subtract_outer(mel_f, fftfreqs)

        for i in range(self.num_bands):
            lower: List[Float64] = List[Float64](length=len(ramps[i]), fill=0.0)
            for j in range(len(ramps[i])):
                lower[j] = -ramps[i][j] / fdiff[i]
            upper: List[Float64] = List[Float64](length=len(ramps[i]), fill=0.0)
            for j in range(len(ramps[i])):
                upper[j] = ramps[i + 2][j] / fdiff[i + 1]

            for j in range(len(ramps[i])):
                self.weights[i][j] = max(0.0, min(lower[j], upper[j]))

        # Slaney-style mel
        var enorm = List[Float64](length=self.num_bands, fill=0.0)
        for i in range(self.num_bands):
            enorm[i] = 2.0 / (mel_f[i + 2] - mel_f[i])
        
        for i in range(self.num_bands):
            for j in range(len(self.weights[i])):
                self.weights[i][j] *= enorm[i]

    @staticmethod
    def mel_frequencies(n_mels: Int = 128, fmin: Float64 = 0.0, fmax: Float64 = 20000.0) -> List[Float64]:
        """Compute an array of acoustic frequencies tuned to the mel scale.

        This implementation is based on Librosa's eponymous [function](https://librosa.org/doc/main/generated/librosa.mel_frequencies.html).  For more information on mel frequencies space see the [MelBands](Analysis.md/#struct-melbands) documentation.

        Args:
            n_mels: The number of mel bands to generate.
            fmin: The lowest frequency (in Hz).
            fmax: The highest frequency (in Hz).

        Returns:
            A List of Float64 representing the center frequencies of each mel band.
        """

        min_mel = MelBands.hz_to_mel(fmin)
        max_mel = MelBands.hz_to_mel(fmax)

        mels = linspace(min_mel, max_mel, n_mels)

        var hz = List[Float64](length=n_mels, fill=0.0)
        for i in range(n_mels):
            hz[i] = MelBands.mel_to_hz(mels[i])
        return hz^

    @staticmethod
    def hz_to_mel[num_chans: Int = 1](freq: SIMD[DType.float64,num_chans]) -> SIMD[DType.float64,num_chans]:
        """Convert Hz to Mels.

        This implementation is based on Librosa's eponymous [function](https://librosa.org/doc/main/generated/librosa.hz_to_mel.html). For more information on mel frequencies space see the [MelBands](Analysis.md/#struct-melbands) documentation.

        Parameters:
            num_chans: Size of the SIMD vector. This parameter is inferred by the values passed to the function.

        Args:
            freq: The frequencies in Hz to convert.
        
        Returns:
            The corresponding mel frequencies.
        """

        # "HTK" is a different way to compute mels. It is not implemented in MMMAudio, but
        # commented out here in case it becomes useful in the future.
        # if htk:
        #     return 2595.0 * log10(1.0 + freq / 700.0)

        f_min = 0.0
        f_sp = 200.0 / 3

        mels = (freq - f_min) / f_sp

        min_log_hz = 1000.0  # beginning of log region (Hz)
        min_log_mel = (min_log_hz - f_min) / f_sp  # same (Mels)
        logstep = log(6.4) / 27.0  # step size for log region

        if freq >= min_log_hz:
            mels = min_log_mel + log(freq / min_log_hz) / logstep

        return mels

    @staticmethod
    def mel_to_hz[num_chans: Int = 1](mel: SIMD[DType.float64,num_chans]) -> SIMD[DType.float64,num_chans]:
        """Convert mel bin numbers to frequencies.

        This implementation is based on Librosa's eponymous [function](https://librosa.org/doc/main/generated/librosa.mel_to_hz.html). For more information on mel frequencies space see the [MelBands](Analysis.md/#struct-melbands) documentation.
        """

        # "HTK" is a different way to compute mels. It is not implemented in MMMAudio, but
        # commented out here in case it becomes useful in the future.
        # if htk:
        #     return 700.0 * (10.0 ** (mel / 2595.0) - 1.0)

        # Fill in the linear scale
        f_min = 0.0
        f_sp = 200.0 / 3
        freq = f_min + f_sp * mel

        # And now the nonlinear scale
        min_log_hz = 1000.0  # beginning of log region (Hz)
        min_log_mel = (min_log_hz - f_min) / f_sp  # same (Mels)
        logstep = log(6.4) / 27.0  # step size for log region

        if mel >= min_log_mel:
            freq = min_log_hz * exp(logstep * (mel - min_log_mel))

        return freq

struct MFCC(FFTProcessable, GetFloat64Featurable):
    """Mel-Frequency Cepstral Coefficients (MFCC) analysis.
    """

    var sr: Float64
    var mel_bands: MelBands
    var db_bands: List[Float64]
    var dct: DCT
    var coeffs: List[Float64]

    def get_features(self) -> List[Float64]:
        """Return the current MFCC values as a List of Float64."""
        return self.coeffs.copy()

    def __init__(out self, sr: Float64, num_coeffs: Int = 13, num_bands: Int = 40, min_freq: Float64 = 20.0, max_freq: Float64 = 20000.0, fft_size: Int = 1024):
        """Initialize the MFCC analyzer.

        Args:
            sr: The sample rate for the mel band computation.
            num_coeffs: The number of MFCC coefficients to compute (including the 0th coefficient).
            num_bands: The number of mel bands to use when computing the MFCCs.
            min_freq: The minimum frequency (in Hz) to consider when computing the mel bands for the MFCCs.
            max_freq: The maximum frequency (in Hz) to consider when computing the mel bands for the MFCCs.
            fft_size: The size of the FFT being used to compute the mel bands for the MFCCs.

        Returns:
            An initialized MFCC struct.
        """
        
        self.sr = sr
        self.mel_bands = MelBands(sr, num_bands, min_freq, max_freq, fft_size)
        self.dct = DCT(num_bands, num_coeffs)
        self.db_bands = List[Float64](length=num_bands, fill=0.0)
        self.coeffs = List[Float64](length=num_coeffs, fill=0.0)

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]) -> None:
        """Compute the MFCCs for a given FFT analysis.

        This function is to be used by [FFTProcess](FFTProcess.md/#struct-fftprocess) if MFCC is passed as the "process".

        Nothing is returned from this function, but the computed MFCC values are stored in self.coeffs.

        Args:
            mags: The input magnitudes as a List of Float64.
            phases: The input phases as a List of Float64.
        """
        self.from_mags(mags)

    def from_mags(mut self, ref mags: List[Float64]):
        """Compute the MFCCs for a given list of magnitudes.
        
        This function is useful when there is an FFT already computed, 
        perhaps as part of a custom struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.
        
        Nothing is returned from this function, but the computed MFCC values are stored in self.coeffs.

        Args:
            mags: The input magnitudes as a List of Float64.
        """
        self.mel_bands.from_mags(mags)
        self.from_mel_bands_internal()

    @doc_hidden
    def from_mel_bands_internal(mut self):
        """Compute the MFCCs using self.mel_bands.bands.
        """
        comptime max_db_range: Float64 = 80.0

        var max_db: Float64 = -1.0e30
        for i in range(len(self.mel_bands.bands)):
            var db = power_to_db(self.mel_bands.bands[i])
            self.db_bands[i] = db
            if db > max_db:
                max_db = db

        var min_db = max_db - max_db_range
        for i in range(len(self.db_bands)):
            if self.db_bands[i] < min_db:
                self.db_bands[i] = min_db

        self.dct.process(self.db_bands, self.coeffs)

    def from_mel_bands(mut self, ref mbands: List[Float64]):
        """Compute the MFCCs for a given list of mel band energies.

        This function is useful when there is a mel band analysis already computed, perhaps as part of a custom struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.

        Nothing is returned from this function, but the computed MFCC values are stored in self.coeffs.

        Args:
            mbands: The input mel band energies as a List of Float64.
        """
        comptime max_db_range: Float64 = 80.0

        var max_db: Float64 = -1.0e30
        # iterate over passed mel bands ref:
        for i in range(len(mbands)):
            var db = power_to_db(mbands[i])
            self.db_bands[i] = db
            if db > max_db:
                max_db = db

        var min_db = max_db - max_db_range
        for i in range(len(self.db_bands)):
            if self.db_bands[i] < min_db:
                self.db_bands[i] = min_db

        self.dct.process(self.db_bands, self.coeffs)

    @staticmethod
    def buf_analysis(buf: Buffer, chan: Int = 0, start_frame: Int = 0, var num_frames: Int = -1, num_coeffs: Int = 13, num_bands: Int = 40, min_freq: Float64 = 20.0, max_freq: Float64 = 20000.0, fft_size: Int = 1024, hop_size: Int = 512) raises -> List[List[Float64]]:
        if num_frames < 0:
            num_frames = buf.num_frames - start_frame
        mfcc = MFCC(buf.sample_rate, num_coeffs, num_bands, min_freq, max_freq, fft_size)
        return MBufAnalysis.fft_process(mfcc, buf, chan, start_frame, num_frames, fft_size, hop_size)

struct DCT(Movable,Copyable):
    """Compute the Discrete Cosine Transform (DCT)."""

    var weights: List[List[Float64]]
    var input_size: Int
    var output_size: Int

    def __init__(out self, input_size: Int, output_size: Int):
        self.input_size = input_size
        self.output_size = output_size
        self.weights = List[List[Float64]](length=output_size, fill=List[Float64](length=input_size, fill=0.0))
        self.make_weights()

    def process(mut self, ref input: List[Float64], mut output: List[Float64]) -> None:
        """Compute the first `output_size` DCT-II coefficients for `input`.

        Nothing is returned from this function, but the computed DCT coefficients are stored in the `output` List passed as an argument.

        Args:
            input: Input vector of length `input_size`.
            output: Output vector of length `output_size`.
        """
        for k in range(self.output_size):
            var acc: Float64 = 0.0
            for n in range(self.input_size):
                acc += self.weights[k][n] * input[n]
            output[k] = acc

    @doc_hidden
    def make_weights(mut self):
        """Precompute the DCT-II weight matrix."""
        var n_inv = 1.0 / Float64(self.input_size)
        var scale0 = sqrt(n_inv)
        var scale = sqrt(2.0 * n_inv)
        var n_f = Float64(self.input_size)

        for k in range(self.output_size):
            var alpha = scale0 if k == 0 else scale
            var k_f = Float64(k)
            for n in range(self.input_size):
                var n_f_idx = Float64(n) + 0.5
                var angle = (pi / n_f) * n_f_idx * k_f
                self.weights[k][n] = alpha * cos(angle)

struct SpectralFlux(FFTProcessable, GetFloat64Featurable):
    """Spectral Flux analysis.

    This implementation computes the squared difference between the magnitudes of the current frame and the previous frame, summed across all frequency bins.

    Args:
    
            num_mags: The number of magnitude bins in the input to expect. This is typically the FFT size divided by 2, but could also be the number of mel bands or another spectral summary that produces a list of values.
            positive_only: Whether to only consider positive differences (increases in energy) when computing the spectral flux. If `False`, spectral flux is the average of squared differences between the magnitudes. If `True`, spectral flux is the average of (non-squared to match FluCoMa) differences between the magnitudes, but negative differences are set to 0. Using `positive_only=True` is a common approach when using spectral flux for onset detection, as onsets are typically characterized by increases in energy.
    """
    var num_mags: Int
    var num_mags_f64: Float64
    var num_mags_reciprocal: Float64
    var prev_mags: List[Float64]
    var flux: Float64
    var positive_only: Bool

    def __init__(out self, num_mags: Int, positive_only: Bool = False):
        """Initialize the Spectral Flux analyzer.

        Args:
            num_mags: The number of magnitude bins in the input to expect. This is typically the FFT size divided by 2, but could also be the number of mel bands or another spectral summary that produces a list of values.
            positive_only: Whether to only consider positive differences (increases in energy) when computing the spectral flux. If `False`, spectral flux is the average of squared differences between the magnitudes. If `True`, spectral flux is the average of (non-squared to match FluCoMa) differences between the magnitudes, but negative differences are set to 0. Using `positive_only=True` is a common approach when using spectral flux for onset detection, as onsets are typically characterized by increases in energy.
        """
        self.num_mags = num_mags
        self.num_mags_f64 = Float64(self.num_mags)
        self.num_mags_reciprocal = 1.0 / self.num_mags_f64
        self.prev_mags = List[Float64](length=self.num_mags, fill=0.0)
        self.flux = 0.0
        self.positive_only = positive_only

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]):
        """Compute the spectral flux onset value for a given FFT analysis.

        This function is to be used by [FFTProcess](FFTProcess.md/#struct-fftprocess) if SpectralFluxOnsets is passed as the "process".

        Nothing is returned from this function, but the computed spectral flux value is stored in self.flux.

        Args:
            mags: The input magnitudes as a List of Float64.
            phases: The input phases as a List of Float64.
        """
        _ = self.from_mags(mags)

    def get_features(self) -> List[Float64]:
        """Return the current spectral flux value as a List of Float64."""
        return [self.flux]

    def from_mags(mut self, ref mags: List[Float64]) -> Float64:
        """Compute the spectral flux onset value for a given list of magnitudes.

        This function is useful when there is an FFT already computed, perhaps as part of a custom struct that implements the [FFTProcessable](FFTProcess.md/#trait-fftprocessable) trait.

        Nothing is returned from this function, but the computed spectral flux value is stored in self.flux.

        Args:
            mags: The input magnitudes as a List of Float64.
        """
        
        self.flux = 0.0
        
        if self.positive_only:
            for i in range(self.num_mags):
                var diff = mags[i] - self.prev_mags[i]
                self.flux += max(0.0, diff) #* self.num_mags_reciprocal
                self.prev_mags[i] = mags[i]
        else:
            for i in range(self.num_mags):
                var diff = mags[i] - self.prev_mags[i]
                self.flux += diff * diff #* self.num_mags_reciprocal
                self.prev_mags[i] = mags[i]
            
        return self.flux

trait GetBoolFeaturable:
    def get_features(self) -> List[Bool]:...

struct SpectralFluxOnsets(Movable,Copyable,GetBoolFeaturable):
    """Spectral Flux Onset analysis.
    """
    var world: World
    var thresh: Float64
    var state: Bool
    var current_slice_length_samps: Float64
    var min_slice_len: Float64
    var filter_size: Int
    var filter: MedianFilter
    var prev_flux: Float64
    var fftp: FFTProcess[SpectralFlux,ifft=False,input_window_shape=WindowType.hann,output_window_shape=WindowType.hann]

    def get_features(self) -> List[Bool]:
        return [self.state]

    def __init__(out self, world: World, window_size: Int = 1024, hop_size: Int = 512, filter_size: Int = 5):
        self.world = world
        self.thresh = 0.5
        self.state = False
        self.current_slice_length_samps = 0
        self.min_slice_len = 1
        self.filter_size = filter_size
        self.filter = MedianFilter(filter_size)
        self.prev_flux = 0.0
        sfp = SpectralFlux(num_mags=(window_size // 2) + 1, positive_only=True)
        self.fftp = FFTProcess[SpectralFlux,ifft=False,input_window_shape=WindowType.hann,output_window_shape=WindowType.hann](self.world,process=sfp^, window_size=window_size, hop_size=hop_size)

    def next(mut self, input: SIMD[DType.float64,1]) -> Bool:

        _ = self.fftp.next(input)
        
        self.current_slice_length_samps += 1

        if self.state: # state is high
            # set low
            self.state = False
        else: # state *will* be low if we're in here:
            flux = self.fftp.buffered_process.process.process.flux
            var filtered_flux: Float64
            if self.filter_size >= 3:
                filtered_flux = flux - self.filter.process_sample(flux)
            else:
                filtered_flux = flux - self.prev_flux
            self.prev_flux = flux
            curr_slice_len_sec = self.current_slice_length_samps / self.world[].sample_rate
            if filtered_flux > self.thresh and curr_slice_len_sec > self.min_slice_len:
                self.state = True

                # should this actually be 1?
                self.current_slice_length_samps = 0

        return self.state
    
    @staticmethod
    def buf_analysis(world: World, buf: Buffer, chan: Int = 0, start_frame: Int = 0, var num_frames: Int = -1, thresh: Float64 = 0.5, min_slice_len: Float64 = 1.0, window_size: Int = 1024, hop_size: Int = 512, filter_size: Int = 5) raises -> List[Int]:
        if num_frames < 0:
            num_frames = buf.num_frames - start_frame

        # run the analysis
        sf_onsets = SpectralFluxOnsets(world,window_size,hop_size,filter_size)
        sf_onsets.thresh = thresh
        sf_onsets.min_slice_len = min_slice_len

        onsets = List[Int]()

        for i in range(num_frames):
            if sf_onsets.next(buf.data[chan][start_frame + i]):
                onsets.append(start_frame + i)
        
        return onsets^

struct TopNFreqs(FFTProcessable, GetFloat64Featurable):
    """An FFTProcessable that identifies the top N frequency peaks in each FFT frame and provides their frequencies and amplitudes as output.

    Args:

        sample_rate: The sample rate of the audio signal.
        window_size: The size of the FFT window. This determines the frequency resolution and the maximum number of frequency bins (window_size // 2 + 1).
        num_peaks: The number of top peaks to identify in each FFT frame.
        sort_by_freq: Whether to sort the output freq, amp pairs by frequency (True) or by amplitude (False).
        thresh: The minimum amplitude threshold (in dB) for a peak to be considered. Peaks below this threshold will be ignored.
    """
    var window_size: Int
    var freq_amp_pairs: List[Tuple[Float64, Float64]]
    var thresh: Float64
    var num_peaks: Int
    var sort_by_freq: Bool
    var bin_freq: Float64
    
    def get_features(self) -> List[Float64]:
        state = List[Float64]()
        for pair in self.freq_amp_pairs:
            state.append(pair[0]) # freq
            state.append(pair[1]) # amp
        return state^

    def get_features_ptr(self) -> Pointer[mut = False, List[Tuple[Float64, Float64]], origin_of(self.freq_amp_pairs)]:
        """Return a pointer to the current List of freq, amp pairs."""
        return Pointer(to=self.freq_amp_pairs)

    def __init__(out self, sample_rate: Float64, window_size: Int, num_peaks: Int = 5, sort_by_freq: Bool = True, thresh: Float64 = -30.0):
        """Initialize the TopNFreqs process.

        Args:
            sample_rate: The sample rate of the audio signal.
            window_size: The size of the FFT window. This determines the frequency resolution and the maximum number of frequency bins (window_size // 2 + 1).
            num_peaks: The number of top peaks to identify in each FFT frame.
            sort_by_freq: Whether to sort the output freq, amp pairs by frequency (True) or by amplitude (False).
            thresh: The minimum amplitude threshold (in dB) for a peak to be considered. Peaks below this threshold will be ignored.
        """
        self.window_size = window_size
        self.freq_amp_pairs = [(0.0, 0.0) for _ in range(num_peaks)]
        self.thresh = dbamp(thresh)*MFloat[1](self.window_size)/4.0 
        self.num_peaks = num_peaks
        self.sort_by_freq = sort_by_freq
        self.bin_freq = sample_rate / Float64(self.window_size)

    def get_messages(mut self) -> None:
        pass

    def next_frame(mut self, mut mags: List[MFloat[]], mut phases: List[MFloat[]]) -> None:
        top_N = topN_indices(mags, self.num_peaks, self.thresh)

        for i in range(self.num_peaks):
            index = top_N[i]
            if index > 0 and index < len(mags) - 1:
                a_db = ampdb(MFloat[4](mags[index-1], mags[index], mags[index+1], 0.0))
                val, mag = find_quadratic_peak(a_db[0], a_db[1], a_db[2])
                offset = val - 1.0
                freq = (MFloat[1](index) + offset) * self.bin_freq
                self.freq_amp_pairs[i] = Tuple(freq, mag * (4.0/MFloat[1](self.window_size)))
            else:
                self.freq_amp_pairs[i] = Tuple(0.0, 0.0)
        if self.sort_by_freq:
            self.sort_pairs_by_freq()

    def sort_pairs_by_freq(mut self):
        def cmp_fn(a: Tuple[Float64, Float64], b: Tuple[Float64, Float64]) capturing -> Bool:
            return a[0] < b[0]

        sort[cmp_fn](self.freq_amp_pairs)


