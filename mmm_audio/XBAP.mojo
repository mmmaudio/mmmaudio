
from std.math import sqrt, floor, cos, pi, sin
from std.sys import simd_width_of
from std.algorithm import vectorize


struct SpeakerArray2D[num_speakers: Int, speaker_positions: InlineArray[MFloat[2], num_speakers], weights: InlineArray[Float64, num_speakers]](Movable, Copyable):
    """
    Defines an array of speakers of arbitrary length and positions. Positions are a given as tuples of (x,y) in meters from center.
    """


    def __init__(out self):
        """
        Initialize SpeakerArray.
        """
        pass
        


struct SpeakerArrayAZ[](Movable, Copyable):
    """
    Defines an array of speakers of abitrary length and positions. Positions are given as tuples of (az, height) in radians where 0 is directly in front of the listener.
    """
    var speaker_positions: List[Tuple[Float64, Float64]]

    def __init__(out self, speaker_positions: List[Tuple[Float64, Float64]]):

        self.speaker_positions = speaker_positions.copy()

        pass
            


        


def dbap2D[simd_out_size: Int = 4](sample: Float64, pos: List[Float64], mut blur: Float64, speakers: SpeakerArray2D, rolloff: Float64 = 6) -> MFloat[simd_out_size]:
    """
    Implements DBAP (Distance Based Amplitude Panning). Takes in a mono signal and produces a signal of arbitrary channel size.
    """

    amps = MFloat[simd_out_size](0.0)
    blur = pow(blur, 2)
    # Calculates the a coefficient given a 6 db rolloff
    a = rolloff/6.02059991328

   
    sum : Float64 = 0.0
    dists : InlineArray[Float64, simd_out_size] = [0.0]

    # Calculates the k coefficient and gets distances for every speaker from the source
    for i in range(len(speakers.speaker_positions)):
        speaker = speakers.speaker_positions[i]
        weight = speakers.weights[i]
        x = pow(speaker[0] - pos[0], 2)
        y = pow(speaker[1] - pos[1], 2)
        dists[i] = sqrt(x + y)
        sum += (weight * weight)/pow(dists[i], 2 * a)
    
    k: Float64 = 1/sum

    for i in range(len(dists)):

        amps[i] = (k * speakers.weights[i])/pow(dists[i], a) * sample
        
        

    return amps
   