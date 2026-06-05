from mmm_audio import *
from std.testing import assert_equal, assert_almost_equal, assert_true
from std.testing import TestSuite
from std.math import inf, nan
from std.pathlib import Path
from std.random import random_float64, random_ui64

def test_Changed() raises:
    # Test with Bool
    changed_bool = Changed(False)
    assert_equal(changed_bool.next(False), False, "Changed failed for Bool: No change should return False")
    assert_equal(changed_bool.next(True), True, "Changed failed for Bool: Change should return True")
    assert_equal(changed_bool.next(True), False, "Changed failed for Bool: No change should return False")

    changed_bools = Changed(MBool[4](False, False, False, False))
    assert_equal(changed_bools.next(MBool[4](False, False, False, False)), False, "Changed failed for Bool: No change should return False")
    assert_equal(changed_bools.next(MBool[4](True, False, True, True)), True, "Changed failed for Bool: Change should return True")
    assert_equal(changed_bools.next(MBool[4](True, True, True, True)), True, "Changed failed for Bool: No change should return False")
    
    # Test with Int
    changed_int = Changed(0)
    assert_equal(changed_int.next(0), False, "Changed failed for Int: No change should return False")
    assert_equal(changed_int.next(1), True, "Changed failed for Int: Change should return True")
    assert_equal(changed_int.next(1), False, "Changed failed for Int: No change should return False")

    changed_ints = Changed(MInt[4](0, 0, 0, 0))
    assert_equal(changed_ints.next(MInt[4](0, 0, 0, 0)), False, "Changed failed for Int: No change should return False")
    assert_equal(changed_ints.next(MInt[4](1, 0, 1, 1)), True, "Changed failed for Int: Change should return True")
    assert_equal(changed_ints.next(MInt[4](1, 1, 1, 1)), True, "Changed failed for Int: No change should return False")
    
    # Test with Float64
    changed_float = Changed(0.0)
    assert_equal(changed_float.next(0.0), False, "Changed failed for Float64: No change should return False")
    assert_equal(changed_float.next(1.0), True, "Changed failed for Float64: Change should return True")
    assert_equal(changed_float.next(1.0), False, "Changed failed for Float64: No change should return False")

    changed_floats = Changed(MFloat[4](0.0, 0.0, 0.0, 0.0))
    assert_equal(changed_floats.next(MFloat[4](0.0, 0.0, 0.0, 0.0)), False, "Changed failed for Float64: No change should return False")
    assert_equal(changed_floats.next(MFloat[4](1.0, 0.0, 1.0, 1.0)), True, "Changed failed for Float64: Change should return True")
    assert_equal(changed_floats.next(MFloat[4](1.0, 1.0, 1.0, 1.0)), True, "Changed failed for Float64: No change should return False")

def test_ChangedSIMD() raises:
    changed_bool = ChangedSIMD(MBool[4](False, False, False, False))
    assert_equal(changed_bool.next(MBool[4](False, False, False, False)), MBool[4](False, False, False, False), "Changed failed for Bool: No change should return False")
    assert_equal(changed_bool.next(MBool[4](True, False, True, True)), MBool[4](True, False, True, True), "Changed failed for Bool: Change should return True")
    assert_equal(changed_bool.next(MBool[4](True, True, True, True)), MBool[4](False, True, False, False), "Changed failed for Bool: No change should return False")
    
    # Test with Int
    changed_int = ChangedSIMD(MInt[4](0, 0, 0, 0))
    assert_equal(changed_int.next(MInt[4](0, 0, 0, 0)), MBool[4](False, False, False, False), "Changed failed for Int: No change should return False")
    assert_equal(changed_int.next(MInt[4](1, 0, 1, 1)), MBool[4](True, False, True, True), "Changed failed for Int: Change should return True")
    assert_equal(changed_int.next(MInt[4](1, 1, 1, 1)), MBool[4](False, True, False, False), "Changed failed for Int: No change should return False")

    # Test with Float64
    changed_float = ChangedSIMD(MFloat[4](0.0, 0.0, 0.0, 0.0))
    assert_equal(changed_float.next(MFloat[4](0.0, 0.0, 0.0, 0.0)), MBool[4](False, False, False, False), "Changed failed for Float64: No change should return False")
    assert_equal(changed_float.next(MFloat[4](1.0, 0.0, 1.0, 1.0)), MBool[4](True, False, True, True), "Changed failed for Float64: Change should return True")
    assert_equal(changed_float.next(MFloat[4](1.0, 1.0, 1.0, 1.0)), MBool[4](False, True, False, False), "Changed failed for Float64: No change should return False")

