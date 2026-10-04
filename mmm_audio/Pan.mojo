from std.math import sqrt, floor, cos, pi, sin
from std.sys import simd_width_of
from std.algorithm import vectorize
from std.python import Python
from mmm_audio.constants import *
from mmm_audio.functions import *
from mmm_audio.MMMWorld_Module import Interp
from std.bit import next_power_of_two

@always_inline
def pan2(sample: Float64, pan: Float64) -> MFloat[2]:
    """
    Simple constant power panning function.

    Args:
        sample: Float64 - Mono input sample.
        pan: Float64 - Pan value from -1.0 (left) to 1.0 (right).

    Returns:
        Stereo output as MFloat[2].
    """

    var pos = clip(pan, -1.0, 1.0)
    var angle = (pos + 1.0) * 0.25 * pi

    return sample * cos(MFloat[2](angle, pi_over_2 - angle))  

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

    var samples_out = samples * sqrt((1 + gains) * 0.5)
    return samples_out  # Return stereo output as List

@always_inline
def splay(*input: MFloat[_], world: World) -> MFloat[2]:
    """
    Splay multiple input channels into stereo output.

    There are multiple versions of splay to handle different input types. It can take a List or Array of SIMD vectors, a VariadicList of SIMD, or a single 1 or many channel SIMD vector. In the case of a list of SIMD vectors, each channel within the vector is treated separately and panned individually.

    Args:
        input: VariadicList of input samples from multiple channels.
        world: Pointer to MMMWorld containing the pan_window. world is a keyword argument that needs to be explicitly assign (`world=world`) when calling splay().

    Returns:
        Stereo output as MFloat[2].
    """
    var num_input_channels = len(input) * input[0].length
    var out = MFloat[2](0.0)

    var pan: Float64
    var index0: Int
    var index1: Int
    var pan_mul: MFloat[2]
    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0][0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)

            index0 = i // input[0].length
            index1 = i % input[0].length
            ref temp = world[].windows()
            pan_mul = temp.at_pan[interp=Interp.none](world, pan)
            out += input[index0][index1] * pan_mul
    return out

@always_inline
def splay[num_simd: SIMDLength](input: Span[MFloat[num_simd], _], world: World) -> MFloat[2]:
    """
    Splay multiple input channels into stereo output.

    There are multiple versions of splay to handle different input types. It can take a List or Array of SIMD vectors, a VariadicList of SIMD, or a single 1 or many channel SIMD vector. In the case of a list of SIMD vectors, each channel within the vector is treated separately and panned individually.

    Parameters:
        num_simd: Number of channels in each SIMD input.

    Args:
        input: VariadicList of input samples from multiple channels.
        world: Pointer to MMMWorld containing the pan_window.

    Returns:
        Stereo output as MFloat[2].
    """
    var num_input_channels = len(input) * num_simd
    var out = MFloat[2](0.0)

    var pan: Float64
    var index0: Int
    var index1: Int
    var pan_mul: MFloat[2]

    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0][0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)

            index0 = i // num_simd
            index1 = i % num_simd
            ref temp = world[].windows()
            pan_mul = temp.at_pan[interp=Interp.none](world, pan)
            out += input[index0][index1] * pan_mul
    return out

@always_inline
def splay[num_input_channels: Int](input: MFloat[num_input_channels], world: World) -> MFloat[2]:
    """
    Splay multiple input channels into stereo output.

    There are multiple versions of splay to handle different input types. It can take a List or Array of SIMD vectors, a VariadicList of SIMD, or a single 1 or many channel SIMD vector. In the case of a list of SIMD vectors, each channel within the vector is treated separately and panned individually.

    Parameters:
        num_input_channels: Number of input channels.

    Args:
        input: VariadicList of input samples from multiple channels.
        world: Pointer to MMMWorld containing the pan_window.

    Returns:
        Stereo output as MFloat[2].
    """
    var out = MFloat[2](0.0)
    var pan: Float64
    var pan_mul: MFloat[2]

    for i in range(num_input_channels):
        if num_input_channels == 1:
            out = input[0] * MFloat[2](0.7071, 0.7071)
        else:
            pan = Float64(i) / Float64(num_input_channels - 1)
            ref temp = world[].windows()
            pan_mul = temp.at_pan[interp=Interp.none](world, pan)
            out += input[i] * pan_mul
    return out

