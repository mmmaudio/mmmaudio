import copy
import glob
from pathlib import Path
import sys
from typing import Any, cast

import joblib
import numpy as np
import torch
import torch.nn as nn
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).parent.parent))

from mmm_python import *


DOG_GLOB = "/Users/ted/Desktop/dog-dataset/_bounces/dog/*"
OTHER_GLOB = "/Users/ted/Desktop/dog-dataset/_bounces/other/*"
CHECKPOINT_PATH = Path(__file__).parent / "nn_trainings" / "mfcc_classifier_state.pt"
TRACED_MODEL_PATH = Path(__file__).parent / "nn_trainings" / "mfcc_classifier_traced.pt"
SCALER_PATH = Path(__file__).parent / "nn_trainings" / "mfcc_classifier_scaler.joblib"
HIDDEN_SIZES = (32, 16)
EPOCHS = 300
LEARNING_RATE = 1e-3
TRAIN_FRACTION = 0.8
SEED = 0


class MFCCClassifier(nn.Module):
    def __init__(self, input_size: int, hidden_sizes: tuple[int, int] = HIDDEN_SIZES):
        super().__init__()
        self.network = nn.Sequential(
            nn.Linear(input_size, hidden_sizes[0]),
            nn.ReLU(),
            nn.Dropout(p=0.1),
            nn.Linear(hidden_sizes[0], hidden_sizes[1]),
            nn.ReLU(),
            nn.Linear(hidden_sizes[1], 1),
        )

    def forward(self, inputs: torch.Tensor) -> torch.Tensor:
        return self.network(inputs).squeeze(-1)


def collect_mfccs(paths: list[str], analysis_config: dict[str, int | str]) -> np.ndarray:
    mfcc_batches = []
    for path in paths:
        mfcc_batches.append(MBufAnalysis.mfcc({**analysis_config, "path": path}))
    if not mfcc_batches:
        return np.empty((0, 13), dtype=np.float32)
    return np.vstack(mfcc_batches).astype(np.float32)


def get_train_count(sample_count: int, train_fraction: float) -> int:
    if sample_count <= 1:
        return sample_count
    proposed_count = int(sample_count * train_fraction)
    return min(max(1, proposed_count), sample_count - 1)


