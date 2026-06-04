from std.math import sin, floor
from mmm_audio import *

struct Phasor[num_chans: Int = 1, os_index: Int = 0](Movable, Copyable):
    """Phasor Oscillator.

    An oscillator that generates a ramp waveform from 0.0 to 1.0. The phasor is the root of all oscillators in MMMAudio.
    
    The Phasor can act as a simple phasor with the .next() function. 
    
    However, it can also be an impulse with next_impulse() and a boolean impulse with next_bool().

    Parameters:
        num_chans: Number of channels.
        os_index: Oversampling index (0 = no oversampling, 1 = 2x, up to 4 = 16x). Phasor does not downsample its output, so oversampling is only useful when used as part of other oversampled oscillators.
    """
    var phase: MFloat[Self.num_chans]
    var freq_mul: Float64
    var rising_bool_detector: RisingBoolDetector[Self.num_chans]  # Track the last reset state
    var rising_bool_detector_impulse: RisingBoolDetector[Self.num_chans]  # Track the last reset state
    var world: World  # Pointer to the MMMWorld instance

    def __init__(out self, world: World):
        """Initialize the phasor oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world
        self.phase = MFloat[Self.num_chans](0.0)
        self.freq_mul = self.world[].os_multiplier[Self.os_index] / self.world[].sample_rate
        self.rising_bool_detector = RisingBoolDetector[Self.num_chans]()
        self.rising_bool_detector_impulse = RisingBoolDetector[Self.num_chans]()

    @doc_hidden
    @always_inline
    def _increment_phase(mut self: Phasor, freq: MFloat[self.num_chans]):
        self.phase += (freq * self.freq_mul)
        self.phase = self.phase - floor(self.phase)

    @doc_hidden
    @always_inline
    def _increment_phase_impulse(mut self, freq: MFloat[self.num_chans], phase_offset: MFloat[self.num_chans] = 0.0) -> MBool[Self.num_chans]:
        """Increments the phase and returns a boolean SIMD indicating when the phase wraps around from 1.0 to 0.0, which is when an impulse would occur. This only works with possive frequencies and phase offsets between 0.0 and 1.0."""

        self.phase += (abs(freq) * self.freq_mul)
        fl = floor(self.phase)
        rbd = self.rising_bool_detector_impulse.next(abs(self.phase+clip(phase_offset, 0.0, 1.0)).gt(1.0))
        self.phase = self.phase - fl 
        return rbd

    @always_inline
    def next(mut self: Phasor, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill=True)) -> MFloat[self.num_chans]:
        """Creates the next sample of the phasor output based on the inputs.

        Args:
          freq: Frequency of the phasor in Hz.
          phase_offset: Offsets the phase of the oscillator (0 to 1).
          trig: Trigger signal to reset the phase when switching from False to True.

        Returns:
            The next sample of the phasor output.
        """
        self._increment_phase(freq)
        
        var resets = self.rising_bool_detector.next(trig)
        self.phase = resets.select(0.0, self.phase)
        
        return (self.phase + phase_offset) % 1.0

    @always_inline
    def next_bool(mut self, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill=True)) -> MBool[self.num_chans]:
        """Increments the phasor and returns a boolean impulse when the phase wraps around from 1.0 to 0.0. This only works with possive frequencies and phase offsets between 0.0 and 1.0.

        Args:
          freq: Frequency of the phasor in Hz (default is 100.0).
          phase_offset: Offsets the phase of the oscillator (default is 0.0).
          trig: Trigger signal to reset the phase when switching from False to True (default is all True, which resets the phasor on the first sample).

        Returns:
            A boolean SIMD indicating True when the impulse occurs.
        """

        tick = self._increment_phase_impulse(freq, phase_offset)
        rbd = self.rising_bool_detector.next(trig)
        self.phase = rbd.select(0.0, self.phase)
        
        return (tick or rbd)

    @always_inline
    def next_impulse(mut self, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill=   True)) -> MFloat[self.num_chans]:
        """Generates an impulse waveform where the output is 1.0 for one sample when the phase wraps around from 1.0 to 0.0, and 0.0 otherwise. This only works with possive frequencies and phase offsets between 0.0 and 1.0.

        Args:
          freq: Frequency of the phasor in Hz (default is 100.0).
          phase_offset: Offsets the phase of the oscillator (default is 0.0).
          trig: Trigger signal to reset the phase when switching from False to True (default is all True, which resets the phasor on the first sample).

        Returns:
            The next impulse sample as a Float64. 1.0 when the impulse occurs, 0.0 otherwise.
        """

        return self.next_bool(freq, phase_offset, trig).cast[DType.float64]()

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.freq_mul = (1.0 / self.world[].sample_rate) / Float64(times_oversampling)


struct Impulse[num_chans: Int = 1, os_index: Int = 0](Movable, Copyable):
    """Impulse Oscillator.

    An oscillator that outputs a 1.0 or True for one sample when the phase wraps around from 1.0 to 0.0.
    
    Impulse is essentially a wrapper around the Phasor oscillator that provides impulse-specific methods.

    Parameters:
        num_chans: Number of channels (default is 1).
        os_index: Oversampling index (0 = no oversampling, 1 = 2x, etc.; default is 0).
    """
    var phasor: Phasor[Self.num_chans, Self.os_index]  # Instance of the Phasor

    def __init__(out self, world: World):
        """Initialize the impulse oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.phasor = Phasor[self.num_chans, Self.os_index](world)

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.phasor.set_looped_times_oversampling(times_oversampling)

    @always_inline
    def next_bool(mut self, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill=True)) -> MBool[self.num_chans]:
         """Increments the phasor and returns a boolean impulse when the phase wraps around from 1.0 to 0.0.

        Args:
          freq: Frequency of the phasor in Hz (default is 100.0).
          phase_offset: Offsets the phase of the oscillator (default is 0.0).
          trig: Trigger signal to reset the phase when switching from False to True (default is all True, which resets the phasor on the first sample).

        Returns:
            A boolean SIMD indicating True when the impulse occurs.
        """

        return self.phasor.next_bool(freq, phase_offset, trig) 

    @always_inline
    def next(mut self, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill= True)) -> MFloat[self.num_chans]:
        """Generates an impulse waveform where the output is 1.0 for one sample when the phase wraps around from 1.0 to 0.0, and 0.0 otherwise.

        Args:
          freq: Frequency of the phasor in Hz (default is 100.0).
          phase_offset: Offsets the phase of the oscillator (default is 0.0).
          trig: Trigger signal to reset the phase when switching from False to True (default is all True, which resets the phasor on the first sample).

        Returns:
            The next impulse sample as a Float64. 1.0 when the impulse occurs, 0.0 otherwise.
        """

        return self.phasor.next_impulse(freq, phase_offset, trig)

