from std.math import sqrt, floor, cos, pi, sin
from std.sys import simd_width_of
from std.algorithm import vectorize
from mmm_audio import *



@always_inline
def pan2(samples: Float64, pan: Float64) -> MFloat[2]:
    """
    Simple constant power panning function.

    Args:
        samples: Float64 - Mono input sample.
        pan: Float64 - Pan value from -1.0 (left) to 1.0 (right).

    Returns:
        Stereo output as MFloat[2].
    """

    var pan2 = clip(pan, -1.0, 1.0)  # Ensure pan is set and clipped before processing
    var gains = MFloat[2](-pan2, pan2)

    samples_out = samples * sqrt((1 + gains) * 0.5)
    return samples_out  # Return stereo output as List

@always_inline
def pan_stereo(samples: MFloat[2], pan: Float64) -> MFloat[2]:
    """
    Simple constant power panning function for stereo samples.

    Args:
        samples: MFloat[2] - Stereo input sample.
        pan: Float64 - Pan value from -1.0 (left) to 1.0 (right).

    Returns:
        Stereo output as MFloat[2].
    """
    var pan2 = clip(pan, -1.0, 1.0)  # Ensure pan is set and clipped before processing
    var gains = MFloat[2](-pan2, pan2)

    samples_out = samples * sqrt((1 + gains) * 0.5)
    return samples_out  # Return stereo output as List

@always_inline
def splay[num_simd: Int](*input: MFloat[num_simd], world: World) -> MFloat[2]:
    """
    Splay multiple input channels into stereo output.

    There are multiple versions of splay to handle different input types. It can take a List or InlineArray of SIMD vectors, a VariadicList of SIMD, or a single 1 or many channel SIMD vector. In the case of a list of SIMD vectors, each channel within the vector is treated separately and panned individually.

    Parameters:
        num_simd: Number of channels in each SIMD input.

    Args:
        input: VariadicList of input samples from multiple channels.
        world: Pointer to MMMWorld containing the pan_window.

    Returns:
        Stereo output as MFloat[2].
    """
    num_input_channels = len(input) * num_simd
    out = MFloat[2](0.0)

    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0][0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)

            index0 = i // num_simd
            index1 = i % num_simd
            temp = world[].windows.value()
            pan_mul = SpanInterpolator.read[
                        interp=Interp.none,
                        bWrap=False,
                        mask=255
                    ](
                        world = world,
                        data=temp[].pan2,
                        f_idx=pan * 255.0
                    )
            out += input[index0][index1] * pan_mul
    return out

@always_inline
def splay[num_simd: Int](input: Span[MFloat[num_simd], ...], world: World) -> MFloat[2]:
    """
    Splay multiple input channels into stereo output.

    There are multiple versions of splay to handle different input types. It can take a List or InlineArray of SIMD vectors, a VariadicList of SIMD, or a single 1 or many channel SIMD vector. In the case of a list of SIMD vectors, each channel within the vector is treated separately and panned individually.

    Parameters:
        num_simd: Number of channels in each SIMD input.

    Args:
        input: VariadicList of input samples from multiple channels.
        world: Pointer to MMMWorld containing the pan_window.

    Returns:
        Stereo output as MFloat[2].
    """
    num_input_channels = len(input) * num_simd
    out = MFloat[2](0.0)

    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0][0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)

            index0 = i // num_simd
            index1 = i % num_simd
            temp = world[].windows.value()
            pan_mul = SpanInterpolator.read[
                        interp=Interp.none,
                        bWrap=False,
                        mask=255
                    ](
                        world = world,
                        data=temp[].pan2,
                        f_idx=pan * 255.0
                    )
            out += input[index0][index1] * pan_mul
    return out

@always_inline
def splay[num_input_channels: Int](input: MFloat[num_input_channels], world: World) -> MFloat[2]:
    out = MFloat[2](0.0)

    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)
            temp = world[].windows.value()
            pan_mul = SpanInterpolator.read[
                        interp=Interp.none,
                        bWrap=False,
                        mask=255
                    ](
                        world = world,
                        data=temp[].pan2,
                        f_idx=pan * 255.0
                    )
            out += input[i] * pan_mul
    return out

