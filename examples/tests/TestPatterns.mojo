

from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestPatterns(Movable, Copyable):
    var world: World
    var imp: Impulse[1]
    var messenger: Messenger
    var which: Int
    var pseq: Pseq[Int]
    var prand: Prand[Int]
    var pxrand: Pxrand[Int]

    def __init__(out self, world: World):
        self.world = world
        self.imp = Impulse[1](self.world)
        self.messenger = Messenger(world)
        self.which = 0
        self.pseq = Pseq([0, 1, 2, 3])
        self.prand = Prand([0, 1, 2, 3])
        self.pxrand = Pxrand([0, 1, 2, 3])

    def next(mut self) -> MFloat[2]:
        self.messenger.update("which", self.which) 
        trig = self.imp.next_bool(1)
        if trig:
            if self.which == 0:
                val = self.pseq.next()
                print("pseq val: ", val)
            elif self.which == 1:
                val = self.prand.next()
                print("prand val: ", val)
            else:
                val = self.pxrand.next()
                print("pxrand val: ", val)
        return [0.0, 0.0]