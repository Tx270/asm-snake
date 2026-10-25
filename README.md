# Snake

A simple Snake CLI game written in x86-64 assembly (NASM) for Linux.

## Controls

- `WSAD` - movment
- `q` or `Esc` - quit

## Building

You need NASM and a linker.

```bash
nasm -f elf64 main.asm -o main.o
ld main.o -o snake
./snake
```

You can change the board size and displayed symbols in `main.asm`.