@always_inline
def pan_az[simd_out_size: Int = 2](sample: Float64, pan: Float64, num_speakers: Int, width: Float64 = 2.0, orientation: Float64 = 0.5) -> MFloat[simd_out_size]:
    """
    Pan a mono sample to N speakers arranged in a circle around the listener using azimuth panning.

    Parameters:
        simd_out_size: Number of output channels (speakers). Must be a power of two that is at least as large as num_speakers.

    Args:
        sample: Mono input sample.
        pan: Pan position from 0.0 to 1.0.
        num_speakers: Number of speakers to pan to.
        width: Width of the speaker array (default is 2.0).
        orientation: Orientation offset of the speaker array (default is 0.5).

    Returns:
        MFloat[simd_out_size]: The panned output sample for each speaker.
    """
    
    comptime assert simd_out_size & (simd_out_size - 1) == 0, "simd_out_size must be a power of two for pan_az"

    var rwidth = 1.0 / width
    var frange = Float64(num_speakers) * rwidth
    var rrange = 1.0 / frange

    var aligned_pos_fac = 0.5 * Float64(num_speakers)
    var aligned_pos_const = width * 0.5 + orientation
    var constant = pan * 2.0 * aligned_pos_fac + aligned_pos_const

    out = MFloat[simd_out_size](0.0)

    # this needs to be checked
    for i in range(num_speakers):
        var pos = (constant - Float64(i)) * rwidth
        pos = (pos - frange * floor(rrange * pos)) * pi

        if pos < pi:
            out[i] = sin(pos) * sample
        else:
            out[i] = 0.0

    return out

comptime pi_over_2 = pi / 2.0

struct SplayN[num_channels: Int = 2, pan_points: Int = 128](Movable, Copyable):
    """
    SplayN - Splays multiple input channels into N output channels. Different from `splay` which only outputs stereo, SplayN can output to any number of channels.
    
    Parameters:
        num_channels: Number of output channels to splay to.
        pan_points: Number of discrete pan points to use for panning calculations. Default is 128.
    """
    var mul_list: InlineArray[MFloat[Self.num_channels], Self.pan_points]

    def __init__(out self):
        """
        Initialize the SplayN instance.
        """

        js = MFloat[self.num_channels](0.0, 1.0)
        comptime if self.num_channels > 2:
            for j in range(self.num_channels):
                js[j] = Float64(j)

        self.mul_list = InlineArray[MFloat[self.num_channels], Self.pan_points](fill=0.0)
        for i in range(self.pan_points):
            pan = Float64(i) * Float64(self.num_channels - 1) / Float64(self.pan_points - 1)

            d = abs(pan - js)
            comptime if self.num_channels > 2:
                for j in range(self.num_channels):
                    if d[j] < 1.0:
                        d[j] = d[j]
                    else:
                        d[j] = 1.0
            
            for j in range(self.num_channels):
                self.mul_list[i][j] = cos(d[j] * pi_over_2)

    @always_inline
    def next[num_simd: Int](mut self, input: Span[MFloat[num_simd], ...]) -> MFloat[self.num_channels]:
        """Evenly distributes multiple input channels to num_channels of output channels.

        Parameters:
            num_simd: Number of channels in each SIMD input.

        Args:
            input: List of input samples from multiple channels.

        Returns:
            MFloat[self.num_channels]: The panned output sample for each output channel.
        """
        out = MFloat[self.num_channels](0.0)

        in_len = len(input) * num_simd
        if in_len == 0:
            return out
        elif in_len == 1:
            out = input[0][0] * self.mul_list[0]
            return out
        for i in range(in_len):
            index0 = i // num_simd
            index1 = i % num_simd

            out += input[index0][index1] * self.mul_list[Int(Float64(i) / Float64(in_len - 1) * Float64(self.pan_points - 1))]
            
        return out

    @always_inline
    def next[num_simd: Int](mut self, *input: MFloat[num_simd]) -> MFloat[self.num_channels]:
        """Evenly distributes multiple input channels to num_channels of output channels.

        Parameters:
            num_simd: Number of channels in each SIMD input.

        Args:
            input: Input samples from multiple channels.

        Returns:
            MFloat[self.num_channels]: The panned output sample for each output channel.
        """
        out = MFloat[self.num_channels](0.0)

        in_len = len(input) * num_simd
        if in_len == 0:
            return out
        elif in_len == 1:
            out = input[0][0] * self.mul_list[0]
            return out
        for i in range(in_len):
            index0 = i // num_simd
            index1 = i % num_simd

            out += input[index0][index1] * self.mul_list[Int(Float64(i) / Float64(in_len - 1) * Float64(self.pan_points - 1))]
            
        return out


