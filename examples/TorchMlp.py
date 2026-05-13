"""
This examples uses a PyTorch MLP model to control a 16 parameter synth
to play the synth, just execute the top "if" statement and play the synth with the mouse. The X and Y
positions control two input parameters to the MLP, which then outputs 16 parameters to control the
synth.

You can also train the Multi-Layer Perceptron by creating any number of input/output pairs and making a new training. When training the MLP, temporarily disable the MLP inference so you can set the synth parameters directly.
"""

if True:
    from mmm_python import *
    from random import random

    mmm_audio = MMMAudio(128, in_device=None, graph_name="TorchMlp", package_name="examples")

    # this one is a bit intense, so maybe start with a low volume
    mmm_audio.start_audio()

# below is the code to make a new training --------------------------------

# toggle inference off so you can set the synth values directly
mmm_audio.send_bool("mlp1.toggle_inference", True)
mmm_audio.send_bool("mlp1.toggle_inference", False)

# how many outputs does your mlp have?
out_size = 16

# create lists to hold your training data
X_train_list = []
y_train_list = []

def make_setting():
    setting = []
    for _ in range(out_size):
        setting.append(random())
    print("setting =", setting)
    mmm_audio.send_floats("mlp1.fake_model_output", setting)

    return setting

# create an output setting to train on
outputs = make_setting()

# print out what you have so far
for i in range(len(y_train_list)):
    print(f"Element {i}: {X_train_list[i]}")
    print(f"Element {i}: {y_train_list[i]}")

# when you like a setting add an input and output pair
# this is assuming you are training on 4 pairs of data points - you do as many as you like

outputs = make_setting()

X_train_list.append([0,0])
y_train_list.append(outputs)

outputs = make_setting()

X_train_list.append([0,1])
y_train_list.append(outputs)

outputs = make_setting()

X_train_list.append([1,1])
y_train_list.append(outputs)

outputs = make_setting()

X_train_list.append([1,0])
y_train_list.append(outputs)

# once you have filled the X_train_list and y_train_list, train the network on your data

def do_the_training():
    print("training the network")
    learn_rate = 0.001
    epochs = 5000

    layers = [ [ 64, "relu" ], [ 64, "relu" ], [ out_size, "sigmoid" ] ]

    # train the network in a separate thread so the audio thread doesn't get interrupted

    from mmm_audio.MLP_Python import train_nn
    import threading

    target_function = train_nn
    args = (X_train_list, y_train_list, layers, learn_rate, epochs, "examples/nn_trainings/model_traced.pt")

    # Create a Thread object
    training_thread = threading.Thread(target=target_function, args=args)
    training_thread.start()

do_the_training()

# load the new training into the synth
mmm_audio.send_string("mlp1.load_mlp_training", "examples/nn_trainings/model_traced.pt")  

# toggle inference off so you can set the synth values directly
mmm_audio.send_bool("mlp1.toggle_inference", True)