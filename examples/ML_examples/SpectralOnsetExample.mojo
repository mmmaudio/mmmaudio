from mmm_audio import *

comptime fft_size: Int = 1024

struct SpectralOnsetExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var onsets: OnsetDetection
    var m: Messenger
    var impulse_vol: Float64
    var onsetcounter: Int64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world)
        self.onsets = OnsetDetection(self.world, OnsetMetric.complex_domain, 0.5, 0.1, fft_size, fft_size // 2)
        self.m = Messenger(self.world)
        self.impulse_vol = 0.5
        self.onsetcounter = 0

    def next(mut self) -> MFloat[2]:
        
        self.m.update("thresh", self.onsets.threshold) 
        self.m.update("impulse_vol", self.impulse_vol)
        self.m.update("debounce", self.onsets.debounce) 
        
        # play the audio file
        var audio = self.playBuf.next(self.buffer)
        
        # analyze for onsets
        _ = self.onsets.next(audio)
        
        # update threshold

        if self.onsets.state:
            print("onset",self.onsetcounter)
            self.onsetcounter += 1
        
        # generate impulse when onset detected
        var impulse = self.impulse_vol if self.onsets.state else 0.0
        
        # left channel: audio, right channel: impulses
        return MFloat[2](audio, impulse)
