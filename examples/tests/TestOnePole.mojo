
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestOnePole[N: Int = 2](Movable, Copyable):
    var world: World
    var noise: WhiteNoise[Self.N]
    var filt: OnePole[Self.N]

    def __init__(out self, world: World):
        self.world = world
        self.noise = WhiteNoise[Self.N]()
        self.filt = OnePole[Self.N](world)

    def next(mut self) -> MFloat[Self.N]:
        sample = self.noise.next()  # Get the next white noise sample
        self.world[].print(sample)  # Print the sample to the console
        coef = MFloat[Self.N](self.world[].mouse_x(), 1-self.world[].mouse_x())  # Coefficient based on mouse X position
        sample = self.filt.next(sample, coef)  # Get the next sample from the filter
        return sample * 0.1