# Getting Started with MMMAudio on MacOS

Only the first three steps below are necessary to get started!!

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
or
```shell
pixi shell
```

This will install a .pixi hidden folder with the pixi virtual environment or update the environment if it is already there.

(You can change the version of python inside the pixi.toml file if you need to.)

## 3 Install Python and Mojo VSCode Extensions

Click on the Extensions icon on the left hand side of VS Code and install the Python and Mojo extensions.

# You are done setting up MMMAudio - below are some tips for troubleshooting

## A Running Python inside the pixi environment

Sometimes you will want to run the Python version with the MMMAudio settings from the command-line. You can do this by running:
```shell
`pixi run python ...`
```
for running just one command, or 
```shell
`pixi shell` 
```
 to drop into the pixi environment for a session.

Running MMMAudio from any other interpreter - a `uv`/`venv` environment, or the system python - will fail.

## B VS Code settings

The repo includes a `.vscode/settings.json` with the settings MMMAudio needs, so you should not have to change any VS Code settings.

If you made your own `.vscode/settings.json` before it was included in the repo, `git pull` will stop with "untracked working tree files would be overwritten". Delete or move your copy and pull again.

## C Checking Your Python Interpreter

The included `.vscode/settings.json` selects the pixi Python automatically, so normally there is nothing to do here. Open a Python file and check that the interpreter shown in the bottom right of the status bar is:

`./.pixi/envs/default/bin/python`

If it shows something else (for example, because you picked a different interpreter for this folder before the settings were included), go to View->Command Palette->Select Python Interpreter and choose the pixi Python above.

Don't select the Global python on your system, or a `.venv`/`venv` you made
yourself. Those won't work.

If the pixi Python isn't listed, quit and restart VS Code and try to Select Python Interpreter again.

## D VSCode issues - Microsoft giveth, Microsoft taketh away

VSCode is amazing, but most of the issues users encounter are caused by VSCode's Python inconsistencies.

- **a)** See B above on the included VS Code settings for Python.
- **b)** If code sent with shift-return fails with `IndentationError: unexpected indent` or arrives garbled, the cause is the new interactive prompt in Python 3.13+, which auto-indents after lines ending in `:` and adds indentation on top of the code VS Code sends. The included settings fix this by setting `PYTHON_BASIC_REPL=1`, which switches back to the classic prompt. Close any open terminals after pulling so new ones pick up the setting. If you run Python in a terminal outside VS Code, run `export PYTHON_BASIC_REPL=1` first.
