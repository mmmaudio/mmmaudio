from mmm_audio import *

comptime num_bands: Int = 100

struct MelBandsExample(Movable, Copyable):
    var world: World
    var buffer: Buffer
    var playBuf: Play
    var analyzer: FFTProcess[MelBands,ifft=False,input_window_shape=WindowType.hann]
    var m: Messenger
    var viz_mul: Float64
    var mix: Float64
    var oscs: List[Osc[]]
    var freqs: List[Float64]
    var lags: List[Lag[]]
    var sines_vol: Float64
    var print_counter: Int
    var update_modulus: Int

    def __init__(out self, world: World):
        self.world = world
        self.buffer = Buffer.load("resources/Shiverer.wav")
        self.playBuf = Play(self.world)
        p = MelBands(self.world[].sample_rate, num_bands, 20.0, 20000.0)
        self.analyzer = FFTProcess[MelBands,ifft=False,input_window_shape=WindowType.hann](self.world,p^, window_size=1024, hop_size=512)
        self.m = Messenger(self.world)
        self.viz_mul = 500.0
        self.mix = 1.0
        self.lags = List[Lag[]]()
        self.sines_vol = -38.0
        self.print_counter = 0
        self.update_modulus = 50

        for _ in range(num_bands):
            self.lags.append(Lag(self.world,512.0 / self.world[].sample_rate))

        self.oscs = List[Osc[]]()
        for _ in range(num_bands):
            self.oscs.append(Osc(self.world))

        self.freqs = MelBands.mel_frequencies(num_bands,20.0,20000.0)

    def next(mut self) -> MFloat[2]:
        
        self.m.update("viz_mul", self.viz_mul)
        self.m.update("mix", self.mix) 
        self.m.update("sines_vol", self.sines_vol)
        self.m.update("update_modulus", self.update_modulus)
        flute = self.playBuf.next(self.buffer)
        
        # do the analysis
        _ = self.analyzer.next(flute)

        # get the results
        if self.world[].top_of_block:
            # print the mel band energies
            if self.print_counter % self.update_modulus == 0:
                string = "\n\n\n\n\n"
                for i in range(num_bands):
                    idx = num_bands - i - 1
                    val = self.analyzer.buffered_process.process.process.bands[idx]
                    for _ in range(Int(val * self.viz_mul)):
                        string += "*"
                    string += "\n"
                
                print(string)
                # print the results
            self.print_counter += 1
            
        sines = 0.0
        for i in range(num_bands):
            amp = self.lags[i].next(self.analyzer.buffered_process.process.process.bands[i])
            sines += self.oscs[i].next(self.freqs[i]) * amp

        sines *= dbamp(self.sines_vol)

        sig = select(self.mix,flute,sines)
        
        return sig
