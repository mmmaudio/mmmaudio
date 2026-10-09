"""
Shows how to train a new MLP in Python using PyTorch and load it into the Mojo synth.

The Mojo side MLP does not use PyTorch, but loads the training weights from a safetensors file saved by the Python training code. 
"""
if True:
    from mmm_python import *

    MMMAudio.compile("MLP_Synth", "examples.ML_examples")
    m_a = MMMAudio(128, in_device=None, graph_name="MLP_Synth", package_name="examples.ML_examples")

    # this one is a bit intense, so maybe start with a low volume
    m_a.start_audio()

# the MLP training GUI can be used to train an MLP in Python and save the weights to a safetensors file that can be loaded into Mojo.

if True:
    from mmm_python.ML import MLP_Trainer
    from mmm_python import *

    qapp = QApplication.instance() or QApplication([])

    input_size = 2
    layers = [ [ 64, "relu" ], [ 64, "relu" ], [ 14, "sigmoid" ] ]

    tg = MLP_Trainer.MLPTrainingGUI(
        m_a, #this cannot be named `mmm_audio` because that is the package name
        input_size,
        layers,
        labels = ["freq1", "mod1", "osc1_frac", "sr_reduction", "lpf1", "q1", "tanh_gain2", "freq2", "mod2", "osc2_frac", "sr_reduction2", "lpf2", "q2", "tanh_gain2"],
        mlp_namespace = "mlp1",
        save_points_path = "examples/ML_examples/nn_trainings/mlp_example_training_points.json",
        save_path = "examples/ML_examples/nn_trainings/mlp_example_training.safetensors",
        controls_list = [
            Slider2D(200, 200)
        ],
        epochs = 5000)
