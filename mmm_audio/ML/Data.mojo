from std.os import abort
from std.math import sqrt
from mmm_audio.ML.SafeTensors import SafeTensors

@doc_hidden
def _open_data_file(path: String, format: String) raises -> SafeTensors:
    """Open a safetensors file written by `mmm_python/ML/Data_Python.py` and check that it holds `format`.

    Args:
        path: Path to the `.safetensors` file.
        format: The expected "format" metadata value.

    Returns:
        The opened file.

    Raises:
        Error: If the file is a joblib file, is missing, or does not hold `format`.
    """
    if path.endswith(".joblib"):
        raise Error("joblib files are no longer supported. Convert " + path + " to safetensors with `mmm_python/ML/Data_Python.py`.")
    var st = SafeTensors(path)
    if not st.has_metadata("format") or st.metadata("format") != format:
        raise Error("not a " + format + " safetensors file: " + path)
    if st.metadata("version") != "1":
        raise Error("unsupported " + format + " file version " + st.metadata("version"))
    return st^

struct StandardScaler(Copyable, Movable):
    """StandardScaler (inverse transform only).

    Mean of 0 and standard deviation of 1.
    
    This is not a *full* StandardScaler implementation. It is only designed 
    to load a "fit" sklearn StandardScaler from Python, saved as a safetensors file with
    `save_standard_scaler` in `mmm_python/ML/Data_Python.py`, that can then be used 
    to inverse_transform_point points from the scaled space back to the original space.
    The pattern of use here would be to do the data analysis and machine learning in Python
    using sklearn, then load only the needed data into Mojo for real-time processing.
    """
    var mean: List[Float64]
    var scale: List[Float64]

    def __init__(out self, path: Optional[String] = None):
        """Initializes the StandardScaler struct. If a path is provided, it loads a fitted
        sklearn StandardScaler from it. The StandardScaler must have been fit in Python and
        saved with `save_standard_scaler` in `mmm_python/ML/Data_Python.py`.

        Args:
            path: Optional path to a StandardScaler `.safetensors` file.
        """
        self.mean = List[Float64]()
        self.scale = List[Float64]()

        if path:
            try:
                self.load(path.value())
            except e:
                abort("Error loading StandardScaler: " + String(e))

    def load(mut self, path: String) raises:
        """Loads StandardScaler data from a safetensors file written by
        `save_standard_scaler` in `mmm_python/ML/Data_Python.py`.

        Args:
            path: Path to a StandardScaler `.safetensors` file.

        Raises:
            Error: If the file is missing or is not a StandardScaler file.
        """
        var st = _open_data_file(path, "mmm_standard_scaler")
        var mean = st.get[DType.float64]("mean")
        var scale = st.get[DType.float64]("scale")
        if len(mean) != len(scale):
            raise Error("StandardScaler mean and scale have different sizes: " + path)
        self.mean = mean^
        self.scale = scale^
    
    def inverse_transform_point(mut self, input: List[Float64], mut output: List[Float64]):
        """Inverse transform a single point from scaled space back to original space.

        Nothing is returned, the result is written to the output list.

        Args:
            input: List of length d (original dimensionality) in scaled space.
            output: List of length d (original dimensionality) that will be filled with the result.
        """
        for i in range(len(input)):
            output[i] = (input[i] * self.scale[i]) + self.mean[i]
    
    def transform_point(mut self, input: List[Float64], mut output: List[Float64]):
        """Transform a single point from original space to scaled space.
        
        Nothing is returned, the result is written to the output list.

        Args:
            input: List of length d (original dimensionality) in original space.
            output: List of length d (original dimensionality) that will be filled with the result in scaled space.
        """
        for i in range(len(input)):
            output[i] = (input[i] - self.mean[i]) / self.scale[i]

