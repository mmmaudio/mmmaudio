from mmm_audio import *

comptime scaler_path = "examples/ML_examples/nn_trainings/mfcc_classifier_scaler.safetensors"
comptime model_path = "examples/ML_examples/nn_trainings/mfcc_classifier.safetensors"

comptime windowsize = 1024
comptime hopsize = windowsize // 2
comptime n_mfcc = 13

struct ClassifierWindow(FFTProcessable):
    var model: MLP[n_mfcc, 1]
    var model_input: Array[Float64, n_mfcc]
    var model_output: Array[Float64, 1]
    var scaler: StandardScaler
    var mfcc: MFCC
    var scaled_coeffs: List[Float64]

    def __init__(out self, world: World):
        self.scaler = StandardScaler(scaler_path)
        self.mfcc = MFCC(sr=world[].sample_rate, fft_size=windowsize, num_coeffs=n_mfcc)
        self.scaled_coeffs = List[Float64](fill=0.0, length=n_mfcc)
    
        # pure Mojo inference: no Python or torch on the audio thread
        self.model = MLP[n_mfcc, 1](model_path)
        self.model_input = Array[Float64, n_mfcc](fill=0.0)
        self.model_output = Array[Float64, 1](fill=0.0)

    def next_frame(mut self, mut mags: List[Float64], mut phss: List[Float64]):
        self.mfcc.from_mags(mags)
        self.scaler.transform_point(self.mfcc.coeffs, self.scaled_coeffs)
        comptime for i in range(n_mfcc):
            self.model_input[i] = self.scaled_coeffs[i]
        # runs the network once per FFT frame
        self.model.forward(self.model_input, self.model_output)
        # the exported model ends in a sigmoid, so this is the probability of "dog"
        var o = self.model_output[0]
        var display: String = "🐶" if o > 0.5 else "❌"
        print("Dog:",display,"---", o)

struct Classifier(Movable,Copyable):
    var world: World
    var fftp: FFTProcess[ClassifierWindow,output_window_shape=WindowType.hann]
    var src: Buffer
    var player: Play
    var src_path: String
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.src_path = "/Users/spluta1/Desktop/Tremblay-BaB-SoundscapeGolcarWithDog.wav"
        self.fftp = FFTProcess[ClassifierWindow](self.world, ClassifierWindow(world), windowsize, hopsize)
        self.src = Buffer.load(self.src_path)
        self.player = Play(self.world)
        self.m = Messenger(self.world)
    
    def next(mut self) -> MFloat[2]:

        if self.m.notify_update("src_path", self.src_path):
            self.src = Buffer.load(self.src_path)

        var src = self.player.next(self.src)
        _ = self.fftp.next(src)
        return src