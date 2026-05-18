from mmm_audio import * 

def wrap_to_pi[num_chans: Int](phase: MFloat[num_chans]) -> MFloat[num_chans]:
    return atan2(sin(phase), cos(phase))
    
def phase_difference_bin[num_chans: Int](current_phase: MFloat[num_chans], previous_phase: MFloat[num_chans], 
                        bin_num: Int, hop_size: Int, fft_size: Int) -> MFloat[num_chans]:
    expected_shift = two_pi * Float64(bin_num * hop_size) / Float64(fft_size)
    delta_phase = current_phase - previous_phase - expected_shift
    
    return wrap_to_pi(delta_phase)

def phase_coherence[num_chans: Int](
    current_phases: Span[MFloat[num_chans], ...], 
    previous_phases: Span[MFloat[num_chans], ...], 
    current_mags: Span[MFloat[num_chans], ...],
    previous_mags: Span[MFloat[num_chans], ...],
    hop_size: Int, fft_size: Int
) -> MFloat[num_chans]:
    var num_bins = len(current_phases)
    var sum_cos = MFloat[num_chans](0.0)
    var weight_sum = MFloat[num_chans](0.0)
    
    for i in range(num_bins):
        var delta = phase_difference_bin(current_phases[i], previous_phases[i], 
                                         i, hop_size, fft_size)
        
        var weight = current_mags[i] * previous_mags[i]
        sum_cos += weight * cos(delta)
        weight_sum += weight
    
    return sum_cos / (weight_sum + 1e-9)

def get_best_coherence[num_chans: Int, num_iterations: Int, call_back: def (mut mags: List[MFloat[num_chans]], mut phases: List[MFloat[num_chans]]) capturing -> None](
    mut mags: List[MFloat[num_chans]], 
    mut phases: List[MFloat[num_chans]], 
    mut previous_mags: List[MFloat[num_chans]], 
    mut previous_phases: List[MFloat[num_chans]], 
    window_size: Int, 
    hop_size: Int, 
    
):
    """Calls a callback function `num_iterations` times, and keeps the mag/phase set with the best coherence to the previous phases. There are two versions of this function, one that allows the callback to modify both mags and phases, and one that only allows the callback to modify just the phases.
    
    Parameters:
        num_chans: The number of channels in the mags and phases lists.
        num_iterations: The number of times to call the callback function with different random phase sets.
        call_back: A function that takes the mags and phases as arguments and modifies them in place. This function will be called `num_iterations` times with different random phase sets, and the mag/phase set with the best coherence to the previous phases will be kept.


    Args:
        mags: The magnitudes of the current frame, which can be modified by the callback function.
        phases: The phases of the current frame, which can be modified by the callback function.
        previous_mags: The magnitudes of the previous frame, which are used to calculate the coherence.
        previous_phases: The phases of the previous frame, which are used to calculate the coherence.
        window_size: The size of the FFT window, used to calculate the expected phase shift.
        hop_size: The hop size of the FFT, used to calculate the expected phase shift.
    """

    phase_corr = MFloat[num_chans](-1.0)
    call_back(mags, phases)
    comptime if num_iterations > 0:
        comptime for i in range(num_iterations):
            temp_phases = phases.copy()
            temp_mags = mags.copy()
            comptime if i > 0:
                call_back(mags, phases)
            phase_corr_new = phase_coherence(phases, previous_phases, mags, previous_mags, hop_size, window_size)

            lt0 = phase_corr_new.lt(0.0)
            phase_corr_new = abs(phase_corr_new)
            gt_last = phase_corr_new.gt(phase_corr)

            # if the absolute value of the new coherence is higher than the last one, we want to keep it, but if the coherence is negative, we want to invert the phases
            # otherwise we want to keep the old phases. 
            for i2 in range(len(phases)):
                phases[i2] = gt_last.select(lt0.select(wrap_to_pi(phases[i2] + pi), phases[i2]), temp_phases[i2])
                mags[i2] = gt_last.select(mags[i2], temp_mags[i2])

            phase_corr = phase_corr_new
    previous_phases = phases.copy()
    previous_mags = mags.copy()