def test_sound_file_reader() raises:
    try:
        # Quick one-liner to read audio
        file = "resources/Shiverer.wav"
        var scipy = Python.import_module("scipy")
        var np = Python.import_module("numpy")
        var result = scipy.io.wavfile.read(file)
        var sample_rate = result[0]
        var data = result[1]
        print("Data type:", data.dtype)
        if data.dtype == np.int16 or data.dtype == np.int32 or data.dtype == np.uint8:
            data = data.astype(np.float64)/np.iinfo(result[1].dtype).max
        else:
            data = data.astype(np.float64)
        
        print("Sample rate:", sample_rate)
        print("Shape:", data.shape)

        header = read_wav_header(file)
        print_wav_info(header)
        wav = read_wav_SIMDs[2](file, header)
        print(len(wav), len(data))
        try:
            for i in range(header.num_samples):
                assert_almost_equal(wav[i][0], py_to_float64(data[i][0]), String(i))
                assert_almost_equal(wav[i][1], py_to_float64(data[i][1]), String(i))
        except err:
            print("What happened: ", err)
    except err:
        print("Error reading WAV file: ", err)

def test_linear_interp() raises:
    a = MFloat[4](0.0, 10.0, 20.0, 30.0)
    b = MFloat[4](10.0, 20.0, 30.0, 40.0)
    t = MFloat[4](0.0, 0.5, 1.0, 0.25)
    result = linear_interp(a, b, t)
    expected = MFloat[4](0.0, 15.0, 30.0, 32.5)
    assert_almost_equal(result, expected, "Test: lerp function failed")

def test_sanitize() raises:
    nan = nan[DType.float64]()
    pos_inf = inf[DType.float64]()
    neg_inf = -inf[DType.float64]()
    values = MFloat[4](1.0, nan, pos_inf, neg_inf)
    sanitized = sanitize(values)
    expected = MFloat[4](1.0, 0.0, 0.0, 0.0)
    assert_almost_equal(sanitized, expected, "Test: sanitize function failed: ")

def test_mel_to_hz() raises:
    """Compare mel_to_hz against librosa's implementation."""
    librosa_results = MFloat[8](345123.07093968056, 334060977.5717811, 323353453109.8285, 312989132696839.3, 3.029570157490985e+17, 2.932464542802523e+20, 2.8384714159964454e+23, 2.747491013729005e+26)
    mels = MFloat[8](100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0)
    mmm_results = MFloat[8]()
    for i in range(8):
        mmm_results[i] = MelBands.mel_to_hz(mels[i])
    assert_almost_equal(mmm_results, librosa_results, "Test: mel_to_hz function failed")

def test_hz_to_mel() raises:
    """Compare hz_to_mel against librosa's implementation."""
    librosa_results = MFloat[8](100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0)
    hz_values = MFloat[8](345123.07093968056, 334060977.5717811, 323353453109.8285, 312989132696839.3, 3.029570157490985e+17, 2.932464542802523e+20, 2.8384714159964454e+23, 2.747491013729005e+26)
    mmm_results = MFloat[8]()
    for i in range(8):
        mmm_results[i] = MelBands.hz_to_mel(hz_values[i])
    assert_almost_equal(mmm_results, librosa_results, "Test: hz_to_mel function failed")

def test_diff() raises:
    arr = List[Float64]([1.0, 2.5, 4.0, 7.0, 10.0])
    expected = List[Float64]([1.5, 1.5, 3.0, 3.0])
    result = diff(arr)

    result_simd = MFloat[4](result[0], result[1], result[2], result[3])
    expected_simd = MFloat[4](expected[0], expected[1], expected[2], expected[3])
    assert_almost_equal(result_simd, expected_simd, "Test: diff function failed")

