// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/04/Fill.asm

// Runs an infinite loop that listens to the keyboard input.
// When a key is pressed (any key), the program blackens the screen,
// i.e. writes "black" in every pixel;
// the screen should remain fully black as long as the key is pressed.
// When no key is pressed, the program clears the screen, i.e. writes
// "white" in every pixel;
// the screen should remain fully clear as long as no key is pressed.

// while true:
//         i = &screen
//         for pixelgroup in (0..256):
//             for col in (0..32):
//                 if KEY:
//                     SCREEN[i++] = 1111111111111111
//                 else:
//                     SCREEN[i++] = 0

(INFINITELOOP)
    @8192
    D=A            // D = 256*32
    @PIXELGROUP
    M=D            // pixelgroup = 256*32
    @SCREEN
    D=A            // D = &screen

    @PIXELGROUPPOINTER
    M=D            // pixelgrouppointer = &screen

    (ROWLOOP)
        @KBD
        D=M        // D = keypressed

        @BLACK
        D;JGT      // jump to (black) if keypressed > 0

        (WHITE)
            @PIXELGROUPPOINTER
            D=M
            A=D
            M=0     // *pixelgrouppointer = 0
            @ENDBLACK
            0;JMP
        (BLACK)
            @PIXELGROUPPOINTER
            D=M
            A=D
            D=0
            D=!D
            M=D     // *pixelgrouppointer = 1111111111111111
        (ENDBLACK)

        @PIXELGROUPPOINTER
        M=M+1

        @PIXELGROUP
        M=M-1       // pixelgroup = pixelgroup - 1
        D=M
        @ROWLOOP
        D;JGT       // jump to (rowloop) if pixelgroup > 0
    @INFINITELOOP
    0;JMP
