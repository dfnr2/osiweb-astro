#include <stdio.h>


/*
  The Character ROM for the C1P is bit-reversed with respect to the
  C2/C4 character ROM; the data lines are fed into the shift register
  in opposite order.  This little routine will convert a
  C1P/superboard CG ROM to a C2/4 CG ROM, or vice-versa.
*/

unsigned int fliptable[256];

void fillfliptable(void)
{
    int i,j;
    unsigned int unreversed, reversed;
    
    for (i = 0; i < 256; i++) {
	reversed = 0;
	unreversed = i;
	for (j = 0; j<8; j++) {
	    reversed = reversed << 1;
	    reversed = reversed | (unreversed & 1);
	    unreversed = unreversed >> 1;
	}
	printf("c=%4x, flip=%4x\n",i,reversed);
	fliptable[i] = reversed;
    }
}
	    
	
main ()
{
    int i,c;
    
    fillfliptable();
    exit(0);
    for (i = 0; i < 256; i++) {
	printf("c=%4x, flip=%4x\n",i,fliptable[i]);
    }
    c == fgetc(stdin);
    while (EOF != c) {
	fputc(fliptable[c],stdout);
	c == fgetc(stdin);
    }
}
