import sys
from pathlib import Path

_bridge = None

def _get_bridge():
    """Compile (the first time) and load the Mojo analysis bridge, on first use.
    After this, reuse the same instance."""
    global _bridge
    if _bridge is None:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "mmm_audio" / "ML"))
        import mojo.importer
        import MBufAnalysisBridge
        _bridge = MBufAnalysisBridge
    return _bridge

class MBufAnalysis:
    
    @staticmethod
    def rms(dict:dict):
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
        return _get_bridge().rms(dict)
    
    @staticmethod
    def yin(dict:dict):
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
        return _get_bridge().yin(dict)
    
    @staticmethod
    def spectral_centroid(dict:dict):
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
        return _get_bridge().spectral_centroid(dict)
    
    @staticmethod
    def spectral_flux_onsets(dict:dict):
        return MBufAnalysis.onset_detection({"metric": "spectral_flux", **dict})

    @staticmethod
    def onset_detection_feature(dict:dict):
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
        return _get_bridge().onset_detection_feature(dict)

    @staticmethod
    def onset_detection(dict:dict):
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
        return _get_bridge().onset_detection(dict)
    
    @staticmethod
    def mfcc(dict:dict):
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
        return _get_bridge().mfcc(dict)
    
    @staticmethod
    def mel_bands(dict:dict):
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

        Returns:
            A NumPy float64 matrix with shape [num_hops, num_bands].

        Raises:
            Error: If input parsing, buffer loading, analysis, or NumPy conversion fails.
        """
        return _get_bridge().mel_bands(dict)
    
    @staticmethod
    def top_n_freqs(dict:dict):
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
        return _get_bridge().top_n_freqs(dict)