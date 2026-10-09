from std.python import PythonObject
from std.python import Python
from std.python import ConvertibleFromPython
from std.python.bindings import PythonModuleBuilder
from std.os import abort
from mmm_audio.constants import *
from mmm_audio.Buffer_Module import Buffer, SpanInterpolator
from mmm_audio.ML.Analysis import *
from mmm_audio.ML.OnsetDetection_Module import OnsetDetection, OnsetMetric, OnsetDetectionFeature
from mmm_audio.MMMWorld_Module import MMMWorld, Environment
from mmm_audio.Windows_Module import Windows, WindowType
from std.memory.alloc import unsafe_alloc

@export
def PyInit_MBufAnalysisBridge() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("MBufAnalysisBridge")
        m.def_function[MBufAnalysisBridge.rms]("rms")
        m.def_function[MBufAnalysisBridge.yin]("yin")
        m.def_function[MBufAnalysisBridge.mfcc]("mfcc")
        m.def_function[MBufAnalysisBridge.mel_bands]("mel_bands")
        m.def_function[MBufAnalysisBridge.onset_detection]("onset_detection")
        m.def_function[MBufAnalysisBridge.onset_detection_feature]("onset_detection_feature")
        m.def_function[MBufAnalysisBridge.spectral_centroid]("spectral_centroid")
        m.def_function[MBufAnalysisBridge.top_n_freqs]("top_n_freqs")
        return m.finalize()
    except e:
        abort(String("error creating Python Mojo module:", e))

@doc_hidden
def get_at_key[T: ConvertibleFromPython & ImplicitlyCopyable & Writable](analysis: String, py_dict: PythonObject, key: String, default: Optional[T] = None) raises -> T:
    if key in py_dict:
        return T(py=py_dict[key])
    else:
        if default is None:
            abort(String("MBufAnalysis", analysis, "requires a '", key, "' key in the input dictionary"))
        else:
            print("MBufAnalysis", analysis, ": No '", key, "' key in input dictionary, defaulting to ", default)
            return default.value()

# the above get_at_key doesn't work with Float64 🤷🏼
# it can stay as a separate function until Modular
# fixes what looks like a bug
@doc_hidden
def getFloat64(analysis: String, py_dict: PythonObject, key: String, default: Optional[Float64] = None) raises -> Float64:
    if key in py_dict:
        return Float64(py=py_dict[key])
    else:
        if default is None:
            abort(String("MBufAnalysis", analysis, "requires a '", key, "' key in the input dictionary"))
        else:
            print("MBufAnalysis", analysis, ": No '", key, "' key in input dictionary, defaulting to ", default)
            return default.value()

@doc_hidden
struct AnalysisParams:
    var buf: Buffer
    var chan: Int
    var start_frame: Int
    var num_frames: Int
    var padding: Padding

    def __init__(out self, py_dict: PythonObject) raises:

        self.buf = Buffer.load(get_at_key[String]("AnalysisParams", py_dict, "path"))
        self.chan = get_at_key[Int]("AnalysisParams", py_dict, "chan", 0)
        self.start_frame = get_at_key[Int]("AnalysisParams", py_dict, "start_frame", 0)
        self.num_frames = get_at_key[Int]("AnalysisParams", py_dict, "num_frames", Int(self.buf.num_frames - self.start_frame))
        var padding_string = get_at_key[String]("AnalysisParams", py_dict, "padding", "half_window")
        self.padding = Padding.from_string(padding_string)

