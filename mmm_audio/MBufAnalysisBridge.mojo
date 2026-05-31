from std.python import PythonObject
from std.python import Python
from std.python import ConvertibleFromPython
from std.python.bindings import PythonModuleBuilder
from std.os import abort
from mmm_audio import *

@export
def PyInit_MBufAnalysisBridge() -> PythonObject:
    try:
        var m = PythonModuleBuilder("MBufAnalysisBridge")
        m.def_function[MBufAnalysisBridge.rms]("rms")
        m.def_function[MBufAnalysisBridge.yin]("yin")
        m.def_function[MBufAnalysisBridge.mfcc]("mfcc")
        m.def_function[MBufAnalysisBridge.mel_bands]("mel_bands")
        m.def_function[MBufAnalysisBridge.spectral_flux_onsets]("spectral_flux_onsets")
        m.def_function[MBufAnalysisBridge.spectral_centroid]("spectral_centroid")
        m.def_function[MBufAnalysisBridge.top_n_freqs]("top_n_freqs")
        # m.def_function[MBufAnalysisBridge.custom]("custom")
        return m.finalize()
    except e:
        abort(String("error creating Python Mojo module:", e))

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
def getFloat64(analysis: String, py_dict: PythonObject, key: String, default: Optional[Float64] = None) raises -> Float64:
    if key in py_dict:
        return Float64(py=py_dict[key])
    else:
        if default is None:
            abort(String("MBufAnalysis", analysis, "requires a '", key, "' key in the input dictionary"))
        else:
            print("MBufAnalysis", analysis, ": No '", key, "' key in input dictionary, defaulting to ", default)
            return default.value()

struct AnalysisParams:
    var buf: Buffer
    var chan: Int
    var start_frame: Int
    var num_frames: Int
    # [TODO]: padding

    def __init__(out self, py_dict: PythonObject) raises:

        self.buf = Buffer.load(get_at_key[String]("AnalysisParams", py_dict, "path"))
        self.chan = get_at_key[Int]("AnalysisParams", py_dict, "chan", 0)
        self.start_frame = get_at_key[Int]("AnalysisParams", py_dict, "start_frame", 0)
        self.num_frames = get_at_key[Int]("AnalysisParams", py_dict, "num_frames", Int(self.buf.num_frames - self.start_frame))

