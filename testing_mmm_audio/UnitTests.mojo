from mmm_audio import *
from std.testing import assert_equal, assert_almost_equal, assert_true, assert_false
from std.testing import TestSuite
from std.math import inf, nan
from std.pathlib import Path
from std.random import random_float64, random_ui64
from std.memory.alloc import unsafe_alloc

def test_Changed() raises:
    # Test with Bool
    var changed_bool = Changed(False)
    assert_equal(changed_bool.next(False), False, "Changed failed for Bool: No change should return False")
    assert_equal(changed_bool.next(True), True, "Changed failed for Bool: Change should return True")
    assert_equal(changed_bool.next(True), False, "Changed failed for Bool: No change should return False")

    var changed_bools = Changed(MBool[4](False, False, False, False))
    assert_equal(changed_bools.next(MBool[4](False, False, False, False)), False, "Changed failed for Bool: No change should return False")
    assert_equal(changed_bools.next(MBool[4](True, False, True, True)), True, "Changed failed for Bool: Change should return True")
    assert_equal(changed_bools.next(MBool[4](True, True, True, True)), True, "Changed failed for Bool: No change should return False")
    
    # Test with Int
    var changed_int = Changed(0)
    assert_equal(changed_int.next(0), False, "Changed failed for Int: No change should return False")
    assert_equal(changed_int.next(1), True, "Changed failed for Int: Change should return True")
    assert_equal(changed_int.next(1), False, "Changed failed for Int: No change should return False")

    var changed_ints = Changed(MInt[4](0, 0, 0, 0))
    assert_equal(changed_ints.next(MInt[4](0, 0, 0, 0)), False, "Changed failed for Int: No change should return False")
    assert_equal(changed_ints.next(MInt[4](1, 0, 1, 1)), True, "Changed failed for Int: Change should return True")
    assert_equal(changed_ints.next(MInt[4](1, 1, 1, 1)), True, "Changed failed for Int: No change should return False")
    
    # Test with Float64
    var changed_float = Changed(0.0)
    assert_equal(changed_float.next(0.0), False, "Changed failed for Float64: No change should return False")
    assert_equal(changed_float.next(1.0), True, "Changed failed for Float64: Change should return True")
    assert_equal(changed_float.next(1.0), False, "Changed failed for Float64: No change should return False")

    var changed_floats = Changed(MFloat[4](0.0, 0.0, 0.0, 0.0))
    assert_equal(changed_floats.next(MFloat[4](0.0, 0.0, 0.0, 0.0)), False, "Changed failed for Float64: No change should return False")
    assert_equal(changed_floats.next(MFloat[4](1.0, 0.0, 1.0, 1.0)), True, "Changed failed for Float64: Change should return True")
    assert_equal(changed_floats.next(MFloat[4](1.0, 1.0, 1.0, 1.0)), True, "Changed failed for Float64: No change should return False")

def test_ChangedSIMD() raises:
    var changed_bool = ChangedSIMD(MBool[4](False, False, False, False))
    assert_equal(changed_bool.next(MBool[4](False, False, False, False)), MBool[4](False, False, False, False), "Changed failed for Bool: No change should return False")
    assert_equal(changed_bool.next(MBool[4](True, False, True, True)), MBool[4](True, False, True, True), "Changed failed for Bool: Change should return True")
    assert_equal(changed_bool.next(MBool[4](True, True, True, True)), MBool[4](False, True, False, False), "Changed failed for Bool: No change should return False")
    
    # Test with Int
    var changed_int = ChangedSIMD(MInt[4](0, 0, 0, 0))
    assert_equal(changed_int.next(MInt[4](0, 0, 0, 0)), MBool[4](False, False, False, False), "Changed failed for Int: No change should return False")
    assert_equal(changed_int.next(MInt[4](1, 0, 1, 1)), MBool[4](True, False, True, True), "Changed failed for Int: Change should return True")
    assert_equal(changed_int.next(MInt[4](1, 1, 1, 1)), MBool[4](False, True, False, False), "Changed failed for Int: No change should return False")

    # Test with Float64
    var changed_float = ChangedSIMD(MFloat[4](0.0, 0.0, 0.0, 0.0))
    assert_equal(changed_float.next(MFloat[4](0.0, 0.0, 0.0, 0.0)), MBool[4](False, False, False, False), "Changed failed for Float64: No change should return False")
    assert_equal(changed_float.next(MFloat[4](1.0, 0.0, 1.0, 1.0)), MBool[4](True, False, True, True), "Changed failed for Float64: Change should return True")
    assert_equal(changed_float.next(MFloat[4](1.0, 1.0, 1.0, 1.0)), MBool[4](False, True, False, False), "Changed failed for Float64: No change should return False")

