"""Subtractive Synthesis Workshop Template.

This is a template for a subtractive synthesis graph. It includes a saw oscillator, 
a Moog ladder filter, and an LFO to modulate the filter cutoff. 

If you want to just start hacking, go for it. If you want a bit of structure, below are some steps you might follow.

In either case, you'll want to use the documentation!: [https://spluta.github.io/MMMAudio/](https://spluta.github.io/MMMAudio/)

1. Start by running this graph from Python using the SubtractiveTemplate.py file. In that
file, adjust some parameters and hear the result.
2. Change the scaling of the LFO so that it sounds different (note that the "exp" range values of linexp must be
greater than zero).
3. Remove the comment "#" signs that are preventing the wavefolder from being used. In Python, adjust the amount and 
listen to the result.
4. Change the oscillator type to something other than a saw by changing the `osc_type` parameter in the `next` method.
5. Add a second LFO to modulate another parameter such as the wavefolder amount or the oscillator frequency.

"""

from mmm_audio import *

comptime num_chans: Int = 2
comptime oversample_index: Int = 1

struct SubtractiveTemplate(Movable, Copyable):
    var world: World
    var m: Messenger

    # Oscillator stuff
    var saw: Osc[num_chans=num_chans,interp=Interp.quad,ov_samp=oversample_index]
    var freq: MFloat[1]

    # Filter stuff
    var lpf: VAMoogLadder[num_chans=num_chans,ov_samp=oversample_index]
    var ffreq: MFloat[1]
    var res: MFloat[1]

    # LFO stuff
    var lfo: Osc[]
    var lfo_freq: MFloat[1]

    # Wavefolder
    # var wavefolder: BuchlaWavefolder[num_chans=num_chans,ov_samp=oversample_index]
    # var fold_amt: MFloat[1]

    def __init__(out self, world: World):
        self.world = world
        self.m = Messenger(self.world)
        
        self.saw = Osc[num_chans=num_chans,interp=Interp.quad,ov_samp=oversample_index](self.world)
        self.freq = MFloat[1](440.0)

        # self.wavefolder = BuchlaWavefolder[num_chans=num_chans,ov_samp=oversample_index](self.world)
        # self.fold_amt = MFloat[1](0.5)
        
        self.lfo = Osc[](self.world)
        self.lfo_freq = MFloat[1](3)

        self.lpf = VAMoogLadder[num_chans=num_chans,ov_samp=oversample_index](self.world)
        self.ffreq = MFloat[1](1000.0)
        self.res = MFloat[1](0.5)
        
    def next(mut self) -> MFloat[2]:
        self.m.update("freq", self.freq)
        self.m.update("ffreq", self.ffreq)
        self.m.update("res", self.res)
        self.m.update("lfo_freq", self.lfo_freq)
        # self.m.update("fold_amt", self.fold_amt)

        sig = self.saw.next[OscType.saw](self.freq)
        # sig = self.wavefolder.next(sig, self.fold_amt)

        lfo = self.lfo.next(self.lfo_freq)
        lfo = linexp(lfo, -1.0, 1.0, 0.1, 10000.0)
        ffreq = clip(self.ffreq + lfo, 20.0, 20000.0)
        sig = self.lpf.next(sig, ffreq, clip(self.res, 0.0, 1.0))
        return sig * dbamp(-10.0)