@always_inline
def pan_az[num_speakers: Int = 2, simd_out_size: Int = 2, width: Float64 = 2.0, orientation: Float64 = 0.5](sample: Float64, pan: Float64) -> MFloat[simd_out_size]:
    """
    Pan a mono sample to N speakers arranged in a circle around the listener using azimuth panning. This version fixes the number of speakers, width, and orientation at compile time for better performance.

    Parameters:
        num_speakers: Number of output speakers. Can be any integer, but must be less than or equal to simd_out_size.
        simd_out_size: Number of channels of the SIMD output vector. Must be a power of two that is at least as large as num_speakers.
        width: Width of the speaker array (default is 2.0).
        orientation: Orientation offset of the speaker array (default is 0.5).

    Args:
        sample: Mono input sample.
        pan: Pan position from 0.0 to 1.0.

    Returns:
        MFloat[simd_out_size]: The panned output sample for each speaker.
    """

    comptime assert num_speakers <= simd_out_size, "num_speakers must be less than or equal to simd_out_size for pan_az"
    comptime assert simd_out_size & (simd_out_size - 1) == 0, "simd_out_size must be a power of two for pan_az"

    comptime num_simd_pairs = num_speakers // 2 + (num_speakers % 2)
    comptime rwidth = 1.0 / width
    comptime frange = Float64(num_speakers) * rwidth
    comptime rrange = 1.0 / frange

    comptime aligned_pos_fac = 0.5 * Float64(num_speakers)
    comptime aligned_pos_const = width * 0.5 + orientation
    var constant = pan * 2.0 * aligned_pos_fac + aligned_pos_const

    out = MFloat[simd_out_size](0.0)

    # this needs to be checked
    for i in range(num_simd_pairs):
        var pos = (constant - MFloat[2](Float64(i*2), Float64(i*2+1))) * rwidth
        pos = (pos - frange * floor(rrange * pos)) * pi

        mask: MBool[2] = pos.lt(pi)
        temp = mask.select(sin(pos) * sample, 0.0)
        out[i*2] = temp[0]
        if i*2+1 < num_speakers:
            out[i*2+1] = temp[1]

    return out

# XBAP Algorithms

