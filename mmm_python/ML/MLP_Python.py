"""Contains a Multi-Layer Perceptron (MLP) implementation using PyTorch and the train_new_mlp function to train the network.

Trained networks are saved as safetensors weight files, which the pure Mojo `MLP` in
`MLP_Module.mojo` loads (with `SafeTensors.mojo`) without Python or torch. Older TorchScript
`.pt` and JSON trainings can be converted with `export_mlp_weights`.

Safetensors weight file format:

    tensors (float32):
        "layers.0.weight"   [out_size, in_size]   (torch's nn.Linear layout)
        "layers.0.bias"     [out_size]
        "layers.1.weight"   ...
    metadata (all strings):
        "format":      "mmm_mlp"
        "version":     "3"
        "num_layers":  number of Linear layers
        "activations": one per layer, comma separated: "none", "relu", "sigmoid" or "tanh"
"""

import json

import torch
import time
import torch.nn as nn
import torch.optim as optim

class MLP(nn.Module):
    """The Multi-Layer Perceptron (MLP) class."""
    def __init__(self, input_size: int, layers_data: list):
        """
        Initialize the MLP.

        Args:
            input_size: Size of the input layer.
            layers_data: A list of tuples where each tuple contains the size of the layer and the activation function.
        """

        super(MLP, self).__init__()

        self.layers = nn.ModuleList()
        for size, activation in layers_data:
            self.layers.append(nn.Linear(input_size, size))
            input_size = size  # For the next layer
            print(activation)
            if activation is not None:
                assert isinstance(activation, nn.Module), \
                    "Each tuples should contain a size (int) and a torch.nn.modules.Module."
                self.layers.append(activation)
       
    def forward(self, input_data: list[list[float]]):
        """
        Forward pass through the MLP.

        Args:
            input_data: Input tensor.
        """
        for layer in self.layers:
            input_data = layer(input_data)
        return input_data
    
    def get_input_size(self):
        """Get the input size of the MLP."""
        return self.input_size

    def get_output_size(self):
        """Get the output size of the MLP."""
        return self.output_size
    
activations = {
    'relu': nn.ReLU(),
    'sigmoid': nn.Sigmoid(),
    'tanh': nn.Tanh()
}
    
def train_new_mlp(X_train_list: list[list[float]], y_train_list: list[list[float]], layers: list[tuple[int, str | None]], learn_rate: float, epochs: int, file_name: str):
    """Train the MLP and save its weights for the Mojo `MLP`.

    Args:
        X_train_list: List of input training data.
        y_train_list: List of output training data.
        layers: List of layer specifications (size and activation).
        learn_rate: Learning rate for the optimizer.
        epochs: Number of training epochs.
        file_name: Where to save the trained weights, as a `.safetensors` file.
    """

    if torch.backends.mps.is_available():
        device = torch.device("mps")
    else:
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Using device:", device)

    # build a new list rather than overwriting `layers`, so the caller can train again with it
    layers_data = [(size, activations[activation] if activation is not None else None) for size, activation in layers]

    # Convert lists to torch tensors and move to the appropriate device
    X_train = torch.tensor(X_train_list, dtype=torch.float32).to(device)
    y_train = torch.tensor(y_train_list, dtype=torch.float32).to(device)

    input_size = X_train.shape[1]
    model = MLP(input_size, layers_data).to(device)
    criterion = nn.MSELoss()
    last_time = time.time()

    for nums in [[learn_rate,epochs]]:
        optimizer = optim.Adam(model.parameters(), lr=nums[0])

        # Train the model
        for epoch in range(nums[1]):
            optimizer.zero_grad()
            outputs = model(X_train)
            loss = criterion(outputs, y_train)
            if epoch % 100 == 0:
                elapsed_time = time.time() - last_time
                last_time = time.time()
                print(epoch, loss.item(), elapsed_time)
            loss.backward()
            optimizer.step()

    # Print the training loss
    print("Training loss:", loss.item())

    # Save the weights for the Mojo MLP
    model = model.to('cpu')
    export_mlp_weights(model, file_name)

