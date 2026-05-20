
from mmm_audio import *

comptime window_size = 4096
comptime hop_size = window_size // 2

# This corresponds to the user defined BufferedProcess.
struct FFTLowPass[window_size: Int](BufferedProcessable):
    var world: World
    var m: Messenger
    var bin: Int
    var fft: RealFFT[]
    # var complex: List[ComplexFloat64]
    var mags: List[Float64]
    var phases: List[Float64]

    def __init__(out self, world: World):
        self.world = world
        self.bin = (Self.window_size // 2) + 1
        self.m = Messenger(self.world)
        self.fft = RealFFT(Self.window_size)
        # self.complex = List[ComplexFloat64](length=(Self.window_size // 2) + 1, fill=ComplexFloat64(0.0,0.0))
        self.mags = List[Float64](length=(Self.window_size // 2) + 1, fill=0.0)
        self.phases = List[Float64](length=(Self.window_size // 2) + 1, fill=0.0)

    def get_messages(mut self) -> None:
        self.m.update("bin", self.bin) 

    def next_window(mut self, mut input: List[Float64]) -> None:
        # self.fft.fft(input,self.complex)
        self.fft.fft(input,self.mags,self.phases)
        for i in range(self.bin,(Self.window_size // 2) + 1):
            self.mags[i] *= 0.0
        # self.fft.ifft(self.complex,input)
        self.fft.ifft(self.mags,self.phases,input)

# User's Synth
struct TestBufferedProcessFFT(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var fftlowpass: BufferedProcess[FFTLowPass[window_size],True,WindowType.sine,WindowType.sine]
    var m: Messenger
    var ps: List[Print]
    var which: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.fftlowpass = BufferedProcess[FFTLowPass[window_size],True,WindowType.sine,WindowType.sine](self.world,process=FFTLowPass[window_size](self.world),window_size=window_size,hop_size=hop_size)
        self.m = Messenger(self.world)
        self.ps = List[Print](length=2,fill=Print(self.world))
        self.which = 0

    def next(mut self) -> SIMD[DType.float64,2]:
        i = self.playBuf.next(self.buffer, 1.0, True)  # Read samples from the buffer
        o = self.fftlowpass.next(i)
        return SIMD[DType.float64,2](o,o)

