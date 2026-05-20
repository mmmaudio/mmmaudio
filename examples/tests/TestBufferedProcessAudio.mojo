
from mmm_audio import *

###########################################################
#                   Test BufferedProcess                  #
###########################################################
# This test creates a BufferedProcess that multiplies
# the input samples by a factor received from a Messenger.
# Because no windowing is applied and there is no overlap
# (hop_size == window_size), the output samples should
# just be the input samples multiplied by the factor.

# This corresponds to the user defined BufferedProcess.
struct BufferedMultiply(BufferedProcessable):
    var world: World
    var m: Messenger
    var vol: Float64

    def __init__(out self, world: World):
        self.world = world
        self.vol = 0.0
        self.m = Messenger(self.world)

    def get_messages(mut self) -> None:
        self.m.update("vol", self.vol) 

    def next_window(self, mut input: List[Float64]) -> None:
        amp = dbamp(self.vol)
        for i in range(len(input)):
            input[i] *= amp

# User's Synth
struct TestBufferedProcessAudio(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var my_buffered_mul: BufferedProcess[BufferedMultiply,True,WindowType.rect,WindowType.hann]
    var m: Messenger
    var ps: List[Print]
    var which: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        var multiply_process = BufferedMultiply(self.world)
        self.my_buffered_mul = BufferedProcess[BufferedMultiply,True,WindowType.rect,WindowType.hann](self.world,process=multiply_process^,window_size=1024,hop_size=512)
        self.m = Messenger(self.world)
        self.ps = List[Print](length=2,fill=Print(self.world))
        self.which = 0

    def next(mut self) -> SIMD[DType.float64,2]:
        i = self.playBuf.next(self.buffer,1.0)  # Read samples from the buffer
        v = self.my_buffered_mul.process.vol
        self.ps[0].next(v,"vol")
        o = self.my_buffered_mul.next(i)
        # self.ps[0].next(i[0],"input")
        self.ps[1].next(o[0],"output")
        self.m.update("which", self.which) 
        o = select(self.which,i,o)
        return SIMD[DType.float64,2](o,o)