def stratified_split(
    features: np.ndarray,
    labels: np.ndarray,
    train_fraction: float = TRAIN_FRACTION,
    seed: int = SEED,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    dog_indices = np.flatnonzero(labels == 1.0)
    other_indices = np.flatnonzero(labels == 0.0)

    rng.shuffle(dog_indices)
    rng.shuffle(other_indices)

    dog_train_count = get_train_count(len(dog_indices), train_fraction)
    other_train_count = get_train_count(len(other_indices), train_fraction)

    train_indices = np.concatenate((dog_indices[:dog_train_count], other_indices[:other_train_count]))
    validation_indices = np.concatenate((dog_indices[dog_train_count:], other_indices[other_train_count:]))

    rng.shuffle(train_indices)
    rng.shuffle(validation_indices)

    return (
        features[train_indices],
        features[validation_indices],
        labels[train_indices],
        labels[validation_indices],
    )


def load_training_checkpoint(checkpoint_path: Path = CHECKPOINT_PATH) -> dict[str, object] | None:
    if not checkpoint_path.exists():
        return None
    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    print(f"loaded checkpoint from {checkpoint_path}")
    return checkpoint


def _to_numpy_array(value: object) -> np.ndarray:
    if isinstance(value, torch.Tensor):
        return value.detach().cpu().numpy()
    return np.asarray(value)


def get_checkpoint_mapping(
    checkpoint: dict[str, object] | None,
    key: str,
) -> dict[str, Any] | None:
    if checkpoint is None:
        return None
    value = checkpoint.get(key)
    if value is None:
        return None
    return cast(dict[str, Any], value)


def get_checkpoint_hidden_sizes(checkpoint: dict[str, object] | None) -> tuple[int, int] | None:
    if checkpoint is None:
        return None
    value = checkpoint.get("hidden_sizes")
    if value is None:
        return None
    hidden_sizes = tuple(int(size) for size in cast(list[int] | tuple[int, int], value))
    if len(hidden_sizes) != 2:
        raise ValueError(f"Expected exactly 2 hidden sizes, got {hidden_sizes}.")
    return (hidden_sizes[0], hidden_sizes[1])


def get_checkpoint_input_size(checkpoint: dict[str, object] | None) -> int | None:
    if checkpoint is None:
        return None
    value = checkpoint.get("input_size")
    if value is None:
        return None
    return int(cast(int | float | str, value))


def rebuild_scaler_from_checkpoint(checkpoint: dict[str, object]) -> StandardScaler | None:
    feature_mean = checkpoint.get("feature_mean")
    feature_scale = checkpoint.get("feature_scale", checkpoint.get("feature_std"))
    if feature_mean is None or feature_scale is None:
        return None

    mean = _to_numpy_array(feature_mean).astype(np.float64)
    scale = _to_numpy_array(feature_scale).astype(np.float64)
    scale[scale < 1e-6] = 1.0

    scaler = StandardScaler()
    scaler.mean_ = mean
    scaler.scale_ = scale
    scaler.var_ = np.square(scale)
    scaler.n_features_in_ = int(mean.shape[0])
    scaler.n_samples_seen_ = 0
    return scaler


def load_or_fit_scaler(
    train_features: np.ndarray,
    checkpoint: dict[str, object] | None = None,
    scaler_path: Path = SCALER_PATH,
) -> StandardScaler:
    if checkpoint is not None and scaler_path.exists():
        print(f"loaded scaler from {scaler_path}")
        return joblib.load(scaler_path)

    if checkpoint is not None:
        scaler = rebuild_scaler_from_checkpoint(checkpoint)
        if scaler is not None:
            print("reconstructed StandardScaler from checkpoint statistics")
            return scaler

    scaler = StandardScaler()
    scaler.fit(train_features)
    print("fit a new StandardScaler on the training split")
    return scaler


def transform_features(scaler: StandardScaler, features: np.ndarray) -> np.ndarray:
    return scaler.transform(features).astype(np.float32)

def get_device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def compute_metrics(logits: torch.Tensor, labels: torch.Tensor) -> dict[str, float]:
    probabilities = torch.sigmoid(logits)
    predictions = (probabilities >= 0.5).float()

    true_positive = float(((predictions == 1.0) & (labels == 1.0)).sum().item())
    true_negative = float(((predictions == 0.0) & (labels == 0.0)).sum().item())
    false_positive = float(((predictions == 1.0) & (labels == 0.0)).sum().item())
    false_negative = float(((predictions == 0.0) & (labels == 1.0)).sum().item())

    total = true_positive + true_negative + false_positive + false_negative
    accuracy = (true_positive + true_negative) / total if total else 0.0
    precision = true_positive / (true_positive + false_positive) if (true_positive + false_positive) else 0.0
    recall = true_positive / (true_positive + false_negative) if (true_positive + false_negative) else 0.0
    f1 = 2.0 * precision * recall / (precision + recall) if (precision + recall) else 0.0

    return {
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "tp": true_positive,
        "tn": true_negative,
        "fp": false_positive,
        "fn": false_negative,
    }


def evaluate_classifier(
    model: MFCCClassifier,
    features: np.ndarray,
    labels: np.ndarray,
    device: torch.device,
) -> dict[str, float]:
    model.eval()
    with torch.no_grad():
        logits = model(torch.from_numpy(features).to(device))
        label_tensor = torch.from_numpy(labels).to(device)
    return compute_metrics(logits, label_tensor)


def load_or_create_model(
    input_size: int,
    hidden_sizes: tuple[int, int],
    device: torch.device,
    checkpoint: dict[str, object] | None = None,
) -> tuple[MFCCClassifier, tuple[int, int]]:
    checkpoint_hidden_sizes = hidden_sizes
    loaded_hidden_sizes = get_checkpoint_hidden_sizes(checkpoint)
    if loaded_hidden_sizes is not None:
        checkpoint_hidden_sizes = loaded_hidden_sizes
        if checkpoint_hidden_sizes != hidden_sizes:
            raise ValueError(
                f"Checkpoint hidden sizes {checkpoint_hidden_sizes} do not match requested {hidden_sizes}."
            )

    checkpoint_input_size = get_checkpoint_input_size(checkpoint)
    if checkpoint_input_size is not None and checkpoint_input_size != input_size:
        raise ValueError(
            f"Checkpoint input size {checkpoint_input_size} does not match current input size {input_size}."
        )

    model = MFCCClassifier(input_size, hidden_sizes=checkpoint_hidden_sizes).to(device)
    model_state_dict = get_checkpoint_mapping(checkpoint, "model_state_dict")
    if model_state_dict is not None:
        model.load_state_dict(model_state_dict)
        print("loaded model weights from checkpoint")
    else:
        print("starting from a new model")

    return model, checkpoint_hidden_sizes


def move_optimizer_state_to_device(optimizer: torch.optim.Optimizer, device: torch.device) -> None:
    for state in optimizer.state.values():
        for key, value in state.items():
            if isinstance(value, torch.Tensor):
                state[key] = value.to(device)


def optimizer_state_dict_to_cpu(optimizer: torch.optim.Optimizer) -> dict[str, object]:
    optimizer_state = copy.deepcopy(optimizer.state_dict())
    for state in optimizer_state["state"].values():
        for key, value in state.items():
            if isinstance(value, torch.Tensor):
                state[key] = value.detach().cpu()
    return optimizer_state


def train_classifier(
    train_features: np.ndarray,
    train_labels: np.ndarray,
    validation_features: np.ndarray,
    validation_labels: np.ndarray,
    checkpoint: dict[str, object] | None = None,
    hidden_sizes: tuple[int, int] = HIDDEN_SIZES,
    learn_rate: float = LEARNING_RATE,
    epochs: int = EPOCHS,
    seed: int = SEED,
) -> tuple[MFCCClassifier, torch.optim.Optimizer, torch.device, float]:
    np.random.seed(seed)
    torch.manual_seed(seed)

    device = get_device()
    model, checkpoint_hidden_sizes = load_or_create_model(
        train_features.shape[1],
        hidden_sizes,
        device,
        checkpoint=checkpoint,
    )

    train_features_tensor = torch.from_numpy(train_features).to(device)
    train_labels_tensor = torch.from_numpy(train_labels).to(device)
    validation_features_tensor = torch.from_numpy(validation_features).to(device)
    validation_labels_tensor = torch.from_numpy(validation_labels).to(device)

    dog_count = float((train_labels == 1.0).sum())
    other_count = float((train_labels == 0.0).sum())
    dog_class_weight = other_count / max(dog_count, 1.0)

    criterion = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([dog_class_weight], device=device))
    optimizer = torch.optim.Adam(model.parameters(), lr=learn_rate, weight_decay=1e-4)
    optimizer_state_dict = get_checkpoint_mapping(checkpoint, "optimizer_state_dict")
    if optimizer_state_dict is not None:
        optimizer.load_state_dict(optimizer_state_dict)
        move_optimizer_state_to_device(optimizer, device)
        print("loaded optimizer state from checkpoint")

    for param_group in optimizer.param_groups:
        param_group["lr"] = learn_rate
        param_group["weight_decay"] = 1e-4

    model.eval()
    with torch.no_grad():
        baseline_validation_logits = model(validation_features_tensor)
        best_validation_loss = criterion(baseline_validation_logits, validation_labels_tensor).item()
        baseline_metrics = compute_metrics(baseline_validation_logits, validation_labels_tensor)

    if checkpoint is not None and "model_state_dict" in checkpoint:
        print(
            f"resume baseline: val_loss={best_validation_loss:.4f} "
            f"val_acc={baseline_metrics['accuracy']:.3f} "
            f"val_f1={baseline_metrics['f1']:.3f}"
        )

    best_state = copy.deepcopy(model.state_dict())

    for epoch in range(1, epochs + 1):
        model.train()
        optimizer.zero_grad()
        train_logits = model(train_features_tensor)
        train_loss = criterion(train_logits, train_labels_tensor)
        train_loss.backward()
        optimizer.step()

        model.eval()
        with torch.no_grad():
            validation_logits = model(validation_features_tensor)
            validation_loss = criterion(validation_logits, validation_labels_tensor).item()
            validation_metrics = compute_metrics(validation_logits, validation_labels_tensor)

        if validation_loss < best_validation_loss:
            best_validation_loss = validation_loss
            best_state = copy.deepcopy(model.state_dict())

        if epoch == 1 or epoch % 25 == 0 or epoch == epochs:
            print(
                f"epoch {epoch:03d} "
                f"train_loss={train_loss.item():.4f} "
                f"val_loss={validation_loss:.4f} "
                f"val_acc={validation_metrics['accuracy']:.3f} "
                f"val_f1={validation_metrics['f1']:.3f}"
            )

    model.load_state_dict(best_state)
    return model, optimizer, device, dog_class_weight


