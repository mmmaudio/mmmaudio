from mmm_audio.constants import *
from std.math import *
from mmm_audio.FFTProcess_Module import FFTProcess, FFTProcessable
from mmm_audio.Buffer_Module import Buffer
from mmm_audio.ML.Analysis import MBufAnalysis, GetFloat64Featurable
from mmm_audio.Filters import MedianFilter
from mmm_audio.MMMWorld_Module import WindowType

@fieldwise_init
struct OnsetMetric(Equatable, ImplicitlyCopyable, Writable):
    """Distance metrics for onset detection.

    The values match FluidOnsetDetection's `metric` parameter.
    """
    var _value: Int

    comptime energy: OnsetMetric = OnsetMetric(0)
    comptime high_frequency_content: OnsetMetric = OnsetMetric(1)
    comptime spectral_flux: OnsetMetric = OnsetMetric(2)
    comptime modified_kullback_leibler: OnsetMetric = OnsetMetric(3)
    comptime itakura_saito: OnsetMetric = OnsetMetric(4)
    comptime cosine: OnsetMetric = OnsetMetric(5)
    comptime phase_deviation: OnsetMetric = OnsetMetric(6)
    comptime weighted_phase_deviation: OnsetMetric = OnsetMetric(7)
    comptime complex_domain: OnsetMetric = OnsetMetric(8)
    comptime rectified_complex_domain: OnsetMetric = OnsetMetric(9)

    @doc_hidden
    @always_inline
    @staticmethod
    def from_string(metric_string: String) -> OnsetMetric:
        # I tried implementing this as a static Dict, but I was getting some typing errors...
        if metric_string == "energy":
            return OnsetMetric.energy
        elif metric_string == "high_frequency_content":
            return OnsetMetric.high_frequency_content
        elif metric_string == "spectral_flux":
            return OnsetMetric.spectral_flux
        elif metric_string == "modified_kullback_leibler":
            return OnsetMetric.modified_kullback_leibler
        elif metric_string == "itakura_saito":
            return OnsetMetric.itakura_saito
        elif metric_string == "cosine":
            return OnsetMetric.cosine
        elif metric_string == "phase_deviation":
            return OnsetMetric.phase_deviation
        elif metric_string == "weighted_phase_deviation":
            return OnsetMetric.weighted_phase_deviation
        elif metric_string == "complex_domain":
            return OnsetMetric.complex_domain
        elif metric_string == "rectified_complex_domain":
            return OnsetMetric.rectified_complex_domain
        else:
            print("Unknown onset metric string: ", metric_string, ", returning complex_domain")
            return OnsetMetric.complex_domain

    def write_to(self, mut writer: Some[Writer]):
        if self._value == OnsetMetric.energy._value:
            writer.write("OnsetMetric: energy")
        elif self._value == OnsetMetric.high_frequency_content._value:
            writer.write("OnsetMetric: high_frequency_content")
        elif self._value == OnsetMetric.spectral_flux._value:
            writer.write("OnsetMetric: spectral_flux")
        elif self._value == OnsetMetric.modified_kullback_leibler._value:
            writer.write("OnsetMetric: modified_kullback_leibler")
        elif self._value == OnsetMetric.itakura_saito._value:
            writer.write("OnsetMetric: itakura_saito")
        elif self._value == OnsetMetric.cosine._value:
            writer.write("OnsetMetric: cosine")
        elif self._value == OnsetMetric.phase_deviation._value:
            writer.write("OnsetMetric: phase_deviation")
        elif self._value == OnsetMetric.weighted_phase_deviation._value:
            writer.write("OnsetMetric: weighted_phase_deviation")
        elif self._value == OnsetMetric.complex_domain._value:
            writer.write("OnsetMetric: complex_domain")
        elif self._value == OnsetMetric.rectified_complex_domain._value:
            writer.write("OnsetMetric: rectified_complex_domain")
        else:
            writer.write("OnsetMetric unknown _value: ", self._value)

    @doc_hidden
    def __eq__(self, other: Self) -> Bool:
        return self._value == other._value

    @doc_hidden
    def __ne__(self, other: Self) -> Bool:
        return not (self == other)

    @always_inline
    @doc_hidden
    @staticmethod
    def uses_frame_delta(metric: OnsetMetric) -> Bool:
        return metric == OnsetMetric.spectral_flux or metric == OnsetMetric.modified_kullback_leibler or metric == OnsetMetric.itakura_saito

    @doc_hidden
    @staticmethod
    def measure(
        metric: OnsetMetric,
        current_mags: List[Float64],
        current_phases: List[Float64],
        previous_mags: List[Float64],
        previous_phases: List[Float64],
        previous_previous_mags: List[Float64],
        previous_previous_phases: List[Float64],
    ) -> Float64:
        if metric == OnsetMetric.energy:
            return OnsetMetric.measure_energy(current_mags)
        elif metric == OnsetMetric.high_frequency_content:
            return OnsetMetric.measure_high_frequency_content(current_mags)
        elif metric == OnsetMetric.spectral_flux:
            return OnsetMetric.measure_spectral_flux(metric, current_mags, previous_mags)
        elif metric == OnsetMetric.modified_kullback_leibler:
            return OnsetMetric.measure_modified_kullback_leibler(current_mags, previous_mags)
        elif metric == OnsetMetric.itakura_saito:
            return OnsetMetric.measure_itakura_saito(current_mags, previous_mags)
        elif metric == OnsetMetric.cosine:
            return OnsetMetric.measure_cosine(current_mags, previous_mags)
        elif metric == OnsetMetric.phase_deviation:
            return OnsetMetric.measure_phase_deviation(
                current_mags,
                current_phases,
                previous_mags,
                previous_phases,
                previous_previous_mags,
                previous_previous_phases,
            )
        elif metric == OnsetMetric.weighted_phase_deviation:
            return OnsetMetric.measure_weighted_phase_deviation(
                current_mags,
                current_phases,
                previous_mags,
                previous_phases,
                previous_previous_mags,
                previous_previous_phases,
            )
        elif metric == OnsetMetric.complex_domain or metric == OnsetMetric.rectified_complex_domain:
            return OnsetMetric.measure_complex_domain(
                current_mags,
                current_phases,
                previous_mags,
                previous_phases,
                previous_previous_mags,
                previous_previous_phases,
            )
        else:
            print("Unknown onset metric: ", metric, ", returning 0.0")
            return 0.0

    @doc_hidden
    @staticmethod
    def measure_energy(current_mags: List[Float64]) -> Float64:
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        for i in range(num_bins):
            value += current_mags[i] * current_mags[i]
        return value / Float64(num_bins)
    
    @doc_hidden
    @staticmethod
    def measure_high_frequency_content(current_mags: List[Float64]) -> Float64:
        var bin_scale = 1.0
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        if num_bins > 1:
            bin_scale = Float64(num_bins) / Float64(num_bins - 1)
        for i in range(num_bins):
            value += Float64(i) * bin_scale * current_mags[i] * current_mags[i]
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_spectral_flux(
        metric: OnsetMetric,
        current_mags: List[Float64],
        previous_mags: List[Float64],
    ) -> Float64:
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        for i in range(num_bins):
            value += max(current_mags[i] - previous_mags[i], 0.0)
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_modified_kullback_leibler(
        current_mags: List[Float64],
        previous_mags: List[Float64],
    ) -> Float64:
        comptime epsilon: Float64 = 2.220446049250313e-16
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        for i in range(num_bins):
            var current = max(current_mags[i], epsilon)
            var previous = max(previous_mags[i], epsilon)
            value += log(max(current / previous, epsilon))
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_itakura_saito(
        current_mags: List[Float64],
        previous_mags: List[Float64],
    ) -> Float64:
        comptime epsilon: Float64 = 2.220446049250313e-16
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        for i in range(num_bins):
            var current = max(current_mags[i], epsilon)
            var previous = max(previous_mags[i], epsilon)
            var ratio = max((current / previous) * (current / previous), epsilon)
            value += ratio - log(ratio) - 1.0
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_cosine(
        current_mags: List[Float64],
        previous_mags: List[Float64],
    ) -> Float64:
        var current_norm: Float64 = 0.0
        var previous_norm: Float64 = 0.0
        var dot: Float64 = 0.0
        comptime epsilon: Float64 = 2.220446049250313e-16
        var num_bins: Int = len(current_mags)
        for i in range(num_bins):
            var current = max(current_mags[i], epsilon)
            var previous = max(previous_mags[i], epsilon)
            current_norm += current * current
            previous_norm += previous * previous
            dot += current * previous
        var denominator = sqrt(current_norm) * sqrt(previous_norm)
        if denominator <= epsilon:
            return 0.0
        return 1.0 - dot / denominator

    @doc_hidden
    @staticmethod
    def measure_phase_deviation(
        current_mags: List[Float64],
        current_phases: List[Float64],
        previous_mags: List[Float64],
        previous_phases: List[Float64],
        previous_previous_mags: List[Float64],
        previous_previous_phases: List[Float64],
    ) -> Float64:
        var num_bins: Int = len(current_mags)
        var value: Float64 = 0.0
        for i in range(num_bins):
            var current_phase = onset_complex_atan_real(current_mags[i], current_phases[i])
            var previous_phase = onset_complex_atan_real(previous_mags[i], previous_phases[i])
            var previous_previous_phase = onset_complex_atan_real(
                previous_previous_mags[i], previous_previous_phases[i]
            )
            var acceleration = (current_phase - previous_phase) - \
                (previous_phase - previous_previous_phase)
            value += onset_wrap_phase(acceleration)
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_weighted_phase_deviation(
        current_mags: List[Float64],
        current_phases: List[Float64],
        previous_mags: List[Float64],
        previous_phases: List[Float64],
        previous_previous_mags: List[Float64],
        previous_previous_phases: List[Float64],
    ) -> Float64:
        var value: Float64 = 0.0
        var num_bins: Int = len(current_mags)
        comptime epsilon: Float64 = 2.220446049250313e-16
        for i in range(num_bins):
            var current_phase = onset_complex_atan_real(current_mags[i], current_phases[i])
            var previous_phase = onset_complex_atan_real(previous_mags[i], previous_phases[i])
            var previous_previous_phase = onset_complex_atan_real(
                previous_previous_mags[i], previous_previous_phases[i]
            )
            var acceleration = (current_phase - previous_phase) - (previous_phase - previous_previous_phase)
            acceleration *= max(current_mags[i], epsilon)
            value += onset_wrap_phase(acceleration)
        return value / Float64(num_bins)

    @doc_hidden
    @staticmethod
    def measure_complex_domain(
        current_mags: List[Float64],
        current_phases: List[Float64],
        previous_mags: List[Float64],
        previous_phases: List[Float64],
        previous_previous_mags: List[Float64],
        previous_previous_phases: List[Float64],
    ) -> Float64:
        comptime epsilon: Float64 = 2.220446049250313e-16
        var complex_value: Float64 = 0.0
        var num_bins: Int = len(current_mags)
        for i in range(num_bins):
            var previous_phase = onset_complex_atan_real(previous_mags[i], previous_phases[i])
            var previous_previous_phase = onset_complex_atan_real(
                previous_previous_mags[i], previous_previous_phases[i]
            )
            var estimated_phase = onset_wrap_phase(
                previous_phase + (previous_phase - previous_previous_phase)
            )
            var previous_magnitude = max(previous_mags[i], epsilon)
            var target_real = previous_magnitude * cos(estimated_phase)
            var target_imag = previous_magnitude * sin(estimated_phase)
            var current_real = current_mags[i] * cos(current_phases[i])
            var current_imag = current_mags[i] * sin(current_phases[i])
            var real_difference = target_real - current_real
            var imag_difference = target_imag - current_imag
            complex_value += sqrt((real_difference * real_difference) + (imag_difference * imag_difference))
        return complex_value / Float64(num_bins)

