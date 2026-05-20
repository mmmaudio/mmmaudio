
from mmm_audio import *

comptime windowsize: Int = 1024
comptime hopsize: Int = windowsize // 4

struct FFTScrambleWindow(FFTProcessable):
    var world: World
    var swaps: List[Tuple[Int,Int]]
    var nbins: Int
    var nscrambles: Int
    var scramble_range: Int
    var m: Messenger

    def next_frame(mut self, mut magnitudes: List[Float64], mut phases: List[Float64]) -> None:
        for (i,j) in self.swaps:
            temp_mag = magnitudes[i]
            magnitudes[i] = magnitudes[j]
            magnitudes[j] = temp_mag
            temp_phase = phases[i]
            phases[i] = phases[j]
            phases[j] = temp_phase

    def __init__(out self, world: World, nbins: Int):
        self.world = world
        self.nbins = nbins
        self.nscrambles = 30
        self.swaps = List[Tuple[Int,Int]]()
        self.scramble_range = 10
        self.m = Messenger(self.world)
        self.scramble()

    def scramble(mut self) -> None:
        self.swaps.clear()
        for _ in range(self.nscrambles):
            i_f = linlin(random_float64() ** 3, 0.0, 1.0, 0.0, Float64(self.nbins - 1))
            i = Int(i_f)
            minj = max(i - self.scramble_range,0)
            maxj = min(i + self.scramble_range, self.nbins - 1)
            j_f = rrand(minj, maxj)
            j = Int(j_f)
            self.swaps.append((i,j))
    
    def get_messages(mut self) -> None:
        self.m.update("n_scrambles", self.nscrambles)
        self.m.update("scramble_range", self.scramble_range)
        if self.m.notify_trig("scramble"):
            self.scramble()

struct FFTScramble(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var fft_scramble: FFTProcess[FFTScrambleWindow]
    
    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.fft_scramble = FFTProcess[FFTScrambleWindow](self.world,process=FFTScrambleWindow(self.world,(windowsize//2)+1),window_size=windowsize,hop_size=hopsize)
        
    def next(mut self) -> SIMD[DType.float64,2]:
        input = self.playBuf.next(self.buffer)  # Read samples from the buffer
        out = self.fft_scramble.next(input)
        return SIMD[DType.float64,2](out,out)