def linspace_test(endpoint: Bool, num: Int) raises:
    start = random_float64() * 100.0
    stop = random_float64() * 100.0
    result_mojo = linspace(start, stop, num, endpoint)

    # Compare against Python implementation
    try:
        np = Python.import_module("numpy")
        result_np = np.linspace(start, stop, num, endpoint=endpoint).tolist()
    
        expected = List[Float64](length=num, fill=0.0)
        for i in range(num):
            expected[i] = Float64(py=result_np[i])
    
        compare_long_lists(result_mojo,expected)
    except err:
        print("Error comparing linspace results with numpy: ", err)

def test_linspace() raises:

    for _ in range(10):  # Run multiple times with random inputs
        num = Int(random_ui64(2, 100))  # Ensure at least 2 points to avoid edge case
        linspace_test(True, num)
        linspace_test(False, num)

    for _ in range(10):  # Run multiple times with random inputs
        linspace_test(True, 1)
        linspace_test(False, 1)

def test_mel_frequencies() raises:
    num_mel_bins = 32
    fmin = 20.0
    fmax = 20000.0
    result = MelBands.mel_frequencies(num_mel_bins, fmin, fmax)
    result_simd = MFloat[32]()
    for i in range(32):
        result_simd[i] = result[i]
    expected = MFloat[32](20.0, 145.31862602399627, 270.63725204799255, 395.95587807198876, 521.274504095985, 646.5931301199813, 771.9117561439776, 897.2303821679739, 1023.526754399107, 1164.733656827089, 1325.421622361244, 1508.2782803824396, 1716.3620486443097, 1953.15328765427, 2222.6125123704865, 2529.2466348500357, 2878.184345807327, 3275.2618958971248, 3727.120711479871, 4241.318477567799, 4826.455545899264, 5492.318782413196, 6250.04526008295, 7112.308534997669, 8093.530621301341, 9210.123210432963, 10480.762169244366, 11926.699908187227, 13572.120844166513, 15444.545903449043, 17575.292830248403, 19999.999999999996)
    assert_almost_equal(result_simd, expected, "Test: mel_frequencies function failed")

def test_fft_frequencies() raises:
    sample_rate = 44100.0
    n_fft = 512
    result = RealFFT.fft_frequencies(sample_rate, n_fft)
    result_simd = MFloat[8]()
    for i in range(8):
        result_simd[i] = result[i]
    expected = MFloat[8](0.0, 86.1328125, 172.265625, 258.3984375, 344.53125, 430.6640625, 516.796875, 602.9296875)
    assert_almost_equal(result_simd, expected, "Test: fft_frequencies function failed")

def test_dct()  raises:
    dct = DCT(4,3)
    input_vals = List[Float64]([1.0, 2.0, 3.0, 4.0])
    output_vals = List[Float64](length=3, fill=0.0)
    dct.process(input_vals, output_vals)

    expected = List[Float64]([5.0, -2.230442497387663, -6.280369834735101e-16])
    for i in range(len(output_vals)):
        assert_almost_equal(output_vals[i], expected[i], "Test: DCT coefficient mismatch")