struct MBufAnalysisBridge:

    @staticmethod
    def mel_bands(py_dict: PythonObject) raises -> PythonObject:
        """Mel-band energy analysis of a buffer.

        Runs short-time FFT analysis and computes mel-band energies per hop.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.
            * **num_bands:** (Int, optional, default 40): Number of mel bands.
            * **min_freq:** (Float64, optional, default 20.0): Minimum analysis frequency in Hz.
            * **max_freq:** (Float64, optional, default 20000.0): Maximum analysis frequency in Hz.
            * **padding:** (Int, optional): Number of frames to pad the buffer with zeros before analysis. If not provided, `window_size` // 2 will be used.

        Returns:
            A NumPy float64 matrix with shape [num_hops, num_bands].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """

        var ap = AnalysisParams(py_dict)
        # TODO: i'm pretty sure window_size and hop_size can be computed in AnalysisParams::init
        var window_size = get_at_key[Int]("mel_bands", py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("mel_bands", py_dict, "hop_size", window_size // 2)
        var num_bands = get_at_key[Int]("mel_bands", py_dict, "num_bands", 40)
        var min_freq: Float64 = getFloat64("mel_bands", py_dict, "min_freq", 20.0)
        var max_freq: Float64 = getFloat64("mel_bands", py_dict, "max_freq", 20000.0)

        var mel_bands = MelBands(ap.buf.sample_rate, num_bands, min_freq, max_freq, window_size)
        var result = MBufAnalysis.fft_process(mel_bands, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size, window_type=WindowType.hann, padding=ap.padding)

        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def mfcc(py_dict: PythonObject) raises -> PythonObject:
        """MFCC analysis of a buffer.

        Runs short-time FFT analysis, maps each frame to mel bands, then computes
        cepstral coefficients per hop.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **num_bands:** (Int, optional, default 40): Number of mel bands used internally.
            * **num_coeffs:** (Int, optional, default 13): Number of MFCC coefficients returned per hop.
            * **min_freq:** (Float64, optional, default 20.0): Minimum analysis frequency in Hz.
            * **max_freq:** (Float64, optional, default 20000.0): Maximum analysis frequency in Hz.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.

        Returns:
            A NumPy float64 matrix with shape [num_hops, num_coeffs].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        # make the analysis params instance
        var ap = AnalysisParams(py_dict)
        var num_bands = get_at_key[Int]("mfcc", py_dict, "num_bands", 40)
        var num_coeffs = get_at_key[Int]("mfcc", py_dict, "num_coeffs", 13)
        var min_freq = getFloat64("mfcc", py_dict, "min_freq", 20.0)
        var max_freq = getFloat64("mfcc", py_dict, "max_freq", 20000.0)

        # # run the analysis
        var mfcc = MFCC(ap.buf.sample_rate, num_coeffs, num_bands, min_freq, max_freq)
        var window_size = get_at_key[Int]("mfcc", py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("mfcc", py_dict, "hop_size", window_size // 2)
        var result = MBufAnalysis.fft_process(mfcc, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size, window_type=WindowType.hann)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def top_n_freqs(py_dict: PythonObject) raises -> PythonObject:
        """Top-N spectral peak analysis of a buffer.

        Runs short-time FFT analysis and extracts up to `num_peaks` dominant peaks
        per hop. Each hop output is flattened as alternating frequency and amplitude
        values: [f0, a0, f1, a1, ...].

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **num_peaks:** (Int, optional, default 5): Number of peaks to return per hop.
            * **thresh:** (Float64, optional, default -30.0): Peak threshold in dB for candidate selection.
            * **sort_by_freq:** (Bool, optional, default False): Sort output peak pairs by frequency when true.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.

        Returns:
            A NumPy float64 matrix with shape [num_hops, num_peaks * 2].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        # make the analysis params instance
        var ap = AnalysisParams(py_dict)
        var num_peaks = get_at_key[Int]("top_n_freqs",py_dict, "num_peaks", 5)
        var thresh = getFloat64("top_n_freqs",py_dict, "thresh", -30.0)
        var sort_by_freq = get_at_key[Bool]("top_n_freqs",py_dict, "sort_by_freq", False)

        var window_size = get_at_key[Int]("top_n_freqs",py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("top_n_freqs",py_dict, "hop_size", window_size // 2)

        # # run the analysis
        var top_n_freqs = TopNFreqs(ap.buf.sample_rate, window_size, num_peaks, sort_by_freq, thresh)
        var result = MBufAnalysis.fft_process(top_n_freqs, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size, window_type=WindowType.hann)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def rms(py_dict: PythonObject) raises -> PythonObject:
        """RMS amplitude analysis of a buffer.

        Computes one root-mean-square amplitude value per analysis hop.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **window_size:** (Int, optional, default 1024): Analysis window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.

        Returns:
            A NumPy float64 matrix with shape [num_hops, 1].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """

        # make the analysis params instance
        var ap = AnalysisParams(py_dict)

        # # run the analysis
        var rms = RMS()
        var window_size = get_at_key[Int]("rms",py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("rms",py_dict, "hop_size", window_size // 2)
        var result = MBufAnalysis.buffered_process(rms, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def yin(py_dict: PythonObject) raises -> PythonObject:
        """YIN pitch analysis of a buffer.

        Computes monophonic pitch and confidence per analysis hop using an FFT-based
        YIN implementation.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **min_freq:** (Float64, optional, default 20.0): Minimum detectable pitch in Hz.
            * **max_freq:** (Float64, optional, default 20000.0): Maximum detectable pitch in Hz.
            * **window_size:** (Int, optional, default 1024): Analysis window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.

        Returns:
            A NumPy float64 matrix with shape [num_hops, 2], with columns
            [pitch_hz, confidence].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        
        # make the analysis params instance
        var ap = AnalysisParams(py_dict)

        # params specific to this analysis
        var min_freq = getFloat64("yin",py_dict, "min_freq", 20.0)
        var max_freq = getFloat64("yin",py_dict, "max_freq", 20000.0)

        # define the window function that will be called for each window of audio. 
        # It has to be a function that takes a List[Float64] and returns a List[Float64] 
        # (even if it's just one value) so that it's consistent with other analyses we 
        # might want to add later
        var window_size = get_at_key[Int]("yin",py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("yin",py_dict, "hop_size", window_size // 2)
        var yin = YIN(ap.buf.sample_rate, window_size, min_freq=min_freq, max_freq=max_freq)

        # run the analysis
        var result = MBufAnalysis.buffered_process(yin,ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def spectral_centroid(py_dict: PythonObject) raises -> PythonObject:
        """Spectral centroid analysis of a buffer.

        Runs short-time FFT analysis and computes one centroid value (in Hz) per hop,
        optionally weighting by power magnitudes.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **min_freq:** (Float64, optional, default 20.0): Minimum frequency in Hz included in the centroid.
            * **max_freq:** (Float64, optional, default 20000.0): Maximum frequency in Hz included in the centroid.
            * **power_mag:** (Bool, optional, default False): Use power magnitudes instead of linear magnitudes.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.

        Returns:
            A NumPy float64 matrix with shape [num_hops, 1].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        # make the analysis params instance
        var ap = AnalysisParams(py_dict)
        var min_freq = getFloat64("spectral_centroid",py_dict, "min_freq", 20.0)
        var max_freq = getFloat64("spectral_centroid",py_dict, "max_freq", 20000.0)
        var power_mag = get_at_key[Bool]("spectral_centroid",py_dict, "power_mag", False)
        var window_size = get_at_key[Int]("spectral_centroid",py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("spectral_centroid",py_dict, "hop_size", window_size // 2)

        # # run the analysis
        var sc = SpectralCentroid(ap.buf.sample_rate, min_freq=min_freq, max_freq=max_freq, power_mag=power_mag)
        var result = MBufAnalysis.fft_process(sc, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size, window_type=WindowType.hann)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def onset_detection_feature(py_dict: PythonObject) raises -> PythonObject:
        """Onset feature analysis of a buffer.

        Uses the OnsetDetectionFeature class to analyze a buffer for onset detection function values. 
        The output is a List of Lists, where each inner List contains one Float64 value (the onset 
        detection function value) for each analysis hop.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **metric:** (String, optional, default "complex_domain"): Onset metric name.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.
            * **filter_size:** (Int, optional, default 5): Median-filter size.
            * **frame_delta:** (Int, optional, default 0): Frame offset for delayed comparison metrics.

        Returns:
            A NumPy float64 matrix where each row contains one onset detection-function value
            for an analysis hop.

        Raises:
            Error: If input parsing, buffer loading, metric conversion, analysis, or NumPy conversion fails.
        """
        var ap = AnalysisParams(py_dict)
        var metric_string = get_at_key[String]("onset_detection_feature", py_dict, "metric", "complex_domain")
        var window_size = get_at_key[Int]("onset_detection_feature", py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("onset_detection_feature", py_dict, "hop_size", window_size // 2)
        var filter_size = get_at_key[Int]("onset_detection_feature", py_dict, "filter_size", 5)
        var frame_delta = get_at_key[Int]("onset_detection_feature", py_dict, "frame_delta", 0)

        var result = OnsetDetectionFeature.buf_analysis(
            ap.buf,
            ap.chan,
            ap.start_frame,
            ap.num_frames,
            OnsetMetric.from_string(metric_string),
            window_size,
            hop_size,
            filter_size,
            frame_delta,
        )
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def onset_detection(py_dict: PythonObject) raises -> PythonObject:
        """Onset Detection on a buffer.

        Uses `OnsetDetection` to analyze a buffer for onsets and return the sample indices of detected onsets.

        Args:
            py_dict: Analysis options dictionary.

        Options in py_dict:
            * **path:** (String, required): Path to the source audio file.
            * **chan:** (Int, optional, default 0): Channel index to analyze.
            * **start_frame:** (Int, optional, default 0): First frame to analyze.
            * **num_frames:** (Int, optional): Number of frames to analyze. Defaults to the remaining buffer.
            * **metric:** (String, optional, default "complex_domain"): Onset metric name.
            * **threshold:** (Float64, optional, default 0.5): Descriptor threshold for trigger detection.
            * **debounce:** (Float64, optional, default 0.1): Minimum seconds between triggers.
            * **window_size:** (Int, optional, default 1024): FFT window size in samples.
            * **hop_size:** (Int, optional, default window_size // 2): Hop size in samples.
            * **filter_size:** (Int, optional, default 5): Median-filter size.
            * **frame_delta:** (Int, optional, default 0): Frame offset for delayed comparison metrics.

        Returns:
            A NumPy int64 vector of onset sample indices.

        Raises:
            Error: If input parsing, world setup, metric conversion, analysis, or NumPy conversion fails.
        """
        var ap = AnalysisParams(py_dict)
        var metric_string = get_at_key[String]("onset_detection", py_dict, "metric", "complex_domain")
        var threshold = getFloat64("onset_detection", py_dict, "threshold", 0.5)
        var debounce = getFloat64("onset_detection", py_dict, "debounce", 0.1)
        var window_size = get_at_key[Int]("onset_detection", py_dict, "window_size", 1024)
        var hop_size = get_at_key[Int]("onset_detection", py_dict, "hop_size", window_size // 2)
        var filter_size = get_at_key[Int]("onset_detection", py_dict, "filter_size", 5)
        var frame_delta = get_at_key[Int]("onset_detection", py_dict, "frame_delta", 0)
        

        var w = unsafe_alloc[MMMWorld](1)
        var environment = unsafe_alloc[Environment](1)
        environment.unsafe_write(Environment(64, 2, 2))
        w.unsafe_write(MMMWorld(ap.buf.sample_rate, environment))

        var result = OnsetDetection.buf_analysis(
            w,
            ap.buf,
            ap.chan,
            ap.start_frame,
            ap.num_frames,
            OnsetMetric.from_string(metric_string),
            threshold,
            debounce,
            window_size,
            hop_size,
            filter_size,
            frame_delta,
        )
        return MBufAnalysisBridge.list_to_numpy(result)
    
    @staticmethod
    def list_to_numpy(list: List[Int]) raises -> PythonObject:
        """Convert a List[Int] to a 1-D NumPy int64 array.

        Args:
            list: Integer values to copy into a NumPy vector.

        Returns:
            A NumPy int64 vector with length equal to `len(list)`.

        Raises:
            Error: If NumPy import/allocation or element assignment fails.
        """
        var np = Python.import_module("numpy")
        var shape = Python.tuple(Int(len(list)))
        var nparray = np.zeros(shape=shape,dtype=np.int64)
        for i in range(len(list)):
            nparray[i] = list[i]
        return nparray

    @staticmethod
    def matrix_to_numpy(list: List[List[Float64]]) raises -> PythonObject:
        """Convert a 2-D Float64 list to a NumPy float64 matrix.

        Args:
            list: Rectangular List[List[Float64]] containing row-major matrix data.

        Returns:
            A NumPy float64 matrix with shape [len(list), len(list[0])].

        Raises:
            Error: If NumPy import/allocation or element assignment fails.
        """
        var np = Python.import_module("numpy")
        var shape = Python.tuple(Int(len(list)), Int(len(list[0])))
        var nparray = np.zeros(shape=shape,dtype=np.float64)
        for i in range(len(list)):
            for j in range(len(list[i])):
                nparray[i][j] = list[i][j]
        return nparray

struct Padding(ImplicitlyCopyable):
    var mode: Int
    var offset: Int

    comptime none = Padding(0)
    comptime half_window = Padding(1)

    def __init__(out self, mode: Int, offset: Int = 0):
        self.mode = mode
        self.offset = offset

    def update(mut self, window_size: Int):
        if self.mode == Padding.none.mode:
            self.offset = 0
        elif self.mode == Padding.half_window.mode:
            self.offset = window_size // 2
        else:
            abort(String("MBufAnalysis: unknown padding mode ", self.mode))

    @staticmethod
    def from_string(padding_string: String) -> Padding:
        if padding_string == "none":
            return Padding.none
        elif padding_string == "half_window":
            return Padding.half_window
        else:
            print("MBufAnalysis: unknown padding string ", padding_string, ", defaulting to half_window")
            return Padding.half_window

@doc_hidden
struct MBufAnalysis:
    # This struct is not really meant to be user facing. It creates these convenience functions for buffer analysis
    # both by MBufAnalysisBridge and the Analysis tools `.buf_analysis` methods. 
    var num_windows: Int
    var start_frame: Int
    var window_func: List[Float64]
    var samps: List[Float64]
    var valid: Bool
    var padding: Padding

    def __init__(out self, buf: Buffer, var start_frame: Int, var num_frames: Optional[Int], window_size: Int, hop_size: Int, window_type: WindowType = WindowType.none, var padding: Padding = Padding.half_window) raises:
        
        self.valid = True

        if num_frames is None:
            num_frames = buf.num_frames - start_frame

        if start_frame + num_frames.value() > buf.num_frames:
            print("MBufAnalysis: requested frames exceed buffer length. start_frame = ", start_frame, ", num_frames = ", num_frames, ", buf.num_frames = ", buf.num_frames)
            self.valid = False

        self.window_func = Windows.make_window(window_type, window_size)
        
        self.samps = List[Float64](length=window_size, fill=0.0)

        self.padding = padding
        self.padding.update(window_size)
        self.start_frame = start_frame - self.padding.offset
        num_frames = num_frames.value() + (self.padding.offset * 2)

        self.num_windows: Int = 1
        if num_frames.value() > window_size:
            self.num_windows = (num_frames.value() - window_size) // hop_size + 1

    @staticmethod
    def buffered_process[T: GetFloat64Featurable & BufferedProcessable](mut analyzer: T,buf: Buffer, chan: Int, var start_frame: Int, var num_frames: Optional[Int], window_size: Int, hop_size: Int, window_type: WindowType = WindowType.none, var padding: Padding = Padding.half_window) raises -> List[List[Float64]]:

        var mba = MBufAnalysis(buf, start_frame, num_frames, window_size, hop_size, window_type, padding)

        if not mba.valid:
            print("MBufAnalysis: invalid buffer analysis parameters. Returning empty result.")
            return List[List[Float64]]()

        var result = List[List[Float64]](capacity=mba.num_windows)
        for w in range(mba.num_windows):
            for i in range(window_size):
                var frame_idx = mba.start_frame + (w * hop_size) + i
                mba.samps[i] = SpanInterpolator.read_none[bWrap=False](buf.data[chan], Float64(frame_idx)) * mba.window_func[i]

            analyzer.next_window(mba.samps)
            result.append(analyzer.get_features())
            
        return result^
    
    @staticmethod
    def fft_process[T: GetFloat64Featurable & FFTProcessable](mut analyzer: T, buf: Buffer, chan: Int, var start_frame: Int, var num_frames: Optional[Int], window_size: Int, hop_size: Int, window_type: WindowType = WindowType.none, var padding: Padding = Padding.half_window) raises -> List[List[Float64]]:
        """Run an FFT-based analysis on a buffer.

        Args:
            analyzer: An instance of a type that implements GetFloat64Featurable and FFTProcessable.
            buf: The audio buffer to analyze.
            chan: The channel index to analyze.
            start_frame: The first frame to analyze.
            num_frames: The number of frames to analyze. If None, defaults to the remaining buffer.
            window_size: The FFT window size in samples.
            hop_size: The hop size in samples.
            window_type: The type of window function to apply (default is none).
            padding: Padding mode for the analysis (default is half_window).
        
        Returns:
            A List of Lists of Float64, where each inner list contains the features for one analysis hop.
        
        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        var mba = MBufAnalysis(buf, start_frame, num_frames, window_size, hop_size, window_type, padding)

        if not mba.valid:
            print("MBufAnalysis: invalid buffer analysis parameters. Returning empty result.")
            return List[List[Float64]]()
        
        var fft = RealFFT(window_size)
        
        var result = List[List[Float64]](capacity=mba.num_windows)
        for w in range(mba.num_windows):
            for i in range(window_size):
                var frame_idx = mba.start_frame + (w * hop_size) + i
                mba.samps[i] = SpanInterpolator.read_none[bWrap=False](buf.data[chan], Float64(frame_idx)) * mba.window_func[i]

            fft.fft(mba.samps)
            analyzer.next_frame(fft.mags,fft.phases)
            result.append(analyzer.get_features())

        return result^