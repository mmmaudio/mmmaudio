from mmm_audio import *

struct PAF_example(Copyable, Movable):
    var world: World

    var paf: PAF[2, Interp.sinc, 1, wrap_gaussian=True] # try changing wrap_gaussian to True

    var fund: MFloat[]
    var center: MFloat[]
    var band: MFloat[]

    var env: Env[]
    var trig: Bool

    var m: Messenger

    def __init__(out self, world: World):
        self.world = world

        self.paf = PAF[2, Interp.sinc, 1, wrap_gaussian=True](world)# try changing wrap_gaussian to True

        self.fund = 73.0
        self.center = 440.0
        self.band = 100

        self.env = Env(world)
        self.env.params = EnvParams([0, 1, 0], [0.01, 0.07])
        self.trig = False

        self.m = Messenger(world)

    def next(mut self) -> MFloat[2]:
        self.m.update("fundamental", self.fund)
        self.m.update("center_freq", self.center)
        self.m.update("bandwidth", self.band)
        self.trig = self.m.notify_trig("trig")

        env = self.env.next[interp=Interp.linear](self.trig)

        osc = self.paf.next(self.fund, self.center, self.band)
        out = osc * env
        # print("osc: " + String(osc))

        return out
