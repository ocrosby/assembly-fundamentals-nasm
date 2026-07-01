# Installation

Get NASM and a linker working on your machine.

## macOS

```bash
xcode-select --install        # provides ld, otool, dsymutil
brew install nasm             # NASM itself
```

`lldb` ships with the Xcode Command Line Tools.

## Linux

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y nasm binutils gdb

# Fedora / RHEL
sudo dnf install -y nasm binutils gdb

# Arch
sudo pacman -S nasm binutils gdb
```

## Windows

Use [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) and follow the Linux steps inside your distribution. Native Windows is possible with NASM + `golink`, but is not covered here.

## Verify

```bash
nasm -v
# NASM version 2.16.01 ...

ld -v           # macOS
ld --version    # Linux
```

Any NASM `>= 2.15` is fine for everything in these docs.

## Next

- [Hello World](02-hello-world.md)
