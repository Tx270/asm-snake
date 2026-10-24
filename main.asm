bits 64


section .data
	len               equ     1250
	board_width:      equ     50
	board_height:     equ     25
	background_tile:  db      "."
	head_tile:        db      "@"
	tail_tile:        db      "#"
	apple_tile:       db      "$"
	new_line:         db      10
	sleep_time: 	  dq      0 
					  dq      250000000
	clear_screen_ansi db      27, "[2J", 27, "[H"
	.len              equ     $ - clear_screen_ansi
	hide_cursor_ansi  db 		27, "[?25l"
	.len        	  equ		$ - hide_cursor_ansi
	show_cursor_ansi  db 		27, "[?25h"
	.len        	  equ		$ - show_cursor_ansi
	direction_up	  equ     0
	direction_down	  equ     1
	direction_left	  equ     2
	direction_right	  equ     3


section .bss
	queue             resw    len
	queue_head        resw    1
	queue_count       resw    1
	saved_termios     resb    44
	termios    		  resb	  44
	was_termios_saved resb	  1
	key_buffer    	  resb    1
	direction		  resb	  1
	signal_action	  resb	  32


section .text
    global _start


_start:
	mov word [rel queue], 160
	mov word [rel queue + 2], 210
	mov word [rel queue + 4], 260
	mov word [rel queue + 6], 310

	mov word [rel queue_head], 0
	mov word [rel queue_count], 4

	mov byte [rel direction], 3

	call setup_term
	call setup_signals

.loop:
    call display
    
	; wait
	mov     eax, 35
	lea     rdi, [rel sleep_time]
	xor     esi, esi
	syscall

	call read_char
	movzx rdi, al
	call set_direction
	call move

	jmp .loop


; isEmpty
; Purpose: Check whether the queue is empty.
; Arguments: None.
; Returns: RAX = 1 if empty, 0 otherwise.
; Clobbers: RAX, RFLAGS.
isEmpty:
	cmp     word [rel queue_count], 0
	sete    al
	movzx   eax, al
	ret


; isFull
; Purpose: Check whether the queue is full.
; Arguments: None.
; Returns: RAX = 1 if full, 0 otherwise.
; Clobbers: RAX, RFLAGS.
isFull:
	cmp     word [rel queue_count], len
	sete    al
	movzx   eax, al
	ret


; get
; Purpose: Retrieve an element by queue index.
; Arguments: RDI = element index.
; Returns: RAX = element value.
; Clobbers: RAX, RCX.
get:
	lea     rcx, [rel queue]
	movzx   eax, word [rcx + rdi*2]
	ret


; first
; Purpose: Retrieve the first queue element.
; Arguments: None.
; Returns: RAX = element value, or -1 if empty.
; Clobbers: RAX, RDI, RCX, RFLAGS.
first:
	call    isEmpty
	test    rax, rax
	jnz     .empty

	movzx   rdi, word [rel queue_head]
	call    get
	ret

.empty:
	mov     rax, -1
	ret


; last
; Purpose: Retrieve the last queue element.
; Arguments: None.
; Returns: RAX = element value, or -1 if empty.
; Clobbers: RAX, RCX, RDX, RDI, RFLAGS.
last:
	call    isEmpty
	test    rax, rax
	jnz     .empty

	movzx   rax, word [rel queue_head]
	movzx   rcx, word [rel queue_count]
	add     rax, rcx
	dec     rax

	xor     edx, edx
	mov     ecx, len
	div     ecx

	movzx   rdi, edx
	call    get
	ret

.empty:
	mov     rax, -1
	ret


; enqueue
; Purpose: Insert an element at the front of the queue.
; Arguments: DI = 16-bit element value.
; Returns: RAX = 0 on success, -1 if full.
; Clobbers: RAX, RCX, RSI, RFLAGS.
enqueue:
	push    rdi
	call    isFull
	pop     rdi
	test    rax, rax
	jnz     .full

	cmp     word [rel queue_head], 0
	jne     .decrement

	mov     word [rel queue_head], len
	jmp     .decrement

.decrement:
	dec     word [rel queue_head]

	movzx   ecx, word [rel queue_head]
	lea     rsi, [rel queue]
	mov     [rsi + rcx*2], di

	inc     word [rel queue_count]
	xor     eax, eax
	ret

.full:
	mov     eax, -1
	ret


; dequeue
; Purpose: Remove and return the last queue element.
; Arguments: None.
; Returns: RAX = removed element value, or -1 if empty.
; Clobbers: RAX, RCX, RDX, RDI, RFLAGS.
dequeue:
	call    isEmpty
	test    rax, rax
	jnz     .empty

	call    last
	dec     word [rel queue_count]
	ret

.empty:
	mov     rax, -1
	ret


; isPresent
; Purpose: Check whether a value is present in the circular queue.
; Arguments: RDI = value to search.
; Returns: RAX = 1 if present, 0 otherwise.
; Clobbers: RAX, RCX, RDX, RDI, RSI, R8, RFLAGS.
isPresent:
    mov rsi, rdi                    ; Preserve searched value
    movzx r8d, word [rel queue_count]     ; Number of elements
    movzx edx, word [rel queue_head]      ; First queue index

    test r8d, r8d
    jz .not_present

