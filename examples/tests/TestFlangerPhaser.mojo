from mmm_audio import *

struct TestFlangerPhaser(Movable, Copyable):
    var world: World
    var m: Messenger
    var which_source: Int
    var which_fx: MFloat[1]
    var buf: SIMDBuffer[2]
    var play: Play
    var phasor: Phaser[2]
    var flanger: Flanger[2]

    var center: MFloat[1]
    var Q: MFloat[1]
    var feedback_coef: MFloat[1]
    var lfo_freq: MFloat[1]
    var lfo_octaves: MFloat[1]
    var freq_offset: MFloat[1]
    var mix: MFloat[1]


    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(world)
        self.buf = SIMDBuffer.load("resources/Shiverer.wav")
        self.play = Play(self.world)
        self.which_source = 0
        self.which_fx = 0

        self.phasor = Phaser[2](world)
        self.flanger = Flanger[2](world)
        self.center = MFloat[1](1000.)
        self.Q = MFloat[1](0.7)
        self.feedback_coef = MFloat[1](0.5)
        self.lfo_freq = MFloat[1](0.7)
        self.lfo_octaves = MFloat[1](1.)
        self.freq_offset = MFloat[1](0.)
        self.mix = MFloat[1](0.5)

    def next(mut self) -> MFloat[2]:
        self.m.update("which_source", self.which_source)
        self.m.update("which_fx", self.which_fx)
        self.m.update("center_freq", self.center)
        self.m.update("Q", self.Q) 
        self.m.update("feedback_coef", self.feedback_coef)
        self.m.update("lfo_freq", self.lfo_freq)
        self.m.update("lfo_octaves", self.lfo_octaves)
        self.m.update("freq_offset", self.freq_offset)
        self.m.update("mix", self.mix) 

        sample = self.play.next(self.buf)

        if self.which_source != 0:
            sample = MFloat[2](rrand(-1., 1.), rrand(-1., 1.)) * 0.1

        phaser = self.phasor.next(sample, self.center, self.Q, self.lfo_freq, self.lfo_octaves, self.freq_offset, self.mix)
        flanger = self.flanger.next(sample, self.center, self.feedback_coef, self.lfo_freq, self.lfo_octaves, self.mix)

        out = select(self.which_fx, phaser, flanger)

        return out 