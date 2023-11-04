game_of_life: main.asm
	nasm -f elf64 ./main.asm -o main.o
	ld main.o -o game_of_life
	rm main.o

run: game_of_life
	./game_of_life