struct Osc[num_chans: Int = 1, interp: Interp = Interp.linear, os_index: Int = 0](Movable, Copyable):
    """Wavetable Oscillator Core.

    A wavetable oscillator capable of all standard waveforms and also able to load custom wavetables. Capable of linear, cubic, quadratic, lagrange, or sinc interpolation. Also capable of [Oversampling](Oversampling.md).
    
    - Pure tones can be generated without oversampling or sinc interpolation.
    - When doing extreme modulation, best practice is to use sinc interpolation and an oversampling index of 1 (2x).
    - Try all the combinations of interpolation and oversampling to find the best tradeoff between quality and CPU usage for your application.

    Parameters:
        num_chans: Number of channels (default is 1).
        interp: Interpolation method. See [Interp](MMMWorld.md/#struct-interp) struct for options (default is Interp.linear).
        os_index: [Oversampling](Oversampling.md) index (0 = no oversampling, 1 = 2x, 2 = 4x, etc.; default is 0).
    """

    var phasor: Phasor[Self.num_chans, Self.os_index]
    var world: World 
    var oversampling: Oversampling[Self.num_chans, 2**Self.os_index]
    var last_phase: MFloat[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world
        self.phasor = Phasor[self.num_chans, Self.os_index](self.world)
        self.oversampling = Oversampling[self.num_chans, 2**Self.os_index](self.world)
        self.last_phase = MFloat[self.num_chans](0.0)

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.phasor.set_looped_times_oversampling(times_oversampling)

    @always_inline
    def next[osc_type: OscType = OscType.sine](
            mut self: Osc, 
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), 
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), 
            trig: Bool = False
        ) -> MFloat[self.num_chans]:
        """
        Generate the next oscillator sample on a single waveform type. All inputs are SIMD types except trig, which is a scalar. This means that an oscillator can have num_chans different instances, each with its own frequency, phase offset, and waveform type, but they will all share the same trigger signal.

        Parameters:
            osc_type: Type of waveform. See the OscType struct for options (default is OscType.sine).

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (0 to 1).
            trig: Trigger signal to reset the phase when switching from False to True (default is 0.0).

        Returns:
            The next sample of the oscillator output.
        """
        var trig_mask = MBool[self.num_chans](fill=trig)
            
        out = MFloat[self.num_chans](0.0)

        comptime osc_type_int = Int(osc_type)

        comptime if Self.os_index == 0:
            
            # last_phase = self.phasor.phase  # Store the last phase for sinc interpolation
            phase = self.phasor.next(freq, phase_offset, trig_mask)
            temp = self.world[].osc_buffers.value()
            comptime for chan in range(self.num_chans):
                out[chan] = SpanInterpolator.read[
                        interp=self.interp,
                        bWrap=True,
                        mask=OscBuffersMask
                    ](
                        world = self.world,
                        data=temp[].buffers[Int(osc_type)],
                        f_idx=phase[chan] * Float64(OscBuffersSize),
                        prev_f_idx=self.last_phase[chan] * Float64(OscBuffersSize)
                    )
            self.last_phase = phase
            return out
        else:
            comptime for i in range(2**Self.os_index):
                
                # last_phase = self.phasor.phase  # Store the last phase for sinc interpolation
                phase = self.phasor.next(freq, phase_offset, trig_mask)

                sample = MFloat[self.num_chans](0.0)
                temp = self.world[].osc_buffers.value()
                comptime for chan in range(self.num_chans):
                    sample[chan] = SpanInterpolator.read[
                        interp=self.interp,
                        bWrap=True,
                        mask=OscBuffersMask
                    ](
                        world = self.world,
                        data=temp[].buffers[Int(osc_type)],
                        f_idx=phase[chan] * Float64(OscBuffersSize),
                        prev_f_idx=self.last_phase[chan] * Float64(OscBuffersSize)
                    )
                self.oversampling.add_sample(sample)  # Get the next sample from the Oscillator buffer using sinc interpolation
                self.last_phase = phase

            return self.oversampling.get_sample()

    @always_inline
    def next_all_basic_waveforms(
            mut self, 
            freq: Float64 = 100.0, 
            phase: Float64 = 0.0,
            last_phase: Float64 = 0.0, 
            trig: Bool = False
        ) -> MFloat[4]:
        """Get the next sample of all basic waveforms (sine, triangle, saw, square) in a SIMD vector, where each waveform is in a different lane.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase: Current oscillator phase.
            last_phase: Previous oscillator phase.
            trig: Trigger signal to reset the waveform phase.

        Returns:
            The next sample of the built-in basic waveforms.
        """

        temp = self.world[].osc_buffers.value()
        return SpanInterpolator.read[
            interp=Self.interp,
            bWrap=True,
            mask=OscBuffersMask
        ](
            world = self.world,
            data=temp[].basic_waveforms,
            f_idx=phase * Float64(OscBuffersSize),
            prev_f_idx=last_phase * Float64(OscBuffersSize)
        )

    @always_inline 
    def next_basic_waveforms[
        *osc_types: OscType
    ](
        mut self, 
        freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), 
        phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), 
        trig: Bool = False, 
        osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0) 
    ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator using built-in waveforms. Generates the next oscillator sample on a variable waveform where the output is interpolated between different waveform types.

        Parameters:
            osc_types: VariadicList of waveform types (OscType) to interpolate between. See the OscType struct for options. This should be indicated as a compile-time parameter pack, e.g. next_basic_waveforms[OscType.sine, OscType.triangle]. This cannot be left empty or it will cause a compile error.

        Args:
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (default is 0.0).
            trig: Trigger signal to reset the phase when switching from False to True (default is 0.0).
            osc_frac: Fractional index for wavetable interpolation. Values are between 0.0 and 1.0. 0.0 corresponds to the first waveform in the osc_types list, 1.0 corresponds to the last waveform in the osc_types list, and values in between interpolate linearly between all waveforms in the list.

        Returns:
            The interpolated output sample.
        """
        
        # 2. Get the length of the parameter pack at compile time
        comptime num_osc_types = len(osc_types)
        comptime max_osc_frac = num_osc_types - 1
        
        var trig_mask = MBool[self.num_chans](fill=trig) 
        var scaled_osc_frac = Float64(max_osc_frac) * min(osc_frac, 1.0) 
        
        var osc_type0: MInt[self.num_chans] = MInt[self.num_chans](scaled_osc_frac) 
        var osc_type1 = MInt[self.num_chans](osc_type0 + 1) 
        
        osc_type0 = clip(osc_type0, 0, MInt[1](max_osc_frac)) 
        osc_type1 = clip(osc_type1, 0, MInt[1](max_osc_frac)) 

        # 4. Map the runtime vector indexes using the compile-time lookup array
        for i in range(self.num_chans): 
            osc_type0[i] = MInt[1](osc_types[Int(osc_type0[i])]._value) 
            osc_type1[i] = MInt[1](osc_types[Int(osc_type1[i])]._value) 
            
        osc_frac_interp = scaled_osc_frac - floor(scaled_osc_frac) 
        var out_sample = MFloat[self.num_chans](0.0) 

        comptime if Self.os_index == 0:
            var phase = self.phasor.next(freq, phase_offset, trig_mask)
            comptime for chan in range(self.num_chans):
                sample = self.next_all_basic_waveforms(freq[chan], phase[chan], self.last_phase[chan], trig)
                out_sample[chan] = (MFloat[2](sample[Int(osc_type0[chan])], sample[Int(osc_type1[chan])]) * MFloat[2](1.0 - osc_frac_interp[chan], osc_frac_interp[chan])).reduce_add()
            self.last_phase = phase
            return out_sample
        else:
            comptime for i in range(2**Self.os_index):
                var phase = self.phasor.next(freq, phase_offset, trig_mask)
                comptime for chan in range(self.num_chans):
                    sample = self.next_all_basic_waveforms(freq[chan], phase[chan], self.last_phase[chan], trig)
                    out_sample[chan] = (MFloat[2](sample[Int(osc_type0[chan])], sample[Int(osc_type1[chan])]) * MFloat[2](1.0 - osc_frac_interp[chan], osc_frac_interp[chan])).reduce_add()
                self.oversampling.add_sample(out_sample)
                self.last_phase = phase
            return self.oversampling.get_sample()
   
    @always_inline
    def next_vwt(
            mut self: Osc, 
            ref buffer: Buffer, 
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), 
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), 
            trig: Bool = False, 
            osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0)
        ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator that interpolates over a loaded Buffer.
        Generates the next oscillator sample on a variable waveform where the output is interpolated between 
        different different channels of a provided Buffer.
        
        Args:
            buffer: Reference to a Buffer containing the waveforms to interpolate between.
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (default is 0.0).
            trig: Trigger signal to reset the phase when switching from False to True (default is 0.0). All waveforms will reset together.
            osc_frac: Fractional index for wavetable interpolation. Values are between 0.0 and 1.0. 0.0 corresponds to the first channel in the input buffer, 1.0 corresponds to the last channel in the input buffer, and values in between interpolate linearly between all channels in the buffer.

        Returns:
            The interpolated wavetable sample.
        """
        var trig_mask = MBool[self.num_chans](fill=trig)

        var max_osc_frac = buffer.num_chans - 1

        var chan0_fl = Float64(max_osc_frac) * min(osc_frac, 1.0) #can't use a modulus here

        var buf_chan0: MInt[self.num_chans] = MInt[self.num_chans](chan0_fl)
        var buf_chan1 = MInt[self.num_chans](buf_chan0 + 1)

        scaled_osc_frac = chan0_fl - floor(chan0_fl)

        var sample0 = MFloat[self.num_chans](0.0)
        var sample1 = MFloat[self.num_chans](0.0)

        comptime if Self.os_index == 0:
            # var last_phase = self.phasor.phase
            var phase = self.phasor.next(freq, phase_offset, trig_mask)
            comptime for out_chan in range(self.num_chans):
                sample0[out_chan] = SpanInterpolator.read[
                        interp=self.interp,
                        bWrap=True,
                        mask=0
                    ](
                        world = self.world,
                        data=buffer.data[buf_chan0[out_chan]],
                        f_idx=phase[out_chan] * buffer.num_frames_f64,
                        prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                    )
                sample1[out_chan] = SpanInterpolator.read[
                        interp=self.interp,
                        bWrap=True,
                        mask=0
                    ](
                        world = self.world,
                        data=buffer.data[buf_chan1[out_chan]],
                        f_idx=phase[out_chan] * buffer.num_frames_f64,
                        prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                    )
            self.last_phase = phase
            return linear_interp(sample0, sample1, scaled_osc_frac)
        else:
            comptime times_os_int = 2**Self.os_index
            comptime for i in range(times_os_int):
                # var last_phase = self.phasor.phase
                var phase = self.phasor.next(freq, phase_offset, trig_mask)
                comptime for out_chan in range(self.num_chans):
                    sample0[out_chan] = SpanInterpolator.read[
                            interp=self.interp,
                            bWrap=True,
                            mask=0
                        ](
                            world = self.world,
                            data=buffer.data[buf_chan0[out_chan]],
                            f_idx=phase[out_chan] * buffer.num_frames_f64,
                            prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                        )
                    sample1[out_chan] = SpanInterpolator.read[
                            interp=self.interp,
                            bWrap=True,
                            mask=0
                        ](
                            world = self.world,
                            data=buffer.data[buf_chan1[out_chan]],
                            f_idx=phase[out_chan] * buffer.num_frames_f64,
                            prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                        )
                self.oversampling.add_sample(linear_interp(sample0, sample1, scaled_osc_frac))
                self.last_phase = phase
            return self.oversampling.get_sample()

    @always_inline
    def next_vwt[simd_chans: Int](
            mut self: Osc, 
            ref buffer: SIMDBuffer[simd_chans], 
            freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), 
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), 
            trig: Bool = False, 
            osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0)
        ) -> MFloat[self.num_chans]:
        """Variable Wavetable Oscillator that interpolates over a loaded SIMDBuffer.
        Generates the next oscillator sample on a variable waveform where the output is interpolated between 
        different different channels of a provided Buffer. This should only be used with low channel counts (maybe up to 4 or 8 channels depending on the CPU).

        Parameters:
            simd_chans: Number of channels stored in the source SIMDBuffer.
        
        Args:
            buffer: Reference to a Buffer containing the waveforms to interpolate between.
            freq: Frequency of the oscillator in Hz.
            phase_offset: Offsets the phase of the oscillator (default is 0.0).
            trig: Trigger signal to reset the phase when switching from False to True (default is 0.0). All waveforms will reset together.
            osc_frac: Fractional index for wavetable interpolation. Values are between 0.0 and 1.0. 0.0 corresponds to the first channel in the input buffer, 1.0 corresponds to the last channel in the input buffer, and values in between interpolate linearly between all channels in the buffer.

        Returns:
            The interpolated wavetable sample.
        """
        var trig_mask = MBool[self.num_chans](fill=trig)

        var max_osc_frac = buffer.num_chans - 1

        var chan0_fl = Float64(max_osc_frac) * min(osc_frac, 1.0) #can't use a modulus here

        var buf_chan0: MInt[self.num_chans] = MInt[self.num_chans](chan0_fl)
        var buf_chan1 = MInt[self.num_chans](buf_chan0 + 1)

        scaled_osc_frac = chan0_fl - floor(chan0_fl)

        comptime if Self.os_index == 0:
            # var last_phase = self.phasor.phase
            var phase = self.phasor.next(freq, phase_offset, trig_mask)
            out_sample = MFloat[self.num_chans](0.0)
            comptime for out_chan in range(self.num_chans):
                sample = SpanInterpolator.read[
                        interp=self.interp,
                        bWrap=True,
                        mask=0
                    ](
                        world = self.world,
                        data=buffer.data,
                        f_idx=phase[out_chan] * buffer.num_frames_f64,
                        prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                    )
                out_sample[out_chan] = (MFloat[2](sample[Int(buf_chan0[out_chan])], sample[Int(buf_chan1[out_chan])]) * MFloat[2](1.0 - scaled_osc_frac[out_chan], scaled_osc_frac[out_chan])).reduce_add()
                
            self.last_phase = phase
            return out_sample
        else:
            comptime times_os_int = 2**Self.os_index
            comptime for i in range(times_os_int):
                # var last_phase = self.phasor.phase
                var phase = self.phasor.next(freq, phase_offset, trig_mask)
                out_sample = MFloat[self.num_chans](0.0)
                comptime for out_chan in range(self.num_chans):
                    sample = SpanInterpolator.read[
                            interp=self.interp,
                            bWrap=True,
                            mask=0
                        ](
                            world = self.world,
                            data=buffer.data,
                            f_idx=phase[out_chan] * buffer.num_frames_f64,
                            prev_f_idx=self.last_phase[out_chan] * buffer.num_frames_f64
                        )
                    out_sample[out_chan] = (MFloat[2](sample[Int(buf_chan0[out_chan])], sample[Int(buf_chan1[out_chan])]) * MFloat[2](1.0 - scaled_osc_frac[out_chan], scaled_osc_frac[out_chan])).reduce_add()
                self.oversampling.add_sample(out_sample)
                self.last_phase = phase
            return self.oversampling.get_sample()

