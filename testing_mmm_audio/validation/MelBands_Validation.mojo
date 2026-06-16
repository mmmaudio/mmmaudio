from mmm_audio import *

comptime fftsize: Int = 1024
comptime hopsize: Int = 512
comptime nbands: Int = 10

struct MelBandsTestSuite(FFTProcessable):
    var melbands: MelBands[]
    var data: List[List[Float64]]

    def __init__(out self, w: World):
        self.melbands = MelBands[](w[].sample_rate,num_bands=nbands,min_freq=20.0,max_freq=20000.0,fft_size=fftsize)
        self.data = List[List[Float64]]()

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]):
        self.melbands.next_frame(mags, phases)
        self.data.append(self.melbands.bands.copy())

def main() raises:
    world_info = alloc[WorldInfo](1)
    world_info.init_pointee_move(WorldInfo())
    
    w = alloc[MMMWorld](1)
    w.init_pointee_move(MMMWorld(48000, world_info))
    
    mbts = MelBandsTestSuite(w)
    fftprocess = FFTProcess[MelBandsTestSuite,False,WindowType.hann](w,mbts^, window_size=fftsize, hop_size=hopsize)
    buf = Buffer.load("resources/Shiverer.wav")
    for i in range(buf.num_frames):
        _ = fftprocess.next(buf.data[0][i])
    
    print("Number of frames processed: ", len(fftprocess.buffered_process.process.process.data))

    with open("testing_mmm_audio/validation/mojo_results/mel_bands_mojo.csv", "w") as f:
        for i,frame in enumerate(fftprocess.buffered_process.process.process.data):
            if i > 0:
                f.write("\n")
            for j,band in enumerate(frame):
                if j > 0:
                    f.write(",")
                f.write(String(band))