@always_inline
def dbap2D[
    num_speakers: Int, 
    simd_out_size: Int,
    speaker_positions: InlineArray[MFloat[2], num_speakers],
    weights: InlineArray[Float64, num_speakers]]
    (
        sample: Float64, 
        pos: MFloat[2], 
        blur: Float64 = 0.1, 
        rolloff: Float64 = 6
    ) -> MFloat[simd_out_size]:
    """
    Implements DBAP (Distance Based Amplitude Panning). Pans a mono sample to N speakers of arbitrary positions in meters.
    For more on DBAP see the paper written by Trond Lossius, Pascal Baltazar, and Theo de la Hague.
    https://jamoma.org/publications/attachments/icmc2009-dbap-rev1.pdf .

    Parameters:
        num_speakers: The number of speakers as an integer.
        simd_out_size: Must be a power of 2 and greater than num_speakers.
        speaker_positions: The speaker positions as an InlineArray of MFloat[2] x/y pairs in meters from a center position.
        weights: An InlineArray of Float64s (between 0.0 and 1.0) defining speaker weights for DBAP. Speaker weights allow for a source to be restricted to a subset of speakers. Speaker weights of 0.0 will disallow a source from playing through that speaker.

    Args:
        sample: Mono input sample.
        pos: X/Y position of the source from center in meters as an MFloat[2].
        blur: Blurs the source, causing it to spread to more speakers. Values must be greater than or equal to 0, with 0 being the most localizable and values > 0 becoming less and less localizable. There is no limit to the amount of blur but values over 5 have diminishing returns.
        rolloff: The amplitude rolloff in dB, this must be > 0.0. 6.0 equals the inverse distance law for sound in an open field. Lower values will decrease the attenuation of the signal over distance, while larger values will increase this attenuation.
    
    Returns:
        MFloat[simd_out_size]: The panned output sample for each speaker.
    """
    comptime assert num_speakers <= simd_out_size, "num_speakers must be less than or equal to simd_out_size for dbap2D"
    comptime assert simd_out_size & (simd_out_size - 1) == 0, "simd_out_size must be a power of two for dbap2D"

    # Calculates the covariance of speaker distances 
    
    def variance_of_dists[comp_num_speakers: Int, comp_speaker_positions: InlineArray[MFloat[2], comp_num_speakers]]() -> Float64:
       
        var dists = MFloat[next_power_of_two(comp_num_speakers)](0.0)
        
        for i in range(comp_num_speakers):
            dist = comp_speaker_positions[i] * comp_speaker_positions[i]
            dist_from_center = sqrt(dist.reduce_add())

            dists[i] = dist_from_center
        
        var mean : Float64 = dists.reduce_add() / Float64(comp_num_speakers)
        
        return pow(dists - mean, 2).reduce_add() / Float64(comp_num_speakers)
        
    
    comptime vec_weights = array_to_mfloat[simd_out_size, weights]()
    comptime speaker_position_variance : Float64 = variance_of_dists[num_speakers, speaker_positions]()
    
    # Calculates the blur factor using the speaker variance to normalize
    var blur_sq : Float64

    # comptime if speaker_position_variance == 0:
    #         blur_sq = pow(max(0.0001, blur), 2)
    #     else:
    #         blur_sq = pow(max(0.0001, blur * speaker_position_variance), 2)

    blur_sq = pow(max(0.0001, blur * speaker_position_variance), 2)
    # var blur_sq = pow(max(0.00001, blur), 2)

   # Set dists to 1.0 by default to avoid divide by 0 when calculating k
    var dists = MFloat[simd_out_size](1.0)
 
    # Calculates the k coefficient and gets distances for every speaker from the source
    for i in range(num_speakers):
        speaker = speaker_positions[i] - pos
        xy = speaker * speaker
        dists[i] = sqrt(xy.reduce_add() + blur_sq)  

    # SIMD optimization 
    comptime num_pairs = num_speakers // 2

    # Calculates the a coefficient given a rolloff in dB
    var a = rolloff/6.02059991328
    var two_a = 2 * a
    var denom = 0.0
    for i in range(num_pairs):
        var w = MFloat[2](vec_weights[i*2], vec_weights[i*2+1])
        var d = MFloat[2](dists[i*2], dists[i*2+1])

        denom += ((w * w) / pow(d, two_a)).reduce_add()

    comptime if num_speakers % 2 != 0:
        denom += (vec_weights[num_speakers - 1] * vec_weights[num_speakers - 1]) / pow(dists[num_speakers - 1], two_a)

    k = 1 / sqrt(denom)

    out = MFloat[simd_out_size](0.0)
    for i in range(num_pairs):
        temp = k * MFloat[2](vec_weights[i*2], vec_weights[i*2+1]) / pow(MFloat[2](dists[i*2], dists[i*2+1]), a) * sample
        out[i*2] = temp[0]
        out[i*2+1] = temp[1]
    comptime if num_speakers % 2 != 0:
        out[num_speakers - 1] = k * vec_weights[num_speakers - 1] / pow(dists[num_speakers - 1], a) * sample


    # out = MFloat[simd_out_size](blur_sq)

    return out