struct OscBank[num: Int](Movable, Copyable):
    """A convenience struct for processing a bank of Osc's with fixed frequencies. The number are indicated by the num parameter. Each output can be accessed via index.

    Parameters:
        num: The total number of Oscillators.
    """
    comptime simd_width = simd_width_of[DType.float64]() * 2
    comptime num_simd = Self.num // Self.simd_width + (1 if Self.num % Self.simd_width != 0 else 0)
    var oscs : List[Osc[Self.simd_width]]
    var freqs: List[MFloat[Self.simd_width]]

    def __init__(out self, world: World):
        self.oscs = [Osc[Self.simd_width](world) for _ in range(Self.num_simd)]
        self.freqs = [MFloat[Self.simd_width](rrand(100.0, 2000.0)) for _ in range(Self.num_simd)]

    def set_freq(mut self, index: Int, freq: Float64):
        """Set the frequency of a specific oscillator in the bank.

        Args:
            index: Index of the oscillator to retune.
            freq: Frequency in Hertz to assign.
        """
        simd_index = index // Self.simd_width
        lane_index = index % Self.simd_width
        if simd_index < Self.num_simd:
            self.freqs[simd_index][lane_index] = freq

    def next[osc_type: OscType = OscType.sine](mut self) -> Float64:
        """Generate the next sample from the oscillator bank.

        Parameters:
            osc_type: Waveform type used by each oscillator in the bank.

        Returns:
            The averaged output of all oscillators in the bank.
        """
        out = MFloat[Self.simd_width](0.0)
        for i in range(Self.num_simd):
            out += self.oscs[i].next[osc_type=osc_type](self.freqs[i])
        return out.reduce_add() / Float64(Self.num) 

