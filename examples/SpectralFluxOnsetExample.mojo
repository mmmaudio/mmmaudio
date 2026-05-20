from mmm_audio import *

comptime fft_size: Int = 1024

struct SpectralFluxOnsetExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var onsets: SpectralFluxOnsets
    var m: Messenger
    var impulse_vol: Float64
    var onsetcounter: Int64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world)
        self.onsets = SpectralFluxOnsets(self.world,(fft_size//2) + 1)
        self.onsets.thresh = 67.0
        self.onsets.min_slice_len = 0.3
        self.m = Messenger(self.world)
        self.impulse_vol = 0.5
        self.onsetcounter = 0

    def next(mut self) -> MFloat[2]:
        
        self.m.update("thresh", self.onsets.thresh) 
        self.m.update("impulse_vol", self.impulse_vol)
        self.m.update("minSliceLength", self.onsets.min_slice_len) 
        
        # play the audio file
        audio = self.playBuf.next(self.buffer)
        
        # analyze for onsets
        _ = self.onsets.next(audio)
        
        # update threshold

        if self.onsets.state:
            print("onset",self.onsetcounter)
            self.onsetcounter += 1
        
        # generate impulse when onset detected
        impulse = self.impulse_vol if self.onsets.state else 0.0
        
        # left channel: audio, right channel: impulses
        return MFloat[2](audio, impulse)
