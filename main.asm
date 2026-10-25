bits 64


section .data
	board_width:        equ     30
	board_height:       equ     15
	background_tile:    db      " "
	head_tile:          db      "@"
	tail_tile:          db      "#"
	apple_tile:         db      "$"
	border_tile:        db      "|"
	border_top_tile:    db      "="
	display_buffer_len  equ	  	8192

	queue_len         	equ     board_width * board_height
	new_line:         	db      10
	sleep_time: 	  	dq      0 
					  	dq      250000000
	clear_screen_ansi 	db      27, "[2J", 27, "[H"
	.len              	equ     $ - clear_screen_ansi
	hide_cursor_ansi  	db 	  	27, "[?25l"
	.len        	  	equ	  	$ - hide_cursor_ansi
	show_cursor_ansi  	db   	  27, "[?25h"
	.len        	  	equ	  	$ - show_cursor_ansi
	direction_up	  	equ     0
	direction_down	  	equ     1
	direction_left	  	equ     2
	direction_right	  	equ     3


section .bss
	queue             resw    queue_len
	queue_head        resw    1
	queue_count       resw    1
	saved_termios     resb    44
	termios    		  resb	  44
	was_termios_saved resb	  1
	key_buffer    	  resb    1
	direction		  resb	  1
	signal_action	  resb	  32
	apple 			  resw	  1
	winsize 		  resb 	  8
	display_buffer	  resb	  display_buffer_len
    esc_state         resb    1


%macro APPEND_CHAR 1
    mov byte [r15], %1
    inc r15
%endmacro

%macro APPEND_MEM_CHAR 1
    mov al, [rel %1]
    mov byte [r15], al
    inc r15
%endmacro

%macro APPEND_REPEAT 2
    mov al, %1
    mov rdi, r15
    mov rcx, %2
    rep stosb
    mov r15, rdi
%endmacro

%macro APPEND_REPEAT_MEM 2
    mov al, [rel %1]
    mov rdi, r15
    mov rcx, %2
    rep stosb
    mov r15, rdi
%endmacro


section .text
    global _start

_start:
init:
	mov word [rel queue], 160
	mov word [rel queue + 2], -1
	mov word [rel queue + 4], -1
	mov word [rel queue + 6], -1

	mov word [rel queue_head], 0
	mov word [rel queue_count], 4

	mov byte [rel direction], 0

	call setup_term
	call setup_signals
	call place_apple

main_loop:
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

	jmp main_loop


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
	cmp     word [rel queue_count], queue_len
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
	mov     ecx, queue_len
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

	mov     word [rel queue_head], queue_len
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
    mov rsi, rdi                          ; Preserve searched value
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
    cmp edx, queue_len
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
; Purpose: Display the game board, padding and borders.
; Arguments: None.
; Returns: None.
; Clobbers: RAX, RCX, RDX, RSI, RDI, R12.
display:
    ; R14 = start of buffor
    ; R15 = save pointer to be incremented
    lea r14, [rel display_buffer]
    mov r15, r14

    cld

	call clear_screen

    call get_board_padding
    test rax, rax
    js .error

.pad_top:
    test rbx, rbx
    jz .top_border

    APPEND_CHAR 10
    dec rbx
    jmp .pad_top

.top_border:
    APPEND_REPEAT ' ', r13
    APPEND_REPEAT_MEM border_top_tile, board_width + 2
    APPEND_CHAR 10

    APPEND_REPEAT ' ', r13

    APPEND_MEM_CHAR border_tile

    xor r12d, r12d

.cell_loop:
    ; apple?
    cmp word [rel apple], r12w
    je .is_apple

    ; snake?
    mov edi, r12d
    call isPresent
    test rax, rax
    jz .is_background

    ; head?
    call first
    cmp eax, r12d
    je .is_head

.is_tail:
    APPEND_MEM_CHAR tail_tile
    jmp .next_cell

.is_head:
    APPEND_MEM_CHAR head_tile
    jmp .next_cell

.is_apple:
    APPEND_MEM_CHAR apple_tile
    jmp .next_cell

.is_background:
    APPEND_MEM_CHAR background_tile