def test_mfcc_paths_consistency() raises:
    """Ensure MFCC outputs match across next_frame, from_mags, and from_mel_bands."""
    comptime fft_size: Int = 64
    comptime num_bands: Int = 8
    comptime num_coeffs: Int = 4

    w = alloc[MMMWorld](1) 
    w.init_pointee_move(MMMWorld(48000.0))

    mags = List[Float64](length=(fft_size // 2) + 1, fill=0.0)
    phases = List[Float64](length=(fft_size // 2) + 1, fill=0.0)

    for i in range(len(mags)):
        mags[i] = 0.001 + 0.001 * Float64(i)

    mel = MelBands(w[].sample_rate, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    mel.from_mags(mags)

    mfcc_next = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    mfcc_mags = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    mfcc_bands = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)

    mfcc_next.next_frame(mags, phases)
    mfcc_mags.from_mags(mags)
    mfcc_bands.from_mel_bands(mel.bands)

    for i in range(num_coeffs):
        assert_almost_equal(mfcc_next.coeffs[i], mfcc_mags.coeffs[i], "Test: MFCC next_frame vs from_mags mismatch")
        assert_almost_equal(mfcc_next.coeffs[i], mfcc_bands.coeffs[i], "Test: MFCC next_frame vs from_mel_bands mismatch")

def test_mel_bands_weights() raises:
    
    n_mels: Int = 40
    n_fft: Int = 512
    sr: Int = 44100

    w = alloc[MMMWorld](1) 
    w.init_pointee_move(MMMWorld(MFloat[1](sr), 64, 2, 2, None, None, None))
    melbands = MelBands(w[].sample_rate, num_bands=n_mels,min_freq=20.0,max_freq=20000.0,fft_size=n_fft)

    weights_flat = List[Float64]()

    for i in range(len(melbands.weights)):
        for j in range(len(melbands.weights[i])):
            weights_flat.append(Float64(melbands.weights[i][j]))

    try:
        librosa = Python.import_module("librosa")
        mel_weights = librosa.filters.mel(sr=sr, n_fft=n_fft, n_mels=n_mels, htk=False,fmin=20.0,fmax=20000.0)
        mel_weights = mel_weights.tolist()

        expected_flat = List[Float64]()
        for i in range(len(mel_weights)):
            for j in range(len(mel_weights[i])):
                expected_flat.append(Float64(py=mel_weights[i][j]))

        compare_long_lists(weights_flat, expected_flat)
    except err:
        print("Error comparing Mel filter weights with librosa: ", err)

def compare_long_lists[chunk_size: Int = 64](a: List[Float64], b: List[Float64], verbose: Bool = False) raises:
    assert_equal(len(a), len(b), "Lists are of different lengths")
    a_simd = SIMD[DType.float64,chunk_size]()
    b_simd = SIMD[DType.float64,chunk_size]()

    i: Int = 0
    while i < len(a):
        a_simd[i % chunk_size] = a[i]
        b_simd[i % chunk_size] = b[i]
        if i > 0 and i % chunk_size == 0:
            if verbose:
                print("Comparing chunk ending at index ", i)
            assert_almost_equal(a_simd,b_simd)
        i += 1

def pca_test(whiten: Bool) raises:

    joblib = Python.import_module("joblib")
    np = Python.import_module("numpy")

    # dataset
    dataset = np.random.rand(100, 8)  # 100 samples, 8 features
    
    # sklearn
    pca_sklearn = Python.import_module("sklearn").decomposition.PCA
    pca_py = pca_sklearn(whiten=whiten)
    pca_py.fit(dataset)

    # write
    pca_py_tmp_path = "tmp_pca.joblib"
    joblib.dump(pca_py, pca_py_tmp_path)

    # read with mojo
    pca_mojo = PCA(pca_py_tmp_path)

    # test 10 transforms
    for _ in range(10):
        input_py = np.random.rand(8)
        input_mojo = List[Float64]()
        for j in range(8):
            input_mojo.append(Float64(py=input_py[j]))
        
        output_mojo = List[Float64](length=pca_mojo.k, fill=0.0)
        pca_mojo.transform_point(input_mojo, output_mojo)
        output_py = pca_py.transform(input_py.reshape(1, -1)).flatten()
        for j in range(pca_mojo.k):
            assert_almost_equal(output_mojo[j], Float64(py=output_py[j]), "PCA Mismatch at index " + String(j) + ": Mojo=" + String(output_mojo[j]) + " vs Py=" + String(output_py[j]) + " (whiten=" + String(whiten) + ")")

    # test 10 inverse transforms
    for _ in range(10):
        input_py = np.random.rand(pca_mojo.k)
        input_mojo = List[Float64]()
        for j in range(pca_mojo.k):
            input_mojo.append(Float64(py=input_py[j]))

        output_mojo = List[Float64](length=pca_mojo.d, fill=0.0)
        pca_mojo.inverse_transform_point(input_mojo, output_mojo)
        output_py = pca_py.inverse_transform(input_py.reshape(1, -1)).flatten()

        for j in range(pca_mojo.d):
            assert_almost_equal(output_mojo[j], Float64(py=output_py[j]), "PCA Mismatch at index " + String(j) + ": Mojo=" + String(output_mojo[j]) + " vs Py=" + String(output_py[j]) + " (whiten=" + String(whiten) + ")")

def test_pca() raises:
    pca_test(whiten=False)
    pca_test(whiten=True)
    
def test_standard_scaler() raises:
    joblib = Python.import_module("joblib")
    np = Python.import_module("numpy")
    sklearn = Python.import_module("sklearn")

    d: Int = 8
    # dataset
    dataset = np.random.rand(100, d)  # 100 samples, 8 features

    # sklearn
    scaler_sklearn = sklearn.preprocessing.StandardScaler()
    scaler_sklearn.fit(dataset)

    # write
    scaler_tmp_path = "tmp_standard_scaler.joblib"
    joblib.dump(scaler_sklearn, scaler_tmp_path)

    # read with mojo
    scaler_mojo = StandardScaler(scaler_tmp_path)

    # test 10 times
    for _ in range(10):
        input_py = np.random.rand(d)
        input_mojo = List[Float64]()
        for j in range(d):
            input_mojo.append(Float64(py=input_py[j]))

        output_mojo = List[Float64](length=d, fill=0.0)
        scaler_mojo.inverse_transform_point(input_mojo, output_mojo)
        output_py = scaler_sklearn.inverse_transform(input_py.reshape(1, -1)).flatten()

        for j in range(d):
            assert_almost_equal(output_mojo[j], Float64(py=output_py[j]), "StandardScaler Mismatch at index " + String(j) + ": Mojo=" + String(output_mojo[j]) + " vs Py=" + String(output_py[j]))

def test_fold() raises:
    """Comprehensive test for the fold function with 8 different test cases."""
    comptime dtype = DType.float32
    
    # Test 1: Values within range stay unchanged
    var x1 = SIMD[dtype, 4](1.0, 2.0, 3.0, 4.0)
    var result1 = fold(x1, SIMD[dtype, 4](0.0), SIMD[dtype, 4](5.0))
    assert_almost_equal(result1, SIMD[dtype, 4](1.0, 2.0, 3.0, 4.0))
    
    # Test 2: Values above range fold back
    var x2 = SIMD[dtype, 4](12.0, 15.0, 20.0, 25.0)
    var result2 = fold(x2, SIMD[dtype, 4](0.0), SIMD[dtype, 4](10.0))
    assert_almost_equal(result2, SIMD[dtype, 4](8.0, 5.0, 0.0, 5.0))
    
    # Test 3: Values below range fold back
    var x3 = SIMD[dtype, 4](-2.0, -5.0, -10.0, -15.0)
    var result3 = fold(x3, SIMD[dtype, 4](0.0), SIMD[dtype, 4](10.0))
    assert_almost_equal(result3, SIMD[dtype, 4](2.0, 5.0, 10.0, 5.0))
    
    # Test 4: Values at exact boundaries
    var x4 = SIMD[dtype, 4](0.0, 10.0, 0.0, 10.0)
    var result4 = fold(x4, SIMD[dtype, 4](0.0), SIMD[dtype, 4](10.0))
    assert_almost_equal(result4, SIMD[dtype, 4](0.0, 10.0, 0.0, 10.0))
    
    # Test 5: Reversed bounds (lo > hi) handled correctly
    var x5 = SIMD[dtype, 4](1.0, 12.0, -2.0, 5.0)
    var result5 = fold(x5, SIMD[dtype, 4](10.0), SIMD[dtype, 4](0.0))
    assert_almost_equal(result5, SIMD[dtype, 4](1.0, 8.0, 2.0, 5.0))
    
    # Test 6: Negative range [-5, 5]
    var x6 = SIMD[dtype, 4](7.0, -7.0, 0.0, 12.0)
    var result6 = fold(x6, SIMD[dtype, 4](-5.0), SIMD[dtype, 4](5.0))
    assert_almost_equal(result6, SIMD[dtype, 4](3.0, -3.0, 0.0, -2.0))
    
    # Test 7: Small range [0, 1] with various values
    var x7 = SIMD[dtype, 4](0.5, 1.5, 2.3, -3.25)
    var result7 = fold(x7, SIMD[dtype, 4](0.0), SIMD[dtype, 4](1.0))
    assert_almost_equal(result7, SIMD[dtype, 4](0.5, 0.5, 0.3, 0.75))
    
    # Test 8: Non-zero based range [5, 15]
    var x8 = SIMD[dtype, 4](3.0, 17.0, 10.0, 25.0)
    var result8 = fold(x8, SIMD[dtype, 4](5.0), SIMD[dtype, 4](15.0))
    assert_almost_equal(result8, SIMD[dtype, 4](7.0, 13.0, 10.0, 5.0))    

def test_cpsmidi_midicps() raises:
    midi_notes = MFloat[4](60.0, 69.0, 72.0, 81.0)
    frequencies = midicps(midi_notes)
    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(midi_notes)):
        py_answer.append(py_to_float64(mmm_python.midicps(midi_notes[i])))
        assert_almost_equal(frequencies[i], py_answer[i], "Test: midicps mismatch at index " + String(i))
    recovered_midi = cpsmidi(frequencies)
    assert_almost_equal(midi_notes,recovered_midi,"Test: cpsmidi and midicps inversion failed")
    py_answer = List[Float64]()
    for i in range(len(py_answer)):
        py_answer.append(py_to_float64(mmm_python.cpsmidi(py_answer[i])))
        assert_almost_equal(midi_notes[i], py_answer[i], "Test: cpsmidi and midicps inversion failed")


def test_linlin() raises:
    x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    result = linlin(x, 0.0, 1.0, -1.0, 1.0)
    expected = MFloat[4](-1.0, 0.0, 1.0, 1.0)
    assert_almost_equal(result, expected, "Test: linlin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linlin(x[i], 0.0, 1.0, -1.0, 1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linlin mismatch at index " + String(i))

def test_linlin2() raises:
    x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    result = linlin(x, 0.0, 1.0, 1.0, -1.0)
    expected = MFloat[4](1.0, 0.0, -1.0, -1.0)
    assert_almost_equal(result, expected, "Test: linlin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linlin(x[i], 0.0, 1.0, 1.0, -1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linlin mismatch at index " + String(i))

def test_linmap() raises:
    x = MFloat[4](0.0, 0.25, 1.0, 1.5)
    result = MFloat[4](0.0, 0.0, 0.0, 0.0)
    for i in range(len(x)):
        result[i] = linmap(x[i], (0.0, 0.0), (0.2, 1.0), (1.0, 0.0))
    expected = MFloat[4](0.0, 0.9375, 0.0, 0.0)
    assert_almost_equal(result, expected, "Test: linmap function failed")

def test_env() raises:
    osc_buffers: Optional[UnsafePointer[mut=True, OscBuffers, MutExternalOrigin]] = alloc[OscBuffers](1)
    osc_buffers.value().init_pointee_move(OscBuffers())
    windows: Optional[UnsafePointer[mut=True, Windows, MutExternalOrigin]] = alloc[Windows](1)
    windows.value().init_pointee_move(Windows())

    world = alloc[MMMWorld](1) 
    world.init_pointee_move(MMMWorld(48000., 64, 0, 0, osc_buffers, windows))

    x = MFloat[4](0.1, 0.25, 0.45, 1.5)
    result = MFloat[4](0.0, 0.0, 0.0, 0.0)
    env_points = [(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)]
    for i in range(len(x)):
        result[i] = env[WindowType.hann, Interp.linear](world, x[i], env_points)
    expected = MFloat[4](0.5, 0.9375, 0.6875, 0.0)
    for i in range(len(x)):
        expected[i] = win_read[WindowType.hann, Interp.linear](world, expected[i]/2.0)
    
    # I am limiting the precision because I think the slight differences are less than significant
    assert_almost_equal(result, expected, "Test: env function failed", rtol=1e-3)


def test_linexp() raises:
    x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    result = linexp(x, 0.0, 1.0, 1.0, 10.0)
    expected = MFloat[4](1.0, 3.1622776601683795, 10.0, 10.0)
    assert_almost_equal(result, expected, "Test: linexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linexp(x[i], 0.0, 1.0, 1.0, 10.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linexp mismatch at index " + String(i))

def test_linexp2() raises:
    x = MFloat[4](2.0, 3.1622776601683795, 10.0, 15.0)
    result = linexp(x, 1.0, 10.0, 10.0, 0.001)
    expected = MFloat[4](3.5938136638046, 1.093925400505, 0.001, 0.001)

    assert_almost_equal(result, expected, "Test: linexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linexp(x[i], 1.0, 10.0, 10.0, 0.001)))
        assert_almost_equal(expected[i], py_answer[i], "Test: linexp mismatch at index " + String(i))
    result = linexp(x, 10.0, 1.0, 10.0, 0.001)
    assert_almost_equal(result, expected, "Test: linexp function failed")

    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linexp(x[i], 1.0, 10.0, 10.0, 0.001)))
        assert_almost_equal(result[i], py_answer[i], "Test: linexp mismatch at index " + String(i))


def test_lincurve() raises:
    x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    curve = [2.0, -2.0, 3.5, 0.5]
    expected = [
        MFloat[4](1.8406839040093, 3.42047279233, 10, 10),
        MFloat[4](4.89019954425, 7.57952720767, 10, 10),
        MFloat[4](1.3554075548362, 2.3324247822852, 10, 10), 
        MFloat[4](2.7219642975622, 4.9404114920278, 10, 10)
    ]
    for i in range(len(curve)):
        result = lincurve(x, 0.0, 1.0, 1.0, 10.0, curve[i])
        
        assert_almost_equal(result, expected[i], "Test: lincurve function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        mmm_python = Python.import_module("mmm_python.functions")
        py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.lincurve(x[i2], 0.0, 1.0, 1.0, 10.0, curve[i])))
        assert_almost_equal(result, py_answer, "Test: lincurve mismatch at index " + String(i))

def test_lincurve2() raises:
    x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    curve = [2.0, -2.0, 3.5, 0.5]
    expected = [
        MFloat[4](9.1593160959907, 7.57952720767, 1.0, 1.0),
        MFloat[4](6.10980045575, 3.42047279233, 1.0, 1.0),
        MFloat[4](9.6445924451638, 8.6675752177148, 1.0, 1.0), 
        MFloat[4](8.2780357024378, 6.0595885079722, 1.0, 1.0)
    ]
    for i in range(len(curve)):
        result = lincurve(x, 0.0, 1.0, 10.0, 1.0, curve[i])
        
        # this was commented out, but it seems like a good thing to test,
        # so I'm putting it back in. 
        assert_almost_equal(result, expected[i], "Test: lincurve function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        mmm_python = Python.import_module("mmm_python.functions")
        py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.lincurve(x[i2], 0.0, 1.0, 10.0, 1.0, curve[i])))
        assert_almost_equal(result, py_answer, "Test: lincurve mismatch at index " + String(i))



