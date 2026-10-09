"""Save fitted sklearn `StandardScaler` and `PCA` objects as safetensors files for the Mojo `StandardScaler` and `PCA` in `ML/Data.mojo`.

The Mojo side reads these with `SafeTensors.mojo`, so it does not need Python, sklearn or joblib.
Older `.joblib` files can be converted by passing their path instead of a fitted object.

StandardScaler file format:

    tensors (float64):
        "mean"   [d]
        "scale"  [d]
    metadata (all strings):
        "format":  "mmm_standard_scaler"
        "version": "1"

PCA file format:

    tensors (float64):
        "mean"                [d]
        "components"          [k, d]
        "explained_variance"  [k]
    metadata (all strings):
        "format":  "mmm_pca"
        "version": "1"
        "whiten":  "true" or "false"
"""

import numpy as np

SCALER_FORMAT = "mmm_standard_scaler"
PCA_FORMAT = "mmm_pca"
VERSION = 1

def _fitted(obj):
    """Return `obj`, or the object stored in it if it is the path to a `.joblib` file."""
    if isinstance(obj, str):
        import joblib
        return joblib.load(obj)
    return obj

def _float64(array) -> np.ndarray:
    return np.ascontiguousarray(array, dtype=np.float64)

def save_standard_scaler(scaler, out_file: str):
    """Save a fitted sklearn StandardScaler as the safetensors file the Mojo `StandardScaler` loads.

    Args:
        scaler: A fitted `sklearn.preprocessing.StandardScaler`, or the path to a `.joblib` file of one.
        out_file: Path of the `.safetensors` file to write.
    """
    from safetensors.numpy import save_file

    scaler = _fitted(scaler)
    tensors = {"mean": _float64(scaler.mean_), "scale": _float64(scaler.scale_)}
    save_file(tensors, out_file, metadata={"format": SCALER_FORMAT, "version": str(VERSION)})
    print(f"StandardScaler saved to {out_file}: {len(scaler.mean_)} features")

def load_standard_scaler(in_file: str):
    """Load a StandardScaler safetensors file back into a sklearn StandardScaler.

    Only the statistics `transform` and `inverse_transform` need are restored.

    Args:
        in_file: Path of a `.safetensors` file written by `save_standard_scaler`.

    Returns:
        A `sklearn.preprocessing.StandardScaler`.
    """
    from safetensors import safe_open
    from sklearn.preprocessing import StandardScaler

    with safe_open(in_file, "np") as f:
        if f.metadata().get("format") != SCALER_FORMAT:
            raise ValueError(f"not a StandardScaler safetensors file: {in_file}")
        mean = f.get_tensor("mean")
        scale = f.get_tensor("scale")
    scaler = StandardScaler()
    scaler.mean_ = mean
    scaler.scale_ = scale
    scaler.var_ = np.square(scale)
    scaler.n_features_in_ = int(mean.shape[0])
    scaler.n_samples_seen_ = 0
    return scaler

def save_pca(pca, out_file: str):
    """Save a fitted sklearn PCA as the safetensors file the Mojo `PCA` loads.

    Args:
        pca: A fitted `sklearn.decomposition.PCA`, or the path to a `.joblib` file of one.
        out_file: Path of the `.safetensors` file to write.
    """
    from safetensors.numpy import save_file

    pca = _fitted(pca)
    tensors = {
        "mean": _float64(pca.mean_),
        "components": _float64(pca.components_),
        "explained_variance": _float64(pca.explained_variance_),
    }
    metadata = {"format": PCA_FORMAT, "version": str(VERSION), "whiten": "true" if pca.whiten else "false"}
    save_file(tensors, out_file, metadata=metadata)
    print(f"PCA saved to {out_file}: {pca.components_.shape[1]} features -> {pca.components_.shape[0]} components")
