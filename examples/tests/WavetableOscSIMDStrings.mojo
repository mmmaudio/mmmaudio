from mmm_audio import *

struct OscVoice(PolyObject):
    var osc: Osc[1,Interp.sinc,0]
    var tri: LFTri[]
    var world: World
    var env: ASREnv
    var gate: Bool
    var freq: Float64
    var vol: Float64
    var wubb_rate: Float64
    var messenger: Messenger
    var triggered: Bool

    def check_active(mut self) -> Bool:
        return self.env.is_active
    
    # Poly will use this function to release the voice when it receives a note off message for the note that this voice is playing. 
    def set_gate(mut self, gate: Bool):
        self.gate = gate

    # necessary to ensure a fresh env when the voice is copied by Poly
    def reset_env(mut self):
        self.env = ASREnv(self.world)

    def __init__(out self, world: World, name_space: String = ""):
        self.osc = Osc[1,Interp.sinc,0](world)
        self.tri = LFTri(world)
        self.env = ASREnv(world)
        self.gate = False
        self.freq = 440.0
        self.vol = 1.0
        self.wubb_rate = 0.5
        self.messenger = Messenger(world, name_space)
        self.world = world
        self.triggered = False

    def next(mut self, ref buffer: SIMDBuffer) -> MFloat[1]:
        osc_frac = self.tri.next(self.wubb_rate, 0.75, trig=self.gate) * 0.5 + 0.5
        return self.osc.next_vwt(buffer, self.freq, osc_frac = osc_frac) * self.env.next(0.01,0.2,0.7,self.gate,2) * self.vol

struct WavetableOscSIMDStrings(Movable, Copyable):
    comptime wavetables_per_channel = 8
    comptime num_messages = 10

    var world: World  
    var voices: List[OscVoice]
    var buffer: SIMDBuffer[Self.wavetables_per_channel]
    var file_name: String
    var messenger: Messenger
    var filter_cutoff: Float64
    var filter_resonance: Float64
    var moog_filter: VAMoogLadder[1,1]
    var poly: PolyGate

    def __init__(out self, world: World):
        self.world = world
        self.file_name = "resources/small_wavetable8.wav"
        
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)
        self.voices = [OscVoice(self.world, "voice_"+String(i)) for i in range(8)]
        
        self.messenger = Messenger(world)
        self.filter_cutoff = 20000.0
        self.filter_resonance = 0.5
        self.moog_filter = VAMoogLadder[1,1](self.world)
        self.poly = PolyGate(8, 16, world, "poly")

    def loadBuffer(mut self):
        self.buffer = SIMDBuffer[Self.wavetables_per_channel].load(self.file_name, num_wavetables=self.wavetables_per_channel)

    def next(mut self) -> MFloat[2]:
        if self.messenger.notify_update(self.file_name, "load_file"):
            self.loadBuffer()

        # the callback function sent to the Poly, to be called whenever a new trigger is received from Python.
        # the kinds of messages the Messenger can receive are defined by the type of the `note` argument in the callback function
        def callback(mut poly_object: OscVoice, mut vals: List[MFloat[1]]) capturing -> None:
            if vals[1] > 0: # the call_back will be called for both note on and note off messages
                poly_object.freq = midicps(Float64(vals[0]))
                poly_object.vol = vals[1] / 127.0
        # the poly has an internal Messenger that receives messages from Python. these have to be in the form of a List[Float64] or a List[Int]
        # for next_gate, the first value in the list is the note to trigger and the second value is the velocity or volume of the note, where 0 denotes a note off message. the callback function receives the list of ints or floats as the second argument, so the PolyObject can be controlled by the message from Python.
        self.poly.next[call_back=callback](self.voices)
        
        # add the output of all the voices
        var out = 0.0
        for ref voice in self.voices:
            out += voice.next(self.buffer)

        self.messenger.update(self.filter_cutoff, "filter_cutoff")
        self.messenger.update(self.filter_resonance, "filter_resonance")
        wubb_rate = 0.0
        got_wubbed = self.messenger.notify_update(wubb_rate, "wubb_rate")
        if got_wubbed:
            for ref voice in self.voices:
                voice.wubb_rate = wubb_rate
        sample = self.moog_filter.next(out, self.filter_cutoff, self.filter_resonance)

        return sample * 0.5