def test_curvelin() raises:
    x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    curve = [2.0, -2.0, 3.5, 0.5]
    expected = [
        MFloat[4](5.1143698508719, 7.4520137371736, 10, 10),
        MFloat[4](2.0172800628429, 3.5479862628264, 10, 10),
        MFloat[4](6.5075658522624, 8.2941226112612, 10, 10),
        MFloat[4](3.5438789977301, 6.0567364651629, 10, 10)
    ]
    for i in range(len(curve)):
        result = curvelin(x, 0.0, 1.0, 1.0, 10.0, curve[i])
        assert_almost_equal(result, expected[i], "Test: curvelin function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        mmm_python = Python.import_module("mmm_python.functions")
        py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.curvelin(x[i2], 0.0, 1.0, 1.0, 10.0, curve[i])))
        assert_almost_equal(result, py_answer, "Test: curvelin mismatch at index " + String(i)) 

def test_curvelin2() raises:
    x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    curve = [2.0, -2.0, 3.5, 0.5]
    expected = [
        MFloat[4](5.8856301491281, 3.5479862628264, 1.0, 1.0),
        MFloat[4](8.9827199371571, 7.4520137371736, 1.0, 1.0),
        MFloat[4](4.4924341477376, 2.7058773887388, 1.0, 1.0),
        MFloat[4](7.4561210022699, 4.9432635348371, 1.0, 1.0)
    ]

    for i in range(len(curve)):
        result = curvelin(x, 0.0, 1.0, 10.0, 1.0, curve[i])
        assert_almost_equal(result, expected[i], "Test: curvelin function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        mmm_python = Python.import_module("mmm_python.functions")
        py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.curvelin(x[i2], 0.0, 1.0, 10.0, 1.0, curve[i])))
            assert_almost_equal(expected[i][i2], py_answer[i2], "Test: curvelin mismatch at index " + String(i)) 

