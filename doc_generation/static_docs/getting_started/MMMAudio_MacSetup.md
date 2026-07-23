# Getting Started with MMMAudio on MacOS

## 1. Clone the Repository

```
git clone https://github.com/mmmaudio/mmmaudio.git
```

or [grab the latest release](https://github.com/mmmaudio/mmmaudio/releases).

## 2a. Installing portaudio and hidapi on MacOS (Apple Silicon Only - Mojo Does not and will not work on Intel Macs)

Use your package manager to install `portaudio` and `hidapi` as system-wide c libraries. 

```shell
brew install portaudio
brew install hidapi
```

## 2b.1. Option 1 - Setup with pixi

### 1 Install pixi with homebrew or curl.

See [pixi's installation instructions](https://pixi.prefix.dev/latest/installation/).

### 2 Install the dependencies

In the MMMAudio directory, type:

```shell
pixi install
```

This will install a .pixi hidden folder with the pixi virtual environment.

(You can change the version of python inside the pixi.toml file if you need to.)

## 2b.2. Option 2 - Setup using uv

### 1 Install uv:

See [Install uv](https://docs.astral.sh/uv/getting-started/installation/)

### 2 Install the uv virtual environment and MMMAudio dependencies:

In the MMMAudio directory, type:

```
uv venv --python 3.14
uv sync
uv add mojo --prerelease allow
```

This 1) creates the virtual environment, 2) sync the dependencies, 3) installs the correct pre-release version of Mojo.

## 2b.3. Option 3 - Setup the Python Virtual Environment

### 1 Set up the environment and install the dependencies:

From the MMMAudio directory:
(I recommend explicitly specifying the Python version here, eg: 'python3.14 -m venv venv')
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

## 4 Select Your Python Interpreter

go to View->Command Palette->Select Python Interpreter. You need to select the version of Python that was installed by pixi or uv or python virtual environments.

This will be at:

`./.pixi/envs/default/python` (for pixi)

`./.venv/bin/python` (for uv)

`./venv/bin/python` (for python virtual environments)

Don't select the Global python on your system. That won't work.

If the venv you just installed isn't available, quit and restart VS Code and try to Select Python Interpreter again.

## 5 Install Python and Mojo VSCode Extensions

Click on the Extensions icon on the left hand side of VS Code and install the Python and Mojo extensions.

## 6 VSCode issues - Microsoft giveth, Microsoft taketh away

VSCode is amazing, but most of the issues users encounter are caused by VSCode's Python inconsistancies. 
#### a) See 2.3 above on proper vscode settings for Python. 
#### b) We have found that setting Settings -> Auto Activation Type to `shellStartup` works better than the default `command` setting.
#### c) This one will drive me to drink: Some versions of VSCode on SOME machines will send garbled Python code to the terminal if a code chunk is too long. I guess you just need to chunk your code up into smaller defs or put big defs into other files and import them?