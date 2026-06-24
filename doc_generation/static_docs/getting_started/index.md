# Getting Started with MMMAudio

MMMAudio uses [Mojo's Python interop](https://docs.modular.com/mojo/manual/python/) to compile audio graphs directly in your Python programming environment.

Currently Mojo's compiler is MacOS(Apple Silicon) & Linux(x86 and arm - builds downstream of Ubuntu 22 LTS) only. It works great on Raspberry Pi when the Pi uses Ubuntu. Windows users can use WSL2 as described below though it is currently a bit rough. 

Please see the [MMMAudio YouTube Playlist](https://www.youtube.com/playlist?list=PLeOjmNO6F-TQ6p9pEYT3zt1dEfFaUWezr) to view the available video tutorials about MMMAudio!

Join the [Discourse](https://mmmaudio.discourse.group/) Community!

## 1. Clone the Repository

```
git clone https://github.com/spluta/MMMAudio.git
```

or [grab the latest release](https://github.com/spluta/MMMAudio/releases).

## 2a. Installing portaudio and hidapi on MacOS (Apple Silicon Only - Mojo Does not and will not work on Intel Macs) and Linux

Use your package manager to install `portaudio` and `hidapi` as system-wide c libraries. On MacOS this is:

```shell
brew install portaudio
brew install hidapi
```

MMMAudio uses `pyAudio` (`portaudio`) for audio input/output and `hid` for HID control.

On linux:
```shell
sudo apt update
sudo apt install libportaudio2 portaudio19-dev
sudo apt install libhidapi-hidraw0 libhidapi-dev
sudo apt install pulseaudio python3-dev build-essential
```

Linux users may encounter issues installing some packages, like pyaudio. This is probably because you need to build the package on your machine. You may need some or more of the following:
```
sudo apt-get install python3-all-dev python3-venv
```
Linux users may also have an issue with pyautogui, which we use to track the mouse. If this is the case, the best solution is to look for how to switch Ubuntu to Xorg instead of Wayland (available on ubuntu 24 and before) or to simply use the fake_mouse window when examples are looking for the mouse. We will look for future solutions that do not use pyautogui.

## 2b.1. Option 1 - Setup with pixi (For Windows, go to [MMMAudio-WindowsSetup](MMMAudio-WindowsSetup.md))

This is confirmed to work on Mac. Linux users should use uv @2b.2 or a standard venv @2b.3 below.

### 1 Install pixi with homebrew or curl.

See [pixi's installation instructions](https://pixi.prefix.dev/latest/installation/).

### 2 In the MMMAudio directory, type:

You can change the version of python inside the pixi.toml file if you need to. 

```shell
pixi install
```


## 2b.2. Option 2 - Setup using uv



```
# Create venv with the Python version specified in pyproject.toml
uv venv

# Or specify Python version explicitly
uv venv --python 3.14

# Sync/install all dependencies from pyproject.toml
uv sync

# add mojo
uv add mojo --prerelease allow
```

## 2b.3. Option 3 - Setup the Python Virtual Environment (Mac and Linux)

`cd` into the root of the downloaded repository, set up your virtual environment, and install required libraries. this should work with python 3.12 and above.  If you find it does or doesn't work with other versions [let us know](https://github.com/spluta/MMMAudio/issues).

### 1 depending on your system set up, you may need to explicitly specify the Python version here, eg: 'python3.12 -m venv venv'. I was only able to get this working with python3.12 on Linux.

```shell
python -m venv venv 
source venv/bin/activate

pip install numpy scipy librosa pyautogui torch supriya-midi python-osc matplotlib PySide6 mojo==1.0.0b2 hidapi pyaudio
```

## 3 Edit the .vscode/settings.json file to have the following:
```
{
    "search.useIgnoreFiles": true, 
    "python.defaultInterpreterPath": "${workspaceFolder}/.pixi/envs/default/bin/python", 
    "python.terminal.activateEnvironment": false,
    "python.REPL.sendToNativeREPL": false,
    "python-envs.defaultEnvManager": "ms-python.python:system"
}
```

## 4 In View -> Command Palette -> Python: Select Interpreter, choose `.pixi/envs/default/bin/python` or `venv/bin/python`. For me, this only appeared after I quit and restarted VSCode.

You should be good to go.

## 5 Install Python and Mojo VSCode Extensions

Click on the Extensions icon on the left hand side of VS Code and install the Python and Mojo extensions.

## 6 VSCode issues - Microsoft giveth, Microsoft taketh away

VSCode is amazing, but most of the issues users encounter are caused by VSCode's Python inconsistancies. 
#### a) See 2.3 above on proper vscode settings for Python. 
#### b) We have found that setting Settings -> Auto Activation Type to `shellStartup` works better than the default `command` setting.

## 2w. Setup the Environment on Windows/WSL2 with Ubuntu

Go to [MMMAudio-WindowsSetup](MMMAudio-WindowsSetup.md)

## 7. Run an Example

The best way to run MMMAudio is in REPL mode in your editor. 

to set up the python REPL correctly in VSCode: with the entire directory loaded into a workspace, go to View->Command Palette->Select Python Interpreter. Make sure to select the version of python that is in your pixi or venv directory, not the system-wide version. Then it should just work. 

Before you run the code in a new REPL, make sure to close all terminal instances in the current workspace. This will ensure that a fresh REPL environment is created.

Most examples run by selecting code in the file and pressing shift-return to execute the code. If your interpeter is not opened in the terminal, it should open a new one, load the virtual environment, and run the code. 

Some examples are designed to run a complete script. These are all marked. In these cases, the script can be run by pressing the "play" button on the top right of VSCode or just running the script `python example.py` from inside your virtual environment.

VS Code has issues with lots of text sometimes. If your code gets garbled as it is sent to the terminal, it is a VS Code problem. Try an earlier version of the editor.

Go to the [Examples](../examples/index.md) page to run an example!

## 4. Make Your Own Sounds

When running an example, the Mojo compiler considers the `examples` directory a "module". This is important because when you make your own directory of files and projects, that directory also needs to be a module. 

For your directory to be considered a "module" by the mojo compiler, in addition to your `.mojo` and `.py` files, there also needs to be an empty `__init__.mojo` file in that directory. (See how the examples folder has this file and it is empty. It is there because it needs to be!)

The `.gitignore` file already ignores two directories, one called "mine" and one called "user_files", so if you make a directory called `mine` or `user_files` next to the `examples` directory, you can put all the `.mojo` and corresponding `.py` files in there you want (plus the `__init__.mojo` file) and git will never accidentally overwrite these directories.

To make a new MMMAudio project, a good approach is to copy and paste a `.mojo` and `.py` file pair from the examples directory to get you started. Then modify them!

!!! Note

    When running a MMMAudio program in your `.py` file, the `MMMAudio(128, etc)` 
    line has important information that must be correct for compilation 
    (notice this pattern in the examples):
    
    1) The `graph_name` corresponds to:  
       - The name of the `.mojo` file to search for the audio graph  
       - AND the name of the struct within that file serving as the main audio graph  
       
       In the example below, the file "MyMojoFile.mojo" contains struct `MyMojoFile`. 
       This struct must have a `.next` function with no input arguments that outputs 
       a `MFloat[N]` vector of any size (typically N=2) or just a Float64.

    2) The `package_name` corresponds to the folder containing your files:  
       - Files in `MMMAudio/mine` use `package_name="mine"`  
       - Files in `MMMAudio/user_files` use `package_name="user_files"`  
       - Your folder must be inside the MMMAudio directory and must contain the `__init__.mojo` file as explained above  


```python
mmm_audio = MMMAudio(128, graph_name="MyMojoFile", package_name="mine")
```

This is how all the examples look, so just look at those for "inspiration."