struct LFOsc[num_chans: Int = 1] (Movable, Copyable):
    """A low-frequency oscillator with multiple waveform options.
    
    This oscillator generates a non-bandlimited oscillator capable of saw, triangle, and square waves. It is useful for modulation, but should be avoided for audio-rate synthesis due to aliasing.

    Outputs values between -1.0 and 1.0.

    Parameters:
        num_chans: Number of channels (default is 1).
    """

    var phasor: Phasor[Self.num_chans]
    var world: World 

    def __init__(out self, world: World):
        """Initialize the low-frequency oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.phasor = Phasor[self.num_chans](world)
        self.world = world

    @always_inline
    def next[osc_type: OscType = OscType.saw](mut self, freq: MFloat[self.num_chans] = 100.0, phase_offset: MFloat[self.num_chans] = 0.0, trig: Bool = False) -> MFloat[self.num_chans]:
        """Generate the next sawtooth wave sample.

        Parameters:
            osc_type: Waveform type to generate.
        
        Args:
            freq: Frequency of the sawtooth wave in Hz.
            phase_offset: Offsets the phase of the oscillator (default is 0.0).
            trig: Trigger signal to reset the phase when switching from False to True (default is 0.0).

        Returns:
            The next low-frequency oscillator sample.
        """

        var trig_mask = MBool[self.num_chans](fill=trig)
        comptime if osc_type == OscType.saw:
            return 1.0 - 2.0 * self.phasor.next(freq, phase_offset, trig_mask)
        elif osc_type == OscType.triangle:
            return (abs((self.phasor.next(freq, phase_offset, trig_mask) * 4.0) - 2.0) - 1.0)
        elif osc_type == OscType.square:
            return -1.0 if self.phasor.next(freq, phase_offset, trig_mask) < 0.5 else 1.0
        else:
            phase = self.phasor.next(freq, phase_offset, trig_mask)
            return sin(phase * two_pi)

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.phasor.set_looped_times_oversampling(times_oversampling)

struct Dust[num_chans: Int = 1] (Movable, Copyable):
    """A dust noise oscillator that generates random impulses at random intervals.
    
    Dust has a Phasor as its core, and the frequency of the Phasor is randomly changed each time an impulse is generated. This allows the Dust to be used in multiple ways. It can be used as a simple random impulse generator, or the user can use the get_phase() method to get the current phase of the internal Phasor and use that phase to drive other oscillators or processes. The user can also set the phase of the internal Phasor using the set_phase() method, allowing for more complex interactions.

    Parameters:
        num_chans: Number of channels.
    """
    var impulse: Phasor[Self.num_chans]
    var freq: MFloat[Self.num_chans]

    def __init__(out self, world: World):
        """Initialize the dust noise oscillator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.impulse = Phasor[Self.num_chans](world)
        # this will cause all Dusts to start at a different phase
        for i in range(self.num_chans):
            self.impulse.phase[i] = rrand(0.0, 1.0)
        self.freq = MFloat[Self.num_chans](1.0)

    def next(mut self: Dust, low: MFloat[self.num_chans] = 100.0, high: MFloat[self.num_chans] = 2000.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill= False)) -> MFloat[self.num_chans]:
        """Generate the next dust noise sample.
        
        Args:
            low: Lower bound for the random frequency range.
            high: Upper bound for the random frequency range.
            trig: Trigger signal to reset the phase when switching from False to True.

        Returns:
            The next dust noise sample as a Float64. Will be 1.0 when an impulse occurs, 0.0 otherwise.
        """
        return self.next_bool(low, high, trig).cast[DType.float64]()

    @always_inline
    def next_bool(mut self: Dust, low: MFloat[self.num_chans] = 100.0, high: MFloat[self.num_chans] = 2000.0, trig: MBool[self.num_chans] = MBool[self.num_chans](fill= False)) -> MBool[self.num_chans]:
        """Generate the next dust noise sample as a boolean impulse.
        
        Args:
            low: Lower bound for the random frequency range.
            high: Upper bound for the random frequency range.
            trig: Trigger signal to reset the phase when switching from False to True.

        Returns:
            The next dust noise sample as a boolean SIMD. Will be True when an impulse occurs, False otherwise.
        """

        var tick = self.impulse.next_bool(self.freq, 0, trig)  # Update the phase

        comptime for i in range(self.num_chans):
            if tick[i]:
                self.freq[i] = random_float64(low[i], high[i])

        return tick

    def get_phase(self) -> MFloat[self.num_chans]:
        return self.impulse.phase

    def set_phase(mut self, phase: MFloat[self.num_chans]):
        self.impulse.phase = phase

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.impulse.set_looped_times_oversampling(times_oversampling)


