# Getting Started with MMMAudio on Windows and WSL 2.0

Mojo does not currently run natively on Windows machines and requires the use of Windows Subsystem for Linux (WSL2). You should also download Visual Studio Code for Windows. You will also need to install the WSL extension in  VSCode before starting.


In a windows terminal, install Ubuntu-26.04 using WSL2. Ubuntu-26.04 comes preinstalled with Python 3.14.4 and git.


If WSL2 is not currently installed windows may prompt you to download and install it, but should do this automatically.

```
wsl --install Ubuntu-26.04
```

Once Ubuntu is installed you will be prompted to create a username and password. Once you've set up your linux login info, change the directory to the home directory (~) and clone the github repo.

```
cd ~
git clone https://github.com/mmmaudio/mmmaudio.git
```

Then install pre-requisites (You will be prompted to give your linux password again.)

```
sudo apt update
sudo apt install libportaudio2 portaudio19-dev
sudo apt install libhidapi-hidraw0 libhidapi-dev
sudo apt install pulseaudio
sudo apt install g++
sudo apt install pkgconf
sudo apt-get install python3-tk python3-all-dev python3-venv
sudo apt install alsa-utils
sudo apt install libasound2-dev
```

Create a sound config file in the home directory called .asoundrc and then open it

```
touch .asoundrc
nano .asoundrc
```

Paste the following into the .asoundrc file

```


pcm.!default {
    type pulse
}
ctl.!default {
    type pulse
}
```

Save and exit nano by pressing ctrl+s and then ctrl+x.

You will also need to create a .Xauthority file in the same way. This file can be left blank.

```
touch .Xauthority
```

After all linux pre-requisites are installed you must restart WSL. Exit linux, shutdown WSL and then restart it. This can all be done in the same terminal.


```
exit
wsl --shutdown
wsl
```

Once WSL restarts, change directories to the MMMAudio folder and open it in Visual Studio Code. This will install VS Code Server for Linux (Which allows the Windows version of VSCode to utilize WSL)

```
cd ~/MMMAudio
code .
```

Once in VSCode, install both the Mojo and Python extensions. It is important to do this *after* opening VSCode from WSL as the extensions installed on the Windows VSCode install will not carry over. 

Then create a new python environment and install the required python packages with pip. You can also look in [MMMAudio-LinuxSetup](MMMAudio-LinuxSetup.md) to see how to install with uv (which has version tracking for all dependencies).

```
python3 -m venv venv 
source venv/bin/activate

pip install numpy scipy librosa pyautogui torch supriya-midi python-osc python-rtmidi matplotlib PySide6 mojo==1.0.0b1 hidapi pyaudio
```

