# PowerPause: pause a shell command when you are on battery

When you're compiling [Firefox](https://github.com/mozilla/gecko-dev) using `./mach build`, and you pick up your laptop to go do something, disconnecting the power cable, you look down 10 minutes later to find your battery is dead.

Instead:

```shell
PowerPause ./mach build
```

Now, when you disconnect power, the build process will get sent a Control-Z (SIGTSTP).  When you plug back in, the process will get continued (SIGCONT).

# Platform support

OSX only for now.  Will take patches for other OSes that include build files.

# Build on OSX

```shell
git clone https://github.com/hildjj/PowerPause.git
cd PowerPause
xcodebuild
./build/Release/PowerPause ls
```