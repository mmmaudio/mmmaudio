"""A GUI for collecting training points, training an MLP, and loading it into a running MMMAudio graph.

`MLPTrainingGUI` is the interactive front end for the pure Mojo `MLP` (`MLP_Module.mojo`)
and the PyTorch training code in `MLP_Python.py`. It maps a set of input controls (the X
side of the network) to a bank of output sliders (the y side), lets you collect X/y pairs
by ear, trains a network on them in PyTorch, and hands the result to the synth, which runs inference in pure Mojo.

A typical session:

1. Turn inference off, so the output sliders drive the synth directly.
2. Move the output sliders (or press "randomize") until you like the sound.
3. Move the input controls to where that sound should live and press "add training point".
4. Repeat for as many points as you like, then press "train model".
5. When training finishes the new weights are loaded into MMMAudio. Turn inference on and
   the input controls now play the synth through the network.

You can also save and load the training points to a JSON file, and the trained weights are saved as a safetensors file. This means you can make a training set in Python, save it, and then load it into the GUI later to continue training or to train a new network.

The Mojo graph needs an `MLP` whose `input_size` and `output_size` match the GUI, and whose
namespace matches `mlp_namespace`. See `examples/ML_examples/MLP_Synth.py` for a full example.
"""

from mmm_python import *
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QLineEdit, QSpinBox
import json