struct MBufAnalysisBridge:

    @staticmethod
    def mel_bands(py_dict: PythonObject) raises -> PythonObject:

        ap = AnalysisParams(py_dict)
        window_size = get_at_key[Int]("mel_bands", py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("mel_bands", py_dict, "hop_size", window_size // 2)
        num_bands = get_at_key[Int]("mel_bands", py_dict, "num_bands", 40)
        min_freq: Float64 = getFloat64("mel_bands", py_dict, "min_freq", 20.0)
        max_freq: Float64 = getFloat64("mel_bands", py_dict, "max_freq", 20000.0)

        mel_bands = MelBands(ap.buf.sample_rate, num_bands, min_freq, max_freq, window_size)
        result = MBufAnalysis.fft_process[WindowType.hann](mel_bands, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)

        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def mfcc(py_dict: PythonObject) raises -> PythonObject:
        # make the analysis params instance
        ap = AnalysisParams(py_dict)
        num_bands = get_at_key[Int]("mfcc", py_dict, "num_bands", 40)
        num_coeffs = get_at_key[Int]("mfcc", py_dict, "num_coeffs", 13)
        min_freq = getFloat64("mfcc", py_dict, "min_freq", 20.0)
        max_freq = getFloat64("mfcc", py_dict, "max_freq", 20000.0)

        # # run the analysis
        mfcc = MFCC(ap.buf.sample_rate, num_coeffs, num_bands, min_freq, max_freq)
        window_size = get_at_key[Int]("mfcc", py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("mfcc", py_dict, "hop_size", window_size // 2)
        result = MBufAnalysis.fft_process[WindowType.hann](mfcc, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def top_n_freqs(py_dict: PythonObject) raises -> PythonObject:
        # make the analysis params instance
        ap = AnalysisParams(py_dict)
        num_peaks = get_at_key[Int]("top_n_freqs",py_dict, "num_peaks", 5)
        thresh = getFloat64("top_n_freqs",py_dict, "thresh", -30.0)
        sort_by_freq = get_at_key[Bool]("top_n_freqs",py_dict, "sort_by_freq", False)

        window_size = get_at_key[Int]("top_n_freqs",py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("top_n_freqs",py_dict, "hop_size", window_size // 2)

        # # run the analysis
        top_n_freqs = TopNFreqs(ap.buf.sample_rate, window_size, num_peaks, sort_by_freq, thresh)
        result = MBufAnalysis.fft_process[WindowType.hann](top_n_freqs, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def rms(py_dict: PythonObject) raises -> PythonObject:

        # make the analysis params instance
        ap = AnalysisParams(py_dict)

        # # run the analysis
        rms = RMS()
        window_size = get_at_key[Int]("rms",py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("rms",py_dict, "hop_size", window_size // 2)
        result = MBufAnalysis.buffered_process(rms, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def yin(py_dict: PythonObject) raises -> PythonObject:
        
        # make the analysis params instance
        ap = AnalysisParams(py_dict)

        # params specific to this analysis
        min_freq = getFloat64("yin",py_dict, "min_freq", 20.0)
        max_freq = getFloat64("yin",py_dict, "max_freq", 20000.0)

        # define the window function that will be called for each window of audio. 
        # It has to be a function that takes a List[Float64] and returns a List[Float64] 
        # (even if it's just one value) so that it's consistent with other analyses we 
        # might want to add later
        window_size = get_at_key[Int]("yin",py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("yin",py_dict, "hop_size", window_size // 2)
        yin = YIN(ap.buf.sample_rate, window_size, min_freq=min_freq, max_freq=max_freq)

        # run the analysis
        result = MBufAnalysis.buffered_process(yin,ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def spectral_centroid(py_dict: PythonObject) raises -> PythonObject:
        # make the analysis params instance
        ap = AnalysisParams(py_dict)
        min_freq = getFloat64("spectral_centroid",py_dict, "min_freq", 20.0)
        max_freq = getFloat64("spectral_centroid",py_dict, "max_freq", 20000.0)
        power_mag = get_at_key[Bool]("spectral_centroid",py_dict, "power_mag", False)
        window_size = get_at_key[Int]("spectral_centroid",py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("spectral_centroid",py_dict, "hop_size", window_size // 2)

        # # run the analysis
        sc = SpectralCentroid(ap.buf.sample_rate, min_freq=min_freq, max_freq=max_freq, power_mag=power_mag)
        result = MBufAnalysis.fft_process[WindowType.hann](sc, ap.buf, ap.chan, ap.start_frame, ap.num_frames, window_size=window_size, hop_size=hop_size)
        
        # return it as a numpy array
        return MBufAnalysisBridge.matrix_to_numpy(result)

    @staticmethod
    def spectral_flux_onsets(py_dict: PythonObject) raises -> PythonObject:
        # make the analysis params instance
        analysis_params = AnalysisParams(py_dict)
        thresh = getFloat64("spectral_flux_onsets",py_dict, "thresh", 0.01)
        window_size = get_at_key[Int]("spectral_flux_onsets",py_dict, "window_size", 1024)
        hop_size = get_at_key[Int]("spectral_flux_onsets",py_dict, "hop_size", window_size // 2)
        filter_size = get_at_key[Int]("spectral_flux_onsets",py_dict, "filter_size", 5)
        min_slice_len = getFloat64("spectral_flux_onsets",py_dict, "min_slice_len", 0.1)
        
        w = alloc[MMMWorld](1) 
        # TODO: need to find a new way to pass the missing pointers
        w.init_pointee_move(MMMWorld(analysis_params.buf.sample_rate))

        # run the analysis
        sf_onsets = SpectralFluxOnsets(w,window_size,hop_size,filter_size)
        sf_onsets.thresh = thresh
        sf_onsets.min_slice_len = min_slice_len

        onsets = List[Int]()

        for i in range(analysis_params.buf.num_frames):
            samp = analysis_params.buf.data[analysis_params.chan][i]
            if sf_onsets.next(samp):
                onsets.append(i)

        # return it as a numpy array
        return MBufAnalysisBridge.list_to_numpy(onsets)
    
    @staticmethod
    def list_to_numpy(list: List[Int]) raises -> PythonObject:
        np = Python.import_module("numpy")
        shape = Python.tuple(Int(len(list)))
        nparray = np.zeros(shape=shape,dtype=np.int64)
        for i in range(len(list)):
            nparray[i] = list[i]
        return nparray

    @staticmethod
    def matrix_to_numpy(list: List[List[Float64]]) raises -> PythonObject:
        np = Python.import_module("numpy")
        shape = Python.tuple(Int(len(list)), Int(len(list[0])))
        nparray = np.zeros(shape=shape,dtype=np.float64)
        for i in range(len(list)):
            for j in range(len(list[i])):
                nparray[i][j] = list[i][j]
        return nparray

struct MBufAnalysis:

    # [TODO]: add windowing
    @staticmethod
    def buffered_process[T: GetFloat64Featurable & BufferedProcessable](mut analyzer: T,buf: Buffer, chan: Int, start_frame: Int, var num_frames: Int, window_size: Int, hop_size: Int) raises -> List[List[Float64]]:
        result = List[List[Float64]]()
        frame: Int = start_frame
        if num_frames < 0:
            num_frames = buf.num_frames - start_frame
        window_samps = List[Float64](length=window_size,fill=0.0)
        while frame < start_frame + num_frames:
            for i in range(window_size):
                if frame + i < buf.num_frames:
                    window_samps[i] = buf.data[chan][frame + i]
                else:
                    window_samps[i] = 0.0
            analyzer.next_window(window_samps)
            result.append(analyzer.get_features())
            frame += hop_size
        return result^
    
    @staticmethod
    def fft_process[T: GetFloat64Featurable & FFTProcessable,//,input_win: WindowType = WindowType.hann](mut analyzer: T, buf: Buffer, chan: Int, start_frame: Int, var num_frames: Int, window_size: Int, hop_size: Int) raises -> List[List[Float64]]:
        result = List[List[Float64]]()
        frame: Int = start_frame
        if num_frames < 0:
            num_frames = buf.num_frames - start_frame
        window_samps = List[Float64](length=window_size,fill=0.0)
        fft = RealFFT(window_size)
        window_func = Windows.make_window[input_win](window_size)
        while frame < start_frame + num_frames:
            for i in range(window_size):
                if frame + i < buf.num_frames:
                    window_samps[i] = buf.data[chan][frame + i] * window_func[i]
                else:
                    window_samps[i] = 0.0
            fft.fft(window_samps)
            analyzer.next_frame(fft.mags,fft.phases)
            result.append(analyzer.get_features())
            frame += hop_size
        return result^

    # @staticmethod
    # def custom(py_path: PythonObject) raises -> PythonObject:
    #     path = String(py=py_path)
    #     print("custom analysis called, not yet implemented", path)
    #     return 42