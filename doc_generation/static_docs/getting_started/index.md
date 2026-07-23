# Getting Started with MMMAudio

MMMAudio uses [Mojo's Python interop](https://docs.modular.com/mojo/manual/python/) to compile audio graphs directly in your Python programming environment.

Currently Mojo's compiler is MacOS(Apple Silicon) & Linux(x86 and arm - builds downstream of Ubuntu 22 LTS) only. It works great on Raspberry Pi when the Pi uses Ubuntu. Windows users can use WSL2 as described below though it is currently a bit rough. 

Join the [Discourse](https://mmmaudio.discourse.group/) Community!


## 1. Setup the Environment in your Operating System:

[MMMAudio-MacSetup](MMMAudio-MacSetup.md)

[MMMAudio-LinuxSetup](MMMAudio-LinuxSetup.md)

[MMMAudio-WindowsSetup](MMMAudio-WindowsSetup.md)

## 2. Running Code

### 2 Running a Script

Some examples in the examples folder are designed to run as a complete script. These are all marked. In these cases, the script can be run by pressing the "play" button on the top right of VSCode or just running the script `python example.py` from inside your virtual environment.

### 3 REPL Mode

The more common way to run MMMAudio is in REPL mode in your editor. 

Before you run the code in a new REPL, make sure to close all terminal instances in the current workspace. This will ensure that a fresh REPL environment is created.

Most examples run by selecting code in the file and pressing shift-return to execute the code. If your interpeter is not opened in the terminal, it should open a new one, load the virtual environment, and run the code. 

VS Code has issues with lots of text sometimes. If your code gets garbled as it is sent to the terminal, it is a VS Code problem. You will need to break the code up into smaller chunks.

Go to the [Examples](../examples/index.md) page to run an example!

## 4. Making Your Own Programs

### 1 Make a directory in the MMMAudio folder
This is to house your own projects. Any directory that is not part of the MMMAudio repo can be used to store user files. (and will be ignored by git if you update the repo, so no worries about it being overwritten or you uploading your files to the repo)

### 2 Add an empty file to that direcotry called `__init__.mojo`

The folder that has your code in it needs to be considered a "module" by the Mojo compiler. The empty `__init__.mojo` file tells the Mojo compiler that your folder is a module.

(For reference, look at the `examples` directory. It has an empty `__init__.mojo` file in it, as will all folders that have mojo code in them.)


!!! Note

    When running a MMMAudio program in your `.py` file, the `MMMAudio(128, etc)` 
    line has important information that must be correct for compilation 
    (notice this pattern in the examples):
    
    1) The `graph_name` corresponds to:  
       - The name of the `.mojo` file to search for the audio graph  
       - AND the name of the struct within that file serving as the main audio graph  
       
       In the example below, the file "MyMojoFile.mojo" contains struct `MyMojoFile`. 
       This struct must have a `.next` function with no input arguments that outputs 
       a `MFloat[num_chans]` vector of any size (typically num_chans=2) or just a Float64.

    2) The `package_name` corresponds to the folder containing your files:  
       - Files in `MMMAudio/mine` use `package_name="mine"`  
       - Files in `MMMAudio/user_files` use `package_name="user_files"`  
       - Your folder must be inside the MMMAudio directory and must contain the `__init__.mojo` file as explained above  


```python
mmm_audio = MMMAudio(128, graph_name="MyMojoFile", package_name="mine")
```

This is how all the examples look, so just look at those for "inspiration."