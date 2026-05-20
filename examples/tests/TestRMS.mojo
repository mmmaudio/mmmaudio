
from mmm_audio import *

# User's Synth
struct TestRMS(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var bi: BufferedProcess[RMS,False,WindowType.rect]
    var m: Messenger
    var printer: Print
    var vol: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        rms = RMS()
        # samplerate of 48000 50 ms for the RMS = 2400 samples
        self.bi = BufferedProcess[RMS,False,WindowType.rect](self.world,process=rms^,window_size=2400,hop_size=2400)
        self.m = Messenger(self.world)
        self.printer = Print(self.world)
        self.vol = 0.0

    def next(mut self) -> SIMD[DType.float64,2]:
        self.m.update("vol", self.vol) 
        
        i = self.playBuf.next(self.buffer, 1.0, True)  # Read samples from the buffer
        
        i *= dbamp(self.vol)
        
        _ = self.bi.next(i)
        analysis_vol = ampdb(self.bi.process.rms)
        self.printer.next(analysis_vol, "RMS dB")
        return SIMD[DType.float64,2](i,i)

