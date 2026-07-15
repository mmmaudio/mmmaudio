from mmm_audio import *

struct SpectralFreezeWindow[window_size: Int](FFTProcessable):
    var world: World
    var stored_mags: List[List[MFloat[2]]]
    var prev_phases: List[List[MFloat[2]]]
    var diff_phases: List[List[MFloat[2]]]
    var mono_mags: List[Float64]
    var toggle: Int
    
    def __init__(out self, world: World):
        self.world = world
        self.prev_phases = [[MFloat[2](0.0) for _ in range(Self.window_size)] for _ in range(2)]
        self.diff_phases = [[MFloat[2](0.0) for _ in range(Self.window_size)] for _ in range(2)]
        self.stored_mags = [[MFloat[2](0.0) for _ in range(Self.window_size)] for _ in range(2)]
        self.mono_mags = [0.0 for _ in range(Self.window_size)]
        self.toggle = 0

    def inc_toggle(mut self):
        self.toggle = (self.toggle + 1) % 2

    def next_stereo_frame(mut self, mut mags: List[MFloat[2]], mut phases: List[MFloat[2]]) -> None:
        tp1 = (self.toggle + 1) % 2
        for i in range(Self.window_size//2 + 1):
            self.diff_phases[self.toggle][i] = phases[i]-self.prev_phases[self.toggle][i]
            self.prev_phases[tp1][i] = self.prev_phases[tp1][i] + self.diff_phases[tp1][i]

        self.prev_phases[self.toggle] = phases.copy()
        self.stored_mags[self.toggle] = mags.copy()
        mags = self.stored_mags[tp1].copy()
        phases = self.prev_phases[tp1].copy()
            
struct SpectralFreeze[window_size: Int](Movable, Copyable):
    """
     Spectral Freeze.
    """

    comptime hop_size = Self.window_size // 4
    var world: World
    var freeze: FFTProcess[SpectralFreezeWindow[Self.window_size],ifft=True,input_window_shape=WindowType.hann,output_window_shape=WindowType.hann]
    var m: Messenger
    var freeze_gate: Bool
    var asr: ASREnv
    var env_delay: Delay[1, Interp.none]

    def __init__(out self, world: World, namespace: Optional[String] = None):
        self.world = world
        self.freeze = FFTProcess[
                SpectralFreezeWindow[Self.window_size],
                ifft=True,
                input_window_shape=WindowType.hann,
                output_window_shape=WindowType.hann
            ](self.world,process=SpectralFreezeWindow[Self.window_size](self.world),window_size=Self.window_size,hop_size=Self.hop_size)
        self.m = Messenger(self.world, namespace)
        self.freeze_gate = False
        self.asr = ASREnv(self.world)
        self.env_delay = Delay[1, Interp.none](self.world, Float64(Self.window_size)/self.world[].sample_rate)

    def next(mut self, sample: MFloat[2]) -> MFloat[2]:
        if self.m.notify_update("freeze_gate", self.freeze_gate):
            if self.freeze_gate:
                self.freeze.get_process().inc_toggle()
        freeze = self.freeze.next_stereo(sample)
        env = self.asr.next(0.01, 1.0, 0.01, self.freeze_gate, 1.0)
        env = self.env_delay.next(env, MInt[1](Self.window_size))
        return select(env, sample, freeze) * 0.3

comptime window_size = 1024

struct SpectralFreezeExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var play_buf: Play   
    var spectral_freeze: SpectralFreeze[window_size]
    var stereo_switch: Bool

    def __init__(out self, world: World, namespace: Optional[String] = None):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.play_buf = Play(self.world) 
        self.spectral_freeze = SpectralFreeze[window_size](self.world)
        self.stereo_switch: Bool = False

    def next(mut self) -> SIMD[DType.float64,2]:

        out = self.play_buf.next[2](self.buffer,1)

        out = self.spectral_freeze.next(out)

        return out