.loop:
    mov edi, edx
    call get
    cmp rax, rsi
    je .present

    inc edx
    cmp edx, len
    jb .no_wrap
    xor edx, edx

.no_wrap:
    dec r8d
    jnz .loop

.not_present:
    xor eax, eax
    ret

.present:
    mov eax, 1
    ret


; display
; Purpose: Display the game board using a linear index.
; Arguments: None.
; Returns: None.
; Clobbers: RAX, RCX, RDX, RSI, RDI, R12.
display:
	call clear_screen
	push r12
	xor r12d, r12d

.loop:
    mov edi, r12d
    call isPresent
    lea rsi, [rel background_tile]

    test rax, rax ; not preasent in queue means background
    jz .print_tile

	call first
	cmp eax, r12d
	je .is_head

.is_tail:
    lea rsi, [rel tail_tile]
	jmp .print_tile

.is_head:
    lea rsi, [rel head_tile]

.print_tile:
    call print

    inc r12d
	; Stop after the last board cell.
	cmp r12d, board_width * board_height
	jae .done

    ; check if next index starts new row 
    mov eax, board_width * board_height
    sub eax, r12d
    xor edx, edx
    mov ecx, board_width
    div ecx

    test edx, edx
    jnz .next_row

    lea rsi, [rel new_line]
    call print

.next_row:
    jmp .loop

.done:
	pop r12
    ret


; print
; Purpose: Write one byte to standard output.
; Arguments: RSI = address of the byte to print.
; Returns: RAX = number of bytes written, or a negative error code.
; Clobbers: RAX, RDI, RDX, RFLAGS.
print:
	mov     rax, 1
	mov     rdi, 1
	mov     rdx, 1
	syscall
	ret


; clear_screen
; Purpose: Clear the terminal.
; Arguments: None
; Returns: RAX = number of bytes written, or a negative error code.
; Clobbers: RAX, RDI, RDX, RFLAGS.
clear_screen:
    mov eax, 1
    mov edi, 1
    lea rsi, [rel clear_screen_ansi]
    mov edx, clear_screen_ansi.len
    syscall
    ret


; hide_cursor
; Purpose: Hides terminal coursor.
; Arguments: None
; Returns: RAX = number of bytes written, or a negative error code.
; Clobbers: RAX, RDI, RDX, RFLAGS.
hide_cursor:
    mov eax, 1
    mov edi, 1
    lea rsi, [rel hide_cursor_ansi]
    mov edx, hide_cursor_ansi.len
    syscall
    ret


; show_cursor
; Purpose: Shows terminal coursor.
; Arguments: None
; Returns: RAX = number of bytes written, or a negative error code.
; Clobbers: RAX, RDI, RDX, RFLAGS.
show_cursor:
    mov eax, 1
    mov edi, 1
    lea rsi, [rel show_cursor_ansi]
    mov edx, show_cursor_ansi.len
    syscall
    ret


; set_direction
; Purpose: Updates direction unless it would reverse the snake.
; Arguments: RDI = requested direction [0 | 1 | 2 | 3]
; Returns: None
; Clobbers: RAX, RDI, RFLAGS
set_direction:
    mov al, [rel direction]

    cmp dil, direction_up
    jne .check_down
    cmp al, direction_down
    je .done
    jmp .update

.check_down:
    cmp dil, direction_down
    jne .check_left
    cmp al, direction_up
    je .done
    jmp .update

.check_left:
    cmp dil, direction_left
    jne .check_right
    cmp al, direction_right
    je .done
    jmp .update

.check_right:
    cmp dil, direction_right
    jne .done
    cmp al, direction_left
    je .done

.update:
    mov [rel direction], dil

.done:
    ret


; move
; Purpose: Moves the snake, checking board boundaries and self-collision.
; Arguments: None
; Returns: None
; Clobbers: RAX, RCX, RDX, RDI, RSI, RFLAGS
move:
    push r12
    push r13
    sub rsp, 8

    call first
    test rax, rax
    js .quit

    mov r12, rax                 ; R12 = current head position

    cmp byte [rel direction], direction_up
    je .up
    cmp byte [rel direction], direction_down
    je .down
    cmp byte [rel direction], direction_left
    je .left
    cmp byte [rel direction], direction_right
    je .right
    jmp .return

.up:
    cmp r12, board_width
    jb .quit
    mov r13, r12
    sub r13, board_width
    jmp .check_collision

.down:
    cmp r12, board_width * (board_height - 1)
    jae .quit
    mov r13, r12
    add r13, board_width
    jmp .check_collision

.left:
    mov rax, r12
    xor edx, edx
    mov ecx, board_width
    div ecx
    test edx, edx
    jz .quit

    mov r13, r12
    dec r13
    jmp .check_collision

.right:
    mov rax, r12
    xor edx, edx
    mov ecx, board_width
    div ecx
    cmp edx, board_width - 1
    je .quit

    mov r13, r12
    inc r13

