#include "print.h"

void kernel_main(){
    print_clear();
    print_set_color(PRINT_COLOR_GREEN, PRINT_COLOR_BLACK);
    print_str("Hola! Bienvenido a mi primer kernel de 64 bits!");

}
