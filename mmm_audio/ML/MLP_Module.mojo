from std.math import exp, tanh
from std.os.path import exists
from std.python import Python
from std.python._cpython import PyGILState_STATE
from std.sys import simd_width_of
from json import load as _load_json, Value as _JsonValue
from mmm_audio.constants import *
from mmm_audio.Oscillators import Phasor

comptime ACT_NONE = 0
comptime ACT_RELU = 1
comptime ACT_SIGMOID = 2
comptime ACT_TANH = 3


comptime MLPWeight = Float32
"""Storage and arithmetic type inside the network.

Torch trains in float32, so float32 loses nothing against the source weights, and it
doubles the lanes per SIMD register, which roughly halves the cost of `forward`.
"""

struct DenseLayer(Copyable, Movable):
    """One `nn.Linear` plus the activation that follows it.

    The weight is kept in torch's row-major `[out_size, in_size]` layout, so each
    output is one contiguous dot product over the input.
    """

    comptime width = simd_width_of[DType.float32]() * 4
    """Lanes per accumulator. Several registers' worth, so the compiler can overlap FMAs."""

    comptime rows = 4
    """Output rows computed together, so each input load feeds `rows` FMAs."""

    var in_size: Int
    var out_size: Int
    var activation: Int
    var weight: List[MLPWeight]
    var bias: List[MLPWeight]

    def __init__(out self, in_size: Int, out_size: Int, activation: Int):
        """Make a zeroed layer.

        Args:
            in_size: Number of inputs.
            out_size: Number of outputs.
            activation: One of `ACT_NONE`, `ACT_RELU`, `ACT_SIGMOID`, `ACT_TANH`.
        """
        self.in_size = in_size
        self.out_size = out_size
        self.activation = activation
        self.weight = List[MLPWeight](length=in_size * out_size, fill=0.0)
        self.bias = List[MLPWeight](length=out_size, fill=0.0)

    @always_inline
    def forward(self, mut scratch: List[MLPWeight], in_offset: Int, out_offset: Int):
        """Compute `activation(weight @ input + bias)` inside a scratch buffer.

        Args:
            scratch: Holds the input and receives the output.
            in_offset: Where the `in_size` inputs start in `scratch`.
            out_offset: Where to write the `out_size` outputs. Must not overlap the input.
        """
        comptime W = Self.width
        comptime R = Self.rows
        var w = self.weight.unsafe_ptr()
        var b = self.bias.unsafe_ptr()
        var buf = scratch.unsafe_ptr()
        var n = self.in_size
        var n_vec = n - n % W

        # Weight @ input + bias, `R` rows at a time
        var j = 0
        while j + R <= self.out_size:
            var acc = InlineArray[SIMD[DType.float32, W], R](fill=0.0)
            for i in range(0, n_vec, W):
                var x = buf.unsafe_load[width=W](in_offset + i)
                comptime for r in range(R):
                    acc[r] += w.unsafe_load[width=W]((j + r) * n + i) * x
            comptime for r in range(R):
                var sum = acc[r].reduce_add() + b[unsafe_offset=j + r]
                for i in range(n_vec, n):
                    sum += w[unsafe_offset=(j + r) * n + i] * buf[unsafe_offset=in_offset + i]
                buf[unsafe_offset=out_offset + j + r] = sum
            j += R

        # The leftover rows, one at a time
        while j < self.out_size:
            var acc = SIMD[DType.float32, W](0.0)
            for i in range(0, n_vec, W):
                acc += w.unsafe_load[width=W](j * n + i) * buf.unsafe_load[width=W](in_offset + i)
            var sum = acc.reduce_add() + b[unsafe_offset=j]
            for i in range(n_vec, n):
                sum += w[unsafe_offset=j * n + i] * buf[unsafe_offset=in_offset + i]
            buf[unsafe_offset=out_offset + j] = sum
            j += 1

        # The activation, vectorized over the whole output
        if self.activation == ACT_NONE:
            return
        var i = 0
        while i + W <= self.out_size:
            var v = buf.unsafe_load[width=W](out_offset + i)
            buf.unsafe_store(out_offset + i, _activate(v, self.activation))
            i += W
        while i < self.out_size:
            buf[unsafe_offset=out_offset + i] = _activate[1](buf[unsafe_offset=out_offset + i], self.activation)
            i += 1

@doc_hidden
@always_inline
def _activate[w: Int](v: SIMD[DType.float32, w], activation: Int) -> SIMD[DType.float32, w]:
    """Apply one of the `ACT_*` activations lane by lane.

    Parameters:
        w: Number of lanes.

    Args:
        v: The pre-activation values.
        activation: One of `ACT_NONE`, `ACT_RELU`, `ACT_SIGMOID`, `ACT_TANH`.

    Returns:
        The activated values.
    """
    if activation == ACT_RELU:
        return max(v, 0.0)
    elif activation == ACT_SIGMOID:
        return 1.0 / (1.0 + exp(-v))
    elif activation == ACT_TANH:
        return tanh(v)
    return v