struct TTrig(Movable, Copyable):
    """A trigger that outputs True for a specified number of samples or amount of time after receiving a trigger signal."""

    var counter: Int
    var world: World

    def __init__(out self, world: World):
        self.counter = 0
        self.world = world

    def next(mut self, trig: Bool, samples: Int) -> Bool:
        """Generate the next trigger sample.
        
        Args:
            trig: Trigger signal.
            samples: Number of samples for which to output True.

        Returns:
            True if the trigger is active, False otherwise.
        """
        if trig:
            self.counter = samples
        if self.counter <=0:
            return False
        else:
            self.counter -= 1
            return True
    
    def next(mut self, trig: Bool, time: MFloat[1]) -> Bool:
        """Generate the next trigger sample based on time.

        Args:
            trig: Trigger signal.
            time: Amount of time in seconds for which to output True.

        Returns:
            True if the trigger is active, False otherwise.
        """
        if trig:
            self.counter = Int(time * self.world[].sample_rate)
        return self.next(False, 0)

struct LFNoise[num_chans: Int = 1, interp: Interp = Interp.cubic](Movable, Copyable):
    """Low-frequency interpolating noise generator generating numbers between -1.0 and 1.0. With stepped (none), linear, or cubic interpolation.

    Parameters:
        num_chans: Number of channels.
        interp: Interpolation method. Options are Interp.none (stepped), Interp.linear, Interp.cubic.
    """
    var impulse: Phasor[Self.num_chans]

    # Cubic inerpolation only needs 4 points, but it needs to know the true previous point so the history
    # needs an extra point: the 4 for interpolation, plus the point that is just changed
    var history: List[MFloat[Self.num_chans]]# used for interpolation

    # history_index: the index of the history list that the impulse's phase is moving *away* from
    # phase is moving *towards* history_index + 1
    var history_index: List[Int]

    def __init__(out self, world: World):
        """Initialize the low-frequency noise generator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.history_index = [0 for _ in range(self.num_chans)]
        self.impulse = Phasor[Self.num_chans](world)
        self.history = [MFloat[Self.num_chans](0.0) for _ in range(5)]
        for i in range(Self.num_chans):
            for j in range(len(self.history)):
                self.history[j][i] = random_float64(0.1, 1.0)
        # Initialize history with random values

    @always_inline
    def next(mut self: LFNoise, freq: MFloat[self.num_chans] = 100.0) -> MFloat[self.num_chans]:
        """Generate the next low-frequency noise sample.
        
        Args:
            freq: Frequency of the noise in Hz.

        Returns:
            The next sample as a Float64.
        """
        # var trig_mask = MBool[self.num_chans](fill=False)
        var tick = self.impulse.next_bool(freq)  # Update the phase

        comptime for i in range(self.num_chans):
            if tick[i]:  # If an impulse is detected
                # advance the history index
                self.history_index[i] = (self.history_index[i] + 1) % len(self.history)

            # so don't change that one, cubic interp needs to know that, so we'll change 
            # history_index - 2 (but, again, computed differently to avoid negative indices) so
            # the next time we wrap around to that part of the history list it will be a new random value
            self.history[(self.history_index[i] + (len(self.history) - 2)) % len(self.history)][i] = random_float64(-1.0, 1.0)

        comptime if Self.interp == Interp.none:
            p0 = MFloat[self.num_chans](0.0)
            comptime for i in range(self.num_chans):
                p0[i] = self.history[(self.history_index[i] + 1) % len(self.history)][i]
            return p0
        elif Self.interp == Interp.linear:
            # Linear interpolation between last and next value
            p0 = MFloat[self.num_chans](0.0)
            p1 = MFloat[self.num_chans](0.0)
            comptime for i in range(Self.num_chans):
                p0[i] = self.history[self.history_index[i]][i]
                p1[i] = self.history[(self.history_index[i] + 1) % len(self.history)][i]
            return linear_interp(p0, p1, self.impulse.phase)
        else:
            p0 = MFloat[self.num_chans](0.0)
            p1 = MFloat[self.num_chans](0.0)
            p2 = MFloat[self.num_chans](0.0)
            p3 = MFloat[self.num_chans](0.0)
            comptime for i in range(self.num_chans):
                p0[i] = self.history[(self.history_index[i] + (len(self.history) - 1)) % len(self.history)][i]
                p1[i] = self.history[self.history_index[i]][i]
                p2[i] = self.history[(self.history_index[i] + 1) % len(self.history)][i]
                p3[i] = self.history[(self.history_index[i] + 2) % len(self.history)][i]
            # Cubic interpolation
            return cubic_interp(p0, p1, p2, p3, self.impulse.phase)

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.impulse.set_looped_times_oversampling(times_oversampling)

struct Sweep[num_chans: Int = 1](Movable, Copyable):
    """A phase accumulator.
    
    Phase accumulator that sweeps from 0 up to inf at a given frequency, resetting on trigger.

    Parameters:
        num_chans: Number of channels.
    """

    var phase: MFloat[Self.num_chans]
    var freq_mul: Float64
    var rising_bool_detector: RisingBoolDetector[Self.num_chans]  # Track the last reset state
    var world: World  # Pointer to the MMMWorld instance

    def __init__(out self, world: World):
        """Initialize the sweep generator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world
        self.phase = MFloat[Self.num_chans](0.0)
        self.freq_mul = 1.0 / self.world[].sample_rate
        self.rising_bool_detector = RisingBoolDetector[Self.num_chans]()
   
    @always_inline
    def next(mut self, freq: MFloat[self.num_chans] = 100.0, trig: MBool[self.num_chans] = False) -> MFloat[self.num_chans]:
        """Generate the next sweep sample.

        Args:
            freq: Frequency of the sweep in Hz.
            trig: Trigger signal to reset the phase when switching from False to True (default is all False).

        Returns:
            The next sample as a Float64.
        """

        self.phase += (freq * self.freq_mul)

        var resets = self.rising_bool_detector.next(trig)

        self.phase = resets.select(0.0, self.phase)

        return self.phase

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.freq_mul = 1.0 / (self.world[].sample_rate * Float64(times_oversampling))

