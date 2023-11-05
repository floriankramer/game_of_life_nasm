bits 64
global _start

; System Call Numbers
SYS_WRITE           equ 1
SYS_MMAP            equ 9
SYS_MUNMAP          equ 11
SYS_NANOSLEEP       equ 35
SYS_EXIT            equ 60
SYS_MMAP2           equ 192
SYS_CLOCK_NANOSLEEP equ 230
SYS_CLOCK_GET_TIME  equ 228

STDOUT        equ 1

; CLOCK_TYPES from time.h
CLOCK_REALTIME  equ 0
CLOCK_MONOTONIC equ 1

ASCII_ESCAPE equ 27

FULL_CELL equ 88
EMPTY_CELL equ 32

; TODO: This might be the wrong flag, and definitely also needs a MAP_PRIVATE
MAP_ANONYMOUS equ 0x20
MAP_PRIVATE   equ 0x02
PROT_READ     equ 1
PROT_WRITE    equ 2

WIDTH     equ 80
HEIGHT    equ 30
SIZE      equ 2400

section .text

_start:
  ; initialize the screen
  call clear_screen

  ; Allocate storage for our world
  mov rcx, qword SIZE
  call malloc
  mov qword[world], rax

  ; Allocate storage for the update process
  mov rcx, qword SIZE
  call malloc
  mov qword[world_after_update], rax

  ; Initialize the world
  call initialize_world

  ; render the initial state
  call render_world
  call sleep

  ; Loop
  mov qword [iterations], 16
  .mainloop:

  ; Update the world
  call update_world

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

update_world:
  push r12
  push rbx

  ; r12 is our loop iterator
  mov r12, 0

  .loopstart:
  ; We need to look at all neighbours of this cell, and add them up.
  ; We can then use that number to calculate the new state of the cell.
  ; 0-1 empty
  ;   2 survives
  ;   3 alive
  ; >=4 dead

  ; split the one-dimensional index into a two dimensional one
  ; x
  mov rax, r12
  mov rcx, WIDTH
  call modulo
  mov r10, rax
 
  ; y
  mov rax, r12
  mov rcx, WIDTH
  mov rdx, 0
  div rcx
  mov r11, rax
   
  ; We use rbx to accumulate the number of living neighbours
  mov rbx, 0

  ; top left
  mov r14, r10
  sub r14, qword 1
  mov r15, r11
  sub r15, qword 1
  call lookup_cell
  add rbx, rax

  ; top center
  mov r14, r10
  mov r15, r11
  sub r15, qword 1
  call lookup_cell
  add rbx, rax

  ; top right 
  mov r14, r10
  add r14, qword 1
  mov r15, r11
  sub r15, qword 1
  call lookup_cell
  add rbx, rax

  ; center left
  mov r14, r10
  sub r14, qword 1
  mov r15, r11
  call lookup_cell
  add rbx, rax

  ; center right 
  mov r14, r10
  add r14, qword 1
  mov r15, r11
  call lookup_cell
  add rbx, rax

  ; bottom left
  mov r14, r10
  sub r14, qword 1
  mov r15, r11
  add r15, qword 1
  call lookup_cell
  add rbx, rax

  ; bottom center
  mov r14, r10
  mov r15, r11
  add r15, qword 1
  call lookup_cell
  add rbx, rax

  ; bottom right 
  mov r14, r10
  add r14, qword 1
  mov r15, r11
  add r15, qword 1
  call lookup_cell
  add rbx, rax

  ; rbx now contains the number of neighbours

  ; we also need the center state, as a living cell with exactly two neighbours
  ; survives.
  ; center center 
  mov r14, r10
  mov r15, r11
  call lookup_cell

  ; assume the reulting cell will be dead
  mov rcx, EMPTY_CELL 

  ; 0, 1, and 4 and upwards do the same, so subtracting 2 turns this into three
  ; cases, 0 (keep living), 1 (grow), and the rest (die)
  sub rbx, 2
  ; after this or theres only two cases: the lowest bit is 1 and all others 0 (live)
  ; and the rest 
  or rbx, rax

  ; after subtracting 1 rbx is now 0 iff the cell should be alive
  sub rbx, 1
  jnz .notalive

  mov rcx, FULL_CELL

  .notalive:

  ; write the new cell state into the world_after_update array
  mov rdx, r12
  add rdx, [world_after_update]
  mov byte [rdx], cl
  
  ; increase our loop counter
  inc r12
  cmp r12, SIZE
  jne .loopstart

  ; Swap world and world after update
  mov rax, [world]
  mov rcx, [world_after_update]
  mov [world], rcx 
  mov [world_after_update], rax

  pop rbx
  pop r12
  ret

