from mmm_audio import *

struct HilbertWindow(ComplexFFTProcessable):
    var m: Messenger
    var radians: Float64
    var window_size: Int

    def __init__(out self, world: World, window_size: Int):
        self.m = Messenger(world)
        self.radians = pi_over2
        self.window_size = window_size

    def get_messages(mut self) -> None:
        pass

    def next_frame(mut self, mut complex: List[ComplexSIMD[DType.float64, 1]]) -> None:
        complex[0] *= ComplexSIMD[DType.float64, 1](0.0, 0.0)
        complex[self.window_size] *= ComplexSIMD[DType.float64, 1](0.0, 0.0)

        for i in range(1, self.window_size):
            complex[i] *= ComplexSIMD[DType.float64, 1](math.cos(self.radians), math.sin(self.radians))

struct Hilbert[window_type: Int = WindowType.sine](Movable, Copyable):
    var world: World
    var hilbert: ComplexFFTProcess[HilbertWindow,True,Self.window_type,Self.window_type]
    var window_size: Int
    var hop_size: Int
    var delay: Delay[1, Interp.none]
    var delay_time: MFloat[]

    def __init__(out self, window_size: Int, hop_size: Int, world: World):
        self.world = world
        self.window_size = window_size
        self.hop_size = hop_size
        self.delay_time = Float64(self.window_size)/self.world[].sample_rate

        self.delay = Delay[1, Interp.none](self.world, Int(self.window_size))

        self.hilbert = ComplexFFTProcess[
                HilbertWindow,
                True,
                Self.window_type,
                Self.window_type
            ](self.world,HilbertWindow(self.world, self.window_size), self.window_size, self.hop_size)

    def next(mut self, input: MFloat[1], radians: Float64) -> Tuple[Float64, Float64]:
        """Process one sample through the Hilbert transform, returning the delayed input sample and the Hilbert transform output sample.
        
        Args:
            input: The input sample to process.
            radians: The angle in radians to rotate the Hilbert transform output by.
        """
        self.hilbert.buffered_process.process.process.radians = radians
        o = self.hilbert.next(input)
        delayed: Float64 = self.delay.next(input, MInt[1](self.window_size))
        return Tuple(delayed, o)

struct SpectralFreezeWindow[window_size: Int](FFTProcessable):
    var world: World
    var stored_mags: List[MFloat[2]]
    var prev_phases: List[MFloat[2]]
    var diff_phases: List[MFloat[2]]
    var mono_mags: List[Float64]
    var frozen: Bool
    
    def __init__(out self, world: World):
        self.world = world
        self.prev_phases = [MFloat[2](0.0) for _ in range(Self.window_size)]
        self.diff_phases = [MFloat[2](0.0) for _ in range(Self.window_size)]
        self.stored_mags = [MFloat[2](0.0) for _ in range(Self.window_size)]
        self.mono_mags = [0.0 for _ in range(Self.window_size)]
        self.frozen = False

    def next_stereo_frame(mut self, mut mags: List[MFloat[2]], mut phases: List[MFloat[2]]) -> None:
        for i in range(Self.window_size//2):
            self.mono_mags[i] = (mags[i][0] + mags[i][1])

        if not self.frozen:
            for i in range(Self.window_size//2):
                self.diff_phases[i] = phases[i]-self.prev_phases[i]
                self.prev_phases[i] = phases[i]
                self.stored_mags[i] = mags[i]
        else:
            for i in range(Self.window_size//2):
                self.prev_phases[i] = self.prev_phases[i] + self.diff_phases[i]
                phases[i] = self.prev_phases[i]
                
            mags = self.stored_mags.copy()