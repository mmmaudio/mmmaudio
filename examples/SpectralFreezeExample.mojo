from mmm_audio import *

comptime two_pi = 2.0 * pi

struct SpectralFreezeWindow[window_size: Int](FFTProcessable):
    var world: World
    var m: Messenger
    var bin: Int
    var freeze_gate: Bool
    var stored_phases: List[MFloat[2]]
    var stored_mags: List[MFloat[2]]

    def __init__(out self, world: World, namespace: Optional[String] = None):
        self.world = world
        self.bin = (Self.window_size // 2) + 1
        self.m = Messenger(world, namespace)
        self.freeze_gate = False
        self.stored_phases = [MFloat[2](0.0) for _ in range(Self.window_size)]
        self.stored_mags = [MFloat[2](0.0) for _ in range(Self.window_size)]
    def get_messages(mut self) -> None:
        self.m.update("freeze_gate", self.freeze_gate)

    def next_stereo_frame(mut self, mut mags: List[MFloat[2]], mut phases: List[MFloat[2]]) -> None:
        if not self.freeze_gate:
            # self.stored_phases = phases.copy()
            self.stored_mags = mags.copy()
        else:
            mags = self.stored_mags.copy()
        for i in range(Self.window_size):
            phases[i] += MFloat[2](random_float64(0, two_pi), random_float64(0, two_pi))
            

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

    def __init__(out self, world: World, namespace: Optional[String] = None):
        self.world = world
        self.freeze = FFTProcess[
                SpectralFreezeWindow[Self.window_size],
                ifft=True,
                input_window_shape=WindowType.hann,
                output_window_shape=WindowType.hann
            ](self.world,process=SpectralFreezeWindow[Self.window_size](self.world, namespace),window_size=Self.window_size,hop_size=Self.hop_size)
        self.m = Messenger(self.world, namespace)
        self.freeze_gate = False
        self.asr = ASREnv(self.world)

    def next(mut self, sample: MFloat[2]) -> MFloat[2]:
        self.m.update("freeze_gate", self.freeze_gate)
        env = self.asr.next(0.01, 1.0, 0.01, self.freeze_gate, 1.0)
        freeze = self.freeze.next_stereo(sample)
        return select(env, sample, freeze) * 0.3

comptime window_size = 2048

struct SpectralFreezeExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var play_buf: Play   
    var spectral_freeze: SpectralFreeze[window_size]
    var m: Messenger
    var stereo_switch: Bool

    def __init__(out self, world: World, namespace: Optional[String] = None):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.play_buf = Play(self.world) 
        self.spectral_freeze = SpectralFreeze[window_size](self.world)
        self.m = Messenger(self.world)
        self.stereo_switch: Bool = False

    def next(mut self) -> SIMD[DType.float64,2]:
        self.m.update("stereo_switch", self.stereo_switch)

        out = self.play_buf.next[2](self.buffer,1)

        out = self.spectral_freeze.next(out)

        return out

