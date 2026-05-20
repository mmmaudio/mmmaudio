
from mmm_audio import *
from std.math import tau

comptime windowsize: Int = 1024
comptime hopsize: Int = windowsize // 4

struct RTPGHIWindow(FFTProcessable):
    var world: World
    var m: Messenger
    var which: Int
    var rtpghi: RTPGHI

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)
        self.which = 0
        self.rtpghi = RTPGHI(windowsize,hopsize)

    def get_messages(mut self) -> None:
        self.m.update("which", self.which) 

    def next_frame(mut self, mut magnitudes: List[Float64], mut phases: List[Float64]) -> None:
        if self.which == 1:
            # random phases
            for ref p in phases:
                p = random_float64(tau)
        elif self.which == 2:
            # rtpghi
            self.rtpghi.process_frame(magnitudes,phases)
        # elif which == 0, do nothing, just return the input magnitudes and phases
        

struct RTPGHIExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var fftp: FFTProcess[RTPGHIWindow,True,WindowType.hann,WindowType.hann]

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.fftp = FFTProcess[RTPGHIWindow,True,WindowType.hann,WindowType.hann](self.world,process=RTPGHIWindow(self.world),window_size=windowsize,hop_size=hopsize)

    def next(mut self) -> SIMD[DType.float64,2]:
        input = self.playBuf.next(self.buffer)  # Read samples from the buffer
        out = self.fftp.next(input)
        return out

