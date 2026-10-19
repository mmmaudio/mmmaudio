# this example will only work with SCExporter
# it shows how we can use a struct as a wrapper for a UGen, in order to use "send_string" or other messages to load buffers, etc
# in this case, we have to use the wrapper because MMMAudio can't use SC Buffers directly. we have to use a MMMAudio Buffer and send a message to the wrapper to load the file in MMMAudio.

from mmm_audio import *

struct WavetableOsc[num_chans:Int = 1, interp:Interp=Interp.linear, ov_samp:TimesOversampling=TimesOversampling.x2](Movable, Copyable):
    var world: World
    var osc: Osc[Self.num_chans, Self.interp, Self.ov_samp]
    var m: Messenger
    var buffer: Buffer
    var num_wavetables: Int

    def __init__(out self, world: World):
        self.world = world
        self.osc = Osc[Self.num_chans, Self.interp, Self.ov_samp](self.world)
        self.m = Messenger(self.world)
        self.buffer = Buffer.zeros(2048, 256, 48000.)
        self.num_wavetables = 256

    def next(mut self, 
    freq: MFloat[self.num_chans] = MFloat[self.num_chans](100.0), 
            phase_offset: MFloat[self.num_chans] = MFloat[self.num_chans](0.0), 
            trig: Bool = False, 
            osc_frac: MFloat[self.num_chans] = MFloat[self.num_chans](0.0)
        ) -> MFloat[self.num_chans]:
        # check if we have a new wavetable to load
        self.m.update("num_wavetables", self.num_wavetables)
        def load_wavetable(wavetable_name: String) capturing -> None:
            print("Loading wavetable:", wavetable_name)
            self.buffer = Buffer.load(wavetable_name, self.num_wavetables)
        self.m.address_callback[load_wavetable]("load_wavetable")

        return self.osc.next_vwt(self.buffer, freq, phase_offset, trig, osc_frac)