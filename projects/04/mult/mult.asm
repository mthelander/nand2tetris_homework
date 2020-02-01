// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Mult.asm

// Multiplies R0 and R1 and stores the result in R2.
// (R0, R1, R2 refer to RAM[0], RAM[1], and RAM[2], respectively.)

@R0
D=M
@counter
M=D   // counter = R0

@R2
M=0 // R2 = 0

@END
D;JEQ // goto end if R0 == 0

(MULT)
    @R1
    D=M
    @R2
    M=M+D  // R2 = R2+R1

    @counter
    M=M-1  // counter = counter - 1
    D=M

    @MULT
    D;JGT
(END)
