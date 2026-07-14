
from mmm_audio import *

# there can only be one graph in an MMMAudio instance
# a graph can have as many synths as you want
struct TestOnePole(Movable, Copyable):
    var world: World
    var noise: WhiteNoise[2]
    var filt: OnePole[2]

    def __init__(out self, world: World):
        self.world = world
        self.noise = WhiteNoise[2]()
        self.filt = OnePole[2](world)

    def next(mut self) -> MFloat[2]:
        sample = self.noise.next()  # Get the next white noise sample
        self.world[].print(sample)  # Print the sample to the console
        # coef = MFloat[Self.N](self.world[].mouse_x(), 1-self.world[].mouse_x())  # Coefficient based on mouse X position
        coef = linlin(self.world[].mouse_x(), 0.0, 1.0, -1.0, 1.0)  # Coefficient based on mouse X position
        sample = self.filt.next(sample, coef)  # Get the next sample from the filter
        return sample * 0.1