.next_cell:
    inc r12d

    ; end of board?
    cmp r12d, board_width * board_height
    jae .bottom_border

    ; end of row?
    mov eax, r12d
    xor edx, edx
    mov ecx, board_width
    div ecx
    test edx, edx
    jnz .cell_loop

    APPEND_MEM_CHAR border_tile
    APPEND_CHAR 10

    APPEND_REPEAT ' ', r13
    APPEND_MEM_CHAR border_tile

    jmp .cell_loop

.bottom_border:
    APPEND_MEM_CHAR border_tile
    APPEND_CHAR 10

    APPEND_REPEAT ' ', r13
    APPEND_REPEAT_MEM border_top_tile, board_width + 2
    APPEND_CHAR 10

	; num of bytes = end pointer - beggining
    mov rdx, r15
    sub rdx, r14

    mov eax, 1
    mov edi, 1
    mov rsi, r14
    syscall

    jmp .done

.error:
	jmp quit

.done:
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
	
	; check apple
	cmp r13w, word [rel apple]
	jne .not_apple
	call place_apple
	jmp .return
 
.not_apple:
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


; place_apple
; Purpose: Randomizes the apple.
; Arguments: None
; Returns: None
; Clobbers: RAX, RDI, RDX, RCX, RSI, R8, RFLAGS.
place_apple:
    push r12

.retry:
    rdrand rax
    jnc .retry

    xor edx, edx
    mov ecx, board_width * board_height
    div rcx

    mov r12, rdx
    mov rdi, r12
    call isPresent

    test rax, rax
    jnz .retry

    mov [rel apple], r12
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
; Clobbers: RAX, RBX, RDI, RDX, RSI, RFLAGS.
read_char:
    push rbx

    mov byte [rel key_buffer], 0

.read_loop:
    xor eax, eax
    xor edi, edi
    lea rsi, [rel key_buffer]
    mov edx, 1
    syscall

    test rax, rax
    jle .done

    mov al, [rel key_buffer]
    mov bl, [rel esc_state]

    test bl, bl
    jnz .escape_sequence

    cmp al, 27
    je .start_escape

.process_char:
    cmp al, 'q'
    je .quit
    cmp al, 'Q'
    je .quit

    cmp al, 'w'
    je .up
    cmp al, 's'
    je .down
    cmp al, 'a'
    je .left
    cmp al, 'd'
    je .right

    jmp .read_loop

.start_escape:
    mov byte [rel esc_state], 1
    jmp .read_loop

.escape_sequence:
    cmp bl, 1
    jne .arrow_key

    cmp al, '['
    jne .reset_escape

    mov byte [rel esc_state], 2
    jmp .read_loop

.reset_escape:
    mov byte [rel esc_state], 0
    jmp .process_char

.arrow_key:
    mov byte [rel esc_state], 0

    cmp al, 'A'
    je .up
    cmp al, 'B'
    je .down
    cmp al, 'D'
    je .left
    cmp al, 'C'
    je .right

    jmp .read_loop

.up:
    mov al, direction_up
    jmp .return

.down:
    mov al, direction_down
    jmp .return

.left:
    mov al, direction_left
    jmp .return

.right:
    mov al, direction_right
    jmp .return

.done:
    mov al, [rel direction]

.return:
    pop rbx
    ret

.quit:
    pop rbx
    jmp quit


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


; get_board_padding
; Purpose: Gets terminal dimensions and calculates needed padding
; Arguments: None
; Returns: R13 = columns, RBX = rows, RAX = 0, negative error code on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R13, RBX
get_board_padding:
    mov eax, 16             ; SYS_ioctl
    mov edi, 1              ; stdout
    mov esi, 0x5413         ; TIOCGWINSZ
    lea rdx, [rel winsize]
    syscall

    test rax, rax
    js .error

    movzx eax, word [rel winsize + 2]
	xor edx, edx
	mov ecx, 2
	div rcx
	mov r13, rax

	mov eax, board_width
	xor edx, edx
	mov ecx, 2
	div rcx

	sub r13, rax

    movzx eax, word [rel winsize]
	xor edx, edx
	mov ecx, 2
	div rcx
	mov rbx, rax

	mov eax, board_height
	xor edx, edx
	mov ecx, 2
	div rcx

	sub rbx, rax

    xor eax, eax
    ret

.error:
    ret