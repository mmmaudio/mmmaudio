from mmm_audio import *

# this really should have a window size of 8192 or more, but the numpy FFT seems to barf on this
comptime window_size = 2048
comptime hop_size = window_size // 2

struct BinDelaysWindow[window_size: Int](FFTProcessable):
    var world: World
    var delays: List[Delay[2, Interp.none]]
    var delay_times: List[Int]
    var feedback: List[Float64]
    var m: Messenger
    var one_samp: Float64


    def __init__(out self, world: World):
        self.world = world
        self.one_samp = 1.0 / self.world[].sample_rate
        self.delays = [Delay[2, Interp.none](world, self.one_samp*200) for _ in range(0, Self.window_size // 2 + 1)]
        self.delay_times = List[Int]()
        self.feedback = List[Float64]()
        vals = [random_float64(0.0, 1.0) for _ in range(5)]
        for _ in range(0, Self.window_size // 2 + 1):
            self.delay_times.append(4)
            self.feedback.append(0.5)
        self.m = Messenger(world)
        self.one_samp = 1.0 / self.world[].sample_rate

    def get_messages(mut self):
        self.m.update("delay_times", self.delay_times)
        self.m.update("feedback", self.feedback) 

    def next_frame(mut self, mut mags: List[Float64], mut phases: List[Float64]):
        for i in range(0, len(mags)):
            read = self.delays[i].read(Float64(self.delay_times[i]) * self.one_samp)
            write = MFloat[2](mags[i] + read[0] * self.feedback[i], phases[i] + read[1] * self.feedback[i])
            self.delays[i].write(write)
            mags[i] = read[0]
            phases[i] = read[1]



# User's Synth
struct FFTBinDelays(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var fft_bin_delays: FFTProcess[BinDelaysWindow[window_size],True,WindowType.sine,WindowType.sine]
    var m: Messenger
    var dur_mult: Float64
    var play: Play

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")

        self.fft_bin_delays = FFTProcess[
                BinDelaysWindow[window_size],
                True,
                WindowType.sine,
                WindowType.sine
            ](self.world,process=BinDelaysWindow[window_size](self.world), window_size=window_size, hop_size=hop_size)

        self.m = Messenger(self.world)
        self.dur_mult = 40.0
        self.play = Play(self.world)

    def next(mut self) -> SIMD[DType.float64,2]:
        sound = self.play.next(self.buffer)
        o = self.fft_bin_delays.next(sound)
        return o

