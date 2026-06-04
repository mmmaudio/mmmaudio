from mmm_audio import *

struct PAF[
    num_chans: Int = 1,
    interp: Interp = Interp.linear,
    os_index: Int = 0,
    wrap_gaussian: Bool = False,
](Copyable, Movable):
    """Phase-Aligned Formant generator using a single phasor to synthesize multiple windows. From Miller Puckette's "Theory and Technique of Electronic Music," page 170.

    Parameters:
        num_chans: Number of channels.
        interp: Interpolation method. See [Interp](MMMWorld.md/#struct-interp) struct for options.
        os_index: [Oversampling](Oversampling.md) index (0 = no oversampling, 1 = 2x, 2 = 4x, etc.).
        wrap_gaussian: Whether to wrap indices that go out of bounds in the gaussian window. Puckette's design only uses half of the table, but enabling wrap_gaussian uses the entire table, resulting in a wider pallette of timbres.
    """

    var world: World

    var phasor: Phasor[Self.num_chans]
    var cos1: Osc[Self.num_chans, Self.interp]
    var cos2: Osc[Self.num_chans, Self.interp]
    var lag: Lag[Self.num_chans]
    var env: Env[]
    var env_buffer: SIMDBuffer[1]
    var gauss_last_phase: MFloat[Self.num_chans]
    var sin_last_phase: MFloat[Self.num_chans]
    var sin: Windows
    var gaussian: Windows
    var cos1_last_phase: MFloat[Self.num_chans]

    var oversampling: Oversampling[Self.num_chans, 2**Self.os_index]

    def __init__(out self, world: World):
        """Initialize the phase-aligned formant synthesizer.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world

        self.phasor = Phasor[Self.num_chans](self.world)
        self.phasor.freq_mul = self.world[].os_multiplier[Self.os_index] / self.world[].sample_rate
        
        self.cos1 = Osc[Self.num_chans, Self.interp](self.world)
        self.cos2 = Osc[Self.num_chans, Self.interp](self.world)
        self.lag = Lag[Self.num_chans](self.world)
        self.env = Env[](self.world)
        self.env_buffer = Env.get_env_buffer[1, win_type=WindowType.gaussian](
            self.world, 2048
        )
        self.gauss_last_phase = 0.0
        self.sin_last_phase = 0.0
        self.sin = Windows()
        self.gaussian = Windows()
        self.cos1_last_phase = MFloat[self.num_chans](0.0)

        self.oversampling = Oversampling[Self.num_chans, 2**Self.os_index](
            self.world
        )

    @always_inline
    def next(
        mut self,
        fundamental: MFloat[Self.num_chans] = MFloat[Self.num_chans](100.0),
        center_freq: MFloat[Self.num_chans] = MFloat[Self.num_chans](440.0),
        bandwidth: MFloat[Self.num_chans] = MFloat[Self.num_chans](1.0),
    ) -> MFloat[Self.num_chans]:
        """Generate the next synthesized sample.

        Args:
            fundamental: Fundamental frequency of the phasor.
            center_freq: Center frequency of the formant.
            bandwidth: Bandwidth.

        Returns:
            The next sample of the synthesizer output.
        """
        fund = self.lag.next(fundamental)
        out = MFloat[Self.num_chans](0.0)

        a = center_freq / fund
        b = wrap(a, 0.0, 1.0)

        comptime for _ in range(2**Self.os_index):
            phasor = self.phasor.next(fund)

            cos1_phase = phasor * (a - b)
            cos2_phase = cos1_phase + phasor
            cos1 = self.cos1.next(
                freq=0, phase_offset=cos1_phase + 0.25
            )

            cos2 = self.cos2.next(
                freq=0, phase_offset=cos2_phase + 0.25
            )

            sin = self.sin.at_phase[
                window_type=WindowType.sine, interp=Self.interp
            ](self.world, phasor, self.sin_last_phase)

            gaussian_phase = (
                sin * ((bandwidth / fund) * 0.25)
            ) + 0.5

            gaussian = self.gaussian.at_phase[
                window_type=WindowType.gaussian, interp=Self.interp
            ](self.world, gaussian_phase, self.gauss_last_phase)

            mod = ((cos2 - cos1) * b) + cos1
            out = mod * gaussian
            self.gauss_last_phase = gaussian_phase
            self.sin_last_phase = phasor
            self.cos1_last_phase = cos1_phase

            # add sample to oversampling buffer each iteration
            if self.os_index != 0:
                self.oversampling.add_sample(out)

        # retrive sample from oversampling buffer only if oversampling is enabled
        if self.os_index != 0:
            return self.oversampling.get_sample()
        else:
            return out
