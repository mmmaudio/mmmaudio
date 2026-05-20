
from mmm_audio import *

comptime windowsize: Int = 1024
comptime hopsize: Int = 512

# User defined struct that just operates on two lists
# and therefore is useful for operating on mags and phases.
# Things like this can basically be used like the PV_
# pattern in SuperCollider, stringing together a bunch of
# operations on the mags and phases.
struct BinScramble(Copyable,Movable):
    var swaps: List[Tuple[Int,Int]]
    var nbins: Int
    var nscrambles: Int
    var scramble_range: Int

    def __init__(out self, nbins: Int, nscrambles: Int):
        self.nbins = nbins
        self.nscrambles = nscrambles
        self.swaps = List[Tuple[Int,Int]]()
        self.scramble_range = 10
        self.new_swaps()

    def new_swaps(mut self) -> None:
        self.swaps.clear()
        for _ in range(self.nscrambles):
            i = rrand(0, self.nbins - 1)
            minj = max(i - self.scramble_range,0)
            maxj = min(i + self.scramble_range, self.nbins - 1)
            j = rrand(minj, maxj)
            self.swaps.append((Int(i),Int(j)))

    def next(mut self, mut magnitudes: List[Float64], mut phases: List[Float64]) -> None:
        for (i,j) in self.swaps:
            temp_mag = magnitudes[i]
            magnitudes[i] = magnitudes[j]
            magnitudes[j] = temp_mag
            temp_phase = phases[i]
            phases[i] = phases[j]
            phases[j] = temp_phase

# User defined struct that implements FFTProcessable
struct ScrambleAndLowPass[window_size: Int = 1024](FFTProcessable):
    var world: World
    var m: Messenger
    var bin: Int
    var bin_scramble: BinScramble

    def __init__(out self, world: World):
        self.world = world
        self.bin = (self.window_size // 2) + 1
        self.m = Messenger(self.world)
        self.bin_scramble = BinScramble(nbins=(self.window_size // 2) + 1, nscrambles=20)

    def get_messages(mut self) -> None:
        self.m.update("lpbin", self.bin) 
        self.m.update("nscrambles", self.bin_scramble.nscrambles) 
        self.m.update("scramble_range", self.bin_scramble.scramble_range)
        if self.m.notify_trig("rescramble"):
            self.bin_scramble.new_swaps()

    def next_frame(mut self, mut magnitudes: List[Float64], mut phases: List[Float64]) -> None:
        self.bin_scramble.next(magnitudes,phases)
        for i in range(self.bin,(self.window_size // 2) + 1):
            magnitudes[i] *= 0.0

# User's Main Synth
struct TestFFTProcess(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var onsets: SpectralFluxOnsets
    var fftlowpass: FFTProcess[ScrambleAndLowPass[windowsize],True,WindowType.hann,WindowType.hann]
    var m: Messenger
    var ps: List[Print]
    var which: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world) 
        self.onsets = SpectralFluxOnsets(self.world,(windowsize//2) + 1)
        self.onsets.thresh = 67
        self.onsets.min_slice_len = 0.3
        self.fftlowpass = FFTProcess[ScrambleAndLowPass[windowsize],True,WindowType.hann,WindowType.hann](self.world,process=ScrambleAndLowPass[windowsize](self.world),window_size=windowsize,hop_size=hopsize)
        self.m = Messenger(self.world)
        self.ps = List[Print](length=2,fill=Print(self.world))
        self.which = 0

    def next(mut self) -> SIMD[DType.float64,2]:

        self.m.update("onsets_thresh", self.onsets.thresh)
        self.m.update("onsets_min_slice_len", self.onsets.min_slice_len)

        input = self.playBuf.next(self.buffer, 1.0, True)  # Read samples from the buffer
        onset = self.onsets.next(input)
        if onset:
            self.fftlowpass.buffered_process.process.process.bin_scramble.new_swaps()
        out = self.fftlowpass.next(input)
        return SIMD[DType.float64,2](out,out)