.check_collision:
    ; allow moving into current tail position
    call last
    cmp rax, r13
    je .move_snake

    ; check if next position is occupied
    mov rdi, r13
    call isPresent
    test rax, rax
    jnz .quit

.move_snake:
    mov rdi, r13
    call enqueue
    test rax, rax
    jnz .quit

    call dequeue
    jmp .return

.quit:
    add rsp, 8
    pop r13
    pop r12
    jmp quit

.return:
    add rsp, 8
    pop r13
    pop r12
    ret


; setup_term
; Purpose: Saves and changes terminal settings through ioctl.
; Arguments: None
; Returns: None
; Clobbers: RAX, RDI, RDX, RCX, RSI, RFLAGS.
setup_term:
	call hide_cursor

    ; ioctl(0, TCGETS, &saved)
	mov     eax, 16
	xor     edi, edi
	mov     esi, 0x5401
	lea     rdx, [rel saved_termios]
	syscall

	; if returned < 0, an error occurred
	test    rax, rax
	js      quit

	mov byte [rel was_termios_saved], 1

    ; copy old settings
	lea     rsi, [rel saved_termios]
	lea     rdi, [rel termios]
	mov     ecx, 44
	cld
	rep     movsb

    ; turn off ICANON and echo
	and     dword [rel termios + 12], 0xFFFFFFF5

	mov     byte [rel termios + 23], 0				; VMIN = 0
	mov     byte [rel termios + 22], 0				; VTIME = 0

    ; ioctl(0, TCSETS, &term)
	mov     eax, 16
	xor     edi, edi
	mov     esi, 0x5402
	lea     rdx, [rel termios]
	syscall

	; if returned < 0, an error occurred
	test    rax, rax
	js      quit

	ret


; read_char
; Purpose: Reads last character from stdin.
; Arguments: None
; Returns: RAX = direction [0 | 1 | 2 | 3]
; Clobbers: RAX, RDI, RDX, RSI, RFLAGS.
read_char:
	mov     byte [rel key_buffer], 0

.drain:
	xor     eax, eax
	xor     edi, edi
	lea     rsi, [rel key_buffer]
	mov     edx, 1
	syscall

	test    rax, rax
	jle     .process

    ; another character may be available
	jmp     .drain

.process:
 	mov al, [rel direction]

	cmp     byte [rel key_buffer], 0
	je		.done

	cmp     byte [rel key_buffer], 0x1B
	je      quit
	cmp     byte [rel key_buffer], 0x7F
	je      quit
	cmp     byte [rel key_buffer], 0x71
	je      quit
	cmp     byte [rel key_buffer], 0x51
	je      quit

	cmp     byte [rel key_buffer], 0x77
	je      .up

	cmp     byte [rel key_buffer], 0x73
	je      .down

	cmp     byte [rel key_buffer], 0x61
	je      .left

	cmp     byte [rel key_buffer], 0x64
	je      .right

	jmp .done

.up:
	mov byte al, direction_up
	jmp .done

.down:
	mov byte al, direction_down
	jmp .done

.left:
	mov byte al, direction_left
	jmp .done

.right:
	mov byte al, direction_right
	jmp .done

.done:
	ret


; quit
; Purpose: Restores terminal settings and exits.
; Arguments: None
; Returns: None, exits program
; Clobbers: RAX, RDI, RDX, RFLAGS.
quit:
	call show_cursor
	call clear_screen

	cmp byte [rel was_termios_saved], 1
    jne .exit

	mov     eax, 16
	xor     edi, edi
	mov     esi, 0x5402
	lea     rdx, [rel saved_termios]
	syscall

.exit:
	mov     rax, 60
	mov     rdi, 0
	syscall


; setup_signals
; Purpose: Registers SIGINT, SIGTERM and SIGHUP signals.
; Arguments: None
; Returns: None
; Clobbers: RAX, RDI, RSI, RDX, R10, RFLAGS.
setup_signals:
    ; struct kernel_sigaction:
    ; handler  offset 0
    ; flags    offset 8
    ; restorer offset 16
    ; mask     offset 24

    mov qword [rel signal_action + 0], quit
    mov qword [rel signal_action + 8], 0x04000000 ; SA_RESTORER
    mov qword [rel signal_action + 16], signal_restorer
    mov qword [rel signal_action + 24], 0

    ; SIGINT = 2
    mov eax, 13
    mov edi, 2
    lea rsi, [rel signal_action]
    xor edx, edx
    mov r10d, 8
    syscall

    ; SIGTERM = 15
    mov eax, 13
    mov edi, 15
    lea rsi, [rel signal_action]
    xor edx, edx
    mov r10d, 8
    syscall

    ; SIGHUP = 1
    mov eax, 13
    mov edi, 1
    lea rsi, [rel signal_action]
    xor edx, edx
    mov r10d, 8
    syscall

    ret


; signal_restorer
; Purpose: Restores signals.
; Arguments: None
; Returns: None
; Clobbers: RAX, RCX, RFLAGS.
signal_restorer:
    mov eax, 15          ; rt_sigreturn
    syscall