def test_sound_file_reader() raises:
    try:
        # Quick one-liner to read audio
        var file = "resources/Shiverer.wav"
        var scipy = Python.import_module("scipy")
        var np = Python.import_module("numpy")
        var result = scipy.io.wavfile.read(file)
        var sample_rate = result[0]
        var data = result[1]
        if data.dtype == np.int16 or data.dtype == np.int32 or data.dtype == np.uint8:
            data = data.astype(np.float64)/np.iinfo(result[1].dtype).max
        else:
            data = data.astype(np.float64)

        var header = read_wav_header(file)
        var wav = read_wav_SIMDs[2](file, header)
        try:
            for i in range(header.num_samples):
                assert_almost_equal(wav[i][0], py_to_float64(data[i][0]), String(i))
                assert_almost_equal(wav[i][1], py_to_float64(data[i][1]), String(i))
        except err:
            assert_true(False, String(err))
    except err:
        assert_true(False, "Error reading WAV file: " + String(err))

def test_linear_interp() raises:
    var a = MFloat[4](0.0, 10.0, 20.0, 30.0)
    var b = MFloat[4](10.0, 20.0, 30.0, 40.0)
    var t = MFloat[4](0.0, 0.5, 1.0, 0.25)
    var result = linear_interp(a, b, t)
    var expected = MFloat[4](0.0, 15.0, 30.0, 32.5)
    assert_almost_equal(result, expected, "Test: lerp function failed")

def test_sanitize() raises:
    var nan = nan[DType.float64]()
    var pos_inf = inf[DType.float64]()
    var neg_inf = -inf[DType.float64]()
    var values = MFloat[4](1.0, nan, pos_inf, neg_inf)
    var sanitized = sanitize(values)
    var expected = MFloat[4](1.0, 0.0, 0.0, 0.0)
    assert_almost_equal(sanitized, expected, "Test: sanitize function failed: ")

def test_mel_to_hz() raises:
    """Compare mel_to_hz against librosa's implementation."""
    var librosa_results = MFloat[8](345123.07093968056, 334060977.5717811, 323353453109.8285, 312989132696839.3, 3.029570157490985e+17, 2.932464542802523e+20, 2.8384714159964454e+23, 2.747491013729005e+26)
    var mels = MFloat[8](100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0)
    var mmm_results = MFloat[8]()
    for i in range(8):
        mmm_results[i] = MelBands.mel_to_hz(mels[i])
    assert_almost_equal(mmm_results, librosa_results, "Test: mel_to_hz function failed")

def test_hz_to_mel() raises:
    """Compare hz_to_mel against librosa's implementation."""
    var librosa_results = MFloat[8](100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0)
    var hz_values = MFloat[8](345123.07093968056, 334060977.5717811, 323353453109.8285, 312989132696839.3, 3.029570157490985e+17, 2.932464542802523e+20, 2.8384714159964454e+23, 2.747491013729005e+26)
    var mmm_results = MFloat[8]()
    for i in range(8):
        mmm_results[i] = MelBands.hz_to_mel(hz_values[i])
    assert_almost_equal(mmm_results, librosa_results, "Test: hz_to_mel function failed")

def test_diff() raises:
    var arr = List[Float64]([1.0, 2.5, 4.0, 7.0, 10.0])
    var expected = List[Float64]([1.5, 1.5, 3.0, 3.0])
    var result = diff(arr)

    var result_simd = MFloat[4](result[0], result[1], result[2], result[3])
    var expected_simd = MFloat[4](expected[0], expected[1], expected[2], expected[3])
    assert_almost_equal(result_simd, expected_simd, "Test: diff function failed")

def linspace_test(endpoint: Bool, num: Int) raises:
    var start = random_float64() * 100.0
    var stop = random_float64() * 100.0
    var result_mojo = linspace(start, stop, num, endpoint)

    # Compare against Python implementation
    try:
        var np = Python.import_module("numpy")
        var result_np = np.linspace(start, stop, num, endpoint=endpoint).tolist()
    
        var expected = List[Float64](length=num, fill=0.0)
        for i in range(num):
            expected[i] = Float64(py=result_np[i])
    
        compare_long_lists(result_mojo,expected)
    except err:
        assert_true(False, "Error comparing linspace results with numpy: " + String(err))

def test_linspace() raises:

    for _ in range(10):  # Run multiple times with random inputs
        var num = Int(random_ui64(2, 100))  # Ensure at least 2 points to avoid edge case
        linspace_test(True, num)
        linspace_test(False, num)

    for _ in range(10):  # Run multiple times with random inputs
        linspace_test(True, 1)
        linspace_test(False, 1)