def get_best_coherence[num_chans: Int, num_iterations: Int, call_back: def (mut phases: List[MFloat[num_chans]]) capturing -> None](mut mags: List[MFloat[num_chans]], mut phases: List[MFloat[num_chans]], mut previous_mags: List[MFloat[num_chans]], mut previous_phases: List[MFloat[num_chans]], window_size: Int, hop_size: Int):
    """Calls a callback function `num_iterations` times, and keeps the mag/phase set with the best coherence to the previous phases. There are two versions of this function, one that allows the callback to modify both mags and phases, and one that only allows the callback to modify just the phases.
    
    Parameters:
        num_chans: The number of channels in the mags and phases lists.
        num_iterations: The number of times to call the callback function with different random phase sets.
        call_back: A function that takes the phases as arguments and modifies them in place.

    Args:
        mags: The magnitudes of the current frame, which can be modified by the callback function.
        phases: The phases of the current frame, which can be modified by the callback function.
        previous_mags: The magnitudes of the previous frame, which are used to calculate the coherence.
        previous_phases: The phases of the previous frame, which are used to calculate the coherence.
        window_size: The size of the FFT window, used to calculate the expected phase shift.
        hop_size: The hop size of the FFT, used to calculate the expected phase shift.
    """

    phase_corr = MFloat[num_chans](-1.0)
    call_back(phases)
    comptime if num_iterations > 0:
        comptime for i in range(num_iterations):
            temp_phases = phases.copy()
            comptime if i > 0:
                call_back(phases)
            phase_corr_new = phase_coherence(phases, previous_phases, mags, previous_mags, hop_size, window_size)

            lt0 = phase_corr_new.lt(0.0)
            phase_corr_new = abs(phase_corr_new)
            gt_last = phase_corr_new.gt(phase_corr)

            # if the absolute value of the new coherence is higher than the last one, we want to keep it, but if the coherence is negative, we want to invert the phases
            # otherwise we want to keep the old phases. 
            for i2 in range(len(phases)):
                phases[i2] = gt_last.select(lt0.select(wrap_to_pi(phases[i2] + pi), phases[i2]), temp_phases[i2])

            phase_corr = phase_corr_new
    previous_phases = phases.copy()
    previous_mags = mags.copy()

def linkwitz_riley_bin(
    freq_bin: Int,
    cutoff_bin: Int,
    order: Int,
    highpass: Bool = False
) -> Float64:
    """
    Calculate Linkwitz-Riley filter response for a single bin.
    
    Args:
        freq_bin: Current frequency bin index.
        cutoff_bin: Cutoff frequency bin index.
        order: Filter order (2=12dB/oct, 4=24dB/oct, 8=48dB/oct).
        highpass: If True, creates highpass; else lowpass.
    
    Returns:
        Filter magnitude coefficient for this bin.
    """
    if cutoff_bin == 0:
        return 1.0
    
    var ratio = Float64(freq_bin) / Float64(cutoff_bin)
    
    # Butterworth squared = Linkwitz-Riley
    # LR is two cascaded Butterworth filters
    var butterworth_order = order // 2
    var omega_ratio_pow = pow(ratio, Float64(butterworth_order * 2))
    
    # Butterworth magnitude squared
    var butterworth_mag_sq = 1.0 / (1.0 + omega_ratio_pow)
    
    # Linkwitz-Riley is Butterworth squared
    var lr_response = butterworth_mag_sq
    
    if highpass:
        lr_response = 1.0 - lr_response
    
    return sqrt(lr_response)


def create_linkwitz_riley_fft_filter(
    fft_size: Int,
    cutoff_bin: Int,
    slope_db_per_octave: Int,
    highpass: Bool = False
) -> List[Float64]:
    """
    Create a Linkwitz-Riley frequency domain filter.
    
    Args:
        fft_size: Size of the FFT.
        cutoff_bin: Cutoff frequency as bin index.
        slope_db_per_octave: Filter slope (12, 24, 36, 48 dB/octave).
        highpass: If True, creates highpass; else lowpass.
    
    Returns:
        List of magnitude coefficients for positive frequencies.
    """
    # Convert slope to order: 12dB/oct = 2nd order, 24dB/oct = 4th order, etc.
    var order = slope_db_per_octave // 6
    
    var num_bins = fft_size // 2 + 1
    var filter_response = List[Float64](capacity=num_bins)
    
    for i in range(num_bins):
        var magnitude = linkwitz_riley_bin(i, cutoff_bin, order, highpass)
        filter_response.append(magnitude)
    
    return filter_response^