from mmm_audio import *

comptime fftsize: Int = 1024
comptime hopsize: Int = 512
comptime num_coeffs: Int = 13
comptime num_bands: Int = 40
comptime min_freq: Float64 = 20.0
comptime max_freq: Float64 = 20000.0

struct MFCCTestSuite(FFTProcessable):
    var mfcc: MFCC
    var data: List[List[Float64]]

    def __init__(out self, w: World):
        self.mfcc = MFCC[](w[].sample_rate,num_coeffs=num_coeffs,num_bands=num_bands,min_freq=min_freq,max_freq=max_freq,fft_size=fftsize)
        self.data = List[List[Float64]]()

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]):
        self.mfcc.next_frame(mags, phases)
        self.data.append(self.mfcc.coeffs.copy())

def main() raises:
    environment = alloc[Environment](1)
    environment.init_pointee_move(Environment())
    
    w = alloc[MMMWorld](1)
    w.init_pointee_move(MMMWorld(44100, environment))
    mfcc_ts = MFCCTestSuite(w)
    fftprocess = FFTProcess[MFCCTestSuite,False,WindowType.hann](w, mfcc_ts^, window_size=fftsize, hop_size=hopsize)
    buf = Buffer.load("resources/Shiverer.wav")
    for i in range(buf.num_frames):
        _ = fftprocess.next(buf.data[0][i])

    print("Number of frames processed: ", len(fftprocess.buffered_process.process.process.data))

    with open("testing_mmm_audio/validation/mojo_results/mfcc_mojo_results.csv", "w") as f:
        f.write("windowsize," + String(fftsize) + "\n")
        f.write("hopsize," + String(hopsize) + "\n")
        f.write("num_coeffs," + String(num_coeffs) + "\n")
        f.write("num_bands," + String(num_bands) + "\n")
        f.write("min_freq," + String(min_freq) + "\n")
        f.write("max_freq," + String(max_freq) + "\n")
        f.write("Coefficients\n")
        for i, frame in enumerate(fftprocess.buffered_process.process.process.data):
            if i > 0:
                f.write("\n")
            for j, coeff in enumerate(frame):
                if j > 0:
                    f.write(",")
                f.write(String(coeff))