@always_inline
@doc_hidden
def onset_complex_atan_real(magnitude: Float64, phase: Float64) -> Float64:
    var real = magnitude * cos(phase)
    var imag = magnitude * sin(phase)
    return 0.5 * atan2(2.0 * real, 1.0 - real * real - imag * imag)

@always_inline
@doc_hidden
def onset_wrap_phase(phase: Float64) -> Float64:
    if phase > pi:
        return phase
    return phase + 2.0 * pi * (1.0 + floor((-pi - phase) / (2.0 * pi)))

struct OnsetDetectionFeature(FFTProcessable, GetFloat64Featurable):
    """Onset detection feature analysis.
    
    This struct is to be used as the process of a `BufferedProcess`. It should use `WindowType.hann` for the input window shape.

    This struct creates a time series of spectral differences based on a provided metric.

    This struct implements the ten FluidOnsetSlice metrics.
    """
    var metric: OnsetMetric
    var window_size: Int
    var filter_size: Int
    var frame_delta: Int
    var filter: MedianFilter
    var frame_history_mags: List[List[Float64]]
    var frame_history_phases: List[List[Float64]]
    var history_size: Int
    var history_write_head: Int
    var raw_value: Float64
    var descriptor: Float64
    var previous_raw_value: Float64

    def __init__(
        out self,
        metric: OnsetMetric = OnsetMetric.complex_domain,
        window_size: Int = 1024,
        filter_size: Int = 5,
        frame_delta: Int = 0,
    ):
        """Initialize an onset detection function.
        
        Args:
            metric: The onset metric to calculate.
            window_size: Analysis window size in samples.
            filter_size: Median-filter size. Values below 3 use a first difference.
            frame_delta: Offset in analysis frames (hops) for Flux, MKL, and Itakura-Saito.
        """
        self.metric = metric
        self.window_size = window_size
        self.filter_size = filter_size
        self.frame_delta = max(frame_delta, 0)
        self.filter = MedianFilter(max(filter_size, 3))
        var num_bins = (self.window_size // 2) + 1
        self.frame_history_mags = List[List[Float64]]()
        self.frame_history_phases = List[List[Float64]]()
        self.history_size = max(self.frame_delta, 2)
        self.history_write_head = 0
        for _ in range(self.history_size):
            self.frame_history_mags.append(List[Float64](length=num_bins, fill=0.0))
            self.frame_history_phases.append(List[Float64](length=num_bins, fill=0.0))
        self.raw_value = 0.0
        self.descriptor = 0.0
        self.previous_raw_value = 0.0

    def get_features(self) -> List[Float64]:
        """Return the filtered onset detection-function value.

        Returns:
            A one-element List containing the current filtered descriptor value.
        """
        return [self.descriptor]

    @doc_hidden
    def filter_value(mut self):
        if self.filter_size >= 3:
            self.descriptor = self.raw_value - self.filter.process_sample(self.raw_value)
        else:
            self.descriptor = self.raw_value - self.previous_raw_value
        self.previous_raw_value = self.raw_value

    def next_frame(mut self, mags: List[Float64], phases: List[Float64]):
        """Process an unwindowed audio region and return its filtered value.

        Args:
            mags: The magnitude spectrum of the input audio frame. This should be a List of Float64 with length equal to `window_size // 2 + 1`.
            phases: The phase spectrum of the input audio frame. This should be a List of Float64 with length equal to `window_size // 2 + 1`.
        """
        var prev_offset = 1
        if self.frame_delta > 0 and OnsetMetric.uses_frame_delta(self.metric):
            prev_offset = self.frame_delta
        var prev_index = (self.history_write_head - prev_offset + self.history_size) % self.history_size
        var prev_prev_index = (self.history_write_head - 2 + self.history_size) % self.history_size

        self.raw_value = OnsetMetric.measure(
            self.metric,
            mags,
            phases,
            self.frame_history_mags[prev_index],
            self.frame_history_phases[prev_index],
            self.frame_history_mags[prev_prev_index],
            self.frame_history_phases[prev_prev_index],
        )
        self.filter_value()
        self.frame_history_mags[self.history_write_head] = mags.copy()
        self.frame_history_phases[self.history_write_head] = phases.copy()
        self.history_write_head = (self.history_write_head + 1) % self.history_size

    @staticmethod
    def buf_analysis(
        buf: Buffer,
        chan: Int = 0,
        start_frame: Int = 0,
        var num_frames: Optional[Int] = None,
        metric: OnsetMetric = OnsetMetric.complex_domain,
        window_size: Int = 1024,
        hop_size: Int = 512,
        filter_size: Int = 5,
        frame_delta: Int = 0,
    ) raises -> List[List[Float64]]:
        """Analyze a buffer for OnsetDetectionFeature values.

        The output is a List of Lists, where each inner List contains one Float64 value (the onset detection function value) for each analysis hop.

        Note the output is not onset times or a time series of onset triggers. To get onset times or triggers, use [OnsetDetection](#struct-onsetdetection).

        Args:
            buf: Source audio buffer.
            chan: Source channel to analyze.
            start_frame: First frame in the source buffer.
            num_frames: Number of source frames to analyze. A negative value analyzes to the end of the buffer.
            metric: Onset metric to calculate.
            window_size: Analysis window size in samples.
            hop_size: Number of samples between analysis frames.
            filter_size: Median-filter size.
            frame_delta: Offset in analysis frames (hops) used by Flux, MKL, and Itakura-Saito.

        Returns:
            One filtered onset detection-function value for each analysis hop.

        Raises:
            Error: If onset analysis or buffered processing fails.
        """
        if num_frames is None:
            num_frames = buf.num_frames - start_frame
        var odf = OnsetDetectionFeature(metric=metric, window_size=window_size, filter_size=filter_size, frame_delta=frame_delta)
        return MBufAnalysis.fft_process(odf, buf, chan, start_frame, num_frames, window_size, hop_size)

struct OnsetDetection(Movable, Copyable):
    """Detect spectral onsets in a time series of audio samples.

    This struct implements the ten FluidOnsetSlice metrics.
    """
    var world: World
    var metric: OnsetMetric
    var threshold: Float64
    var debounce: Float64
    var window_size: Int
    var hop_size: Int
    var filter_size: Int
    var frame_delta: Int
    var state: Bool
    var descriptor: Float64
    var previous_descriptor: Float64
    var debounce_count: Float64
    var fftp: FFTProcess[
        OnsetDetectionFeature,
        ifft=False,
        input_window_shape=WindowType.hann
    ]

    def __init__(
        out self,
        world: World,
        metric: OnsetMetric = OnsetMetric.complex_domain,
        threshold: Float64 = 0.5,
        debounce: Float64 = 0.1,
        window_size: Int = 1024,
        hop_size: Int = 512,
        filter_size: Int = 5,
        frame_delta: Int = 0,
    ):
        """Initialize an onset slicer.
        
        Args:
            world: The MMMWorld used for buffered processing.
            metric: The onset metric to calculate.
            threshold: Threshold crossing required to emit an onset.
            debounce: Minimum time duration (in seconds) between onsets.
            window_size: Analysis window size in samples.
            hop_size: Number of samples between analysis frames.
            filter_size: Median-filter size.
            frame_delta: Offset in analysis frames (hops) used by Flux, MKL, and Itakura-Saito.
        """
        self.world = world
        self.metric = metric
        self.threshold = threshold
        self.debounce = max(debounce, 0.0)
        self.window_size = window_size
        self.hop_size = hop_size
        self.filter_size = filter_size
        self.frame_delta = max(frame_delta, 0)
        self.state = False
        self.descriptor = 0.0
        self.previous_descriptor = 0.0
        self.debounce_count = 0

        var processor = OnsetDetectionFeature(
            metric=self.metric,
            window_size=self.window_size,
            filter_size=self.filter_size,
            frame_delta=self.frame_delta,
        )
        self.fftp = FFTProcess[
            OnsetDetectionFeature,
            ifft=False,
            input_window_shape=WindowType.hann,
        ](self.world, processor^, window_size=self.window_size, hop_size=self.hop_size)

    def next(mut self, input: SIMD[DType.float64,1]) -> Bool:
        """Process one sample and return whether this sample is an onset.
        
        Args:
            input: The input audio sample to analyze.
        
        Returns:
            True if this sample is an onset, False otherwise.
        """
        self.state = False

        _ = self.fftp.next(input)

        self.descriptor = self.fftp.get_process().descriptor
        if self.descriptor >= self.threshold and self.previous_descriptor < self.threshold and self.debounce_count <= 0.0:
            self.state = True
            self.debounce_count = self.debounce
        elif self.debounce_count > 0:
            self.debounce_count -= self.world[].sample_dur_seconds
        self.previous_descriptor = self.descriptor

        return self.state

    @staticmethod
    def buf_analysis(
        world: World,
        buf: Buffer,
        chan: Int = 0,
        start_frame: Int = 0,
        var num_frames: Optional[Int] = None,
        metric: OnsetMetric = OnsetMetric.complex_domain,
        threshold: Float64 = 0.5,
        debounce: Float64 = 0.1,
        window_size: Int = 1024,
        hop_size: Int = 512,
        filter_size: Int = 5,
        frame_delta: Int = 0,
    ) -> List[Int]:
        """Return onset sample indices for a buffer.
        
        Args:
            world: The MMMWorld used for buffered processing.
            buf: Source audio buffer.
            chan: Source channel to analyze.
            start_frame: First frame in the source buffer.
            num_frames: Number of source frames to analyze. A negative value analyzes to the end of the buffer.
            metric: The onset metric to calculate.
            threshold: Threshold crossing required to emit an onset.
            debounce: Minimum time duration (in seconds) between onsets.
            window_size: Analysis window size in samples.
            hop_size: Number of samples between analysis frames.
            filter_size: Median-filter size.
            frame_delta: Offset in analysis frames (hops) used by Flux, MKL, and Itakura-Saito.

        Returns:
            A List of Int sample indices where onsets were detected.        """
        if num_frames is None:
            num_frames = buf.num_frames - start_frame
        var end_frame = min(start_frame + num_frames.value(), buf.num_frames)

        var detector = OnsetDetection(
            world=world,
            metric=metric,
            threshold=threshold,
            debounce=debounce,
            window_size=window_size,
            hop_size=hop_size,
            filter_size=filter_size,
            frame_delta=frame_delta,
        )
        var onsets = List[Int]()
        
        for frame in range(start_frame, end_frame):
            var sample = buf.data[chan][frame]
            if detector.next(sample):
                onsets.append(frame - (window_size // 2)) # subtract half the window size because I want it to be in the "middle" of the fft window

        return onsets^

