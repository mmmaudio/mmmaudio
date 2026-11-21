from mmm_audio.constants import *
from mmm_audio.Oscillators import *
from mmm_audio.MMMWorld_Module import Interp, WindowType

struct PAF[
    num_chans: SIMDLength = 1,
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
        self.oversampled_world = world[].create_subworld(Self.ov_samp)

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
        var out = MFloat[Self.num_chans](0.0)

        var a = center_freq / fundamental
        var b = wrap(a, 0.0, 1.0)

        comptime for _ in range(Self.ov_samp.times):
            var phasor = self.phasor.next(fundamental)

            var cos1_phase = phasor * (a - b)
            var cos2_phase = cos1_phase + phasor
            var cos1 = self.cos1.next(
                freq=0, phase_offset=cos1_phase + 0.25
            )

            var cos2 = self.cos2.next(
                freq=0, phase_offset=cos2_phase + 0.25
            )

            ref temp = self.oversampled_world[].windows()
            var sin = temp.at_phase[
                window_type=WindowType.sine, interp=Self.interp
            ](self.oversampled_world, phasor, self.sin_last_phase)

            var gaussian_phase = (
                sin * ((bandwidth / fundamental) * 0.25)
            ) + 0.5

            var gaussian = temp.at_phase[
                window_type=WindowType.gaussian, interp=Self.interp
            ](self.oversampled_world, gaussian_phase, self.gauss_last_phase)

            var mod = ((cos2 - cos1) * b) + cos1
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

struct Pulsar[num_chans: SIMDLength = 1, interp: Interp = Interp.linear, ov_samp: TimesOversampling = TimesOversampling.none](Movable, Copyable):
    """A Pulsar oscillator with a phase-width control ala Curtis Roads.

    Plays a single waveform with a controllable pulse width. The waveform will be the width of the pulse within each cycle and the rest of the cycle will hold the waveform's value at the end of the pulse (should be 0.0).

    Parameters:
        num_chans: Number of channels (default is 1).
        interp: Interpolation method passed to the inner Osc (default is Interp.linear).
        ov_samp: Oversampling of the Phasor and Osc (default is TimesOversampling.none).
    """

    var world: World
    var osc: Osc[Self.num_chans, Self.interp, TimesOversampling.none]
    var phasor: Phasor[Self.num_chans]
    var downsampler: Optional[Downsampler[Self.num_chans, Self.ov_samp]]
    var freq_upsampler: Optional[Upsampler[Self.num_chans, Self.ov_samp]]
    var phase_upsampler: Optional[Upsampler[Self.num_chans, Self.ov_samp]]
    var width_upsampler: Optional[Upsampler[Self.num_chans, Self.ov_samp]]

    def __init__(out self, world: World):
        """Initialize the oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world
        comptime if Self.ov_samp == TimesOversampling.none:
            self.osc = Osc[Self.num_chans, Self.interp, TimesOversampling.none](world)
            self.phasor = Phasor[Self.num_chans](world)
            self.downsampler = None
            self.freq_upsampler = None
            self.phase_upsampler = None
            self.width_upsampler = None
        else:
            var sub_world = world[].create_subworld(Self.ov_samp)
            self.osc = Osc[Self.num_chans, Self.interp, TimesOversampling.none](sub_world)
            self.phasor = Phasor[Self.num_chans](sub_world)
            self.downsampler = Downsampler[Self.num_chans, Self.ov_samp](world)
            # The Upsamplers are designed from the main world's sample rate, not the subworld's.
            self.freq_upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)
            self.phase_upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)
            self.width_upsampler = Upsampler[Self.num_chans, Self.ov_samp](world)

    @doc_hidden
    @always_inline
    def _phase(
            mut self,
            freq: MFloat[self.num_chans],
            phase_offset: MFloat[self.num_chans],
            width: MFloat[self.num_chans],
            trig: Bool,
            i: Int
        ) -> MFloat[self.num_chans]:
        """Advances the Phasor by one (sub)sample and returns the phase to feed the Osc.
        """
        var freq2 = freq
        var phase_offset2 = phase_offset
        var width2 = width
        comptime if Self.ov_samp != TimesOversampling.none:
            freq2 = self.freq_upsampler.value().next(freq, i)
            phase_offset2 = self.phase_upsampler.value().next(phase_offset, i)
            width2 = self.width_upsampler.value().next(width, i)
        var phase = self.phasor.next(freq2, 0.0, MBool[self.num_chans](fill=trig))
        return linlin(phase, 0.0, clip(width2, 1e-9, 1.0), 0.0, 1.0) + phase_offset2

    @always_inline
    def next[osc_type: OscType = OscType.sine](
            mut self,
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0),
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
            trig: Bool = False,
            width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)
        ) -> MFloat[self.num_chans]:
        """Generate the next oscillator sample on a single waveform type.

        Parameters:
            osc_type: Type of waveform. See the OscType struct for options (default is OscType.sine).

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the oscillator output.
        """
        comptime if Self.ov_samp == TimesOversampling.none:
            return self.osc.next[osc_type](0.0, self._phase(freq, phase_offset, width, trig, 0), False)
        else:
            comptime for i in range(Self.ov_samp.times):
                var phase = self._phase(freq, phase_offset, width, trig, i)
                self.downsampler.value().add_sample(self.osc.next[osc_type](0.0, phase, False))
            return self.downsampler.value().get_sample()

    def sine(mut self, freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), trig: Bool = False, width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)) -> MFloat[self.num_chans]:
        """Generate the next sample of a width-warped sine wave.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the oscillator output."""
        return self.next[OscType.sine](freq, phase_offset, trig, width)

    def triangle(mut self, freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), trig: Bool = False, width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)) -> MFloat[self.num_chans]:
        """Generate the next sample of a width-warped triangle wave.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the oscillator output."""
        return self.next[OscType.triangle](freq, phase_offset, trig, width)

    def saw(mut self, freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), trig: Bool = False, width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)) -> MFloat[self.num_chans]:
        """Generate the next sample of a width-warped saw wave.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the oscillator output."""
        return self.next[OscType.saw](freq, phase_offset, trig, width)

    def square(mut self, freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), trig: Bool = False, width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)) -> MFloat[self.num_chans]:
        """Generate the next sample of a width-warped square wave.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the oscillator output."""
        return self.next[OscType.square](freq, phase_offset, trig, width)

    @always_inline
    def next_all_basic_waveforms(
            mut self,
            phase: Float64 = 0.0,
            last_phase: Float64 = 0.0,
            trig: Bool = False,
            width: Float64 = 1.0
        ) -> MFloat[4]:
        """Get the next sample of all basic waveforms (sine, triangle, saw, square) in a SIMD vector, where each waveform is in a different lane.

        This method does not advance the Phasor and is not oversampled: the given `phase` is warped by `width` directly.

        Args:
            phase: Current oscillator phase (0 to 1).
            last_phase: Previous oscillator phase.
            trig: Trigger signal to reset the waveform phase.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The next sample of the built-in basic waveforms.
        """
        var w = clip(width, 1e-9, 1.0)
        return self.osc.next_all_basic_waveforms(min(phase / w, 1.0), min(last_phase / w, 1.0), trig)

    @always_inline
    def next_basic_waveforms[
        *osc_types: OscType
    ](
        mut self,
        freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0),
        phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
        trig: Bool = False,
        osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
        width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)
    ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator using built-in waveforms, with a width-warped phase.

        Parameters:
            osc_types: Waveform types (OscType) to interpolate between, e.g. next_basic_waveforms[OscType.sine, OscType.triangle].

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            osc_frac: Fractional index (0 to 1) for interpolating between the waveforms in osc_types.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The interpolated output sample.
        """
        comptime if Self.ov_samp == TimesOversampling.none:
            return self.osc.next_basic_waveforms[*osc_types](0.0, self._phase(freq, phase_offset, width, trig, 0), False, osc_frac)
        else:
            comptime for i in range(Self.ov_samp.times):
                var phase = self._phase(freq, phase_offset, width, trig, i)
                self.downsampler.value().add_sample(self.osc.next_basic_waveforms[*osc_types](0.0, phase, False, osc_frac))
            return self.downsampler.value().get_sample()

    @always_inline
    def next_vwt[mask: Int = 0](
            mut self,
            ref buffer: Buffer,
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0),
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
            trig: Bool = False,
            osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
            width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)
        ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator over a loaded Buffer, with a width-warped phase.

        Parameters:
            mask: Bitmask used to wrap read positions in the buffer. Leave at 0 (default) to wrap with modulo, which works for any buffer length. Set it to the buffer length minus 1 (e.g. 2047 for a 2048-frame buffer) for a faster bitwise wrap. Only valid when the buffer length is a power of two.

        Args:
            buffer: Reference to a Buffer containing the waveforms to interpolate between.
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            osc_frac: Fractional index (0 to 1) for interpolating between the channels of the buffer.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The interpolated wavetable sample.
        """
        comptime if Self.ov_samp == TimesOversampling.none:
            return self.osc.next_vwt[mask](buffer, 0.0, self._phase(freq, phase_offset, width, trig, 0), False, osc_frac)
        else:
            comptime for i in range(Self.ov_samp.times):
                var phase = self._phase(freq, phase_offset, width, trig, i)
                self.downsampler.value().add_sample(self.osc.next_vwt[mask](buffer, 0.0, phase, False, osc_frac))
            return self.downsampler.value().get_sample()

    @always_inline
    def next_vwt[simd_chans: SIMDLength, mask: Int = 0](
            mut self,
            ref buffer: SIMDBuffer[simd_chans],
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0),
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
            trig: Bool = False,
            osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0),
            width: MFloat[self.num_chans] = MFloat[self.num_chans](1.0)
        ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator over a loaded SIMDBuffer, with a width-warped phase.

        Parameters:
            simd_chans: Number of channels stored in the source SIMDBuffer.
            mask: Bitmask used to wrap read positions in the buffer. Leave at 0 (default) to wrap with modulo, which works for any buffer length. Set it to the buffer length minus 1 (e.g. 2047 for a 2048-frame buffer) for a faster bitwise wrap. Only valid when the buffer length is a power of two.

        Args:
            buffer: Reference to a SIMDBuffer containing the waveforms to interpolate between.
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True.
            osc_frac: Fractional index (0 to 1) for interpolating between the channels of the buffer.
            width: Fraction of the cycle (0 to 1) it takes the Osc's phase to go from 0 to 1.

        Returns:
            The interpolated wavetable sample.
        """
        comptime if Self.ov_samp == TimesOversampling.none:
            return self.osc.next_vwt[simd_chans, mask](buffer, 0.0, self._phase(freq, phase_offset, width, trig, 0), False, osc_frac)
        else:
            comptime for i in range(Self.ov_samp.times):
                var phase = self._phase(freq, phase_offset, width, trig, i)
                self.downsampler.value().add_sample(self.osc.next_vwt[simd_chans, mask](buffer, 0.0, phase, False, osc_frac))
            return self.downsampler.value().get_sample()