@doc_hidden
def _activation_code(name: String) raises -> Int:
    """Map an activation name from the weight file to its `ACT_*` code.

    Args:
        name: One of "none", "relu", "sigmoid", "tanh".

    Returns:
        The matching `ACT_*` constant.
    """
    if name == "none":
        return ACT_NONE
    elif name == "relu":
        return ACT_RELU
    elif name == "sigmoid":
        return ACT_SIGMOID
    elif name == "tanh":
        return ACT_TANH
    raise Error("unknown activation: " + name)

struct MLPNetwork[input_size: Int, output_size: Int](Copyable, Movable):
    """A multi-layer perceptron in pure Mojo which loads its weights from a torch trained JSON file.

    Runs a network trained by `train_new_mlp` in `mmm_audio/ML/MLP_Python.py`, which saves
    the JSON weight file this loads. Older TorchScript `.pt` trainings must be converted
    to JSON first with:
    ```
        from mmm_audio.ML.MLP_Python import export_mlp_weights
        export_mlp_weights("old_training.pt", "new_training.json")
    ```

    Supports any stack of `nn.Linear` layers, each optionally followed by ReLU,
    Sigmoid or Tanh -- everything `MLP_Python.MLP` can build. Hidden layer sizes come
    from the file; only the input and output sizes are compile-time, so a file with
    the wrong shape is rejected at load time.

    At each inference step, call `forward(input, output)`: it reads `input` and writes `output`. 

    Parameters:
        input_size: Size of the input vector.
        output_size: Size of the output vector.
    """

    var layers: List[DenseLayer]
    # Two halves of `half_size` each; layers ping-pong between them
    var scratch: List[MLPWeight]
    var half_size: Int
    var loaded: Bool

    def __init__(out self):
        """Make an empty network. `forward` leaves its output untouched until `load` succeeds."""
        self.layers = List[DenseLayer]()
        self.scratch = List[MLPWeight]()
        self.half_size = 0
        self.loaded = False

    def __init__(out self, file_name: String):
        """Make a network and load its weights, printing an error if the load fails.

        Args:
            file_name: Path to a file written by `MLP_Python.py`.
        """
        self = Self()
        try:
            self.load(file_name)
        except e:
            print("Error loading MLP weights:", e)

    def load(mut self, file_name: String) raises:
        """Replace the network with the one stored in `file_name`. It is looking for a JSON file written by `MLP_Python.py`. TorchScript `.pt` files are not supported; convert them with `export_mlp_weights` first.

        The current network is kept if the file is missing, malformed, or the wrong shape.

        Args:
            file_name: Path to a file written by `MLP_Python.py`.

        Raises:
            Error: If the file is missing, malformed, or the wrong shape.
        """
        var path = String(file_name)
        if path.endswith(".pt"):
            raise Error("TorchScript files are not supported directly. Please convert them to JSON format first using `export_mlp_weights`.")
        var doc = _load_json(path)

        if not doc.is_object() or doc.get("format", _JsonValue("")).string_or("") != "mmm_mlp":
            raise Error("not an MLP weight file: " + path)
        var version = doc["version"].as_int()
        if version != 2:
            raise Error("unsupported MLP weight file version " + String(version))

        var layers_json = doc["layers"]
        var layers = List[DenseLayer](capacity=len(layers_json))
        var widest = Self.input_size
        var expected_in = Self.input_size
        var l = 0
        for layer_json in layers_json:
            var in_size = Int(layer_json["in_size"].as_int())
            var out_size = Int(layer_json["out_size"].as_int())
            var activation = _activation_code(layer_json["activation"].as_string())
            if in_size != expected_in:
                raise Error(
                    "layer " + String(l) + " expects " + String(in_size)
                    + " inputs but receives " + String(expected_in)
                )

            var layer = DenseLayer(in_size, out_size, activation)
            var weight_json = layer_json["weight"]
            if len(weight_json) != out_size:
                raise Error("layer " + String(l) + " weight has the wrong number of rows")
            var i = 0
            for row in weight_json:
                if len(row) != in_size:
                    raise Error("layer " + String(l) + " weight has the wrong number of columns")
                for v in row:
                    layer.weight[i] = MLPWeight(v.as_float())
                    i += 1
            var bias_json = layer_json["bias"]
            if len(bias_json) != out_size:
                raise Error("layer " + String(l) + " bias has the wrong size")
            i = 0
            for v in bias_json:
                layer.bias[i] = MLPWeight(v.as_float())
                i += 1
            layers.append(layer^)

            expected_in = out_size
            widest = max(widest, out_size)
            l += 1

        if expected_in != Self.output_size:
            raise Error(
                "network outputs " + String(expected_in) + " values but MLP expects "
                + String(Self.output_size)
            )

        self.layers = layers^
        self.scratch = List[MLPWeight](length=2 * widest, fill=0.0)
        self.half_size = widest
        self.loaded = True

    @always_inline
    def forward(mut self, input: Array[Float64, Self.input_size], mut output: Array[Float64, Self.output_size]):
        """Run `input` through the network into `output`.

        Does nothing if no network is loaded.

        Args:
            input: The input vector.
            output: Where the network's output is written.
        """
        if not self.loaded:
            return

        var src = 0
        var dst = self.half_size
        comptime for i in range(Self.input_size):
            self.scratch[i] = MLPWeight(input[i])

        for l in range(len(self.layers)):
            self.layers[l].forward(self.scratch, src, dst)
            var tmp = src
            src = dst
            dst = tmp

        comptime for i in range(Self.output_size):
            output[i] = Float64(self.scratch[src + i])

    def num_layers(self) -> Int:
        """Number of Linear layers in the loaded network.

        Returns:
            The layer count, or 0 before a successful `load`.
        """
        return len(self.layers)