struct Line[num_chans: Int = 1, linexpcurve: Int = 0](Movable, Copyable):
    """
        A Line between start and end that takes dur seconds to complete.
    """

    var phase: MFloat[Self.num_chans]
    var freq_mul: Float64
    var rising_bool_detector: RisingBoolDetector[Self.num_chans]  # Track the last reset state
    var world: World  # Pointer to the MMMWorld instance
    var freq: MFloat[Self.num_chans]
    var curve: MFloat[1]

    def __init__(out self, world: World):
        """Initialize the line generator.

        Args:
            world: Pointer to the MMMWorld instance.
        """
        self.world = world
        self.phase = MFloat[Self.num_chans](0.0)
        self.freq_mul = 1.0 / self.world[].sample_rate
        self.rising_bool_detector = RisingBoolDetector[Self.num_chans]()
        self.freq = MFloat[Self.num_chans](0.0)
        self.curve = 2.0

    @always_inline
    def next(mut self, start: MFloat[self.num_chans], end: MFloat[self.num_chans], dur: MFloat[self.num_chans], trig: MBool[self.num_chans] = True) -> MFloat[self.num_chans]:
        """Generate the next line sample.

        Args:
            start: Starting value of the line.
            end: Ending value of the line.
            dur: Duration of the line in seconds.
            trig: Trigger signal to reset the phase when switching from False to True (default is all False).

        Returns:
            The next interpolated line value.
        """
        self.phase += (self.freq * self.freq_mul)
        var resets = self.rising_bool_detector.next(trig)
        self.freq = resets.select((1.0 / dur), self.freq)
        self.phase = resets.select(0.0, self.phase)
        self.phase = clip(self.phase, 0.0, 1.0)

        comptime if Self.linexpcurve == 0:
            return linlin(self.phase, 0.0, 1.0, start, end)
        elif Self.linexpcurve == 1:
            start_mask = start.gt(0.000001)
            end_mask = end.gt(0.000001)
            start2 = start_mask.select(start, 0.000001)
            end2 = end_mask.select(end, 0.000001)
            return linexp(self.phase, 0.0, 1.0, start2, end2)
        elif Self.linexpcurve == 2:
            return lincurve(self.phase, 0.0, 1.0, start, end, self.curve)
        else:
            return linlin(self.phase, 0.0, 1.0, start, end)

    def set_looped_times_oversampling(mut self, times_oversampling: Int):
        """Sets times oversampling for the oscillator when it is used in an Oversampling loop. This is not for when using the oscillator with the built-in oversampling, but rather for when the oscillator is used as part of a custom oversampling implementation.

        Args:
            times_oversampling: The new oversampling multiplier (1 for no oversampling, 2 for 2x, 4 for 4x, etc.).
        """
        self.freq_mul = 1.0 / (self.world[].sample_rate * Float64(times_oversampling))