def make_dummy_mlp_training(input_size: int, layers: list[tuple[int, str | None]], file_name: str):
    """Save an untrained MLP, with torch's default random weights, for the Mojo `MLP`.

    Useful as a placeholder to load before there is any training data.

    Args:
        input_size: Size of the input layer.
        layers: List of layer specifications (size and activation), as in `train_new_mlp`.
        file_name: Where to save the weights, as a `.safetensors` file.
    """
    layers_data = [(size, activations[activation] if activation is not None else None) for size, activation in layers]
    model = MLP(input_size, layers_data)
    export_mlp_weights(model, file_name)

#--------The code below is for exporting the weights of a trained MLP to a safetensors file that can be loaded by the Mojo MLP. It is also useful for converting older TorchScript `.pt` and JSON trainings to the safetensors format that the Mojo MLP expects.

FORMAT = "mmm_mlp"
VERSION = 3

ACTIVATION_NAMES = {"ReLU": "relu", "Sigmoid": "sigmoid", "Tanh": "tanh"}

def _module_kind(module) -> str:
    """The torch class name of a module, for both eager and TorchScript modules."""
    return getattr(module, "original_name", type(module).__name__)


# layers that do nothing at inference time, so they can be left out of the export
SKIPPED_LAYERS = {"Dropout"}

def _leaf_modules(module):
    """Yield the leaf modules of `module` in order, looking inside containers like `nn.Sequential`."""
    # Not `modules()`/`children()`: they skip repeated modules, and `activations` hands every
    # layer the same ReLU/Sigmoid/Tanh instance. `_modules` works for eager and TorchScript.
    children = list(module._modules.values())
    if not children:
        yield module
    for child in children:
        yield from _leaf_modules(child)

def _collect_layers(model) -> list[tuple[torch.Tensor, torch.Tensor, str]]:
    """Walk the layers of `model` and pair every Linear with the activation that follows it."""
    layers = []
    for module in _leaf_modules(model):
        kind = _module_kind(module)
        if kind in SKIPPED_LAYERS:
            continue
        if kind == "Linear":
            layers.append([module.weight.detach().cpu(), module.bias.detach().cpu(), "none"])
        elif kind in ACTIVATION_NAMES:
            if not layers or layers[-1][2] != "none":
                raise ValueError(f"{kind} is not directly after a Linear layer")
            layers[-1][2] = ACTIVATION_NAMES[kind]
        else:
            raise ValueError(f"unsupported layer type: {kind}")
    if not layers:
        raise ValueError("model has no Linear layers")
    return [tuple(layer) for layer in layers]


def _load_json_layers(json_file: str) -> list[tuple[torch.Tensor, torch.Tensor, str]]:
    """Read the layers of an older (version 2) JSON weight file."""
    with open(json_file) as f:
        doc = json.load(f)
    if doc.get("format") != FORMAT or doc.get("version") != 2:
        raise ValueError(f"not a version 2 MLP JSON weight file: {json_file}")
    return [
        (torch.tensor(layer["weight"], dtype=torch.float32),
         torch.tensor(layer["bias"], dtype=torch.float32),
         layer["activation"])
        for layer in doc["layers"]
    ]

def export_mlp_weights(model, out_file: str):
    """Write an MLP's weights as the safetensors file the Mojo `MLP` loads.

    Args:
        model: A model made of Linear layers, each optionally followed by ReLU, Sigmoid or Tanh
            (Dropout layers are skipped), such as an `MLP` instance or an `nn.Sequential`. Or the
            path to a TorchScript `.pt` file of one, or to an older JSON weight file.
        out_file: Path of the `.safetensors` file to write.
    """
    from safetensors.torch import save_file

    if isinstance(model, str) and model.endswith(".json"):
        layers = _load_json_layers(model)
    else:
        if isinstance(model, str):
            model = torch.jit.load(model, map_location="cpu")
        layers = _collect_layers(model)

    tensors = {}
    for i, (weight, bias, _) in enumerate(layers):
        tensors[f"layers.{i}.weight"] = weight.to(torch.float32).contiguous()
        tensors[f"layers.{i}.bias"] = bias.to(torch.float32).contiguous()
    metadata = {
        "format": FORMAT,
        "version": str(VERSION),
        "num_layers": str(len(layers)),
        "activations": ",".join(activation for _, _, activation in layers),
    }
    save_file(tensors, out_file, metadata=metadata)

    sizes = [layers[0][0].shape[1]] + [w.shape[0] for w, _, _ in layers]
    print(f"Model saved to {out_file}: layer sizes {sizes}")