def save_training_checkpoint(
    model: MFCCClassifier,
    optimizer: torch.optim.Optimizer,
    scaler: StandardScaler,
    hidden_sizes: tuple[int, int] = HIDDEN_SIZES,
    checkpoint_path: Path = CHECKPOINT_PATH,
) -> None:
    checkpoint_path.parent.mkdir(parents=True, exist_ok=True)
    state_dict = {name: parameter.detach().cpu() for name, parameter in model.state_dict().items()}
    torch.save(
        {
            "model_state_dict": state_dict,
            "optimizer_state_dict": optimizer_state_dict_to_cpu(optimizer),
            "feature_mean": torch.from_numpy(np.asarray(scaler.mean_, dtype=np.float32)),
            "feature_scale": torch.from_numpy(np.asarray(scaler.scale_, dtype=np.float32)),
            "feature_std": torch.from_numpy(np.asarray(scaler.scale_, dtype=np.float32)),
            "feature_var": torch.from_numpy(np.asarray(scaler.var_, dtype=np.float32)),
            "hidden_sizes": hidden_sizes,
            "input_size": model.network[0].in_features,
            "label_mapping": {"dog": 1, "other": 0},
        },
        checkpoint_path,
    )
    print(f"saved training checkpoint to {checkpoint_path}")


