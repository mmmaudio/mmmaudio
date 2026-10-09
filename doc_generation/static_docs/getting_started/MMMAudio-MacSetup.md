# Getting Started with MMMAudio on MacOS

## 1. Clone the Repository

```
git clone https://github.com/mmmaudio/mmmaudio.git
```

or [grab the latest release](https://github.com/mmmaudio/mmmaudio/releases).

## 2. Set up the environment with pixi

*(Apple Silicon only - Mojo does not and will not work on Intel Macs.)*

MMMAudio uses [pixi](https://pixi.prefix.dev/latest/installation/) for its
environment. pixi installs everything MMMAudio needs, including the needed C libraries.

### 1 Install pixi with homebrew or curl.

See [pixi's installation instructions](https://pixi.prefix.dev/latest/installation/).

### 2 Install the dependencies

In the root MMMAudio directory, type:

```shell
pixi install
```

This will install a .pixi hidden folder with the pixi virtual environment.

(You can change the version of python inside the pixi.toml file if you need to.)

### 3 Run everything inside that environment

Use `pixi run python ...` for one command, or `pixi shell` to drop into the
environment for a session. Running MMMAudio from any other interpreter - a
`uv`/`venv` environment, or the system python - will fail with:

```
Exception: could not find libportaudio. ...
```

because those environments do not contain the PortAudio library.

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

*(This requires you to have the [Python Extension](https://github.com/microsoft/vscode-python#quick-start) installed in your VSCode.)*

go to View->Command Palette->Select Python Interpreter. You need to select the version of Python that pixi installed.

This will be at:

`./.pixi/envs/default/bin/python`

Don't select the Global python on your system, or a `.venv`/`venv` you made
yourself. Those won't work - see step 2.3 above.

If the venv you just installed isn't available, quit and restart VS Code and try to Select Python Interpreter again.

## 5 Install Python and Mojo VSCode Extensions

Click on the Extensions icon on the left hand side of VS Code and install the Python and Mojo extensions.

## 6 VSCode issues - Microsoft giveth, Microsoft taketh away

VSCode is amazing, but most of the issues users encounter are caused by VSCode's Python inconsistancies. 
#### a) See 2.3 above on proper vscode settings for Python. 
#### b) We have found that setting Settings -> Auto Activation Type to `shellStartup` works better than the default `command` setting.
#### c) This one will drive me to drink: Some versions of VSCode on SOME machines will send garbled Python code to the terminal if a code chunk is too long. I guess you just need to chunk your code up into smaller defs or put big defs into other files and import them?