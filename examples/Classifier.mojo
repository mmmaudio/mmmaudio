from mmm_audio import *

comptime scaler_path = "examples/nn_trainings/mfcc_classifier_scaler.joblib"
comptime model_path = "examples/nn_trainings/mfcc_classifier_traced.pt"

comptime windowsize = 1024
comptime hopsize = windowsize // 2
comptime n_mfcc = 13

struct ClassifierWindow(FFTProcessable):
    var model: PythonObject
    var scaler: StandardScaler
    var mfcc: MFCC
    var scaled_coeffs: List[Float64]
    var py_input: PythonObject
    var py_output: PythonObject

    def __init__(out self, sr: Float64):
        self.scaler = StandardScaler(scaler_path)
        self.mfcc = MFCC(sr=sr, fft_size=windowsize, num_coeffs=n_mfcc)
        self.scaled_coeffs = List[Float64](fill=0.0, length=n_mfcc)
    
        try:
            torch = Python.import_module("torch")
            self.model = torch.jit.load(model_path)
            self.py_input = torch.zeros(n_mfcc)
            self.py_output = torch.zeros(1)  # Adjust the size based on your model's output
        except e:
            abort("Error loading PyTorch model: " + String(e))

    def next_frame(mut self, mut mags: List[Float64], mut phss: List[Float64]):
        self.mfcc.from_mags(mags)
        self.scaler.transform_point(self.mfcc.coeffs, self.scaled_coeffs)
        try:
            for i in range(n_mfcc):
                self.py_input[i] = self.scaled_coeffs[i]
            self.py_output = self.model(self.py_input)
            o = Float64(py=self.py_output.item())
            display: String = "🐶" if o > 0.5 else "❌"
            print("Dog:",display,"---", o)
        except e:
            abort("Error predicting: " + String(e))

struct Classifier(Movable,Copyable):
    var world: World
    var fftp: FFTProcess[ClassifierWindow,output_window_shape=WindowType.hann]
    var src: Buffer
    var player: Play
    var src_path: String
    var m: Messenger

    def __init__(out self, world: World):
        self.world = world
        self.src_path = "/Users/ted/Desktop/dog-dataset/Media/Tremblay-BaB-SoundscapeGolcarWithDog.wav"
        self.fftp = FFTProcess[ClassifierWindow](self.world, ClassifierWindow(self.world[].sample_rate), windowsize, hopsize)
        self.src = Buffer.load(self.src_path)
        self.player = Play(self.world)
        self.m = Messenger(self.world)
    
    def next(mut self) -> MFloat[2]:

        if self.m.notify_update(self.src_path,"src_path"):
            self.src = Buffer.load(self.src_path)

        src = self.player.next(self.src)
        _ = self.fftp.next(src)
        return src