; takes in a x and y coordinate in r14 and r15 and returns 1 or 0 in rax depending
; on the cell's state. Coordinates will be wrapped using modulo operators.
lookup_cell:
  ; x 
  mov rax, r14 
  mov rcx, WIDTH
  call modulo
  mov r14, rax
  
  ; y
  mov rax, r15 
  mov rcx, HEIGHT
  call modulo
  mov r15, rax

  ; combine the 2d index back into a 1d index 
  mov rax, r15
  mov rcx, WIDTH
  mul rcx
  add rax, r14

  ; turn the index into a memory address
  add rax, [world]
  
  ; load the memory at the address
  xor rcx, rcx 
  mov cl, byte[rax]
  mov rax, rcx

  ; map the two CELL_FULL and CELL_EMPTY values to 0 and 1
  sub rax, EMPTY_CELL 

  ; set the zero flag
  cmp rax, 0

  ; using a jump here is not the nicest, an alternative would be a division
  ; by FULL_CELL
  jz .iszero

  mov rax, qword 1
  ret

  .iszero:

  mov rax, qword 0
  ret


; Calculates rax % rcx and returns the result in rax
modulo:
  mov rdx, 0
  ; div stores the remainder in rdx
  div rcx
  mov rax, rdx
  ret

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
  add rax, [world]
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
  mov rdi, CLOCK_MONOTONIC
  mov rsi, 0 ; no flags, relative time
  mov rdx, sleep_time_seconds
  mov r10, 0 ; no output arg

  syscall
  ret

; Allocate storage for a world of size $rax
malloc:
  ; Ask the kernel for storage
  mov rax, SYS_MMAP
  ; Let the kernel decide where to take the memory from
  mov rdi, 0
  ; Allocate SIZE bytes
  mov rsi, rcx
  ; Allocate readable and writeable memory
  mov rdx, PROT_READ | PROT_WRITE
  ; we do not want file backed memory
  mov r10, MAP_ANONYMOUS | MAP_PRIVATE
  ; fd
  mov r8, -1
  ; offset
  mov r9, 0
  syscall
  ret

initialize_world:
  ; generate a seed
  call get_random_seed
  ; store the seed in r10
  push r12
  mov r12, rax

  ; we use r13 for our loop index
  push r13
  mov r13, 0

  .loopstart:
  ; run the rng to determine the state of the next cell
  mov rax, r12
  call xorshift_64
  mov r12, rax

  ; ro rax %= 2, then map it to EMPTY_CELL and FULL_CELL 
  and rax, 1
  mov rdx, FULL_CELL - EMPTY_CELL
  mul rdx
  mov rdx, rax
  add rdx, EMPTY_CELL

  ; Determine the offset into the world array
  mov rcx, r13
  ; Add the world start position
  add rcx, [world]

  ; copy the lowest byte of rdx into the array 
  mov byte[rcx], dl 

  ; increment our loop counter
  inc r13

  ; check if we are done
  cmp r13, SIZE
  jne .loopstart

  ; restore non scramble registers
  pop r13
  pop r12

  ret

; Uses the current time to generate a seed. Stores the seed in rax 
get_random_seed:
  ; Allocate 18 bytes of space on the stack for the result
  push rax
  push rax

  mov rax, SYS_CLOCK_GET_TIME
  mov rdi, CLOCK_REALTIME
  ; The stack grows donwards, so we use the current stack pointer as 
  ; the place to write
  mov rsi, rsp 
  syscall
  
  ; The first value is gonna be seconds
  pop rcx
  ; The second value is nanoseconds
  pop rax
  ; multiply the two and ignore overflow
  xor rax, rcx

  ; rax now contains the seed
  ret

; Takes the value in rax as a seed, and applies xorshift64. The result
; is stored in rax and is both the result and the new seed
xorshift_64:
  ; rax ^= rax << 13
  mov rcx, rax
  shl rcx, 13
  xor rax, rcx

  ; rax ^= rax >> 7
  mov rcx, rax
  shr rcx, 13
  xor rax, rcx

  ; rax ^= rax << 17
  mov rcx, rax
  shl rcx, 17
  xor rax, rcx
  
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
; an array for storing the worlds new state after an update
world_after_update resq 1
