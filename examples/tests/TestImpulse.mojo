

from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestImpulse(Movable, Copyable):
    var world: World
    var synth: Impulse[2]
    var trig: MBool[2]
    var freqs: MFloat[2]
    var messenger: Messenger
    var ints: List[Int]
    var phase_offsets: MFloat[2]

    def __init__(out self, world: World):
        self.world = world
        self.synth = Impulse[2](self.world)
        self.trig = MBool[2](fill=True)
        self.freqs = MFloat[2](5,5)
        self.messenger = Messenger(world)
        self.ints = []
        self.phase_offsets = MFloat[2](0.0, 0.0)


    def next(mut self) -> MFloat[2]:
        if self.messenger.notify_update("trig", self.ints) :
            for i in range(min(2, len(self.ints))):
                self.trig[i] = self.ints[i] > 0
        else:
            self.trig = MBool[2](fill = False)

        offsets = [0.0,0.0]
        if self.messenger.notify_update("phase_offsets", offsets):
            for i in range(min(2, len(offsets))):
                self.phase_offsets[i] = offsets[i]

        freqs = List[Float64]()
        if self.messenger.notify_update("freqs", freqs) :
            for i in range(min(2, len(freqs))):
                self.freqs[i] = freqs[i]

        sample = self.synth.next(self.freqs, self.phase_offsets, self.trig)  # Get the next sample from the synth
        return sample * 0.2  # Get the next sample from the synth