# There are multiple versions of vbap2D for using x/y coordinates or azimuth in radians

@always_inline
def vbap2D[num_speakers: Int, simd_out_size: Int, speaker_positions: InlineArray[Float64, num_speakers]](sample: Float64, az: Float64, offset: Float64 = 0.0) -> MFloat[simd_out_size]:
    """
    An implementation of VBAP (Vector Base Amplitude Panning). Pans a mono sample to a 2D array of N speakers of arbitrary positions in radians that are equidistant from the listener.
    For more on VBAP see the paper written by Ville Pulkki:
    https://www.audiolabs-erlangen.de/media/pages/resources/aps-w23/papers/935eb793db-1663358804/sap_Pulkki1997.pdf .

    Parameters:
        num_speakers: The number of speakers as an integer.
        simd_out_size: Must be a power of 2 and greater than num_speakers.
        speaker_positions: The speaker positions as an InlineArray of Float64 azimuth angles in radians.
    
    Args:
        sample: The mono signal to be panned.
        az: The angle of the source in radians.
        offset: An offset in radians. This rotates the entire speaker array. Is this needed?

    Returns:
        MFloat[simd_out_size]: The panned output sample for each speaker.
    """
    
    #This is pretty brute force right now. Could maybe be more elegant?
    def calc_speaker_unit_vectors() -> InlineArray[MFloat[2], num_speakers]:
        var speaker_vectors = InlineArray[MFloat[2], num_speakers](fill=MFloat[2](0.0,0.0))
        
        for i in range(num_speakers):
            speaker_vectors[i] = MFloat[2](cos(speaker_positions[i]), sin(speaker_positions[i]))

            if speaker_vectors[i][0] < 0.0000001 and speaker_vectors[i][0] > -0.0000001:
                speaker_vectors[i][0] = 0

            if speaker_vectors[i][1] < 0.0000001 and speaker_vectors[i][1] > -0.0000001:
                speaker_vectors[i][1] = 0
            
        return speaker_vectors

    def calc_inverse_base[speaker_pairs:InlineArray[InlineArray[Int, 2], num_speakers], speaker_vectors: InlineArray[MFloat[2], num_speakers]]() -> InlineArray[InlineArray[MFloat[2], 2], num_speakers]:
        var inverse_bases = InlineArray[InlineArray[MFloat[2], 2], num_speakers](fill=InlineArray[MFloat[2], 2](fill=0.0))

        for i in range(num_speakers):
            var speaker_a = speaker_vectors[speaker_pairs[i][0]] #[-2, 1]  [a, b]
            var speaker_b = speaker_vectors[speaker_pairs[i][1]] #[1, 2]   [c, d]
            
            var determinate = (speaker_a[0] * speaker_b[1]) - (speaker_a[1] * speaker_b[0]) # ad - bc : -2 * 2 - 1 * 1 = -5

            var inverted_a = MFloat[2](speaker_b[1], -1 * speaker_a[1]) # [d, -b] = [2, -1]
            var inverted_b = MFloat[2](-1 * speaker_b[0], speaker_a[0]) # [-c, a] = [-1, -2]
            inverse_bases[i][0] = inverted_a/determinate
            inverse_bases[i][1] = inverted_b/determinate


        return inverse_bases

    def index_of[](array: InlineArray[Float64, _], element: Float64) -> Int:
        var index : Int = 0
        for i in range(len(array)):
                if array[i] == element:
                    index = i
                    break
        
        return index

    #Find the pairs of speakers as indices, allows for arbitrary assignment of output channels. Meaning speaker positions are given as their channel out
    def calc_speaker_pairs[speaker_az: InlineArray[Float64, num_speakers]]() -> InlineArray[InlineArray[Int, 2], num_speakers]:
        var speaker_pairs = InlineArray[InlineArray[Int, 2], num_speakers](fill=[0, 0])
        var sorted_array = speaker_az.copy()
        sort(sorted_array)
        
        for i in range(num_speakers):
            speaker_pairs[i] = [index_of(speaker_az, sorted_array[i]), index_of(speaker_az, sorted_array[(i + 1) % num_speakers])] #MInt[2](i, i + 1)
        
        
        return speaker_pairs
    
    comptime speaker_unit_vectors = calc_speaker_unit_vectors()
    comptime speaker_pairs = calc_speaker_pairs[speaker_positions]()
    comptime speaker_inverse_bases = calc_inverse_base[speaker_pairs, speaker_unit_vectors]()
    
    var active_speaker_pair : InlineArray[Int, 2] = [0, 0]
    var active_gain_factors = MFloat[2](0.5)
    
    def calc_gain_factors(source_vec: MFloat[2], mut active_pair: InlineArray[Int, 2], mut active_gains: MFloat[2], source_az: Float64):
        
        for speaker_pair in speaker_pairs:
            
            if source_az == speaker_positions[speaker_pair[0]]:
                active_pair = speaker_pair
                active_gains = MFloat[2](1.0, 0.0)
                
                return
            elif source_az == speaker_positions[speaker_pair[1]]:
                active_pair = speaker_pair
                active_gains = MFloat[2](0.0, 1.0)
                return
        
        
        var gain_factors = InlineArray[MFloat[2], num_speakers](fill=0.0)
        var active_index : Int = 0
        
        for i in range(num_speakers):

            var speaker_a_vector = speaker_inverse_bases[i][0] # [c, d]
            var speaker_b_vector = speaker_inverse_bases[i][1] # [e, f]
            
            var speaker_a_product = source_vec[0] * speaker_a_vector # [ac, ad]
            var speaker_b_product = source_vec[1] * speaker_b_vector # [be, bf]

            var speaker_gains = MFloat[2](
                speaker_a_product[0] + speaker_b_product[0],
                speaker_a_product[1] + speaker_b_product[1],
            )
            
            gain_factors[i] = speaker_gains
        
        var largest_small_gain = 0
        for i in range(num_speakers):

            var smallest_gain = min(gain_factors[i][0], gain_factors[i][1])
            
            if gain_factors[i][0] >= 0.0 and gain_factors[i][1] >= 0.0:
                active_index = i 
                active_pair = speaker_pairs[active_index]
                scaled_gains = gain_factors[active_index] / (sqrt((gain_factors[active_index] * gain_factors[active_index]).reduce_add()))
                active_gains = scaled_gains
                break
            elif smallest_gain > min(gain_factors[largest_small_gain][0], gain_factors[largest_small_gain][1]):
                largest_small_gain = i 
                active_index = i

        active_pair = speaker_pairs[active_index]
        scaled_gains = gain_factors[active_index] / (sqrt((gain_factors[active_index] * gain_factors[active_index]).reduce_add()))
        active_gains = scaled_gains
    
    var source_vector = MFloat[2](cos(az), sin(az))

    calc_gain_factors(source_vector, active_speaker_pair, active_gain_factors, az)
   
    
    
    var gain_factors = MFloat[simd_out_size](0.0)
    
    gain_factors[Int(active_speaker_pair[0])] = active_gain_factors[0]
    gain_factors[Int(active_speaker_pair[1])] = active_gain_factors[1]
    
    return gain_factors * sample
    


# def vbap2D[num_speakers: Int, simd_out_size: Int, speaker_positions: InlineArray[MFloat[2], num_speakers]](sample: Float64, pos: MFloat[2]) -> MFloat[simd_out_size]:
#     """
#     An implementation of VBAP (Vector Base Amplitude Panning).

#     Parameters:
#         num_speakers: The number of speakers as an integer.
#         simd_out_size: Must be a power of 2 and greater than num_speakers.
#         speaker_positions: The speaker positions as an InlineArray of MFloat[2] x/y pairs in meters from a center position.
#     """

#     return MFloat[simd_out_size](sample)