struct PCA(Copyable, Movable):
    """Principle Component Analysis (PCA) (inverse transform only).
    
    This is not a *full* PCA implementation. It is only designed to load a "fit" sklearn 
    [PCA](https://scikit-learn.org/stable/modules/generated/sklearn.decomposition.PCA.html)
    from Python, saved as a safetensors file with `save_pca` in `mmm_python/ML/Data_Python.py`, that can then be used to inverse_transform_point points from the PCA space 
    back to the original space. The pattern of use here would be to do the data analysis 
    and machine learning in Python using sklearn, then load only the needed data into 
    Mojo for real-time processing.
    """
    var components: List[List[Float64]]
    var mean: List[Float64]
    var evals: List[Float64]
    var whiten: Bool
    var k: Int # number of principal components Kept
    var d: Int # original Dimensionality
    var x: List[Float64]

    def __init__(out self, path: Optional[String] = None):
        """Initializes the PCA struct. If a path is provided, it loads a fitted sklearn PCA
        from it. The PCA must have been fit in Python and saved with `save_pca` in
        `mmm_python/ML/Data_Python.py`.
        
        Args:
            path: Optional path to a PCA `.safetensors` file.
        """
        self.mean = List[Float64]()
        self.components = List[List[Float64]]()
        self.evals = List[Float64]()
        self.whiten = False
        self.k = 0
        self.d = 0
        self.x = List[Float64]()

        if path:
            try:
                self.load(path.value())
            except e:
                abort("Error loading PCA: " + String(e))

    def load(mut self, path: String) raises:
        """Loads PCA data from a safetensors file written by `save_pca` in `mmm_python/ML/Data_Python.py`.

        Args:
            path: Path to a PCA `.safetensors` file.

        Raises:
            Error: If the file is missing, is not a PCA file, or its tensors have mismatched sizes.
        """
        var st = _open_data_file(path, "mmm_pca")
        var shape = st.shape("components")
        if len(shape) != 2:
            raise Error("PCA components are not 2 dimensional: " + path)
        var k = shape[0]
        var d = shape[1]
        var flat = st.get[DType.float64]("components")
        var mean = st.get[DType.float64]("mean")
        var evals = st.get[DType.float64]("explained_variance")
        if len(mean) != d or len(evals) != k:
            raise Error("PCA mean or explained_variance does not match the components: " + path)

        var components = List[List[Float64]](capacity=k)
        for i in range(k):
            components.append(List[Float64](flat[i * d:(i + 1) * d]))

        self.components = components^
        self.mean = mean^
        self.evals = evals^
        self.k = k
        self.d = d
        self.x = List[Float64](length=d, fill=0.0)
        self.whiten = st.metadata("whiten") == "true"

    def transform_point(mut self, input: List[Float64], mut output: List[Float64]):
        """Transform a single point from original space to PCA space.
        
        Nothing is returned, the result is written to the output list.

        Args:
            input: List of length d (original dimensionality).
            output: List of length k (number of principal components kept) that will be filled with the result.
        """
        # Center the input by subtracting the mean: x = input - mean
        for j in range(self.d):
            self.x[j] = input[j] - self.mean[j]

        if self.whiten:
            for i in range(self.k):
                var dot_val = 0.0
                for j in range(self.d):
                    dot_val += self.x[j] * self.components[i][j]
                var s = sqrt(self.evals[i])
                output[i] = dot_val / s
        else:
            for i in range(self.k):
                var dot_val = 0.0
                for j in range(self.d):
                    dot_val += self.x[j] * self.components[i][j]
                output[i] = dot_val

    def inverse_transform_point(mut self, input: List[Float64], mut output: List[Float64]):
        """Inverse transform a single point from PCA space back to original space.

        Nothing is returned, the result is written to the output list.

        Args:
            input: List of length k (number of principal components kept).
            output: List of length d (original dimensionality) that will be filled with the result.
        """
        for j in range(self.d):
            self.x[j] = 0.0

        # Precompute scaled input if whitening
        if self.whiten:
            for i in range(self.k):
                # scale by sqrt of variance
                var s = sqrt(self.evals[i])
                var ui = input[i] * s
                # x += ui * components[i]
                for j in range(self.d):
                    self.x[j] += ui * self.components[i][j]
        else:
            for i in range(self.k):
                for j in range(self.d):
                    self.x[j] += input[i] * self.components[i][j]

        # add mean
        for j in range(self.d):
            output[j] = self.x[j] + self.mean[j]