def test_mel_frequencies() raises:
    var num_mel_bins = 32
    var fmin = 20.0
    var fmax = 20000.0
    var result = MelBands.mel_frequencies(num_mel_bins, fmin, fmax)
    var result_simd = MFloat[32]()
    for i in range(32):
        result_simd[i] = result[i]
    var expected = MFloat[32](20.0, 145.31862602399627, 270.63725204799255, 395.95587807198876, 521.274504095985, 646.5931301199813, 771.9117561439776, 897.2303821679739, 1023.526754399107, 1164.733656827089, 1325.421622361244, 1508.2782803824396, 1716.3620486443097, 1953.15328765427, 2222.6125123704865, 2529.2466348500357, 2878.184345807327, 3275.2618958971248, 3727.120711479871, 4241.318477567799, 4826.455545899264, 5492.318782413196, 6250.04526008295, 7112.308534997669, 8093.530621301341, 9210.123210432963, 10480.762169244366, 11926.699908187227, 13572.120844166513, 15444.545903449043, 17575.292830248403, 19999.999999999996)
    assert_almost_equal(result_simd, expected, "Test: mel_frequencies function failed")

def test_fft_frequencies() raises:
    var sample_rate = 44100.0
    var n_fft = 512
    var result = RealFFT.fft_frequencies(sample_rate, n_fft)
    var result_simd = MFloat[8]()
    for i in range(8):
        result_simd[i] = result[i]
    var expected = MFloat[8](0.0, 86.1328125, 172.265625, 258.3984375, 344.53125, 430.6640625, 516.796875, 602.9296875)
    assert_almost_equal(result_simd, expected, "Test: fft_frequencies function failed")

    # The bins are generated a vector at a time with a scalar tail, so check the whole
    # ramp and not just its head -- the tail is where a partial final vector lands.
    var binHz = sample_rate / Float64(n_fft)
    assert_equal(len(result), n_fft // 2 + 1, "Test: fft_frequencies returned the wrong count")
    for i in range(len(result)):
        assert_almost_equal(result[i], Float64(i) * binHz,
            "Test: fft_frequencies wrong at bin " + String(i), atol=1e-9)
    assert_almost_equal(result[len(result) - 1], sample_rate / 2.0,
        "Test: fft_frequencies last bin is not Nyquist", atol=1e-9)

    # Counts that are not a whole number of vectors, and a nonzero starting bin
    for min_bin in [0, 1, 7]:
        for num_bins in [1, 3, 5, 17, 33]:
            var partial = RealFFT.fft_frequencies(sample_rate, n_fft, min_bin, num_bins)
            assert_equal(len(partial), num_bins,
                "Test: fft_frequencies returned the wrong count for a partial range")
            for i in range(num_bins):
                assert_almost_equal(partial[i], Float64(min_bin + i) * binHz,
                    "Test: fft_frequencies wrong at bin " + String(i)
                    + " of a partial range starting at " + String(min_bin), atol=1e-9)

def test_fft_against_numpy() raises:
    """Check the forward and inverse transforms against numpy.fft.rfft / irfft.

    A round trip alone is a weak check here, because the forward and inverse passes share
    the twiddle tables and some corruptions cancel out between them. Comparing the spectrum
    itself against numpy pins the forward transform independently.
    """
    comptime tol = 1e-9

    try:
        var np = Python.import_module("numpy")
        var builtins = Python.import_module("builtins")

        for size in [16, 64, 256, 1024]:
            var num_bins = size // 2 + 1
            var fft = RealFFT[1](size)
            var signal = List[Float64](length=size, fill=0.0)
            var output = List[Float64](length=size, fill=0.0)

            # A couple of partials plus noise, so every bin carries something
            for i in range(size):
                var t = Float64(i) / Float64(size)
                signal[i] = (
                    sin(2.0 * pi * 3.0 * t)
                    + 0.5 * cos(2.0 * pi * 5.0 * t)
                    + 0.25 * random_float64(-1.0, 1.0)
                )

            var py_signal = builtins.list()
            for i in range(size):
                py_signal.append(signal[i])
            var spectrum = np.fft.rfft(np.array(py_signal))
            var expected_mags = np.abs(spectrum).tolist()
            var expected_phases = np.angle(spectrum).tolist()

            fft.fft(signal)

            for k in range(num_bins):
                var want_mag = Float64(py=expected_mags[k])
                assert_almost_equal(fft.mags[k], want_mag,
                    "Test: fft magnitude disagrees with numpy at size " + String(size)
                    + " bin " + String(k), atol=tol)

                # Phase is meaningless where there is no magnitude to carry it
                if want_mag > 1e-6:
                    var want_phase = Float64(py=expected_phases[k])
                    var diff = abs(fft.phases[k] - want_phase)
                    if diff > pi:
                        diff = 2.0 * pi - diff   # the wrap at +-pi is not a disagreement
                    assert_true(diff < tol,
                        "Test: fft phase disagrees with numpy at size " + String(size)
                        + " bin " + String(k) + " by " + String(diff))

            # And the inverse against numpy.fft.irfft, driven from the same spectrum
            var recovered = np.fft.irfft(spectrum, n=size).tolist()
            fft.ifft(output)
            for i in range(size):
                assert_almost_equal(output[i], Float64(py=recovered[i]),
                    "Test: ifft disagrees with numpy at size " + String(size)
                    + " sample " + String(i), atol=tol)

        # Stereo: the lanes must stay independent, each matching its own numpy transform
        comptime N = 256
        var fft2 = RealFFT[2](N)
        var stereo = List[MFloat[2]](length=N, fill=MFloat[2](0.0))
        var left = builtins.list()
        var right = builtins.list()
        for i in range(N):
            var t = Float64(i) / Float64(N)
            var l = sin(2.0 * pi * 3.0 * t) + 0.25 * random_float64(-1.0, 1.0)
            var r = cos(2.0 * pi * 11.0 * t) + 0.25 * random_float64(-1.0, 1.0)
            stereo[i] = MFloat[2](l, r)
            left.append(l)
            right.append(r)

        var left_mags = np.abs(np.fft.rfft(np.array(left))).tolist()
        var right_mags = np.abs(np.fft.rfft(np.array(right))).tolist()

        fft2.fft(stereo)
        for k in range(N // 2 + 1):
            assert_almost_equal(fft2.mags[k][0], Float64(py=left_mags[k]),
                "Test: stereo fft left channel disagrees with numpy at bin " + String(k),
                atol=tol)
            assert_almost_equal(fft2.mags[k][1], Float64(py=right_mags[k]),
                "Test: stereo fft right channel disagrees with numpy at bin " + String(k),
                atol=tol)

        var stereo_out = List[MFloat[2]](length=N, fill=MFloat[2](0.0))
        fft2.ifft(stereo_out)
        for i in range(N):
            assert_almost_equal(stereo_out[i], stereo[i],
                "Test: stereo fft round trip did not reconstruct sample " + String(i),
                atol=tol)

    except err:
        assert_true(False, "Error comparing FFT results with numpy: " + String(err))

def test_adsr_env() raises:
    """ADSREnv has to hit each breakpoint at the right time and level.

    ASREnv has no decay stage, so this checks the thing that distinguishes them: the fall
    from full down to the sustain level while the gate is still open.
    """
    var e = unsafe_alloc[Environment](1)
    e.unsafe_write(Environment())
    var world = unsafe_alloc[MMMWorld](1)
    world.unsafe_write(MMMWorld(48000.0, e))

    comptime tol = 1e-6
    var env = ADSREnv(world)

    def advance(mut env: ADSREnv, samples: Int, gate: Bool) capturing -> Float64:
        var v = 0.0
        for _ in range(samples):
            v = env.next(0.1, 0.2, 0.5, 0.4, gate)
        return v

    # attack: 0.1s from 0 to 1, so halfway up at 0.05s
    assert_almost_equal(advance(env, 2400, True), 0.5,
        "Test: ADSREnv attack is not halfway at half the attack time", atol=tol)
    assert_almost_equal(advance(env, 2400, True), 1.0,
        "Test: ADSREnv did not reach full at the end of the attack", atol=tol)

    # decay: 0.2s from 1 down to the sustain level of 0.5
    assert_almost_equal(advance(env, 4800, True), 0.75,
        "Test: ADSREnv decay is not halfway at half the decay time", atol=tol)
    assert_almost_equal(advance(env, 4800, True), 0.5,
        "Test: ADSREnv did not settle at the sustain level", atol=tol)

    # sustain holds for as long as the gate is open
    assert_almost_equal(advance(env, 48000, True), 0.5,
        "Test: ADSREnv did not hold at the sustain level", atol=tol)
    assert_true(env.is_active, "Test: ADSREnv should be active while gated")

    # release: 0.4s from the sustain level to zero
    assert_almost_equal(advance(env, 9600, False), 0.25,
        "Test: ADSREnv release is not halfway at half the release time", atol=tol)
    _ = advance(env, 9605, False)
    assert_almost_equal(env.value, 0.0,
        "Test: ADSREnv did not reach zero at the end of the release", atol=tol)
    assert_false(env.is_active, "Test: ADSREnv should go inactive once released")

    # curve shapes the segment as phase to the power of the curve, endpoints unmoved
    var shaped = ADSREnv(world)
    def advance_curved(mut env: ADSREnv, samples: Int, curve: Float64) capturing -> Float64:
        var v = 0.0
        for _ in range(samples):
            v = env.next(0.1, 0.2, 0.5, 0.4, True, MFloat[2](curve, curve))
        return v
    assert_almost_equal(advance_curved(shaped, 1200, 2.0), 0.0625,
        "Test: ADSREnv curve did not shape the attack", atol=tol)
    assert_almost_equal(advance_curved(shaped, 3600, 2.0), 1.0,
        "Test: ADSREnv curve moved the end of the attack", atol=tol)

    # retriggering part way through a release resumes from the current value
    var again = ADSREnv(world)
    _ = advance(again, 48000, True)
    var released = advance(again, 4800, False)
    var retriggered = again.next(0.1, 0.2, 0.5, 0.4, True)
    assert_true(abs(retriggered - released) < 0.01,
        "Test: ADSREnv jumped on retrigger instead of resuming from its current value")

    # zero length segments must arrive immediately rather than divide by zero
    var instant = ADSREnv(world)
    var v = 0.0
    for _ in range(4):
        v = instant.next(0.0, 0.0, 0.3, 0.0, True)
    assert_almost_equal(v, 0.3,
        "Test: ADSREnv with zero attack and decay did not land on the sustain level", atol=tol)

    # reset clears a recycled voice
    instant.reset()
    assert_almost_equal(instant.value, 0.0, "Test: ADSREnv reset did not clear the value", atol=tol)
    assert_false(instant.is_active, "Test: ADSREnv reset did not clear is_active")

def test_dct()  raises:
    var dct = DCT(4,3)
    var input_vals = List[Float64]([1.0, 2.0, 3.0, 4.0])
    var output_vals = List[Float64](length=3, fill=0.0)
    dct.process(input_vals, output_vals)

    var expected = List[Float64]([5.0, -2.230442497387663, -6.280369834735101e-16])
    for i in range(len(output_vals)):
        assert_almost_equal(output_vals[i], expected[i], "Test: DCT coefficient mismatch")

def test_mfcc_paths_consistency() raises:
    """Ensure MFCC outputs match across next_frame, from_mags, and from_mel_bands."""
    comptime fft_size: Int = 64
    comptime num_bands: Int = 8
    comptime num_coeffs: Int = 4

    var w = unsafe_alloc[MMMWorld](1) 
    w.unsafe_write(MMMWorld(48000.0))

    var mags = List[Float64](length=(fft_size // 2) + 1, fill=0.0)
    var phases = List[Float64](length=(fft_size // 2) + 1, fill=0.0)

    for i in range(len(mags)):
        mags[i] = 0.001 + 0.001 * Float64(i)

    var mel = MelBands(w[].sample_rate, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    mel.from_mags(mags)

    var mfcc_next = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    var mfcc_mags = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)
    var mfcc_bands = MFCC(w[].sample_rate, num_coeffs=num_coeffs, num_bands=num_bands, min_freq=20.0, max_freq=20000.0, fft_size=fft_size)

    mfcc_next.next_frame(mags, phases)
    mfcc_mags.from_mags(mags)
    mfcc_bands.from_mel_bands(mel.bands)

    for i in range(num_coeffs):
        assert_almost_equal(mfcc_next.coeffs[i], mfcc_mags.coeffs[i], "Test: MFCC next_frame vs from_mags mismatch")
        assert_almost_equal(mfcc_next.coeffs[i], mfcc_bands.coeffs[i], "Test: MFCC next_frame vs from_mel_bands mismatch")

def test_mel_bands_weights() raises:
    
    var n_mels: Int = 40
    var n_fft: Int = 512
    var sr: Int = 44100

    
    var w = unsafe_alloc[MMMWorld](1) 
    w.unsafe_write(MMMWorld(MFloat[1](sr)))
    var melbands = MelBands(w[].sample_rate, num_bands=n_mels,min_freq=20.0,max_freq=20000.0,fft_size=n_fft)

    var weights_flat = List[Float64]()

    for i in range(len(melbands.weights)):
        for j in range(len(melbands.weights[i])):
            weights_flat.append(Float64(melbands.weights[i][j]))

    try:
        var librosa = Python.import_module("librosa")
        var mel_weights = librosa.filters.mel(sr=sr, n_fft=n_fft, n_mels=n_mels, htk=False,fmin=20.0,fmax=20000.0)
        mel_weights = mel_weights.tolist()

        var expected_flat = List[Float64]()
        for i in range(len(mel_weights)):
            for j in range(len(mel_weights[i])):
                expected_flat.append(Float64(py=mel_weights[i][j]))

        compare_long_lists(weights_flat, expected_flat)
    except err:
        assert_true(False, "Error comparing Mel filter weights with librosa")

def test_chroma_weights() raises:
    var n_chroma: Int = 12
    var n_fft: Int = 512
    var sr: Int = 44100

    var chroma = Chroma(Float64(sr), n_fft, n_chroma=n_chroma)
    var weights_flat = List[Float64]()

    for i in range(len(chroma.weights)):
        for j in range(len(chroma.weights[i])):
            weights_flat.append(chroma.weights[i][j])

    try:
        var librosa = Python.import_module("librosa")
        var chroma_weights = librosa.filters.chroma(sr=sr, n_fft=n_fft, n_chroma=n_chroma, tuning=0.0)
        chroma_weights = chroma_weights.tolist()

        var expected_flat = List[Float64]()
        for i in range(len(chroma_weights)):
            for j in range(len(chroma_weights[i])):
                expected_flat.append(Float64(py=chroma_weights[i][j]))

        compare_long_lists(weights_flat, expected_flat)
    except err:
        assert_true(False, "Error comparing Chroma filter weights with librosa")

def compare_long_lists[chunk_size: Int = 64](a: List[Float64], b: List[Float64], verbose: Bool = False) raises:
    assert_equal(len(a), len(b), "Lists are of different lengths")
    var a_simd = SIMD[DType.float64,chunk_size]()
    var b_simd = SIMD[DType.float64,chunk_size]()

    var i: Int = 0
    while i < len(a):
        a_simd[i % chunk_size] = a[i]
        b_simd[i % chunk_size] = b[i]
        if i > 0 and i % chunk_size == 0:
            if verbose:
                print("Comparing chunk ending at index ", i)
            assert_almost_equal(a_simd,b_simd)
        i += 1

def pca_test(whiten: Bool) raises:

    Python.add_to_path(".")
    var data_python = Python.import_module("mmm_python.ML.Data_Python")
    var np = Python.import_module("numpy")

    # dataset
    var dataset = np.random.rand(100, 8)  # 100 samples, 8 features
    
    # sklearn
    var pca_sklearn = Python.import_module("sklearn").decomposition.PCA
    var pca_py = pca_sklearn(whiten=whiten)
    pca_py.fit(dataset)

    # write
    var pca_py_tmp_path = "tmp_pca.safetensors"
    data_python.save_pca(pca_py, pca_py_tmp_path)

    # read with mojo
    var pca_mojo = PCA(pca_py_tmp_path)

    # test 10 transforms
    for _ in range(10):
        var input_py = np.random.rand(8)
        var input_mojo = List[Float64]()
        for j in range(8):
            input_mojo.append(Float64(py=input_py[j]))
        
        var output_mojo = List[Float64](length=pca_mojo.k, fill=0.0)
        pca_mojo.transform_point(input_mojo, output_mojo)
        var output_py = pca_py.transform(input_py.reshape(1, -1)).flatten()
        for j in range(pca_mojo.k):
            assert_almost_equal(output_mojo[j], Float64(py=output_py[j]), "PCA Mismatch at index " + String(j) + ": Mojo=" + String(output_mojo[j]) + " vs Py=" + String(output_py[j]) + " (whiten=" + String(whiten) + ")")

    # test 10 inverse transforms
    for _ in range(10):
        var input_py = np.random.rand(pca_mojo.k)
        var input_mojo = List[Float64]()
        for j in range(pca_mojo.k):
            input_mojo.append(Float64(py=input_py[j]))

        var output_mojo = List[Float64](length=pca_mojo.d, fill=0.0)
        pca_mojo.inverse_transform_point(input_mojo, output_mojo)
        var output_py = pca_py.inverse_transform(input_py.reshape(1, -1)).flatten()

        for j in range(pca_mojo.d):
            assert_almost_equal(output_mojo[j], Float64(py=output_py[j]), "PCA Mismatch at index " + String(j) + ": Mojo=" + String(output_mojo[j]) + " vs Py=" + String(output_py[j]) + " (whiten=" + String(whiten) + ")")

def test_pca() raises:
    pca_test(whiten=False)
    pca_test(whiten=True)
    
def test_standard_scaler() raises:
    Python.add_to_path(".")
    var data_python = Python.import_module("mmm_python.ML.Data_Python")
    var np = Python.import_module("numpy")
    var sklearn = Python.import_module("sklearn")

    var d: Int = 8
    # dataset
    var dataset = np.random.rand(100, d)  # 100 samples, 8 features

    # sklearn
    var scaler_sklearn = sklearn.preprocessing.StandardScaler()
    scaler_sklearn.fit(dataset)

    # write
    var scaler_tmp_path = "tmp_standard_scaler.safetensors"
    data_python.save_standard_scaler(scaler_sklearn, scaler_tmp_path)

    # read with mojo
    var scaler_mojo = StandardScaler(scaler_tmp_path)

    # test 10 times
    for _ in range(10):
        var input_py = np.random.rand(d)
        var input_mojo = List[Float64]()
        for j in range(d):
            input_mojo.append(Float64(py=input_py[j]))

        var output_mojo = List[Float64](length=d, fill=0.0)
        scaler_mojo.inverse_transform_point(input_mojo, output_mojo)
        var output_py = scaler_sklearn.inverse_transform(input_py.reshape(1, -1)).flatten()

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
    var midi_notes = MFloat[4](60.0, 69.0, 72.0, 81.0)
    var frequencies = midicps(midi_notes)
    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(midi_notes)):
        py_answer.append(py_to_float64(mmm_python.midicps(midi_notes[i])))
        assert_almost_equal(frequencies[i], py_answer[i], "Test: midicps mismatch at index " + String(i))
    var recovered_midi = cpsmidi(frequencies)
    assert_almost_equal(midi_notes,recovered_midi,"Test: cpsmidi and midicps inversion failed")
    py_answer = List[Float64]()
    for i in range(len(py_answer)):
        py_answer.append(py_to_float64(mmm_python.cpsmidi(py_answer[i])))
        assert_almost_equal(midi_notes[i], py_answer[i], "Test: cpsmidi and midicps inversion failed")


def test_linlin() raises:
    var x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    var result = linlin(x, 0.0, 1.0, -1.0, 1.0)
    var expected = MFloat[4](-1.0, 0.0, 1.0, 1.0)
    assert_almost_equal(result, expected, "Test: linlin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linlin(x[i], 0.0, 1.0, -1.0, 1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linlin mismatch at index " + String(i))

def test_linlin2() raises:
    var x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    var result = linlin(x, 0.0, 1.0, 1.0, -1.0)
    var expected = MFloat[4](1.0, 0.0, -1.0, -1.0)
    assert_almost_equal(result, expected, "Test: linlin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linlin(x[i], 0.0, 1.0, 1.0, -1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linlin mismatch at index " + String(i))

def test_linmap() raises:
    var x = MFloat[4](0.0, 0.25, 1.0, 1.5)
    var result = MFloat[4](0.0, 0.0, 0.0, 0.0)
    for i in range(len(x)):
        result[i] = linmap(x[i], (0.0, 0.0), (0.2, 1.0), (1.0, 0.0))
    var expected = MFloat[4](0.0, 0.9375, 0.0, 0.0)
    assert_almost_equal(result, expected, "Test: linmap function failed")

def test_env() raises:

    var e = unsafe_alloc[Environment](1)
    e.unsafe_write(Environment())

    var world = unsafe_alloc[MMMWorld](1) 
    world.unsafe_write(MMMWorld(48000.,e))

    var x = MFloat[4](0.1, 0.25, 0.45, 1.5)
    var result = MFloat[4](0.0, 0.0, 0.0, 0.0)
    var env_points = [(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)]
    for i in range(len(x)):
        result[i] = env[WindowType.hann, Interp.linear](world, x[i], env_points)
    var expected = MFloat[4](0.5, 0.9375, 0.6875, 0.0)
    for i in range(len(x)):
        expected[i] = win_read[WindowType.hann, Interp.linear](world, expected[i]/2.0)
    
    # I am limiting the precision because I think the slight differences are less than significant
    assert_almost_equal(result, expected, "Test: env function failed", rtol=1e-3)


def test_linexp() raises:
    var x = MFloat[4](0.0, 0.5, 1.0, 1.5)
    var result = linexp(x, 0.0, 1.0, 1.0, 10.0)
    var expected = MFloat[4](1.0, 3.1622776601683795, 10.0, 10.0)
    assert_almost_equal(result, expected, "Test: linexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.linexp(x[i], 0.0, 1.0, 1.0, 10.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: linexp mismatch at index " + String(i))

def test_linexp2() raises:
    var x = MFloat[4](2.0, 3.1622776601683795, 10.0, 15.0)
    var result = linexp(x, 1.0, 10.0, 10.0, 0.001)
    var expected = MFloat[4](3.5938136638046, 1.093925400505, 0.001, 0.001)

    assert_almost_equal(result, expected, "Test: linexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
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
    var x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    var curve = [2.0, 0.5, 3.5, 0.25]
    var expected = [
        MFloat[4](1.492804, 3.25, 10, 10),
        MFloat[4](5.353619184, 7.363961031, 10, 10),
        MFloat[4](1.0557825046580311, 1.7954951288341925, 10, 10), 
        MFloat[4](7.259598442129002, 8.56806773728343, 10, 10)
    ]
    for i in range(len(curve)):
        var result = lincurve(x, 0.0, 1.0, 1.0, 10.0, curve[i])
        
        assert_almost_equal(result, expected[i], "Test: lincurve function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        var mmm_python = Python.import_module("mmm_python.functions")
        var py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.lincurve(x[i2], 0.0, 1.0, 1.0, 10.0, curve[i])))
        assert_almost_equal(result, py_answer, "Test: lincurve mismatch at index " + String(i))

    for test in [[0.0, 8.0, -1.0, 5.0], [-1.0, 1.0, 11.0, 5.678]]:
        for i in range(len(curve)):
            var result = lincurve(x, test[0], test[1], test[2], test[3], curve[i])
            var cwd = Path()
            Python.add_to_path(cwd.path)
            var mmm_python = Python.import_module("mmm_python.functions")
            var py_answer = SIMD[DType.float64, 4]()
            for i2 in range(len(x)):
                py_answer[i2]=(py_to_float64(mmm_python.lincurve(x[i2], test[0], test[1], test[2], test[3], curve[i])))
            assert_almost_equal(result, py_answer, "Test: lincurve mismatch at index " + String(i))

def test_lincurve2() raises:
    var x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    var curve = [2.0, 0.5, 3.5, 0.25]
    var expected = [
        MFloat[4](5.646380815918783, 3.636038969321072, 1.0, 1.0),
        MFloat[4](9.507196, 7.75, 1.0, 1.0),
        MFloat[4](4.0568256812618735, 2.6169817959312582, 1.0, 1.0), 
        MFloat[4](9.973016024176, 9.4375, 1.0, 1.0)
    ]
    for i in range(len(curve)):
        var result = lincurve(x, 0.0, 1.0, 10.0, 1.0, curve[i])
        
        # this was commented out, but it seems like a good thing to test,
        # so I'm putting it back in. 
        assert_almost_equal(result, expected[i], "Test: lincurve function failed")

        var cwd = Path()
        Python.add_to_path(cwd.path)
        var mmm_python = Python.import_module("mmm_python.functions")
        var py_answer = SIMD[DType.float64, 4]()
        for i2 in range(len(x)):
            py_answer[i2]=(py_to_float64(mmm_python.lincurve(x[i2], 0.0, 1.0, 10.0, 1.0, curve[i])))
        assert_almost_equal(result, py_answer, "Test: lincurve mismatch at index " + String(i))

def test_explin() raises:
    var x = MFloat[4](1.0, 3.1622776601683795, 10.0, 15.0)
    var result = explin(x, 1.0, 10.0, 0.0, 1.0)
    var expected = MFloat[4](0.0, 0.5, 1.0, 1.0)
    assert_almost_equal(result, expected, "Test: explin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.explin(x[i], 1.0, 10.0, 0.0, 1.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: explin mismatch at index " + String(i))

def test_explin2() raises:
    var x = MFloat[4](0.234, 0.5, 1.0, 1.5)
    var expected = MFloat[4](2.8923524277696, 1.9030899869919, 1.0, 1.0)

    var result = explin(x, 0.001, 1.0, 10.0, 1.0)
    assert_almost_equal(result, expected, "Test: explin function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = SIMD[DType.float64, 4]()
    for i2 in range(len(x)):
        py_answer[i2]=(py_to_float64(mmm_python.explin(x[i2], 0.001, 1.0, 10.0, 1.0)))
    assert_almost_equal(expected, py_answer, "Test: explin mismatch at index ") 

def test_expexp() raises:
    var x = MFloat[4](1.0, 3.1622776601683795, 10.0, 15.0)
    var result = expexp(x, 1.0, 10.0, 1.0, 10.0)
    var expected = MFloat[4](1.0, 3.1622776601683795, 10.0, 10.0)
    assert_almost_equal(result, expected, "Test: expexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
    for i in range(len(x)):
        py_answer.append(py_to_float64(mmm_python.expexp(x[i], 1.0, 10.0, 1.0, 10.0)))
        assert_almost_equal(result[i], py_answer[i], "Test: expexp mismatch at index " + String(i))

def test_expexp2() raises:
    var x = MFloat[4](2.0, 3.1622776601683795, 10.0, 15.0)
    var result = expexp(x, 1.0, 10.0, 10.0, 0.001)
    var expected = MFloat[4](0.625, 0.1, 0.001, 0.001)
    assert_almost_equal(result, expected, "Test: expexp function failed")

    var cwd = Path()
    Python.add_to_path(cwd.path)
    var mmm_python = Python.import_module("mmm_python.functions")
    var py_answer = List[Float64]()
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
    var files = select_files("mmm_audio", [".mojo"])
    var expected_files = ["mmm_audio/Delays.mojo", "mmm_audio/FFTs.mojo"]
    for expected in expected_files:
        assert_true(expected in files, "Test: select_files missing expected file " + expected)

    var files2 = select_files("resources", [".wav"])
    var expected_files2 = ["resources/Growl 15.wav","resources/Shiverer.wav","resources/small_wavetable.wav","resources/small_wavetable8.wav"]
    for expected in expected_files2:
        assert_true(expected in files2, "Test: select_files missing expected file " + expected)

def test_top_n_indices() raises:
    var tpi = TopNPeaks()
    var n: Int = 3

    var arr: List[Float64] = [0.1, 0.5, 0.3, 0.9, 0.2, 0.8, 0.7]
    var output: List[Int] = List[Int](length=n, fill=0)
    var n_valid = tpi.process(arr, n, output, 0.01)
    var expected: List[Int] = [3, 5, 1]
    assert_equal(n_valid, 3, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    var arr2: List[Float64] = [0.99, 0.5, 0.3, 0.9, 0.2, 0.8, 0.7]
    n_valid = tpi.process(arr2, n, output, 0.01)
    expected: List[Int] = [3, 5]
    assert_equal(n_valid, 2, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    var arr3: List[Float64] = [0.1, 0.5, 0.3, 0.9, 0.2, 0.8, 0.99]
    n_valid = tpi.process(arr3, n, output, 0.01)
    expected: List[Int] = [3, 1]
    assert_equal(n_valid, 2, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

    var arr4: List[Float64] = [0.6, 0.1, 0.1, 0.2, 0.1, 0.7, 0.1]
    n_valid = tpi.process(arr4, n, output, 0.3)
    expected: List[Int] = [5]
    assert_equal(n_valid, 1, "Test: top_n_indices returned incorrect number of valid peaks")
    for i in range(n_valid):
        assert_equal(output[i], expected[i], "Test: top_n_indices function failed at index " + String(i))

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()