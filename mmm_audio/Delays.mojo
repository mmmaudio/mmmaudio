from mmm_audio import *
from std.math import tanh
from std.math import log
from std.bit import next_power_of_two

# would be great - but in order for this to mean something we need params in structs or 
trait Tapable(Movable, Copyable):
  ...
#     def tap[num_chans: Int](mut self, delay_samps: MInt[num_chans]) -> MFloat[num_chans]:
#       ...
#     def tap[num_chans: Int](mut self, delay_time: MFloat[num_chans]) -> MFloat[num_chans]:
#       ...

struct Delay[num_chans: Int = 1, interp: Interp = Interp.linear](Tapable, PolyReset):
    """A variable delay line with interpolation.

    Parameters:
      num_chans: Size of the SIMD vector - defaults to 1.
      interp: The interpolation method to use. See the struct [Interp](MMMWorld.md#struct-interp) for interpolation options.
    """

    var world: World
    var max_delay_time: Float64
    var max_delay_samples: Int
    var delay_line: Recorder[Self.num_chans]
    var two_sample_duration: Float64
    var sample_duration: Float64

    def __init__(out self, world: World, max_delay_time: Float64 = 1.0):
      """Initialize the Delay line.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_time: The maximum delay time in seconds. The internal buffer will be allocated to accommodate this delay.
      """
        self.world = world
        self.max_delay_time = max_delay_time
        self.max_delay_samples = Int(max_delay_time * self.world[].sample_rate)
        var size_of_buffer = self.max_delay_samples

        comptime if Self.interp == Interp.linear:
          size_of_buffer += 1
        elif Self.interp == Interp.cubic or Self.interp == Interp.quad:
          size_of_buffer += 2
        elif Self.interp == Interp.lagrange4:
          size_of_buffer += 4
        
        self.delay_line = Recorder[Self.num_chans](self.world, size_of_buffer, self.world[].sample_rate)
        self.two_sample_duration = 2.0 / self.world[].sample_rate
        self.sample_duration = 1.0 / self.world[].sample_rate

    def __init__(out self, world: World, max_delay_samples: Int = 1024):
      """Initialize the Delay line.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_samples: The maximum delay time in samples. The internal buffer will be allocated to accommodate this delay.
      """
        self.world = world
        self.max_delay_time = Float64(max_delay_samples) / self.world[].sample_rate
        self.max_delay_samples = max_delay_samples
        var size_of_buffer = self.max_delay_samples
        
        comptime if Self.interp == Interp.linear:
          size_of_buffer += 1
        elif Self.interp == Interp.cubic or Self.interp == Interp.quad:
          size_of_buffer += 2
        elif Self.interp == Interp.lagrange4:
          size_of_buffer += 4

        self.delay_line = Recorder[Self.num_chans](self.world, size_of_buffer, self.world[].sample_rate)
        self.two_sample_duration = 2.0 / self.world[].sample_rate
        self.sample_duration = 1.0 / self.world[].sample_rate

    def tap(mut self, var delay_samps: Int) -> MFloat[Self.num_chans]:
      """Taps into the delay line at an exact sample delay and no interpolation. Tap is different from read in that it always returns the full SIMD vector of one point in the delay line.

      Args:
        delay_samps: The amount of delay to apply (in samples).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with no interpolation.
      """
      idx = (self.delay_line.write_head + delay_samps) % self.delay_line.buf.num_frames
      return self.delay_line.buf.data[idx]

    def tap(mut self, var delay_time: Float64) -> MFloat[Self.num_chans]:
      """Taps into the delay line at a fractional delay time with `Self.interp` interpolation. Tap is different from read in that it always returns the full SIMD vector of one point in the delay line.

      Args:
        delay_time: The amount of delay to apply (in seconds).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with specified interpolation.
      """

      return self.delay_line.buf.at_phase[Self.interp, True, 0](self.world, self.get_phase(delay_time), 0)

    @always_inline
    def read(mut self, var delay_samps: MInt[Self.num_chans]) -> MFloat[Self.num_chans]:
      """Reads into the delay line at an exact sample delay and no interpolation.

      Args:
        delay_samps: (MInt) The amount of delay to apply (in samples).

      Returns:
        A single sample read from the delay buffer with no interpolation.
      """
      comptime if Self.num_chans == 1:
        return self.tap(Int(delay_samps[0]))
      else:
        idx = (MInt[1](self.delay_line.write_head) + delay_samps) % MInt[1](self.delay_line.buf.num_frames)
        a_l_e = all_lanes_equal(delay_samps)
        if a_l_e:
          return self.tap(Int(delay_samps[0]))
        else:
          out = MFloat[Self.num_chans](0.0)
          for chan in range(Self.num_chans):
            out[chan] = self.delay_line.buf.data[idx[chan]][chan]
          return out

    @always_inline
    def read(mut self, var delay_time: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
      """Reads into the delay line at a fractional delay time with `Self.interp` interpolation.

      Args:
        delay_time: (MFloat) The amount of delay to apply (in seconds).

      Returns:
        A single sample read from the delay buffer with specified interpolation.
      """
      delay_time = min(delay_time, self.max_delay_time)
      comptime if Self.num_chans == 1:
        return self.tap(delay_time[0])
      else:
        a_l_e = all_lanes_equal(delay_time)
        if a_l_e:
          return self.tap(delay_time[0])
        else:
          out = MFloat[Self.num_chans](0.0)
          for chan in range(Self.num_chans):
            out[chan] = self.tap(delay_time[chan])[chan]
        return out

    @always_inline
    def write(mut self, input: MFloat[Self.num_chans]):
      """Writes a single sample into the delay line.

      Args:
        input: The input sample to store in the delay buffer.
      """

        self.delay_line.write_previous(input)

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], delay_samps: MInt[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the delay line, first reading from the delay then writing into it. This version uses an integer lookup into the delay line and no interpolation.

        Args:
          input: The input sample to process.
          delay_samps: The amount of delay to apply (in samples).

        Returns:
          The processed output sample.
        """
        
        out = self.read(delay_samps)
        self.write(input)

        return out

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], var delay_time: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the delay line, first reading from the delay then writing into it.

        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).

        Returns:
          The processed output sample.
        """
        
        out = self.read(delay_time)
        self.write(input)

        return out

    def reset(mut self):
        """Reset the delay line to its initial state. This will clear the internal buffer and reset the write head."""
        self.delay_line.buf.zero()

    @always_inline
    def get_phase(self, delay_time: Float64) -> Float64:
        """Calculate the fractional index in the delay buffer for the given delay time.

        Args:
          delay_time: The delay time in seconds.

        Returns:
          The fractional index in the delay buffer.
        """

        delay_samps = max(delay_time, self.sample_duration) * self.world[].sample_rate
        # Because the SpanInterpolator functions always "read" forward,
        # we're writing into the delay line buffer backwards, so therefore,
        # here to go backwards in time we add the delay samples to the write head.
        f_idx = (Float64(self.delay_line.write_head) + delay_samps) % Float64(self.delay_line.buf.num_frames)
        return f_idx / Float64(self.delay_line.buf.num_frames)



def calc_feedback[num_chans: Int = 1](delaytime: MFloat[num_chans], decaytime: MFloat[num_chans]) -> MFloat[num_chans]:
      """Calculate the feedback coefficient for a Comb filter or Allpass line based on desired delay time and decay time.
      
      Parameters:
        num_chans: Number of channels.

      Args:
        delaytime: The delay time in seconds.
        decaytime: The decay time in seconds (time to -60dB).

      Returns:
        The feedback coefficient for the requested delay and decay times.
      """
      
      comptime log001: Float64 = log(0.001)

      zero: MBool[num_chans] = delaytime.eq(0) or decaytime.eq(0)
      dec_pos: MBool[num_chans] = decaytime.ge(0)

      absret = exp(log001 * delaytime / abs(decaytime))

      return zero.select(MFloat[num_chans](0.0), dec_pos.select(absret, -absret))

struct Comb[num_chans: Int = 1, interp: Interp = Interp.quad](Tapable, PolyReset):
    """
    A simple comb filter using a delay line with feedback.

    Parameters:
      num_chans: Size of the SIMD vector.
      interp: The interpolation method to use. See the struct [Interp](MMMWorld.md#struct-interp) for interpolation options.

    """

    var world: World
    var delay: Delay[Self.num_chans, Self.interp]
    var fb: MFloat[Self.num_chans]

    def __init__(out self, world: World, max_delay_time: Float64 = 1.0):
      """Initialize the Comb filter.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_time: The maximum delay time in seconds. The internal buffer will be allocated to accommodate this delay.
      """
        self.world = world
        self.delay = Delay[Self.num_chans, Self.interp](self.world, max_delay_time)
        self.fb = MFloat[Self.num_chans](0.0)

    def tap(mut self, delay_samps: Int) -> MFloat[Self.num_chans]:
      """Taps into the delay line at an exact sample delay and no interpolation.

      Args:
        delay_samps: The amount of delay to apply (in samples).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with no interpolation.
      """
        return self.delay.tap(delay_samps)
        
    def tap(mut self, delay_time: Float64) -> MFloat[Self.num_chans]:
      """Taps into the delay line at a fractional delay time with `Self.interp` interpolation.

      Args:
        delay_time: The amount of delay to apply (in seconds).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with specified interpolation.
      """
        return self.delay.tap(delay_time)

    def reset(mut self):
        """Reset the Comb filter to its initial state. This will clear the internal buffer and reset the feedback."""
        self.delay.reset()
        self.fb = MFloat[Self.num_chans](0.0)

    def next(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans] = 0.0, feedback: MFloat[Self.num_chans] = 0.0) -> MFloat[Self.num_chans]:
        """Process one sample through the comb filter.
        
        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          feedback: The amount of feedback to apply (-1.0 to 1.0).

        Returns:
          The delayed output sample.
        """
        var delayed = self.delay.read(delay_time)  # read first
        var fb_in = input + delayed * clip(feedback, -1.0, 1.0)
        self.delay.write(fb_in)  # write separately
        return delayed

    def next_decaytime(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans], decay_time: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the comb filter with decay time calculation.
        
        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          decay_time: The desired decay time (time to -60dB). Feedback is calculated internally.

        Returns:
          The delayed output sample.
        """
        feedback = calc_feedback(delay_time, decay_time)
        return self.next(input, delay_time, feedback)

struct LP_Comb[num_chans: Int = 1, interp: Interp = Interp.linear](Tapable, PolyReset):
    """
    A simple comb filter with an integrated one-pole low-pass filter.
    
    Parameters:
      num_chans: Size of the SIMD vector - defaults to 1.
      interp: The interpolation method to use. See the struct [Interp](MMMWorld.md#struct-interp) for interpolation options.
    """
    var world: World
    var delay: Delay[Self.num_chans, Self.interp] # Delay line without automatic feedback
    var one_pole: OnePole[Self.num_chans]
    var fb: MFloat[Self.num_chans]

    def __init__(out self, world: World, max_delay_time: Float64 = 1.0):
      """Initialize the LP_Comb filter.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_time: The maximum delay time in seconds. The internal buffer will be allocated to accommodate this delay.
      """ 

        self.world = world
        self.delay = Delay[Self.num_chans, Self.interp](self.world, max_delay_time)
        self.one_pole = OnePole[Self.num_chans](self.world)
        self.fb = MFloat[Self.num_chans](0.0)

    def tap(mut self, delay_samps: Int) -> MFloat[Self.num_chans]:
      """Taps into the delay line at an exact sample delay and no interpolation.

      Args:
        delay_samps: The amount of delay to apply (in samples).

      Returns:
        A single sample read from the delay buffer with no interpolation.
      """
        return self.delay.tap(delay_samps)
        
    def tap(mut self, delay_time: Float64) -> MFloat[Self.num_chans]:
      """Taps into the delay line at a fractional delay time with `Self.interp` interpolation.

      Args:
        delay_time: The amount of delay to apply (in seconds).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with specified interpolation.
      """
        return self.delay.tap(delay_time)

    @always_inline
    def next(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans] = 0.0, feedback: MFloat[Self.num_chans] = 0.0, lp_freq: MFloat[Self.num_chans] = 0.0) -> MFloat[Self.num_chans]:
        """Process one sample through the comb filter.

        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          feedback: The amount of feedback to apply (-1.0 to 1.0).
          lp_freq: The cutoff frequency of the OnePole filter in the feedback loop.

        Returns:
          The processed output sample.
        """
        fb_in = input + self.fb * clip(feedback, -1.0, 1.0)
        var out = self.delay.next(fb_in, delay_time)

        self.fb = self.one_pole.lpf(out, lp_freq)  # Low-pass filter the feedback

        return out

    def reset(mut self):
      """Reset the LP_Comb filter to its initial state. This will clear the internal buffer and reset the feedback."""
      self.delay.reset()
      self.one_pole.reset()
      self.fb = MFloat[Self.num_chans](0.0)

struct Allpass[num_chans: Int = 1, interp: Interp = Interp.linear](Tapable, PolyReset):
    """
    A simple allpass filter using a delay line with feedback.
    
    Parameters:
      num_chans: Size of the SIMD vector.
      interp: The interpolation method to use. See the struct [Interp](MMMWorld.md#struct-interp) for interpolation options.
    """
    var world: World
    var delay: Delay[Self.num_chans, Self.interp]

    def __init__(out self, world: World, max_delay_time: Float64 = 1.0):
      """Initialize the Allpass filter.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_time: The maximum delay time in seconds. The internal buffer will be allocated to accommodate this delay.
      """

        self.world = world
        self.delay = Delay[Self.num_chans, Self.interp](self.world, max_delay_time)

    def tap(mut self, delay_samps: Int) -> MFloat[Self.num_chans]:
      """Taps into the delay line at an exact sample delay and no interpolation.

      Args:
        delay_samps: The amount of delay to apply (in samples).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with no interpolation.
      """
        return self.delay.tap(delay_samps)
        
    def tap(mut self, delay_time: Float64) -> MFloat[Self.num_chans]:
      """Taps into the delay line at a fractional delay time with `Self.interp` interpolation.

      Args:
        delay_time: The amount of delay to apply (in seconds).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with specified interpolation.
      """
        return self.delay.tap(delay_time)

    def next(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans] = 0.0, feedback_coef: MFloat[Self.num_chans] = 0.0) -> MFloat[Self.num_chans]:
        """Process one sample through the allpass filter. Uses a direct-form 1 structure.

        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          feedback_coef: The feedback coefficient (-1.0 to 1.0).

        Returns:
          The delayed/filtered output sample.
        """

        var delayed = self.delay.read(delay_time)
        var to_delay = input + feedback_coef * delayed
        var output = delayed - feedback_coef * to_delay  
        self.delay.write(to_delay)
        
        return output

    def next_df2(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans] = 0.0, feedback_coef: MFloat[Self.num_chans] = 0.0) -> MFloat[Self.num_chans]:
      """Process one sample through the allpass filter using a direct-form 2 structure.

      Args:
        input: The input sample to process.
        delay_time: The amount of delay to apply (in seconds).
        feedback_coef: The feedback coefficient.

      Returns:
        The delayed and phase-rotated output sample.
      """

        var delayed = self.delay.read(delay_time)
        var to_delay = input + feedback_coef * delayed
        var output = (-feedback_coef * input) + delayed
        self.delay.write(to_delay)
        
        return output

    def next_decaytime(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans], decay_time: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample through the allpass filter with decay time calculation.
        
        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          decay_time: The desired decay time (time to -60dB).

        Returns:
          The delayed output sample with feedback derived from decay time.
        """
        feedback = calc_feedback(delay_time, decay_time)
        return self.next(input, delay_time, feedback)

    def reset(mut self):
        """Reset the allpass filter to its initial state. This will clear the internal buffer."""
        self.delay.reset()
        

struct FB_Delay[num_chans: Int = 1, interp: Interp = Interp.lagrange4, ADAA_dist: Bool = False, ov_samp: TimesOversampling = TimesOversampling.none](Tapable, PolyReset):
    """A feedback delay structured like a Comb filter, but with possible feedback coefficient above 1 due to an integrated tanh function.
    
    By default, Anti-aliasing is disabled and no oversampling is applied, but this can be changed by setting the ADAA_dist and ov_samp template parameters.
    
    Parameters:
      num_chans: Size of the SIMD vector.
      interp: The interpolation method to use. See the struct [Interp](MMMWorld.md#struct-interp) for interpolation options.
      ADAA_dist: Whether to apply ADAA distortion to the feedback signal instead of standard tanh.
      ov_samp: The [TimesOversampling](MMMWorld.md#struct-timesoversampling) for ADAA distortion.
    """

    var world: World
    var delay: Delay[Self.num_chans, Self.interp]
    var dc: DCTrap[Self.num_chans]
    var fb: MFloat[Self.num_chans]
    var tanh_ad: TanhAD[Self.num_chans, Self.ov_samp]

    def __init__(out self, world: World, max_delay_time: Float64 = 1.0):
      """Initialize the FB_Delay.

      Args:
        world: A pointer to the MMMWorld.
        max_delay_time: The maximum delay time in seconds. The internal buffer will be allocated to accommodate this delay.
      """

        self.world = world
        self.delay = Delay[Self.num_chans, Self.interp](self.world, max_delay_time)
        self.dc = DCTrap[Self.num_chans](self.world)
        self.fb = MFloat[Self.num_chans](0.0)
        self.tanh_ad = TanhAD[Self.num_chans, Self.ov_samp](self.world)

    def tap(mut self, delay_samps: Int) -> MFloat[Self.num_chans]:
      """Taps into the delay line at an exact sample delay and no interpolation.

      Args:
        delay_samps: The amount of delay to apply (in samples).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with no interpolation.
      """
        return self.delay.tap(delay_samps)
        
    def tap(mut self, delay_time: Float64) -> MFloat[Self.num_chans]:
      """Taps into the delay line at a fractional delay time with `Self.interp` interpolation.

      Args:
        delay_time: The amount of delay to apply (in seconds).

      Returns:
        A single `Self.num_chans` sized sample read from the delay buffer with specified interpolation.
      """
        return self.delay.tap(delay_time)

    def reset(mut self):
        """Reset the FB_Delay to its initial state. This will clear the internal buffer and reset the feedback."""
        self.delay.reset()
        self.dc.reset()
        self.tanh_ad.reset()
        self.fb = MFloat[Self.num_chans](0.0)

    def next(mut self, input: MFloat[Self.num_chans], delay_time: MFloat[Self.num_chans], feedback: MFloat[Self.num_chans]) -> MFloat[Self.num_chans]:
        """Process one sample or SIMD vector through the feedback delay.
        
        Args:
          input: The input sample to process.
          delay_time: The amount of delay to apply (in seconds).
          feedback: The amount of feedback to apply (0.0 to 1.0).

        Returns:
          The processed output sample or SIMD vector.
        """
        var out = self.delay.next(self.fb, delay_time)  # Get the delayed sample

        comptime if Self.ADAA_dist:
            self.fb = self.dc.next(self.tanh_ad.next((input + out) * feedback))
        else:
          self.fb = self.dc.next(tanh((input + out) * feedback))

        return out  # Return the delayed sample
