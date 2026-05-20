from mmm_audio import *

comptime window_size = 2048
comptime hop_size = window_size // 2

struct PaulStretchWindow[window_size: Int](FFTProcessable):
    var world: World
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)

    def get_messages(mut self) -> None:
        pass

    def next_stereo_frame(mut self, mut mags: List[MFloat[2]], mut phases: List[MFloat[2]]) -> None:
        for ref p in phases:
            p = MFloat[2](random_float64(0.0, 2.0 * 3.141592653589793), random_float64(0.0, 2.0 * 3.141592653589793))

# User's Synth
struct PaulStretch(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    var phasor: Phasor[]
    var paul_stretch: FFTProcess[PaulStretchWindow[window_size],ifft=True,input_window_shape=WindowType.sine,output_window_shape=WindowType.sine]
    var m: Messenger
    var dur_mult: Float64

    def __init__(out self, world: World):
        self.world = world
        self.buffer = SIMDBuffer.load("resources/Shiverer.wav")
        self.phasor = Phasor(self.world)
        self.paul_stretch = FFTProcess[
                PaulStretchWindow[window_size],
                ifft=True,
                input_window_shape=WindowType.sine,
                output_window_shape=WindowType.sine
            ](self.world,process=PaulStretchWindow[window_size](self.world),window_size=window_size,hop_size=hop_size)

        self.m = Messenger(self.world)
        self.dur_mult = 40.0

    def next(mut self) -> SIMD[DType.float64,2]:
        self.m.update("dur_mult", self.dur_mult)
        speed = 1.0/self.buffer.duration * (1.0/self.dur_mult)
        phase = self.phasor.next(speed)
        o = self.paul_stretch.next_from_stereo_buffer(self.buffer, phase)
        return o

