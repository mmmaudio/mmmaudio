"""Spectral Crest Unit Test."""

from mmm_audio import *

comptime windowsize: Int = 1024
comptime hopsize: Int = 512

struct Analyzer(BufferedProcessable):
    var world: World
    var fft: RealFFT[]
    var crest_values: List[Float64]
    var sample_rate: Float64

    def __init__(out self, world: World, sample_rate: Float64):
        self.world = world
        self.fft = RealFFT[](windowsize)
        self.crest_values = List[Float64]()
        self.sample_rate = sample_rate

    def next_window(mut self, mut buffer: List[Float64]):
        self.fft.fft(buffer)
        val = SpectralCrest.from_mags(self.fft.mags, self.sample_rate)
        self.crest_values.append(val)
        return

def main():
    world_info = alloc[WorldInfo](1)
    world_info.init_pointee_move(WorldInfo())
    
    w = alloc[MMMWorld](1)
    w.init_pointee_move(MMMWorld(44100, world_info))

    buffer = Buffer.load("resources/Shiverer.wav")
    playBuf = Play(w)
    analyzer = BufferedProcess[Analyzer,False,WindowType.hann](w, Analyzer(w, w[].sample_rate), window_size=windowsize, hop_size=hopsize)

    for _ in range(buffer.num_frames):
        sample = playBuf.next(buffer)
        _ = analyzer.next(sample)

    pth = "testing_mmm_audio/validation/mojo_results/spectral_crest_mojo_results.csv"
    try:
        with open(pth, "w") as f:
            f.write("windowsize,",windowsize,"\n")
            f.write("hopsize,",hopsize,"\n")
            f.write("Crest\n")
            for i in range(len(analyzer.process.crest_values)):
                f.write(String(analyzer.process.crest_values[i]) + "\n")
        print("Wrote results to ", pth)
    except err:
        print("Error writing to file: ", err)