comptime OscBuffersSize: Int = 16384  # 2^14
comptime OscBuffersMask: Int = 16383  # 2^14 - 1

@doc_hidden
struct OscBuffers(Movable, Copyable):
    # var buffers: List[List[Float64]]
    var buffers: List[List[Float64]]
    var basic_waveforms: List[MFloat[4]]

    def at_phase[osc_type: Int, interp: Interp = Interp.none](self, world: World, phase: Float64, prev_phase: Float64 = 0) -> Float64:
        comptime if osc_type < 4 and osc_type >= 0:
            return SpanInterpolator.read[
                interp=interp,
                bWrap=True,
                mask=OscBuffersMask
            ](
                world=world,
                data=self.buffers[osc_type],
                f_idx=phase * Float64(OscBuffersSize),
                prev_f_idx=prev_phase * Float64(OscBuffersSize)
            )
        else:
            return 0.0

    def at_phase_basic_waveform[osc_type: Int, interp: Interp = Interp.none](self, world: World, phase: Float64, prev_phase: Float64 = 0) -> MFloat[4]:
        return SpanInterpolator.read[
            num_chans = 4,
            interp=interp,
            bWrap=True,
            mask=OscBuffersMask
        ](
            world=world,
            data=self.basic_waveforms,
            f_idx=phase * Float64(OscBuffersSize),
            prev_f_idx=prev_phase * Float64(OscBuffersSize)
        )

    @doc_hidden
    def __init__(out self):
        self.buffers = [List[Float64]() for _ in range(4)] 
        self.basic_waveforms = List[MFloat[4]]()
        
        self.init_sine()  # Initialize sine wave buffer
        self.init_triangle()  # Initialize triangle wave buffer using harmonics
        self.init_sawtooth()  # Initialize sawtooth wave buffer using harmonics
        self.init_square()  # Initialize square wave buffer using harmonics

        self.init_basic_waveforms()  # Initialize basic waveforms for quick access

    # Build Wavetables:
    # =================
    @doc_hidden
    def init_sine(mut self):
        for i in range(OscBuffersSize):
            v = sin(2.0 * 3.141592653589793 * Float64(i) / Float64(OscBuffersSize))
            self.buffers[0].append(v)

    @doc_hidden
    def init_triangle(mut self):
        # Construct triangle wave from sine harmonics
        # Triangle formula: 8/pi^2 * sum((-1)^(n+1) * sin(n*x) / n^2) for n=1 to 512
        for i in range(OscBuffersSize):
            var x = 2.0 * 3.141592653589793 * Float64(i) / Float64(OscBuffersSize)
            var sample: Float64 = 0.0
            
            for n in range(1, 513):  # Using 512 harmonics
                var harmonic = sin(Float64(2 * n - 1) * x) / (Float64(2 * n - 1) * Float64(2 * n - 1))
                if n % 2 == 0:  # (-1)^(n+1) is -1 when n is even
                    harmonic = -harmonic

                sample += harmonic
            
            # Scale by 8/π² for correct amplitude
            self.buffers[1].append(8.0 / (3.141592653589793 * 3.141592653589793) * sample)

    @doc_hidden
    def init_sawtooth(mut self):
        # Construct sawtooth wave from sine harmonics
        # Sawtooth formula: 2/pi * sum((-1)^(n+1) * sin(n*x) / n) for n=1 to 512
        for i in range(OscBuffersSize):
            var x = 2.0 * 3.141592653589793 * Float64(i) / Float64(OscBuffersSize)
            var sample: Float64 = 0.0
            
            for n in range(1, 513):  # Using 512 harmonics
                var harmonic = sin(Float64(n) * x) / Float64(n)
                # if n % 2 == 0:  # (-1)^(n+1) is -1 when n is even
                #     harmonic = -harmonic
                sample += harmonic
            
            # Scale by 2/π for correct amplitude
            self.buffers[2].append(2.0 / 3.141592653589793 * sample)

    @doc_hidden
    def init_square(mut self):
        # Construct square wave from sine harmonics
        # Square formula: 4/pi * sum(sin((2n-1)*x) / (2n-1)) for n=1 to 512
        for i in range(OscBuffersSize):
            var x = 2.0 * 3.141592653589793 * Float64(i) / Float64(OscBuffersSize)
            var sample: Float64 = 0.0
            
            for n in range(1, 513):  # Using 512 harmonics
                var harmonic = sin(Float64(2 * n - 1) * x) / Float64(2 * n - 1)
                sample += harmonic
            
            # Scale by 4/π for correct amplitude
            self.buffers[3].append(4.0 / 3.141592653589793 * sample)

    @doc_hidden
    def init_basic_waveforms(mut self):
        for i in range(OscBuffersSize):
            self.basic_waveforms.append(MFloat[4](
                self.buffers[0][i],  # sine
                self.buffers[1][i],  # triangle
                self.buffers[2][i],  # sawtooth
                self.buffers[3][i]   # square
            ))
