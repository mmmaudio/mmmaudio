from mmm_audio import *

struct Freeverb[num_chans: Int = 1](Movable, Copyable):
    """
    A custom implementation of the Freeverb reverb algorithm. Based on Romain Michon's Faust implementation (https://github.com/grame-cncm/faustlibraries/blob/master/reverbs.lib), thus is licensed under LGPL.

    Parameters:
      num_chans: Size of the SIMD vector - defaults to 1.
    """
    var world: World
    var lp_comb0: LP_Comb[Self.num_chans]
    var lp_comb1: LP_Comb[Self.num_chans]
    var lp_comb2: LP_Comb[Self.num_chans]
    var lp_comb3: LP_Comb[Self.num_chans]
    var lp_comb4: LP_Comb[Self.num_chans]
    var lp_comb5: LP_Comb[Self.num_chans]
    var lp_comb6: LP_Comb[Self.num_chans]
    var lp_comb7: LP_Comb[Self.num_chans]

    var temp: List[Float64]
    var allpasss: List[Allpass[Self.num_chans]]
    var feedback: List[Float64]
    var lp_comb_lpfreq: List[Float64]
    var in_list: List[Float64]

    def __init__(out self, world: World):
      """
      Initialize the Freeverb struct.

      Args:
          world: A pointer to the MMMWorld instance.
      """
      
        self.world = world
        
        # I tried doing this with lists of LP_Comb[N] but avoiding lists seems to work better in Mojo currently

        self.lp_comb0 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb1 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb2 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb3 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb4 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb5 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb6 = LP_Comb[Self.num_chans](self.world, 0.04)
        self.lp_comb7 = LP_Comb[Self.num_chans](self.world, 0.04)

        self.temp = [0.0 for _ in range(8)]
        self.allpasss = [Allpass[Self.num_chans](self.world, 0.015) for _ in range(4)]
        
        self.feedback = [0.0]
        self.lp_comb_lpfreq = [1000.0]
        self.in_list = [0.0]

    # @always_inline
    def next(mut self, input: MFloat[self.num_chans], room_size: MFloat[self.num_chans] = 0.0, lp_comb_lpfreq: MFloat[self.num_chans] = 1000.0, added_space: MFloat[self.num_chans] = 0.0) -> MFloat[self.num_chans]:
        """Process one sample through the freeverb.

        Args:
          input: The input sample to process.
          room_size: The size of the reverb room (0-1).
          lp_comb_lpfreq: The cutoff frequency of the low-pass filter (in Hz).
          added_space: The amount of added space (0-1).

        Returns:
          The processed output sample.

        """
        room_size_clipped = clip(room_size, 0.0, 1.0)
        added_space_clipped = clip(added_space, 0.0, 1.0)
        feedback = 0.28 + (room_size_clipped * 0.7)
        feedback2 = 0.5

        delay_offset = added_space_clipped * 0.0012

        out = self.lp_comb0.next(input, 0.025306122448979593 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb1.next(input, 0.026938775510204082 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb2.next(input, 0.02895691609977324 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb3.next(input, 0.03074829931972789 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb4.next(input, 0.03224489795918367 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb5.next(input, 0.03380952380952381 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb6.next(input, 0.03530612244897959 + delay_offset, feedback, lp_comb_lpfreq)
        out += self.lp_comb7.next(input, 0.03666666666666667 + delay_offset, feedback, lp_comb_lpfreq)

        out = self.allpasss[0].next(out, 0.012607709750566893, feedback2)
        out = self.allpasss[1].next(out, 0.01, feedback2)
        out = self.allpasss[2].next(out, 0.007732426303854875, feedback2)
        out = self.allpasss[3].next(out, 0.00510204081632653, feedback2)

        out = sanitize(out)

        return out  # Return the delayed sample

comptime dattoro_sr = 29761.

struct DattorroReverb[interp: Interp = Interp.none](Movable, Copyable):
  """Dattorro reverb algorithm created by Jon Dattorro in his classic paper "Effect Design Part 1: Reverberator and Other Filters".
  
  Parameters:
    interp: The interpolation method to use for the delay lines which are not modulated. Default is none because that is what is used in the original Dattorro paper.

  """
    var world: World
    var EXCURSION: Float64
    var shimmer: Osc[2]
    var decay: Float64
    var decay_diffusion1: Float64
    var decay_diffusion2: Float64
    var input_diffusion1: Float64
    var input_diffusion2: Float64
    var bandwidth: Float64
    var damping: Float64
    var feedback: MFloat[2]
    var pre_delay: Delay[]
    var pre_delay_time: Float64
    var one_pole: OnePole[]
    var allpass_early: List[Allpass[interp = Interp.none]]
    var early_dtimes: List[Float64]

    var ap1: Allpass[2, interp = Interp.lagrange4]
    var del1: Delay[2, interp = Self.interp]
    var pole: OnePole[2]
    var ap2: Allpass[2, interp = Self.interp]
    var del2: Delay[2, interp = Self.interp]

    var tank_delay_times: List[MFloat[2]]
    var tank_delay_samples: List[MInt[2]]

    var trap: DCTrap[2]

    var final_taps: List[MInt[]]

    def __init__(out self, world: World, pre_delay_time: Float64 = 0.02, decay: Float64 = 0.3, input_diffusion1: Float64 = 0.75, input_diffusion2: Float64 = 0.625, decay_diffusion1: Float64 = 0.7, decay_diffusion2: Float64 = 0.5, bandwidth: Float64 = 0.9995, damping: Float64 = 0.0005):
      """
      Initialize the DattorroReverb struct.

      Args:
          world: A pointer to the MMMWorld instance.
          pre_delay_time: The time of the pre-delay in seconds. 0-0.5 seconds.
          decay: The decay factor of the reverb (0-1). Larger values will create a longer reverb tail.
          input_diffusion1: The feedback coefficient for the first two allpass filters in the early reflection stage (0-1).
          input_diffusion2: The feedback coefficient for the second two allpass filters in the early reflection stage (0-1).
          decay_diffusion1: The feedback coefficient for two allpass filters in the tank (0-1).
          decay_diffusion2: The feedback coefficient for two allpass filters in the tank (0-1).
          bandwidth: The bandwidth of the low-pass filters in the tank (0-1, where 1 is no filtering).
          damping: The damping factor of the reverb (0-1, where 0 is no damping).
      """
        self.world = world
        self.EXCURSION = 16./dattoro_sr
        self.shimmer = Osc[2](world)

        self.decay = decay
        self.decay_diffusion1 = decay_diffusion1
        self.decay_diffusion2 = decay_diffusion2
        self.pre_delay_time = pre_delay_time
        self.input_diffusion1 = input_diffusion1
        self.input_diffusion2 = input_diffusion2
        self.bandwidth = bandwidth
        self.damping = damping 
        self.feedback = MFloat[2](0.0)

        self.pre_delay = Delay[](world, 0.5)
        self.one_pole = OnePole[](world)
        self.allpass_early = [Allpass[interp = Interp.none](world, 0.1) for _ in range(4)]
        self.early_dtimes = [142. / dattoro_sr, 107. / dattoro_sr, 379. / dattoro_sr, 277. / dattoro_sr]

        self.tank_delay_times = [MFloat[2](672./dattoro_sr, 908./dattoro_sr), MFloat[2](4453./dattoro_sr, 4217./dattoro_sr), MFloat[2](1800./dattoro_sr, 2656./dattoro_sr), MFloat[2](3720./dattoro_sr, 3163./dattoro_sr)]

        self.tank_delay_samples = [MInt[2](t * world[].sample_rate) for t in self.tank_delay_times]

        self.ap1 = Allpass[2, interp = Interp.lagrange4](world, 0.11)
        self.del1 = Delay[2, interp = Self.interp](world, 0.17)
        self.pole = OnePole[2](world)
        self.ap2 = Allpass[2, interp = Self.interp](world, 0.11)
        self.del2 = Delay[2, interp = Self.interp](world, 0.17)
        self.trap = DCTrap[2](world)

        self.final_taps = [MInt[1](266/dattoro_sr*world[].sample_rate), MInt[1](2974/dattoro_sr*world[].sample_rate), MInt[1](1913/dattoro_sr*world[].sample_rate), MInt[1](1996/dattoro_sr*world[].sample_rate), MInt[1](1990/dattoro_sr*world[].sample_rate), MInt[1](187/dattoro_sr*world[].sample_rate), MInt[1](1066/dattoro_sr*world[].sample_rate), \
        MInt[1](353/dattoro_sr*world[].sample_rate), MInt[1](3627/dattoro_sr*world[].sample_rate), MInt[1](1228/dattoro_sr*world[].sample_rate), MInt[1](2673/dattoro_sr*world[].sample_rate), MInt[1](2111/dattoro_sr*world[].sample_rate), MInt[1](335/dattoro_sr*world[].sample_rate), MInt[1](121/dattoro_sr*world[].sample_rate)]

    def set_all(mut self, pre_delay_time: Float64, decay: Float64, input_diffusion1: Float64, input_diffusion2: Float64, decay_diffusion1: Float64, decay_diffusion2: Float64, bandwidth: Float64, damping: Float64):
        """Set all the main parameters of the reverb at once.

        Args:
          pre_delay_time: The time of the pre-delay in seconds. 0-0.5 seconds.
          decay: The decay factor of the reverb (0-1).
          input_diffusion1: The diffusion amount for the first two allpass filters in the early reflection stage (0-1).
          input_diffusion2: The diffusion amount for the second two allpass filters in the early reflection stage (0-1).
          decay_diffusion1: The diffusion amount for the first allpass filter in the feedback loop (0-1).
          decay_diffusion2: The diffusion amount for the second allpass filter in the feedback loop (0-1).
          bandwidth: The bandwidth of the low-pass filters in the feedback loop (0-1, where 1 is no filtering).
          damping: The damping factor of the reverb (0-1, where 0 is no damping).
        """
        self.pre_delay_time = pre_delay_time
        self.decay = decay
        self.input_diffusion1 = input_diffusion1
        self.input_diffusion2 = input_diffusion2
        self.decay_diffusion1 = decay_diffusion1
        self.decay_diffusion2 = decay_diffusion2
        self.bandwidth = bandwidth
        self.damping = damping

    def next(mut self, input: MFloat[2]) -> MFloat[2]:
        
        upper = (input[0] + input[1]) * 0.5
        upper = self.pre_delay.next(upper,self.pre_delay_time)
        upper = self.one_pole.next(upper, 1-self.bandwidth)
        for i in range(len(self.allpass_early)):
          upper = self.allpass_early[i].next(upper, self.early_dtimes[i], self.input_diffusion1 if i < 2 else self.input_diffusion2)

        excursion = self.shimmer.next(MFloat[2](1, 0.707), MFloat[2](0.0, 0.678)) * self.EXCURSION

        tank = upper + self.feedback
        tank = self.ap1.next(tank, self.tank_delay_times[0] + excursion, self.decay_diffusion1)
        tank = self.del1.next(tank, self.tank_delay_samples[1])
        tank = self.pole.next(tank, self.damping)
        tank = tank * self.decay
        tank = self.ap2.next(tank, self.tank_delay_times[2], -self.decay_diffusion2)
        tank = self.del2.next(tank, self.tank_delay_samples[3])
        
        self.feedback = self.trap.next(MFloat[2](tank[1], tank[0])) # flip left and right for feedback

        accumulator = MFloat[2](0.0, 0.6) * self.del1.tap(self.final_taps[0])
        accumulator += MFloat[2](0.0, 0.6) * self.del1.tap(self.final_taps[1])
        accumulator -= MFloat[2](0.0, 0.6) * self.ap2.tap(self.final_taps[2])
        accumulator += MFloat[2](0.0, 0.6) * self.del2.tap(self.final_taps[3])
        accumulator -= MFloat[2](0.6, 0.0) * self.del1.tap(self.final_taps[4])
        accumulator -= MFloat[2](0.6, 0.0) * self.ap2.tap(self.final_taps[5])
        accumulator -= MFloat[2](0.6, 0.0) * self.del2.tap(self.final_taps[6])
        L = accumulator.reduce_add()

        accumulator = MFloat[2](0.6, 0.0) * self.del1.tap(self.final_taps[7])
        accumulator += MFloat[2](0.6, 0.0) * self.del1.tap(self.final_taps[8])
        accumulator -= MFloat[2](0.6, 0.0) * self.ap2.tap(self.final_taps[9])
        accumulator += MFloat[2](0.6, 0.0) * self.del2.tap(self.final_taps[10])
        accumulator -= MFloat[2](0.0, 0.6) * self.del1.tap(self.final_taps[11])
        accumulator -= MFloat[2](0.0, 0.6) * self.ap2.tap(self.final_taps[12])
        accumulator -= MFloat[2](0.0, 0.6) * self.del2.tap(self.final_taps[13])
        R = accumulator.reduce_add()

        return MFloat[2](L, R)

struct Phaser[num_chans: Int = 1, stages: Int = 8](Movable, Copyable):
    """A phaser effect implemented as a series of allpass filters, with the center frequencies modulated by an LFO.
    
    Parameters:
        num_chans: The number of audio channels to process (e.g. 1 for mono, 2 for stereo).
        stages: The number of allpass filter stages to use in the phaser. More stages will create a more pronounced phasing effect. Usually between 4 and 12..
    """
    var world: World
    var all_passes: List[SVF[Self.num_chans]]
    var lfo: LFOsc[]

    def __init__(out self, world: World):
        """Initialize the phaser effect.
        
        Args:
            world: The World instance.
        """
        self.world = world
        self.all_passes = [SVF[Self.num_chans](self.world) for _ in range (Self.stages)]
        self.lfo = LFOsc[](world)

    def next(mut self, input: MFloat[Self.num_chans], center_freq: MFloat[1] = 1000., Q: MFloat[1] = 0.7, lfo_freq: MFloat[1] = 0.7, lfo_octaves: MFloat[1] = 1., freq_offset: MFloat[1] = 0., mix: MFloat[1] = 0.5) -> MFloat[Self.num_chans]:
        """Process the input audio through the phaser effect.

        Args:
            input: The input audio signal to process, as an MFloat vector with length equal to num_chans.
            center_freq: The base center frequency for the allpass filters, in Hz. This is the frequency around which the phasing effect will occur.
            Q: The resonance of the allpass filters.
            lfo_freq: The frequency of the LFO that modulates the center frequencies of the allpass filters, in Hz.
            lfo_octaves: The number of octaves above and below the base center frequency that the LFO will modulate. For example, if center_freq is 1000 Hz and lfo_octaves is 1, then the LFO will modulate between 500 Hz and 2000 Hz.
            freq_offset: A fixed frequency offset applied to each subsequent allpass stage. For example, if freq_offset is 0.1 and center_freq is 1000 Hz, then the first stage will be centered at 1000 Hz, the second at 1100 Hz, the third at 1200 Hz, etc.
            mix: The wet/dry mix of the effect. A value of 0 means only the original signal (dry), while a value of 1 means only the processed signal (wet). Values in between blend the two signals together.
        """

        allpass_out = input
        lfo = self.lfo.next[OscType.triangle](lfo_freq)
        center_freq_real = abs(center_freq)
        center_freq_real = center_freq_real + linexp(lfo, -1., 1., center_freq_real/(2**lfo_octaves), center_freq_real*(2**lfo_octaves))
        for i in range(Self.stages):
            freq_offset_real = 1.0 + (MFloat[1](i) * freq_offset)
            allpass_out = self.all_passes[i].allpass(allpass_out, clip(center_freq_real * freq_offset_real, 20., 20000.), Q)
        mix_real = clip(mix, 0., 1.)
        wet_dry = sqrt(MFloat[2](mix_real, 1.0 - mix_real))
        return (allpass_out * wet_dry[0]) + (input * wet_dry[1])


struct Flanger[num_chans: Int = 1, interp: Interp = Interp.lagrange4](Movable, Copyable):
    """A flanger effect implemented as a single comb filter with the delay time modulated by an LFO.

    Parameters:
        num_chans: The number of audio channels to process (e.g. 1 for mono, 2 for stereo).
        interp: The interpolation method to use for the delay line.
    """
    var world: World
    var comb: Comb[Self.num_chans, Self.interp]
    var lfo: LFOsc[]

    def __init__(out self, world: World):
        self.world = world
        self.comb = Comb[Self.num_chans, Self.interp](self.world, max_delay_time=0.05)
        self.lfo = LFOsc[](world)

    def next(mut self, input: MFloat[Self.num_chans], center_freq: MFloat[1], feedback_coef: MFloat[1], lfo_freq: MFloat[1], lfo_octaves: MFloat[1], mix: MFloat[1]) -> MFloat[Self.num_chans]:
        """Process the input audio through the flanger effect.

        Args:
            input: The input audio signal to process, as an MFloat vector with length equal to num_chans.
            center_freq: The base delay time for the comb filter, in milliseconds. This is the delay time around which the flanging effect will occur.
            feedback_coef: The feedback coefficient for the comb filter (0-1). Higher values will create a more pronounced flanging effect, but can also lead to self-oscillation if set too high.
            lfo_freq: The frequency of the LFO that modulates the delay time of the comb filter, in Hz.
            lfo_octaves: The number of octaves above and below the base center frequency that the LFO will modulate. For example, if center_freq is 1000 Hz and lfo_octaves is 1, then the LFO will modulate between 500 Hz and 2000 Hz.
            mix: The wet/dry mix of the effect. A value of 0 means only the original signal (dry), while a value of 1 means only the processed signal (wet). Values in between blend the two signals together.
        """
        lfo = self.lfo.next[OscType.triangle](lfo_freq)
        center_freq_real = abs(center_freq)
        center_freq_real = center_freq_real + linexp(lfo, -1., 1., center_freq_real/(2**lfo_octaves), center_freq_real*(2**lfo_octaves))
        center_freq_real = clip(center_freq_real, 20., 20000.)
        
        comb = self.comb.next(input, 1./center_freq_real, feedback_coef)
        
        mix_real = clip(mix, 0., 1.)
        wet_dry = sqrt(MFloat[2](mix_real, 1.0 - mix_real))
        return (comb * wet_dry[0]) + (input * wet_dry[1])