"""Spectral Centroid Unit Test."""

from mmm_audio import *

comptime windowsize: Int = 1024
comptime hopsize: Int = 512

struct Analyzer(BufferedProcessable):
    var world: World
    var fft: RealFFT[]
    var centroids: List[Float64]
    var sample_rate: Float64

    def __init__(out self, world: World, sample_rate: Float64):
        self.world = world
        self.fft = RealFFT[](windowsize)
        self.centroids = List[Float64]()
        self.sample_rate = sample_rate

    def next_window(mut self, mut buffer: List[Float64]):
        self.fft.fft(buffer)
        # Passing in the "self.sample_rate" here instead of using the world sample rate
        # because the world was causing issues. Somehow the pointer was getting losses or something.
        val = SpectralCentroid.from_mags(self.fft.mags, self.sample_rate)
        self.centroids.append(val)
        return

def main():
    environment = alloc[Environment](1)
    environment.init_pointee_move(Environment())
    
    w = alloc[MMMWorld](1)
    w.init_pointee_move(MMMWorld(44100, environment))

    buffer = Buffer.load("resources/Shiverer.wav")
    playBuf = Play(w)
    analyzer = BufferedProcess[Analyzer,False,WindowType.hann](w, Analyzer(w, w[].sample_rate), window_size=windowsize, hop_size=hopsize)

    for _ in range(buffer.num_frames):
        sample = playBuf.next(buffer)
        _ = analyzer.next(sample)
    
    pth = "testing_mmm_audio/validation/mojo_results/spectral_centroid_mojo_results.csv"
    try:
        with open(pth, "w") as f:
            f.write("windowsize,",windowsize,"\n")
            f.write("hopsize,",hopsize,"\n")
            f.write("Centroid\n")
            for i in range(len(analyzer.process.centroids)):
                f.write(String(analyzer.process.centroids[i]) + "\n")
        print("Wrote results to ", pth)
    except err:
        print("Error writing to file: ", err)