def make_mul_list[num_speakers: Int, simd_out_size: Int, pan_points: Int]() -> Array[MFloat[simd_out_size], pan_points]:
    var js = MFloat[simd_out_size]()
    comptime for j in range(simd_out_size):
        js[j] = Float64(j)

    var mul_list = Array[MFloat[simd_out_size], pan_points](fill=0.0)
    comptime for i in range(pan_points):
        var pan = Float64(i) * Float64(num_speakers - 1) / Float64(pan_points - 1)

        var d = abs(pan - js)
        comptime if simd_out_size > 2:
            comptime for j in range(simd_out_size):
                if d[j] < 1.0:
                    d[j] = d[j]
                else:
                    d[j] = 1.0
        
        comptime for j in range(num_speakers):
            mul_list[i][j] = cos(d[j] * pi_over_2)
    return mul_list^

def splay_n[simd_in_width: SIMDLength, num_speakers: Int, simd_out_size: SIMDLength, pan_points: Int](input: Span[MFloat[simd_in_width], ...], world: World) -> MFloat[simd_out_size]:
    """Splay multiple input channels into an arbitrary number of output channels.

    Parameters:
        simd_in_width: Number of channels in each SIMD input.
        num_speakers: Number of output speakers. Must be less than or equal to simd_out_size.
        simd_out_size: Number of channels of the SIMD output vector. Must be a power of two that is at least as large as num_speakers.
        pan_points: Number of discrete pan points to calculate for the panning algorithm. More pan points will increase the resolution of the pan but also increase CPU usage. 100 is usually sufficient for smooth panning.

    Args:
        input: Span of input samples from multiple channels, where each channel is a SIMD vector.
        world: Pointer to MMMWorld containing the pan_window.

    Returns:
        MFloat[simd_out_size]: The panned output with one speaker per channel. Extra SIMD channels will be filled with zeros.
    """
    comptime assert simd_out_size & (simd_out_size - 1) == 0, "simd_out_size must be a power of two for splay_n"

    comptime mul_list = make_mul_list[num_speakers, simd_out_size, pan_points]()
    var mul_list_materialized: Array[MFloat[simd_out_size], pan_points] = materialize[mul_list]()
    var num_input_channels = len(input) * simd_in_width
    var out = MFloat[simd_out_size](0.0)
    var index0: Int
    var index1: Int

    for i in range(num_input_channels):
        if num_input_channels == 1:
            for chan in range(num_speakers):
                out[chan] = input[0][0] * mul_list_materialized[0][chan]
        else:
            index0 = i // simd_in_width
            index1 = i % simd_in_width
            out += input[index0][index1] * mul_list_materialized[Int(Float64(i) / Float64(num_input_channels - 1) * Float64(pan_points - 1))]

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

    var out = MFloat[simd_out_size](0.0)

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

    var out = MFloat[simd_out_size](0.0)
    var mask: MBool[2]
    var temp: MFloat[2]

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
    speaker_positions: Array[MFloat[2], num_speakers],
    weights: Array[Float64, num_speakers]]
    (
        sample: Float64, 
        pos: MFloat[2], 
        blur: Float64 = 0.1, 
        rolloff: Float64 = 6
    ) -> MFloat[simd_out_size]:
    """
    Implements 2D DBAP (Distance Based Amplitude Panning). Pans a mono sample to N speakers of arbitrary positions in meters.
    For more on DBAP see the paper written by Trond Lossius, Pascal Baltazar, and Theo de la Hague.
    https://jamoma.org/publications/attachments/icmc2009-dbap-rev1.pdf .

    Parameters:
        num_speakers: The number of speakers as an integer.
        simd_out_size: Must be a power of 2 and greater than num_speakers.
        speaker_positions: The speaker positions as an Array of MFloat[2] x/y pairs in meters from a center position.
        weights: An Array of Float64s (between 0.0 and 1.0) defining speaker weights for DBAP. Speaker weights allow for a source to be restricted to a subset of speakers. Speaker weights of 0.0 will disallow a source from playing through that speaker.

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

    def variance_of_dists[
        comp_num_speakers: Int, 
        comp_speaker_positions: Array[MFloat[2], 
        num_speakers]]() -> Float64:
       
        var positions = materialize[
            comp_speaker_positions
        ]()

        var dists = MFloat[next_power_of_two(comp_num_speakers)](0.0)
        
        var dist: MFloat[2]
        var dist_from_center: Float64
        for i in range(comp_num_speakers):
            dist = positions[i] * positions[i]
            dist_from_center = sqrt(dist.reduce_add())

            dists[i] = dist_from_center
        
        var mean : Float64 = dists.reduce_add() / Float64(comp_num_speakers)
        
        return pow(dists - mean, 2).reduce_add() / Float64(comp_num_speakers)
        
    
    comptime vec_weights = array_to_mfloat[simd_out_size, weights]()
    comptime speaker_position_variance : Float64 = variance_of_dists[num_speakers, speaker_positions]()
    
    
    var materialized_speaker_positions = materialize[speaker_positions]()
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
        var speaker = materialized_speaker_positions[i] - pos
        var xy = speaker * speaker
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

    var k = 1 / sqrt(denom)

    var out = MFloat[simd_out_size](0.0)
    for i in range(num_pairs):
        var temp = k * MFloat[2](vec_weights[i*2], vec_weights[i*2+1]) / pow(MFloat[2](dists[i*2], dists[i*2+1]), a) * sample
        out[i*2] = temp[0]
        out[i*2+1] = temp[1]
    comptime if num_speakers % 2 != 0:
        out[num_speakers - 1] = k * vec_weights[num_speakers - 1] / pow(dists[num_speakers - 1], a) * sample


    # out = MFloat[simd_out_size](blur_sq)

    return out



@always_inline
def dbap3D[
    num_speakers: Int, 
    simd_out_size: Int,
    speaker_positions: InlineArray[MFloat[4], num_speakers],
    weights: InlineArray[Float64, num_speakers]]
    (
        sample: Float64, 
        pos: MFloat[4], 
        blur: Float64 = 0.1, 
        rolloff: Float64 = 6
    ) -> MFloat[simd_out_size]:
    """
    Implements 3D DBAP (Distance Based Amplitude Panning). Pans a mono sample to N speakers of arbitrary positions in meters.
    For more on DBAP see the paper written by Trond Lossius, Pascal Baltazar, and Theo de la Hague.
    https://jamoma.org/publications/attachments/icmc2009-dbap-rev1.pdf .

    Parameters:
        num_speakers: The number of speakers as an integer.
        simd_out_size: Must be a power of 2 and greater than num_speakers.
        speaker_positions: The speaker positions as an InlineArray of Tuple[Float64] x/y/z coordinates in meters from a center position.
        weights: An InlineArray of Float64s (between 0.0 and 1.0) defining speaker weights for DBAP. Speaker weights allow for a source to be restricted to a subset of speakers. Speaker weights of 0.0 will disallow a source from playing through that speaker.

    Args:
        sample: Mono input sample.
        pos: X/Y position of the source from center in meters as a List[Float64].
        blur: Blurs the source, causing it to spread to more speakers. Values must be greater than or equal to 0, with 0 being the most localizable and values > 0 becoming less and less localizable. There is no limit to the amount of blur but values over 5 have diminishing returns.
        rolloff: The amplitude rolloff in dB, this must be > 0.0. 6.0 equals the inverse distance law for sound in an open field. Lower values will decrease the attenuation of the signal over distance, while larger values will increase this attenuation.
    
    Returns:
        MFloat[simd_out_size]: The panned output sample for each speaker.
    """
    comptime assert num_speakers <= simd_out_size, "num_speakers must be less than or equal to simd_out_size for dbap2D"
    comptime assert simd_out_size & (simd_out_size - 1) == 0, "simd_out_size must be a power of two for dbap2D"

    # Calculates the covariance of speaker distances 
    

    def variance_of_dists[comp_num_speakers: Int, comp_speaker_positions: InlineArray[MFloat[4], comp_num_speakers]]() -> Float64:
       
        var dists = MFloat[next_power_of_two(comp_num_speakers)](0.0)
        
        for i in range(comp_num_speakers):
            var dist = materialize[comp_speaker_positions]()[i] * materialize[comp_speaker_positions]()[i]
            var dist_from_center = sqrt(dist.reduce_add())

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
        var speaker = materialize[speaker_positions]()[i] - pos
        var xyz = speaker * speaker
        dists[i] = sqrt(xyz.reduce_add() + blur_sq)  

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

    var k = 1 / sqrt(denom)

    var out = MFloat[simd_out_size](0.0)
    for i in range(num_pairs):
        var temp = k * MFloat[2](vec_weights[i*2], vec_weights[i*2+1]) / pow(MFloat[2](dists[i*2], dists[i*2+1]), a) * sample
        out[i*2] = temp[0]
        out[i*2+1] = temp[1]
    comptime if num_speakers % 2 != 0:
        out[num_speakers - 1] = k * vec_weights[num_speakers - 1] / pow(dists[num_speakers - 1], a) * sample


    # out = MFloat[simd_out_size](blur_sq)

    return out






struct VBAP2D[num_speakers: Int = 4, simd_out_size: Int = 4](Movable, Copyable):
    """
    An implementation of VBAP (Vector Base Amplitude Panning). Pans a mono sample to a 2D array of N speakers of arbitrary positions in radians that are equidistant from the listener.
    For more on VBAP see the paper written by Ville Pulkki:
    https://www.audiolabs-erlangen.de/media/pages/resources/aps-w23/papers/935eb793db-1663358804/sap_Pulkki1997.pdf .
    """
    var speaker_positions: Array[Float64, Self.num_speakers]
    var speaker_unit_vectors: List[MFloat[2]]
    var speaker_pairs: List[List[Int]]
    var speaker_inverse_bases: List[Array[MFloat[2], 2]]
    
    
    def __init__(out self, imm speaker_positions: Array[Float64, Self.num_speakers]):
        """
        Initializes an instance of VBAP2D.

        Args:
            speaker_positions: A List of azimuth values in radians. The order of speakers given corresponds to the output channels ie. The speaker defined as the first element of the list will output on channel 0.
        """
        
        self.speaker_unit_vectors = []
        self.speaker_pairs = []
        self.speaker_inverse_bases = []
        
        self.speaker_positions = speaker_positions.copy()

        self.speaker_unit_vectors = self.calc_speaker_unit_vectors()
        self.speaker_pairs = self.calc_speaker_pairs()
        self.speaker_inverse_bases = self.calc_inverse_base()


        pass


    def calc_speaker_unit_vectors(mut self) -> List[MFloat[2]]:
        """
        Used internally to calculate the unit vectors of each speaker from a given azimuth.

        Returns:
            A list of unit vectors.
        """
        var speaker_vectors = List[MFloat[2]](length=self.num_speakers, fill=MFloat[2](0.0,0.0))
        

        for i in range(self.num_speakers):
            speaker_vectors[i] = MFloat[2](cos(self.speaker_positions[i]), sin(self.speaker_positions[i]))

            if speaker_vectors[i][0] < 0.0000001 and speaker_vectors[i][0] > -0.0000001:
                speaker_vectors[i][0] = 0

            if speaker_vectors[i][1] < 0.0000001 and speaker_vectors[i][1] > -0.0000001:
                speaker_vectors[i][1] = 0
            
        return speaker_vectors^
    
    def calc_inverse_base(mut self) -> List[Array[MFloat[2], 2]]:
        """
        Used internally to calculate the inverse bases of speaker matrices.

        Returns:
            A list of inverse base matrices.
        """
        var inverse_bases = List[Array[MFloat[2], 2]](length= self.num_speakers, fill=Array[MFloat[2], 2](fill=0.0))

        

        for i in range(self.num_speakers):
            var speaker_a = self.speaker_unit_vectors[self.speaker_pairs[i][0]] #[-2, 1]  [a, b]
            var speaker_b = self.speaker_unit_vectors[self.speaker_pairs[i][1]] #[1, 2]   [c, d]
            
            var determinant = (speaker_a[0] * speaker_b[1]) - (speaker_a[1] * speaker_b[0]) # ad - bc : -2 * 2 - 1 * 1 = -5

            var inverted_a = MFloat[2](speaker_b[1], -1 * speaker_a[1]) # [d, -b] = [2, -1]
            var inverted_b = MFloat[2](-1 * speaker_b[0], speaker_a[0]) # [-c, a] = [-1, -2]
            inverse_bases[i][0] = inverted_a/determinant
            inverse_bases[i][1] = inverted_b/determinant


        return inverse_bases^

    def index_of(mut self, list: Array[Float64, Self.num_speakers], element: Float64) -> Int:
        """
        Finds the index of the first appearance of an element in a list.

        Args:
            list: The list to search through.
            element: The element to search for.

        Returns:
            The index of the element.
        """
        var index : Int = 0
        for i in range(len(list)):
                if list[i] == element:
                    index = i
                    break
        
        return index
    
    def calc_speaker_pairs(mut self) -> List[List[Int]]:
        """
        Used internally by VBAP2D to determine speaker pairs.

        Returns:
            A list of speaker pairs.
        """
        var speaker_pairs = [[0 for _ in range(2)] for _ in range(self.num_speakers)]
        var unsorted_array = self.speaker_positions.copy()
        var sorted_array = self.speaker_positions.copy()
        sort(sorted_array)
        
        for i in range(self.num_speakers):
            speaker_pairs[i] = [self.index_of(unsorted_array, sorted_array[i]), self.index_of(unsorted_array, sorted_array[(i + 1) % self.num_speakers])]#List[Float64](i, i + 1)
        

        return speaker_pairs^
    
    def calc_gain_factors(mut self, source_vec: MFloat[2], mut active_pair: List[Int], mut active_gains: MFloat[2], source_az: Float64):
        """
        Internal method used for calculating gain factors of speaker pairs.

        Args:
            source_vec: The unit vector of the source.
            active_pair: The current active speaker pair.
            active_gains: The current active gains.
            source_az: The azimuth position of the source.
        """

        for speaker_pair in self.speaker_pairs:

            if source_az == self.speaker_positions[speaker_pair[0]]:
                for i in range(2):
                    active_pair[i] = speaker_pair[i]
                active_gains[0] = 1.0
                active_gains[1] = 0.0
                
                return
            elif source_az == self.speaker_positions[speaker_pair[1]]:
                for i in range(2):
                    active_pair[i] = speaker_pair[i]
                active_gains[0] = 0.0
                active_gains[1] = 1.0
                return
        
        
        var gain_factors = List[MFloat[2]](length=self.num_speakers, fill=0.0)
        var active_index : Int = 0
        
        for i in range(self.num_speakers):

            var speaker_a_vector = self.speaker_inverse_bases[i][0] # [c, d]
            var speaker_b_vector = self.speaker_inverse_bases[i][1] # [e, f]
            
            var speaker_a_product = source_vec[0] * speaker_a_vector # [ac, ad]
            var speaker_b_product = source_vec[1] * speaker_b_vector # [be, bf]

            var speaker_gains = MFloat[2](
                speaker_a_product[0] + speaker_b_product[0],
                speaker_a_product[1] + speaker_b_product[1],
            )
            
            gain_factors[i] = speaker_gains
        
        var largest_small_gain = 0
        for i in range(self.num_speakers):

            var smallest_gain = min(gain_factors[i][0], gain_factors[i][1])
            
            if gain_factors[i][0] >= 0.0 and gain_factors[i][1] >= 0.0:
                active_index = i 
                var scaled_gains = gain_factors[active_index] / (sqrt((gain_factors[active_index] * gain_factors[active_index]).reduce_add()))
                active_gains[0] = scaled_gains[0]
                active_gains[1] = scaled_gains[1]
                break
            elif smallest_gain > min(gain_factors[largest_small_gain][0], gain_factors[largest_small_gain][1]):
                largest_small_gain = i 
                active_index = i

        for i in range(2):
            active_pair[i] = self.speaker_pairs[active_index][i]
        var scaled_gains = gain_factors[active_index] / (sqrt((gain_factors[active_index] * gain_factors[active_index]).reduce_add()))
        active_gains[0] = scaled_gains[0]
        active_gains[1] = scaled_gains[1]
    
    def next(mut self, sample: Float64, az: Float64) -> MFloat[self.simd_out_size]:
        """
        Pans a mono sample based on a target azimuth.

        Args:
            sample: A mono sample to pan.
            az: The azimuth in radians.
        
        Returns:
            An MFLoat of the panned sample.
        """
        var active_speaker_pair : List[Int] = [0, 1]
        var active_gain_factors = MFloat[2](0.5)
        var source_vector = MFloat[2](cos(az), sin(az))
        
        self.calc_gain_factors(source_vector, active_speaker_pair, active_gain_factors, az)

        var gain_factors = MFloat[self.simd_out_size](0.0)
    
        gain_factors[Int(active_speaker_pair[0])] = active_gain_factors[0]
        gain_factors[Int(active_speaker_pair[1])] = active_gain_factors[1]
        
        return gain_factors * sample






from std.python import PythonObject
from std.python import Python

struct VBAP3D[num_speakers: Int, simd_out_size: Int](Movable, Copyable):
    """
    An implementation of 3D Vector Base Amplitude Panning.

    Parameters:
        num_speakers: The total number of speakers in the speaker array.
        simd_out_size: The SIMD vector out. Must be a power of two and greater than or equal to the number of speakers.
    """
    var speaker_triplets: List[Array[Int, 3]]
    var speaker_unit_vectors: Array[MFloat[4], Self.num_speakers]
    
    var speaker_inverse_bases: Array[Array[MFloat[4], 3], Self.num_speakers * 2]
    
    var active_triplet: Array[Int, 3]
    var prev_az: Float64
    var prev_ht: Float64
    var potential_gain_factors: Array[MFloat[4], Self.num_speakers * 2]
    var gain_factors: MFloat[Self.simd_out_size]
    var active_gain_factors: MFloat[4]
    var speaker_positions: Array[MFloat[2], Self.num_speakers]
    var active_index: Int 
    # var num_speakers: Int = num_speakers

    def __init__(out self, speaker_positions: Array[MFloat[2], Self.num_speakers]):
        """
        An implementation of VBAP.

        Args:
            speaker_positions: An array of azimuth/height pairs for the speakers. A speaker with azimuth 0 is placed directly left. A speaker with height 0 is placed on the same horizontal plane as the listeners head.
        """

        
        var scipy : PythonObject
        var np : PythonObject
        var py_list : PythonObject
        self.speaker_triplets : List[Array[Int,3]] = []
        self.speaker_unit_vectors = Array[MFloat[4], self.num_speakers](fill=MFloat[4](0.0))
        
        self.speaker_inverse_bases = Array[Array[MFloat[4], 3], self.num_speakers * 2](fill=[MFloat[4](0.0),MFloat[4](0.0), MFloat[4](0.0)])
        self.potential_gain_factors = Array[MFloat[4], self.num_speakers * 2](fill=MFloat[4](0.0))
        self.active_triplet = [0,1,2]
        self.prev_az = 7
        self.prev_ht = 7
        self.active_gain_factors = MFloat[4](0.0)
        self.speaker_positions = speaker_positions.copy()
        self.gain_factors = MFloat[self.simd_out_size](0.0)
        self.active_index = 0
        self.speaker_unit_vectors = self.calc_speaker_unit_vectors()
        
        
        # print("Unit vectors: ", self.speaker_unit_vectors)
        try:
            
           
            scipy = Python.import_module("scipy.spatial")
            np = Python.import_module("numpy")
            py_list = Python.list()
            
            for vec in self.speaker_unit_vectors:
                py_list.append([vec[0], vec[1], vec[2]])
            var qhull = scipy.ConvexHull(py_list)

            var bases = Python.list()
            var triplets = Python.list()
            
            
            for triplet in qhull.simplices:
                var mat = np.array([
                    py_list[triplet[0]],
                    py_list[triplet[1]],
                    py_list[triplet[2]]
                ])

                ## Determines if the matrix is coplanar with origin. If so, the speakers are removed.
                var check = mat[0][2] == 0.0 and mat[1][2] == 0.0 and mat[2][2] == 0.0
                
                if not check:
                    triplets.append(triplet)
                    
                    bases.append(np.linalg.pinv(mat).T)



            
            for i in range(len(triplets)):
                var triplet = triplets[i]
                var targ_inv = bases[i]
                var first = Int(py=triplet[0])
                var second = Int(py=triplet[1])
                var third = Int(py=triplet[2])
                
                
                for j in range(len(targ_inv)):
                    var vec = targ_inv[j]
                    
                    self.speaker_inverse_bases[i][j] = MFloat[4](Float64(py=vec[0]), Float64(py=vec[1]), Float64(py=vec[2]), 0.0)
                    
                        
                        
                
                self.speaker_triplets.append([first, second, third])
        
            # print("Speaker triplets calculated successfully")
        except ImportError:
            print("Error importing scipy ConvexHull")
            pass
        
        
        
    
    def calc_speaker_unit_vectors(mut self) -> Array[MFloat[4], Self.num_speakers]:
        """
        Used internally to calculate the unit vectors of each speaker from a given azimuth.

        Returns:
            A list of unit vectors.
        """
        var speaker_vectors = Array[MFloat[4], self.num_speakers](fill=MFloat[4](0.0))
        

        for i in range(self.num_speakers): 
            var new_vec = MFloat[4](cos(self.speaker_positions[i][0]) * cos(self.speaker_positions[i][1]), cos(self.speaker_positions[i][1]) * sin(self.speaker_positions[i][0]), sin(self.speaker_positions[i][1]), 0)
            
            speaker_vectors[i][0] = new_vec[0]
            speaker_vectors[i][1] = new_vec[1]
            speaker_vectors[i][2] = new_vec[2]

            if speaker_vectors[i][0] < 0.0000001 and speaker_vectors[i][0] > -0.0000001:
                speaker_vectors[i][0] = 0

            if speaker_vectors[i][1] < 0.0000001 and speaker_vectors[i][1] > -0.0000001:
                speaker_vectors[i][1] = 0

            if speaker_vectors[i][2] < 0.0000001 and speaker_vectors[i][2] > -0.0000001:
                speaker_vectors[i][2] = 0
            
        return speaker_vectors^

    
    @always_inline
    def calc_gain_factors(mut self, source_vec: MFloat[4], source_az: Float64, source_ht: Float64):
        """
        Internal method used for calculating gain factors of speaker pairs.

        Args:
            source_vec: The unit vector of the source.
            source_az: The azimuth position of the source in radians.
            source_ht: The height of the source in radians.
        """
        
        
        for speaker_triplet in self.speaker_triplets:

            if speaker_triplet[0] != -1:
                if source_az == self.speaker_positions[speaker_triplet[0]][0] and source_ht == self.speaker_positions[speaker_triplet[0]][1]:
                    self.active_triplet[0] = speaker_triplet[0]
                    self.active_triplet[1] = speaker_triplet[1]
                    self.active_triplet[2] = speaker_triplet[2]
                    self.active_gain_factors[0] = 1.0
                    self.active_gain_factors[1] = 0.0
                    self.active_gain_factors[2] = 0.0
                    
                    
                    return
                elif source_az == self.speaker_positions[speaker_triplet[1]][0] and source_ht == self.speaker_positions[speaker_triplet[1]][1]:
                    self.active_triplet[0] = speaker_triplet[0]
                    self.active_triplet[1] = speaker_triplet[1]
                    self.active_triplet[2] = speaker_triplet[2]
                    self.active_gain_factors[0] = 0.0
                    self.active_gain_factors[1] = 1.0
                    self.active_gain_factors[2] = 0.0
                    
                    return
                elif source_az == self.speaker_positions[speaker_triplet[2]][0] and source_ht == self.speaker_positions[speaker_triplet[2]][1]:
                    self.active_triplet[0] = speaker_triplet[0]
                    self.active_triplet[1] = speaker_triplet[1]
                    self.active_triplet[2] = speaker_triplet[2]
                    self.active_gain_factors[0] = 0.0
                    self.active_gain_factors[1] = 0.0
                    self.active_gain_factors[2] = 1.0
                    
                    return
        
        
        var smallest_gain = -10000.0
        
        
        for i in range(len(self.speaker_triplets)):
        

            self.potential_gain_factors[i][0] = (source_vec * self.speaker_inverse_bases[i][0]).reduce_add() 
            self.potential_gain_factors[i][1] = (source_vec * self.speaker_inverse_bases[i][1]).reduce_add() 
            self.potential_gain_factors[i][2] = (source_vec * self.speaker_inverse_bases[i][2]).reduce_add() 
            
        
            
            
            var largest_small_gain = min(self.potential_gain_factors[i][0], self.potential_gain_factors[i][1], self.potential_gain_factors[i][2])
            if self.potential_gain_factors[i][0] > 0.0 and self.potential_gain_factors[i][1] > 0.0 and self.potential_gain_factors[i][2] > 0.0:
                self.active_index = i
                
                var scaled_gains = self.potential_gain_factors[self.active_index] / (sqrt((self.potential_gain_factors[self.active_index] * self.potential_gain_factors[self.active_index]).reduce_add()))
                self.active_triplet[0] = self.speaker_triplets[self.active_index][0]
                self.active_triplet[1] = self.speaker_triplets[self.active_index][1]
                self.active_triplet[2] = self.speaker_triplets[self.active_index][2]
                
                self.active_gain_factors = scaled_gains.cast[DType.float64]()
                
                return

            elif  smallest_gain < largest_small_gain:
                smallest_gain = largest_small_gain
                self.active_index = i
        
        
        # Handle all <= 0 values gracefully. Occurs when a source vector points too far from an array.
        if self.potential_gain_factors[self.active_index][0] <= 0.0 and self.potential_gain_factors[self.active_index][1] <= 0.0 and self.potential_gain_factors[self.active_index][2] <= 0.0:
            return
        
        for i in range(3):
            if self.potential_gain_factors[self.active_index][i] < 0.0:
                self.potential_gain_factors[self.active_index][i] = 0.0

        self.active_triplet[0] = self.speaker_triplets[self.active_index][0]
        self.active_triplet[1] = self.speaker_triplets[self.active_index][1]
        self.active_triplet[2] = self.speaker_triplets[self.active_index][2]
        
        var scaled_gains = self.potential_gain_factors[self.active_index] / (sqrt((self.potential_gain_factors[self.active_index] * self.potential_gain_factors[self.active_index]).reduce_add()))
        self.active_gain_factors = scaled_gains.cast[DType.float64]()
    
    @always_inline
    def next(mut self, sample: Float64, az: Float64, ht: Float64) -> MFloat[Self.simd_out_size]:
        """
        Pans a mono sample based on a target azimuth and height.

        Args:
            sample: A mono sample to pan.
            az: The azimuth in radians. 0.0 is directly ahead, positive values move clockwise.
            ht: The height of the source in radians. 0.0 is on the same horizontal plane as the listener's ears. Positve values are above the listener, negative values are below. From -1pi radians (directly below) to 1pi radians (directly above).

        Returns:
            An MFloat of the panned sample. 
        """
        

        comptime two_pi = 2 * pi
        
       
        if az != self.prev_az or ht != self.prev_ht:
            
            
            var source_vector = SIMD[DType.float64, 4](cos(az) * cos(ht), cos(ht) * sin(az), sin(ht), 0.0)
            
            self.calc_gain_factors(source_vector, az, ht)
            self.prev_az = az
            self.prev_ht = ht
        
        var gain_factors = MFloat[self.simd_out_size](0.0)
    
        gain_factors[Int(self.active_triplet[0])] = self.active_gain_factors[0]
        gain_factors[Int(self.active_triplet[1])] = self.active_gain_factors[1]
        gain_factors[Int(self.active_triplet[2])] = self.active_gain_factors[2]
        
        return gain_factors * sample
