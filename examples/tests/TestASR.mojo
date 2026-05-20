
from mmm_audio import *

struct TestASR(Movable, Copyable):
    var world: World
    var env: ASREnv
    var synth: Osc[]
    var messenger: Messenger
    var curves: MFloat[2]
    var gate: Bool

    def __init__(out self, world: World):
        self.world = world
        self.env = ASREnv(self.world)
        self.synth = Osc(self.world)
        self.messenger = Messenger(self.world)
        self.curves = MFloat[2](1.0, 1.0)
        self.gate = False

    def next(mut self) -> MFloat[2]:
        self.messenger.update("curves", self.curves) 
        self.messenger.update("gate", self.gate) 

        env = self.env.next(self.world[].mouse_x, 1, self.world[].mouse_y, self.gate, self.curves)
        sample = self.synth.next(200)
        return env * sample * 0.1



        