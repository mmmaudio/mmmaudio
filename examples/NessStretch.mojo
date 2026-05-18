from mmm_audio import *

comptime iterations = 2

struct NessStretchWindow[num_iterations: Int=1](FFTProcessable):
    var world: World
    var window_size: Int
    var hop_size: Int
    var m: Messenger
    var lrbp_window: List[Float64]
    var previous_phases: List[MFloat[2]]
    var previous_mags: List[MFloat[2]]
    var low_cut: Int
    var high_cut: Int
    var m_s: List[Float64]

    def __init__(out self, world: World, window_size: Int, hop_size: Int, low_cut: Int, high_cut: Int):
        self.world = world
        self.window_size = window_size
        self.hop_size = hop_size
        self.m = Messenger(self.world)
        lrhp_window = create_linkwitz_riley_fft_filter(self.window_size, low_cut, 24, highpass=True)
        lrlp_window = create_linkwitz_riley_fft_filter(self.window_size, high_cut, 24, highpass=False)
        self.lrbp_window = [lrhp_window[i] * lrlp_window[i] for i in range(len(lrhp_window))]
        self.previous_phases = [MFloat[2](0.0, 0.0) for _ in range(self.window_size // 2 + 1)]
        self.previous_mags = [MFloat[2](0.0, 0.0) for _ in range(self.window_size // 2 + 1)]
        self.low_cut = low_cut
        self.high_cut = high_cut
        self.m_s = [0.0 for _ in range(self.window_size // 2 + 1)]

    def get_messages(mut self) -> None:
        pass

    def next_stereo_frame(mut self, mut mags: List[MFloat[2]], mut phases: List[MFloat[2]]) -> None:
        mags[0] = 0.0 # zero the bottom bin
        for i in range(len(mags)):
            mags[i] *= self.lrbp_window[i]

        def call_back(mut phases: List[MFloat[2]]) capturing -> None:
            for ref p in phases:
                p = MFloat[2](rrand(0.0, 2.0 * 3.141592653589793), rrand(0.0, 2.0 * 3.141592653589793))

        get_best_coherence[2, Self.num_iterations, call_back](mags, phases, self.previous_mags, self.previous_phases, self.window_size, self.hop_size)

        self.previous_phases = phases.copy()
        

struct NessStretch(Movable, Copyable):
    var world: World
    var buffer: SIMDBuffer[2]
    var phasor: Phasor[]
    var window_sizes: List[Int] 
    var hop_sizes: List[Int]

    var ness_stretches: List[FFTProcess[NessStretchWindow[num_iterations=iterations],ifft=True,input_window_shape=WindowType.sine,output_window_shape=WindowType.sine]]

    var m: Messenger
    var dur_mult: Float64
    var file_name: String

    def __init__(out self, world: World):
        self.world = world
        self.file_name = "resources/Shiverer.wav"
        self.buffer = SIMDBuffer.load("resources/Shiverer.wav")
        self.phasor = Phasor(self.world)
        self.window_sizes = [65536, 32768, 16384, 8192, 4096, 2048, 1024, 512, 256]
        self.hop_sizes = [32768, 16384, 8192, 4096, 2048, 1024, 512, 256, 128]

        start_cut = [0, 64, 64, 64, 64, 64, 64, 64, 64]

        # the upper register benefit from less coherence, so I am using fewer in the upper register.
        self.ness_stretches = [FFTProcess[
                NessStretchWindow[num_iterations=iterations],
                ifft=True,
                input_window_shape=WindowType.sine,
                output_window_shape=WindowType.sine,
                
            ](self.world,process=NessStretchWindow[num_iterations=iterations](self.world, self.window_sizes[i], self.hop_sizes[i],start_cut[i], 128),window_size=self.window_sizes[i],hop_size=self.hop_sizes[i]) for i in range(0,9)]
  
        self.m = Messenger(self.world)
        self.dur_mult = 40.0

    def next(mut self) -> SIMD[DType.float64,2]:
        self.m.update(self.dur_mult,"dur_mult")
        new_file = self.m.notify_update(self.file_name, "file_name")
        if new_file:
            self.buffer = SIMDBuffer.load(self.file_name)
        speed = 1.0/self.buffer.duration * (1.0/self.dur_mult)
        phase = self.phasor.next(speed, trig = new_file)
        o = MFloat[2](0.0, 0.0)
        for ref n in self.ness_stretches:
            o += n.buffered_process.next_from_stereo_buffer[Interp.lagrange4](self.buffer, phase)
        return o * 0.5