def save_scaler(scaler: StandardScaler, scaler_path: Path = SCALER_PATH) -> None:
    scaler_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(scaler, scaler_path)
    print(f"saved scaler to {scaler_path}")


def save_traced_model(
    model: MFCCClassifier,
    input_size: int,
    traced_model_path: Path = TRACED_MODEL_PATH,
) -> None:
    traced_model_path.parent.mkdir(parents=True, exist_ok=True)
    model_for_export = copy.deepcopy(model).to("cpu")
    model_for_export.eval()
    example_input = torch.randn(1, input_size, dtype=torch.float32)
    traced_model = cast(torch.jit.ScriptModule, torch.jit.trace(model_for_export, example_input))
    torch.jit.save(traced_model, traced_model_path.as_posix())
    print(f"saved traced model to {traced_model_path}")


def print_metrics(split_name: str, metrics: dict[str, float]) -> None:
    print(
        f"{split_name}: "
        f"acc={metrics['accuracy']:.3f} "
        f"precision={metrics['precision']:.3f} "
        f"recall={metrics['recall']:.3f} "
        f"f1={metrics['f1']:.3f} "
        f"tp={int(metrics['tp'])} "
        f"tn={int(metrics['tn'])} "
        f"fp={int(metrics['fp'])} "
        f"fn={int(metrics['fn'])}"
    )

if __name__ == "__main__":
    dog = sorted(glob.glob(DOG_GLOB))
    other = sorted(glob.glob(OTHER_GLOB))

    analysis_config: dict[str, int | str] = {
        "fftsize": 1024,
        "hopsize": 512,
    }

    dog_mfccs = collect_mfccs(dog, analysis_config)
    other_mfccs = collect_mfccs(other, analysis_config)

    print("dog_mfccs =", dog_mfccs.shape)
    print("other_mfccs =", other_mfccs.shape)

    if dog_mfccs.size == 0 or other_mfccs.size == 0:
        raise RuntimeError("Expected non-empty MFCC feature matrices for both classes.")

    features = np.vstack((dog_mfccs, other_mfccs)).astype(np.float32)
    labels = np.concatenate(
        (
            np.ones(dog_mfccs.shape[0], dtype=np.float32),
            np.zeros(other_mfccs.shape[0], dtype=np.float32),
        )
    )

    train_features, validation_features, train_labels, validation_labels = stratified_split(features, labels)
    checkpoint = load_training_checkpoint()
    scaler = load_or_fit_scaler(train_features, checkpoint=checkpoint)
    train_features = transform_features(scaler, train_features)
    validation_features = transform_features(scaler, validation_features)

    print("train split =", train_features.shape, train_labels.shape)
    print("validation split =", validation_features.shape, validation_labels.shape)

    model, optimizer, device, dog_class_weight = train_classifier(
        train_features,
        train_labels,
        validation_features,
        validation_labels,
        checkpoint=checkpoint,
    )

    parameter_count = sum(parameter.numel() for parameter in model.parameters())
    print("device =", device)
    print("parameters =", parameter_count)
    print("dog class weight =", round(dog_class_weight, 3))

    print_metrics("train", evaluate_classifier(model, train_features, train_labels, device))
    print_metrics("validation", evaluate_classifier(model, validation_features, validation_labels, device))
    save_training_checkpoint(model, optimizer, scaler)
    save_scaler(scaler)
    save_traced_model(model, train_features.shape[1])