struct MLP[input_size: Int, output_size: Int](Copyable, Movable):
    """A multi-layer perceptron, trained in PyTorch by `MLP_Python.py`, that runs in pure Mojo. This is a convenience class around the MLPNetwork, which stores the input and output Arrays, allows the user to toggle on and off inference, allows the user to load new trainings, and allows the user to send `fake` model outputs from python (necessary when training certain networks).

    The weights come from the JSON file trained by MLP_Python.train_new_mlp`. 
    
    Older TorchScript `.pt` trainings need to be converted to a `.json` file before they can be used. You can convert a `.pt` to `.json` with:

        from mmm_audio.ML.MLP_Python import export_mlp_weights
        export_mlp_weights(pt_file_path, json_file_path)

    Messages:

    - `toggle_inference` (bool): run the network, or hold still for training
    - `fake_model_output` (floats): with inference off, write these to `model_output`
    - `load_mlp_training` (string): load a new training (`.json` files only)

    Parameters:
      input_size: The size of the input vector.
      output_size: The size of the output vector.
    """
    var world: World
    var mlp: MLPNetwork[Self.input_size, Self.output_size]
    var model_input: Array[Float64, Self.input_size]
    var model_output: Array[Float64, Self.output_size]
    var fake_model_output: List[Float64]
    var inference_trig: Phasor[1]
    var inference_gate: Bool
    var trig_rate: Float64
    var messenger: Messenger
    var file_name: String

    def __init__(out self, world: World, file_name: String, namespace: Optional[String] = None, trig_rate: Float64 = 25.0):
        """Initialize the MLP struct.

        Args:
          world: Pointer to the MMMWorld.
          file_name: The path to the JSON weight file.
          namespace: Optional namespace for the Messenger.
          trig_rate: The rate in Hz at which to trigger inference.
        """
        self.world = world
        self.mlp = MLPNetwork[Self.input_size, Self.output_size]()
        self.model_input = Array[Float64, Self.input_size](fill=0.0)
        self.model_output = Array[Float64, Self.output_size](fill=0.0)
        self.fake_model_output = [0.0 for _ in range(Self.output_size)]
        self.inference_trig = Phasor[1](world)
        self.inference_gate = True
        self.trig_rate = trig_rate
        self.messenger = Messenger(world, namespace)
        self.file_name = String()

        self.reload_model(file_name)

    def reload_model(mut self, var file_name: String):
        """Reload the MLP model from a specified file.

        If the load fails, inference is turned off.

        Args:
          file_name: The path to the model file (`.json` only).
        """
        try:
            self.mlp.load(file_name)
            print("MLP model loaded successfully")
        except e:
            print("Error reloading MLP model:", e, "Turning off inference.")
            self.inference_gate = False

    @always_inline
    def next[every_next: Bool = False](mut self):
        """MLP next function to be called every sample in the audio thread. The model input is taken from `model_input`, and the output is written to `model_output`.

        Parameters:
            every_next: If True, the MLP will perform inference on every `next()` call. If False (default), the MLP will perform inference at the rate specified by `trig_rate`. In both cases, this is only if `inference_gate` is True.
        """

        self.messenger.update("toggle_inference", self.inference_gate)

        if self.messenger.notify_update("load_mlp_training", self.file_name):
            print("loading model from file: ", self.file_name)
            self.reload_model(self.file_name)

        if not self.inference_gate:
            if self.messenger.notify_update("fake_model_output", self.fake_model_output):
                comptime for i in range(Self.output_size):
                    if i < len(self.fake_model_output):
                        self.model_output[i] = self.fake_model_output[i]

        if self.inference_gate:
            comptime if every_next:
                self.mlp.forward(self.model_input, self.model_output)
            else:
                if self.inference_trig.next_bool(self.trig_rate):
                    self.mlp.forward(self.model_input, self.model_output)

