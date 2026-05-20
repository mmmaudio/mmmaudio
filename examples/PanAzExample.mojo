from mmm_audio import *

struct PanAz_Synth(Movable, Copyable):
    var world: World  
    var osc: Osc[1]
    var freq: Float64

    var pan_osc: Phasor[1]
    var num_speakers: Int
    var width: Float64
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc(self.world)
        self.freq = 440.0

        self.pan_osc = Phasor(self.world)
        self.num_speakers = 7  # default to 7 speakers
        self.width = 2.0
        self.messenger = Messenger(self.world)

    def next(mut self) -> MFloat[8]:
        self.messenger.update("freq", self.freq) 
        self.messenger.update("num_speakers", self.num_speakers)
        self.messenger.update("width", self.width) 

        # PanAz needs to be given a SIMD size that is a power of 2, in this case [8], but the speaker size can be anything smaller than that
        panned = pan_az[8](self.osc.next(self.freq, osc_type=2), self.pan_osc.next(0.1), self.num_speakers, self.width) * 0.1

        if self.num_speakers == 2:
            return MFloat[8](panned[0], panned[1], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        else:
            return MFloat[8](panned[0], panned[2], panned[1], 0.0, panned[6], panned[3], panned[5], panned[4])


# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct PanAzExample(Movable, Copyable):
    var world: World
    var synth: PanAz_Synth

    def __init__(out self, world: World):
        self.world = world
        self.synth = PanAz_Synth(self.world)

    def next(mut self) -> MFloat[8]:

        sample = self.synth.next()  # Get the next sample from the synth

        # the output will pan to the number of channels available 
        # if there are fewer than 5 channels, only those channels will be output
        return sample  # Return the combined output samples