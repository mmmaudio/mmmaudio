from mmm_audio import *

struct DattorroReverbExample(Movable, Copyable):
        var world: World
        var m: Messenger
        var reverb: DattorroReverb[Interp.none] #the original uses Interp.none on the non-modulated delay lines
        var in_chan: Int

        def __init__(out self, world: World):
                self.world = world
                self.m = Messenger(world)
                self.reverb = DattorroReverb[Interp.none](world)
                self.in_chan = 0

        def next(mut self) -> MFloat[2]:
                self.m.update("in_chan", self.in_chan)
                input = MFloat[2](self.world[].sound_in(self.in_chan))

                self.m.update("pre_delay_time", self.reverb.pre_delay_time)
                self.m.update("decay", self.reverb.decay) 
                self.m.update("bandwidth", self.reverb.bandwidth) 
                self.m.update("damping", self.reverb.damping) 
                self.m.update("decay_diffusion1", self.reverb.decay_diffusion1)
                self.m.update("decay_diffusion2", self.reverb.decay_diffusion2)
                self.m.update("input_diffusion1", self.reverb.input_diffusion1)
                self.m.update("input_diffusion2", self.reverb.input_diffusion2)

                return self.reverb.next(input)