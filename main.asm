bits 64
global _start

; System Call Numbers
SYS_WRITE     equ 1
SYS_MMAP      equ 9
SYS_MUNMAP    equ 11
SYS_NANOSLEEP equ 35
SYS_CLOCK_NANOSLEEP equ 230
SYS_EXIT      equ 60

STDOUT        equ 1

ASCII_ESCAPE equ 27

FULL_CELL equ 88
EMPTY_CELL equ 32

MAP_ANONYMOUS equ 0x10

WIDTH     equ 80
HEIGHT    equ 30
SIZE      equ 2400

section .text

_start:
  ; initialize the screen
  call clear_screen

  ; Allocate storage for our world
  mov rcx, SIZE
  call allocate_world
  mov qword[world], rax

  ; Initialize the world
  call initialize_world
  ; For now we just set one cell in the second row to full
  mov rax, world
  add rax, 84
  mov byte[rax], FULL_CELL

  ; Loop
  mov qword [iterations], 16
  .mainloop:

  ; Update the world

  ; Render
  call render_world

  ; Sleep
  call sleep
  
  ; decrease our loop iterator
  mov rcx, [iterations]
  dec rcx
  mov qword [iterations], rcx

  ; do another iteration if we aren't done yet
  cmp rcx, 0
  jnz .mainloop


  ; sys_exit
  call exit_ok

; Uses the ansi escape code for clearing the screen until the end
clear_screen:
  call cursor_to_start

  mov rax, SYS_WRITE
  mov rdi, STDOUT
  mov rsi, ansi_clear_screen
  mov rdx, ansi_clear_screen_len

  syscall

  ret

; draw the world to the screen
render_world:
  ; reset the cursor position
  call cursor_to_start

  ; we use r11 for our loop index
  push r12
  mov r12, 0

  .loopstart:

  ; Determine the offset into the world array
  mov rax, r12
  mov rcx, WIDTH
  mul rcx
  ; Add the world start position
  add rax, world
  ; move it into rsi
  mov rsi, rax 

  ; We always render full lines
  mov rax, SYS_WRITE
  mov rdi, STDOUT
  mov rdx, WIDTH
  syscall

  ; move the cursor to the next line
  mov rax, SYS_WRITE
  mov rdi, STDOUT
  mov rsi, string_newline_cr
  mov rdx, 2
  syscall

  ; increment our loop counter
  inc r12

  ; If haven't rendered everything jump back to start
  mov rax, HEIGHT 
  cmp r12, rax
  jne .loopstart

  ; we have to preserve r12
  pop r12

  ret


; Move the cursor to position 1 1
cursor_to_start:
  mov rax, SYS_WRITE
  mov rdi, STDOUT
  mov rsi, ansi_goto_start
  mov rdx, ansi_goto_start_len

  syscall

  ret
  

; Exit the program with a status code of 0
exit_ok:
  mov rax, SYS_EXIT
  mov rdi, 0
  syscall
  ret

; Sleeps for a second and returns
sleep:
  mov qword[sleep_time_seconds], 1
  mov qword[sleep_time_nanoseconds], 0

  mov rax, SYS_CLOCK_NANOSLEEP
  mov rdi, 1 ; ClOCK_MONOTONIC
  mov rsi, 0 ; no flags, relative time
  mov rdx, sleep_time_seconds
  mov r10, 0 ; no output arg

  syscall
  ret

; Allocate storage for a world of size $rax
allocate_world:
  ; Ask the kernel for storage
  mov rax, SYS_MMAP
  ; Let the kernel decide where to take the memory from
  mov rdi, 0
  ; Allocate SIZE bytes
  mov rsi, rcx
  ; Allocate readable and writeable memory
  mov rdx, 3
  ; we do not want file backed memory
  mov r10, MAP_ANONYMOUS
  ; fd
  mov r8, 0
  ; offset
  mov r9, 0
  syscall
  ret

initialize_world:
  ; we use r11 for our loop index
  mov r11, 0

  .loopstart:

  ; Determine the offset into the world array
  mov rcx, r11
  ; Add the world start position
  add rcx, world

  ; initilize the data to spaces
  mov byte[rcx], EMPTY_CELL

  ; increment our loop counter
  inc r11

  ; check if we are done
  cmp r11, SIZE
  jne .loopstart

  ret

section .data

ansi_clear_screen db ASCII_ESCAPE, '[J'
ansi_clear_screen_len equ $ - ansi_clear_screen

ansi_goto_start db ASCII_ESCAPE, '[H'
ansi_goto_start_len equ $ - ansi_goto_start

string_newline_cr db 0xa, 0xd


; This mirrors the layout of a timespec struct with two fields, one
; for seconds and one for nanoseconds.
; The two variables are declared right next to each other, which is
; the same layout as in the struct.
; This allows for easy and efficient allocation free nanosleep in a
; singlethreaded application
sleep_time_seconds dq 0
sleep_time_nanoseconds dq 0 

section .bss
; The iteration counter for the main loop
iterations resq 1

; A pointer to mapped memory for the world
world resq 1