def test_explin() raises:
    x = MFloat[4](1.0, 3.1622776601683795, 10.0, 15.0)
    result = explin(x, 1.0, 10.0, 0.0, 1.0)
    expected = MFloat[4](0.0, 0.5, 1.0, 1.0)
    assert_almost_equal(result, expected, "Test: explin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.explin(x[i], 1.0, 10.0, 0.0, 1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: explin mismatch at index " + String(i))

def test_explin2() raises:
    x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    expected = MFloat[4](2.8923524277696, 1.9030899869919, 1.0, 1.0)

    result = explin(x, 0.001, 1.0, 10.0, 1.0)
    assert_almost_equal(result, expected, "Test: explin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = SIMD[DType.float64, 4]()
    for i2 in range(len(x)):
        py_answer[i2]=(py_to_float64(mmm_python.explin(x[i2], 0.001, 1.0, 10.0, 1.0)))
    assert_almost_equal(expected, py_answer, "Test: explin mismatch at index ") 

def test_expexp() raises:
    x = MFloat[4](1.0, 3.1622776601683795, 10.0, 15.0)
    result = expexp(x, 1.0, 10.0, 1.0, 10.0)
    expected = MFloat[4](1.0, 3.1622776601683795, 10.0, 10.0)
    assert_almost_equal(result, expected, "Test: expexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.expexp(x[i], 1.0, 10.0, 1.0, 10.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: expexp mismatch at index " + String(i))

def test_expexp2() raises:
    x = MFloat[4](2.0, 3.1622776601683795, 10.0, 15.0)
    result = expexp(x, 1.0, 10.0, 10.0, 0.001)
    expected = MFloat[4](0.625, 0.1, 0.001, 0.001)
    assert_almost_equal(result, expected, "Test: expexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    mmm_python = Python.import_module("mmm_python.functions")
    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.expexp(x[i], 1.0, 10.0, 10.0, 0.001)))
        assert_almost_equal(result[i], py_answer[i], "Test: expexp mismatch at index " + String(i))
    result = expexp(x, 10.0, 1.0, 10.0, 0.001)
    expected = MFloat[4](0.625, 0.1, 0.001, 0.001)
    assert_almost_equal(result, expected, "Test: expexp function failed")

    py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.expexp(x[i], 1.0, 10.0, 10.0, 0.001)))
        assert_almost_equal(result[i], py_answer[i], "Test: expexp mismatch at index " + String(i))
        
