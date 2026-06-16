from mmm_audio import *

# this is the simplest possible
struct In2Out(Movable, Copyable):
    var world: World
    var messenger: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.messenger = Messenger(self.world)

    def next(mut self) -> MFloat[16]:
        if self.messenger.notify_trig("print_inputs"):
            for i in range(self.world[].num_in_chans()):
                print("input[", i, "] =", self.world[].sound_in(i))

        # the SIMD vector has to be a power of 2
        output = MFloat[16](0.0)

        # whichever is smaller, the output or the sound_in - that number of values are copied to the output
        smaller  = min(len(output), self.world[].num_in_chans())
        for i in range(smaller):
            output[i] = self.world[].sound_in(i)

        return output  # Return the combined output samples
