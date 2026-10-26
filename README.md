# asm-snake

A simple Snake CLI game written in x86-64 assembly (NASM) for Linux.

<img width="790" height="548" alt="image" src="https://github.com/user-attachments/assets/737d441e-c79f-42c3-afd1-cebc9ffffa5e" />

## Controls

- `WSAD` or arrows - movment
- `q` - quit

## Building

You need a Linux system with `NASM` and `GNU binutils`. Clone this repo and run:
```bash
nasm -f elf64 main.asm -o main.o
ld main.o -o snake
./snake
```

You can change the board size and displayed symbols in `main.asm`.
