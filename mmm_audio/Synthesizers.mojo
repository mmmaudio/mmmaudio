from mmm_audio import *

struct PAF[
    num_chans: Int = 1,
    interp: Interp = Interp.linear,
    ov_samp: TimesOversampling = TimesOversampling.none,
    wrap_gaussian: Bool = False,
](Copyable, Movable):
    """Phase-Aligned Formant generator using a single phasor to synthesize multiple windows. From Miller Puckette's "Theory and Technique of Electronic Music," page 170.

    Parameters:
        num_chans: Number of channels.
        interp: Interpolation method. See [Interp](MMMWorld.md/#struct-interp) struct for options.
        ov_samp: A [TimesOversampling](MMMWorld.md#struct-timesoversampling) struct to indicate times oversampling.
        wrap_gaussian: Whether to wrap indices that go out of bounds in the gaussian window. Puckette's design only uses half of the table, but enabling wrap_gaussian uses the entire table, resulting in a wider pallette of timbres.
    """

    var oversampled_world: World

    var phasor: Phasor[Self.num_chans]
    var cos1: Osc[Self.num_chans, Self.interp]
    var cos2: Osc[Self.num_chans, Self.interp]
    var gauss_last_phase: MFloat[Self.num_chans]
    var sin_last_phase: MFloat[Self.num_chans]
    var cos1_last_phase: MFloat[Self.num_chans]

    var downsampler: Optional[Downsampler[Self.num_chans, Self.ov_samp]]

    def __init__(out self, world: World):
        """Initialize the phase-aligned formant synthesizer.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.oversampled_world = create_subworld(world, Self.ov_samp)

        self.phasor = Phasor[Self.num_chans](self.oversampled_world)
        
        self.cos1 = Osc[Self.num_chans, Self.interp](self.oversampled_world)
        self.cos2 = Osc[Self.num_chans, Self.interp](self.oversampled_world)
        self.gauss_last_phase = 0.0
        self.sin_last_phase = 0.0
        self.cos1_last_phase = MFloat[self.num_chans](0.0)

        self.downsampler = None
        comptime if Self.ov_samp != TimesOversampling.none:
            self.downsampler = Optional[Downsampler[Self.num_chans, Self.ov_samp]](
                Downsampler[Self.num_chans, Self.ov_samp](
                    world # use main world for downsampler, not the oversampled subworld
                )
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
        out = MFloat[Self.num_chans](0.0)

        a = center_freq / fundamental
        b = wrap(a, 0.0, 1.0)

        comptime for _ in range(Self.ov_samp.times):
            phasor = self.phasor.next(fundamental)

            cos1_phase = phasor * (a - b)
            cos2_phase = cos1_phase + phasor
            cos1 = self.cos1.next(
                freq=0, phase_offset=cos1_phase + 0.25
            )

            cos2 = self.cos2.next(
                freq=0, phase_offset=cos2_phase + 0.25
            )

            temp = self.oversampled_world[].windows.value()
            sin = temp[].at_phase[
                window_type=WindowType.sine, interp=Self.interp
            ](self.oversampled_world, phasor, self.sin_last_phase)

            gaussian_phase = (
                sin * ((bandwidth / fundamental) * 0.25)
            ) + 0.5

            gaussian = temp[].at_phase[
                window_type=WindowType.gaussian, interp=Self.interp
            ](self.oversampled_world, gaussian_phase, self.gauss_last_phase)

            mod = ((cos2 - cos1) * b) + cos1
            out = mod * gaussian
            self.gauss_last_phase = gaussian_phase
            self.sin_last_phase = phasor
            self.cos1_last_phase = cos1_phase

            # add sample to downsampling buffer each iteration
            comptime if Self.ov_samp != TimesOversampling.none:
                self.downsampler.value().add_sample(out)

        # retrieve sample from downsampling buffer only if oversampling is enabled
        comptime if Self.ov_samp != TimesOversampling.none:
            return self.downsampler.value().get_sample()
        else:
            return out
