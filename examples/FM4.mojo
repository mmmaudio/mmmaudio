from mmm_audio import *

struct FM4(Movable, Copyable):
    var oversampled_world: World

    comptime times_oversampling = TimesOversampling.x4

    var over: Downsampler[2, Self.times_oversampling]

    var osc0: Osc[1, Interp.sinc]
    var osc1: Osc[1, Interp.sinc]
    var osc2: Osc[1, Interp.sinc]
    var osc3: Osc[1, Interp.sinc]

    var osc0_freq: MFloat[1]
    var osc1_freq: MFloat[1]
    var osc2_freq: MFloat[1]
    var osc3_freq: MFloat[1]

    var osc0_mul: List[MFloat[1]]
    var osc1_mul: List[MFloat[1]]
    var osc2_mul: List[MFloat[1]]
    var osc3_mul: List[MFloat[1]]
    var m: Messenger

    var fb: List[MFloat[1]]

    var osc_frac: List[MFloat[1]]

    def __init__(out self, world: World) :
        # create a subworld for the downsampling to live in
        self.oversampled_world = create_subworld(world, Self.times_oversampling)

        # the oversampler exists in the main world! don't give it the oversampled world!
        self.over = Downsampler[2, Self.times_oversampling](world)

        # the oscillators live in the oversampled world since they need to run at the oversampled rate
        self.osc0 = Osc[1, Interp.sinc](self.oversampled_world)
        self.osc1 = Osc[1, Interp.sinc](self.oversampled_world)
        self.osc2 = Osc[1, Interp.sinc](self.oversampled_world)
        self.osc3 = Osc[1, Interp.sinc](self.oversampled_world)

        # set the initial frequencies
        self.osc0_freq = 220.0
        self.osc1_freq = 440.0
        self.osc2_freq = 220.0
        self.osc3_freq = 220.0

        # initial modulation amounts for each oscillator
        self.osc0_mul = [0.0, 0.0]
        self.osc1_mul = [0.0, 0.0]
        self.osc2_mul = [0.0, 0.0]
        self.osc3_mul = [0.0, 0.0]

        # the value that controls the warping of the oscillators' waveforms
        self.osc_frac = [0.0, 0.0, 0.0, 0.0]
        # output of each oscillator to be fed back in the next audio cycle
        self.fb = [0.0, 0.0, 0.0, 0.0]

        self.m = Messenger(self.oversampled_world)

    def next_ov_loop(mut self):
        for _ in range(Self.times_oversampling.times):
            fm_0 = self.fb[1] * self.osc0_mul[0] + self.fb[2] * self.osc0_mul[1]
            osc0 = self.osc0.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](self.osc0_freq + fm_0, osc_frac=self.osc_frac[0])

            fm_1 = osc0 * self.osc1_mul[0] + self.fb[3] * self.osc1_mul[1]
            osc1 = self.osc1.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](self.osc1_freq + fm_1, osc_frac=self.osc_frac[1])

            fm_2 = osc1 * self.osc2_mul[0] + self.fb[3] * self.osc2_mul[1]
            osc2 = self.osc2.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](self.osc2_freq + fm_2, osc_frac=self.osc_frac[2])

            fm_3 = osc0 * self.osc3_mul[0] + osc1 * self.osc3_mul[1]
            osc3 = self.osc3.next_basic_waveforms[OscType.sine, OscType.triangle, OscType.saw, OscType.square](self.osc3_freq + fm_3, osc_frac=self.osc_frac[3])

            # feedback all the oscillators for the next cycle
            self.fb = [osc0, osc1, osc2, osc3]

            # add the sample to the downsampling buffer (we only hear the first two oscillators)
            self.over.add_sample(MFloat[2](osc0, osc1))
        

    def next(mut self) -> MFloat[2]:

        self.m.update("osc0_freq", self.osc0_freq)
        self.m.update("osc1_freq", self.osc1_freq)
        self.m.update("osc2_freq", self.osc2_freq)
        self.m.update("osc3_freq", self.osc3_freq)

        self.m.update("osc0_mula", self.osc0_mul[0])
        self.m.update("osc0_mulb", self.osc0_mul[1])

        self.m.update("osc1_mula", self.osc1_mul[0])
        self.m.update("osc1_mulb", self.osc1_mul[1])

        self.m.update("osc2_mula", self.osc2_mul[0])
        self.m.update("osc2_mulb", self.osc2_mul[1])

        self.m.update("osc3_mula", self.osc3_mul[0])
        self.m.update("osc3_mulb", self.osc3_mul[1])

        self.m.update("osc_frac0", self.osc_frac[0])
        self.m.update("osc_frac1", self.osc_frac[1])
        self.m.update("osc_frac2", self.osc_frac[2])
        self.m.update("osc_frac3", self.osc_frac[3])

        self.next_ov_loop()

        # downsample the oversampled signal and return
        return self.over.get_sample() * 0.25
