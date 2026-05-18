from std.os import abort
from std.python import PythonObject, Python
from std.math import sqrt 

struct StandardScaler(Copyable, Movable):
    """StandardScaler (inverse transform only).

    Mean of 0 and standard deviation of 1.
    
    This is not a *full* StandardScaler implementation. It is only designed 
    to load a "fit" sklearn StandardScaler object from Python that can then be used 
    to inverse_transform_point points from the scaled space back to the original space.
    The pattern of use here would be to do the data analysis and machine learning in Python
    using sklearn, then load only the needed data into Mojo for real-time processing.
    """
    var mean: List[Float64]
    var scale: List[Float64]

    def __init__(out self, sklearn_path: Optional[String] = None):
        """Initializes the StandardScaler struct. If a sklearn_path is provided, 
        it will attempt to load a fitted sklearn StandardScaler object from Python. 
        The StandardScaler object must have been fit in Python before saving, and should be saved
        from Python using `joblib.dump(scaler, path)`.
        """
        self.mean = List[Float64]()
        self.scale = List[Float64]()

        if sklearn_path:
            self.load_from_sklearn(sklearn_path.value())

    def load_from_sklearn(mut self, path_joblib: String):
        """Loads StandardScaler data from a fitted sklearn StandardScaler 
        object saved with joblib. The StandardScaler object must have been 
        fit in Python before saving, and should be saved from Python 
        using `joblib.dump(scaler, path)`.

        Args:
            path_joblib: Path to a joblib file containing a fitted sklearn StandardScaler object.
        """
        try:
            joblib = Python.import_module("joblib")
            scaler: PythonObject = joblib.load(path_joblib)
            self.mean.clear()
            self.scale.clear()
            for i in range(len(scaler.scale_)):
                self.scale.append(Float64(py=scaler.scale_[i]))
                self.mean.append(Float64(py=scaler.mean_[i]))
        except e:
            abort("Error importing sklearn.preprocessing module:" + String(e))
    
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
    from Python that can then be used to inverse_transform_point points from the PCA space 
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

    def __init__(out self, joblib_path: Optional[String] = None):
        """Initializes the PCA struct. If a joblib_path is provided, 
        it will attempt to load the PCA data from a sklearn PCA 
        object saved with joblib. The PCA object must have been fit 
        in Python before saving, and should be saved from Python 
        using `joblib.dump(pca, path)`.
        
        Args:
            joblib_path: Optional path to a joblib file containing a fitted sklearn PCA object.
        """
        self.mean = List[Float64]()
        self.components = List[List[Float64]]()
        self.evals = List[Float64]()
        self.whiten = False
        self.k = 0
        self.d = 0
        self.x = List[Float64]()

        if joblib_path:
            self.load_from_sklearn(joblib_path.value())

    def load_from_sklearn(mut self, joblib_path: String):
        """Loads PCA data from a sklearn PCA object saved with joblib. 
        The PCA object must have been fit in Python before saving, and 
        should be saved from Python using `joblib.dump(pca, path)`.

        Args:
            joblib_path: Path to a joblib file containing a fitted sklearn PCA object.
        """
        try:
            joblib = Python.import_module("joblib")
            pca: PythonObject = joblib.load(joblib_path)

            for i in range(len(pca.mean_)):
                self.mean.append(Float64(py=pca.mean_[i]))
            
            for i in range(len(pca.components_)):
                row = List[Float64]()
                for j in range(len(pca.components_[i])):
                    row.append(Float64(py=pca.components_[i][j]))
                self.components.append(row^)

            for i in range(len(pca.explained_variance_)):
                self.evals.append(Float64(py=pca.explained_variance_[i]))

            self.k = len(self.components)
            self.d = len(self.components[0])
            self.x = List[Float64](length=self.d, fill=0.0)
            self.whiten = Bool(py=pca.whiten)

        except e:
            abort("Error importing sklearn.decomposition module:" + String(e))

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