def test_select_files() raises:
    files = select_files("mmm_audio", [".mojo"])
    expected_files = ["mmm_audio/Delays.mojo", "mmm_audio/FFTs.mojo"]
    for expected in expected_files:
        assert_true(expected in files, "Test: select_files missing expected file " + expected)

    files2 = select_files("resources", [".wav"])
    expected_files2 = ["resources/Growl 15.wav","resources/Shiverer.wav","resources/small_wavetable.wav","resources/small_wavetable8.wav"]
    for expected in expected_files2:
        assert_true(expected in files2, "Test: select_files missing expected file " + expected)

def test_top_n_indices() raises:
    tpi = TopNPeaks()
    n: Int = 3

    arr: List[Float64] = [0.1, 0.5, 0.3, 0.9, 0.2, 0.8, 0.7]
    output: List[Int] = List[Int](length=n, fill=0)
    n_valid = tpi.process(arr, n, output, 0.01)
    expected: List[Int] = [3, 5, 1]
    assert_equal(n_valid, 3, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    arr2: List[Float64] = [0.99, 0.5, 0.3, 0.9, 0.2, 0.8, 0.7]
    n_valid = tpi.process(arr2, n, output, 0.01)
    expected: List[Int] = [3, 5]
    assert_equal(n_valid, 2, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    arr3: List[Float64] = [0.1, 0.5, 0.3, 0.9, 0.2, 0.8, 0.99]
    n_valid = tpi.process(arr3, n, output, 0.01)
    expected: List[Int] = [3, 1]
    assert_equal(n_valid, 2, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    arr4: List[Float64] = [0.6, 0.1, 0.1, 0.2, 0.1, 0.7, 0.1]
    n_valid = tpi.process(arr4, n, output, 0.3)
    expected: List[Int] = [5]
    assert_equal(n_valid, 1, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()