"""Contains a Multi-Layer Perceptron (MLP) implementation using PyTorch and the train_new_mlp function to train the network.

Trained networks are saved as JSON weight files, which the pure Mojo `MLP` in
`MLP_Module.mojo` loads without Python or torch. Older TorchScript `.pt` trainings can be
converted with `export_mlp_weights`.

JSON weight file format:

    {
      "format": "mmm_mlp",
      "version": 2,
      "layers": [
        {
          "in_size": 2,
          "out_size": 64,
          "activation": "relu",           # "none", "relu", "sigmoid" or "tanh"
          "weight": [[...], ...],         # out_size rows of in_size floats (torch's [out, in] layout)
          "bias": [...]                   # out_size floats
        },
        ...
      ]
    }

Weights are float32 in torch; they are written as the float64 values they widen to,
so reading them back and narrowing to float32 is exact.
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
        file_name: Where to save the trained weights, as a JSON file.
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
        file_name: Where to save the weights, as a JSON file.
    """
    layers_data = [(size, activations[activation] if activation is not None else None) for size, activation in layers]
    model = MLP(input_size, layers_data)
    export_mlp_weights(model, file_name)

#--------The code below is for exporting the weights of a trained MLP to a JSON file that can be loaded by the Mojo MLP. It is not used in the Mojo code, but is useful for converting older TorchScript `.pt` trainings to the JSON format that the Mojo MLP expects.

FORMAT = "mmm_mlp"
VERSION = 2

ACTIVATION_NAMES = {"ReLU": "relu", "Sigmoid": "sigmoid", "Tanh": "tanh"}

def _module_kind(module) -> str:
    """The torch class name of a module, for both eager and TorchScript modules."""
    return getattr(module, "original_name", type(module).__name__)


def _collect_layers(model) -> list[tuple[torch.Tensor, torch.Tensor, str]]:
    """Walk `model.layers` and pair every Linear with the activation that follows it."""
    layers = []
    # Not `children()`: it skips repeated modules, and `activations` hands every layer
    # the same ReLU/Sigmoid/Tanh instance. `_modules` works for eager and TorchScript.
    for module in model.layers._modules.values():
        kind = _module_kind(module)
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


def export_mlp_weights(model, out_file: str):
    """Write an MLP's weights as the JSON file the Mojo `MLP` loads.

    Args:
        model: An `MLP` instance, or the path to a TorchScript `.pt` file of one.
        out_file: Path of the JSON file to write.
    """
    if isinstance(model, str):
        model = torch.jit.load(model, map_location="cpu")

    layers = _collect_layers(model)

    doc = {
        "format": FORMAT,
        "version": VERSION,
        "layers": [
            {
                "in_size": weight.shape[1],
                "out_size": weight.shape[0],
                "activation": activation,
                "weight": weight.to(torch.float32).tolist(),
                "bias": bias.to(torch.float32).tolist(),
            }
            for weight, bias, activation in layers
        ],
    }
    with open(out_file, "w") as f:
        json.dump(doc, f)

    sizes = [layers[0][0].shape[1]] + [w.shape[0] for w, _, _ in layers]
    print(f"Model saved to {out_file}: layer sizes {sizes}")