class MLPTrainingGUI():
    """A Qt window for building a training set, training an MLP on it, and loading it into MMMAudio.

    The window has one slider per output of the network on the left, with the provided labels.

    The provided input controls plus the training buttons are on the right:

    - **randomize**: set every output slider to a random value.
    - **add training point**: store the current input controls (X) and output sliders (y) as a pair.
    - **print points**: print every stored pair.
    - **prev point / next point**: step through the stored pairs, setting the controls and sliders to each one.
    - **Delete @ / Insert @**: delete the pair at the number in the box, or insert the current X/y there.
    - **clear training data**: remove every stored pair.
    - **save data to json / load data from json**: save or load the pairs at "save points path".
    - **train model**: train a new network on the stored pairs in a background thread, save it to
      "save path", and load it into MMMAudio when it is done.
    - **load model to MMMAudio**: load the weights at "save path" without training.
    - **toggle inference**: switch the Mojo `MLP` between running the network and following the output sliders.
    - **namespace, save points path, save path, epochs**: edit the matching settings while the GUI is running.

    Input values are normalized to 0.0-1.0: a `Slider2D` adds two inputs (x and y), and any
    other control (e.g. a `QSlider`) adds one, scaled from its minimum and maximum. All nn parameters are scaled to 0.0-1.0. This simplifies training and avoids the need for a separate normalization step. The output sliders are also normalized to 0.0-1.0, but a user's synth can scale them to whatever range is needed for the actual parameters.

    Example:
        see `examples/ML_examples/MLP_Synth.py` for a complete example of using this GUI to train a new MLP and load it into a running MMMAudio graph.
    """


    def __init__(self,
                 mmm_audio: MMMAudio,
                 input_size: int,
                 layers: list[list],
                 labels: list[str],
                 mlp_namespace: str,
                 save_points_path: str,
                 save_path: str,
                 controls_list: list,
                 epochs: int = 5000):
        """Build the window and show it.

        Args:
            mmm_audio: The `MMMAudio` instance to send messages to. This variable
                should be named something other than `mmm_audio`. Doing so will cause an error.
            input_size: Number of inputs to the network. Must equal the number of values the
                controls in `controls_list` produce.
            layers: Layer specifications as `[size, activation]` pairs, as in
                `MLP_Python.train_new_mlp`. The last size must equal `len(lables)`.
            labels: One label per network output; one output slider is made for each.
            mlp_namespace: Namespace of the Mojo `MLP` to send messages to (e.g. `"mlp1"`).
            save_points_path: JSON file the training points are saved to and loaded from.
            save_path: `.safetensors` file the trained weights are saved to and loaded into MMMAudio from.
            controls_list: Input controls: `Slider2D`s (two inputs each) or Qt sliders with
                `value()`, `minimum()` and `maximum()` (one input each). This list of controls should match the number of inputs specified by `input_size`. The controls will be added to the window and their values will be normalized to 0.0-1.0 for training.
            epochs: Number of training epochs. Can also be changed in the GUI. Default is 5000.
        """
        self.mmm_audio = mmm_audio
        self.app = QApplication.instance() or QApplication([])
        self.mlp_namespace = mlp_namespace
        self.save_points_path = save_points_path
        self.save_path = save_path
        self.out_size = len(labels)
        self.labels = labels
        self.controls_list = controls_list
        self.input_size = input_size
        self.layers = layers
        self.epochs = epochs

        self.running = True

        self.sliders = []
        self.window = QWidget()
        self.window.setWindowTitle("MLP Training GUI")
        self.window.resize(600, 100)

        main_layout = QHBoxLayout()

        self.layouts = []
        self.settings = [0.0 for _ in range(self.out_size)]
        
        self.layouts.append(QVBoxLayout())
        self.layouts[0].setSpacing(0)
        
        self.layouts.append(QVBoxLayout())
        self.layouts[1].setSpacing(0)
        
        main_layout.addLayout(self.layouts[0])
        main_layout.addLayout(self.layouts[1])
        
        for i in range(self.out_size):
            self.add_handle(self.labels[i], i, rrand(0.0, 1.0), 0)
        # Handle doesn't run its callback on creation, so pick up where the sliders start
        self.settings = [s.get_value() for s in self.sliders]
        self.mmm_audio.send_floats(self.mlp_namespace + ".fake_model_output", self.settings)

        button = QPushButton("randomize")
        button.clicked.connect(lambda: [s.set_value(s.spec.unnormalize(rrand(0.0001, 1.0))) for s in self.sliders])
        self.layouts[1].addWidget(button)

        self.scroll_counter = 0
        self.current_X = []  # filled in as each control is placed below
        self.X_train_list = []
        self.y_train_list = []

        button = QPushButton("add training point")
        button.clicked.connect(self.collect_data)
        self.layouts[1].addWidget(button)

        print_points_button = QPushButton("print points")
        print_points_button.clicked.connect(self.print_points)
        self.layouts[1].addWidget(print_points_button)

        row_layout = QHBoxLayout()
        prev_button = QPushButton("prev point")
        prev_button.clicked.connect(self.prev_point)
        row_layout.addWidget(prev_button)
        self.layouts[1].addLayout(row_layout)

        next_button = QPushButton("next point")
        next_button.clicked.connect(self.next_point)
        row_layout.addWidget(next_button)
        
        row_layout = QHBoxLayout()
        self.number_box = QSpinBox()
        self.number_box.setMaximum(999999)  # QSpinBox defaults to a max of 99
        button = QPushButton("Delete @")
        button2 = QPushButton("Insert @")

        button.clicked.connect(self.delete_box_value)
        button2.clicked.connect(self.insert_box_value)
        row_layout.addWidget(self.number_box)
        row_layout.addWidget(button)
        row_layout.addWidget(button2)
        self.layouts[1].addLayout(row_layout)

        clear_training_data_button = QPushButton("clear training data")
        clear_training_data_button.clicked.connect(self.clear_training_data)
        self.layouts[1].addWidget(clear_training_data_button)

        save_data_button = QPushButton("save data to json")
        save_data_button.clicked.connect(self.save_data)
        self.layouts[1].addWidget(save_data_button)

        load_data_button = QPushButton("load data from json")
        load_data_button.clicked.connect(self.load_data)
        self.layouts[1].addWidget(load_data_button)

        train_button = QPushButton("train model")
        train_button.clicked.connect(self.do_the_training)
        self.layouts[1].addWidget(train_button)

        row_layout = QHBoxLayout()
        epochs_box = QSpinBox()
        epochs_box.setRange(1, 1000000)
        epochs_box.setSingleStep(100)
        epochs_box.setValue(self.epochs)
        epochs_box.valueChanged.connect(lambda v: setattr(self, 'epochs', v))
        row_layout.addWidget(QLabel("epochs"))
        row_layout.addWidget(epochs_box)
        self.layouts[1].addLayout(row_layout)

        load_button = QPushButton("load model to MMMAudio")
        load_button.clicked.connect(self.load_model)
        self.layouts[1].addWidget(load_button)

        toggle_inference_button = QPushButton("toggle inference")
        toggle_inference_button.setCheckable(True)
        toggle_inference_button.clicked.connect(lambda: self.mmm_audio.send_bool(self.mlp_namespace + ".toggle_inference", toggle_inference_button.isChecked()))
        self.layouts[1].addWidget(toggle_inference_button)

        row_layout = QHBoxLayout()
        namespace_box = QLineEdit()
        namespace_box.setText(self.mlp_namespace)
        namespace_box.textChanged.connect(lambda text: setattr(self, 'mlp_namespace', text))
        row_layout.addWidget(QLabel("namespace"))
        row_layout.addWidget(namespace_box)
        self.layouts[1].addLayout(row_layout)

        row_layout = QHBoxLayout()
        path_box = QLineEdit()
        path_box.setText(self.save_points_path)
        path_box.textChanged.connect(self._set_save_points_path)
        row_layout.addWidget(QLabel("save points path"))
        row_layout.addWidget(path_box)
        self.layouts[1].addLayout(row_layout)

        row_layout = QHBoxLayout()
        path_box = QLineEdit()
        path_box.setText(self.save_path)
        path_box.textChanged.connect(self._set_save_path)
        row_layout.addWidget(QLabel("save path"))
        row_layout.addWidget(path_box)
        self.layouts[1].addLayout(row_layout)

        # each control adds its starting value(s) to current_X, and updates them at that index when it moves
        for ctl in self.controls_list:
            self.layouts[1].addWidget(ctl)
            index = len(self.current_X)
            if isinstance(ctl, Slider2D):
                self.current_X.extend(ctl.get_values())
                ctl.valueChanged.connect(
                    lambda *args, counter=index: self.map_slider_changed2(counter, *args)
                )
            else:
                self.current_X.append(self._slider_to_norm(ctl, ctl.value()))
                ctl.valueChanged.connect(
                    lambda arg, counter=index, ctl=ctl: self.map_slider_changed1(counter, ctl, arg)
                )

        self.window.closeEvent = self.on_close
        self.window.setLayout(main_layout)
        self.window.show()
        self.window.raise_()

        # Timer for non-blocking event processing in REPL
        self.timer = QTimer()
        self.timer.timeout.connect(self._process)
        self.timer.start(50)  # Process events every 50ms

    def add_handle(self, name, num: int, default: float, layout_index: int):
        """Add an output slider that writes to `settings` and sends it to the synth.

        Args:
            name: Label of the slider.
            num: Index of the network output this slider controls.
            default: Starting value.
            layout_index: Which column of the window to put it in.
        """
        def lil_func(v):
            self.settings[num] = v
            print(self.settings)
            self.mmm_audio.send_floats(self.mlp_namespace + ".fake_model_output", self.settings)
        slider = Handle(name, default=default, callback=lil_func)
        self.sliders.append(slider)
        self.layouts[layout_index].addWidget(slider)

    def collect_data(self):
        """Add the current inputs and outputs to the end of the training data."""
        x = self.current_X.copy()
        y = self.settings.copy()
        self.X_train_list.append(x)
        self.y_train_list.append(y)
        self.scroll_counter = len(self.X_train_list) - 1
        print(f"added data point {self.scroll_counter}: X={x}, y={y}")

    def insert_box_value(self):
        """Insert the current inputs and outputs at the index in the number box."""
        x = self.current_X.copy()
        y = self.settings.copy()
        index = self.number_box.value()
        # index == len appends, so this also works on an empty list
        if 0 <= index <= len(self.X_train_list):
            self.X_train_list.insert(index, x)
            self.y_train_list.insert(index, y)
            self.scroll_counter = index
            print(f"inserted data point {index}: X={x}, y={y}")

    @staticmethod
    def _slider_to_norm(ctl, value):
        return (value - ctl.minimum()) / (ctl.maximum() - ctl.minimum())

    def map_slider_changed2(self, index, *args):
        """Store a `Slider2D` move in `current_X` at `index` and `index + 1`."""
        self.current_X[index] = args[0]
        self.current_X[index+1] = args[1]
        print(self.current_X)

    def map_slider_changed1(self, index, ctl, arg):
        """Store a slider move in `current_X` at `index`, normalized to 0.0-1.0."""
        self.current_X[index] = self._slider_to_norm(ctl, arg)
        print(self.current_X)

    def clear_training_data(self):
        """Remove every training point."""
        self.X_train_list = []
        self.y_train_list = []
        self.scroll_counter = 0
        print("cleared training data")

    def print_points(self):
        """Print every training point as `index X y`."""
        for i in range(len(self.X_train_list)):
            print(i, self.X_train_list[i], self.y_train_list[i])

    def delete_box_value(self):
        """Delete the training point at the index in the number box."""
        index = self.number_box.value()
        if 0 <= index < len(self.X_train_list):
            del self.X_train_list[index]
            del self.y_train_list[index]
            self.scroll_counter = min(self.scroll_counter, max(len(self.X_train_list) - 1, 0))
            print(f"deleted data point {index}")

    def _process(self):
        self.app.processEvents()

    def _set_save_points_path(self, text):
        self.save_points_path = text

    def _set_save_path(self, text):
        self.save_path = text

    def set_point_sliders(self):
        """Set the input controls and output sliders to the current training point."""
        self.number_box.setValue(self.scroll_counter)
        y_vals = self.y_train_list[self.scroll_counter]
        for i, val in enumerate(y_vals):
            # settings already holds unnormalized values (Handle.get_value)
            self.sliders[i].set_value(val)

        x_vals = self.X_train_list[self.scroll_counter]
        ind = 0
        for ctl in self.controls_list:
            if isinstance(ctl, Slider2D):
                ctl.set_values(x_vals[ind], x_vals[ind + 1])
                ind += 2
            else:
                ctl.setValue(x_vals[ind]*(ctl.maximum()-ctl.minimum())+ctl.minimum())
                ind += 1

        print(self.scroll_counter, self.X_train_list[self.scroll_counter])

    def next_point(self):
        """Step to the next training point, wrapping around at the end."""
        if not self.X_train_list:
            print("no training points")
            return
        self.scroll_counter = (self.scroll_counter + 1) % len(self.X_train_list)
        self.set_point_sliders()

    def prev_point(self):
        """Step to the previous training point, wrapping around at the start."""
        if not self.X_train_list:
            print("no training points")
            return
        self.scroll_counter = (self.scroll_counter - 1) % len(self.X_train_list)
        self.set_point_sliders()

    def save_data(self):
        """Save the training points to `save_points_path` as JSON."""
        print("saving data to: " + self.save_points_path)
        data = {}
        for i in range(len(self.X_train_list)):
            data[str(i)] = [self.X_train_list[i], self.y_train_list[i]]

        with open(self.save_points_path, "w") as f:
            json.dump(data, f, indent=2)

    def load_data(self):
        """Replace the training points with the ones saved at `save_points_path`."""
        print("loading data from: " + self.save_points_path)
        with open(self.save_points_path, "r") as f:
            data = json.load(f)

        self.X_train_list.clear()
        self.y_train_list.clear()

        for _, val in data.items():
            self.X_train_list.append(val[0])
            self.y_train_list.append(val[1])

        self.scroll_counter = 0
        print(f"loaded {len(self.X_train_list)} data points")

    def do_the_training(self):
        """Train a new network on the training points and load it into MMMAudio.

        Training runs in a background thread on a copy of the points, so the GUI and audio
        keep running. When it finishes, the weights are saved to `save_path` and loaded into
        the `MLP` at `mlp_namespace`. Nothing is trained if there are no points or the sizes
        of the points, `input_size`, `layers` and the labels don't agree.
        """
        if not self.X_train_list:
            print("no training points - add some before training")
            return
        # catch size mismatches here, rather than when the Mojo MLP rejects the file
        out_size = self.layers[-1][0]
        if out_size != self.out_size:
            print(f"last layer size {out_size} doesn't match the {self.out_size} labels")
            return
        bad = [i for i, (x, y) in enumerate(zip(self.X_train_list, self.y_train_list))
               if len(x) != self.input_size or len(y) != out_size]
        if bad:
            print(f"data points {bad} don't match input size {self.input_size} / output size {out_size}")
            return

        print("training the network")
        learn_rate = 0.001

        from mmm_audio.ML.MLP_Python import train_new_mlp
        import threading

        # copies, so adding or deleting points mid-training doesn't touch this run
        save_path = self.save_path
        args = ([x.copy() for x in self.X_train_list], [y.copy() for y in self.y_train_list],
                self.layers, learn_rate, self.epochs, save_path)

        def train_and_load():
            try:
                train_new_mlp(*args)
            except Exception as e:
                print(f"training failed: {e}")
                return
            print("training done, loading into MMMAudio")
            self.mmm_audio.send_string(self.mlp_namespace + ".load_mlp_training", save_path)

        training_thread = threading.Thread(target=train_and_load, daemon=True)
        training_thread.start()

    def load_model(self):
        """Load the weights at `save_path` into the `MLP` at `mlp_namespace`."""
        self.mmm_audio.send_string(self.mlp_namespace + ".load_mlp_training", self.save_path)

    def on_close(self, event):
        """Stop the event timer when the window is closed."""
        self.timer.stop()
        self.running = False
        event.accept()

    def close(self):
        """Stop the event timer and close the window."""
        self.timer.stop()
        self.window.close()