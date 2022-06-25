global start
extern long_mode_start

section .text
bits 32
start:
    mov esp, stack_top ; El registro esp apunta a la cima de la pila

    call check_multiboot
    call check_cpuid
    call check_long_mode

    ; La idea es implementar la memoria virtual para acceder al 64-bit long mode a traves del proceso
    ; llamado paging

    call setup_page_tables
    call enable_paging

    lgdt [gdt64.pointer]
    jmp gdt64.code_segment:long_mode_start

    hlt

check_multiboot:
    cmp eax, 0x36d76289  ; El valor de eax es el que indica que el sistema esta en modo multiboot
	jne .no_multiboot
	ret

.no_multiboot:
    mov al, "M"
    jmp error

check_cpuid:
    ; Queremos cambiar el CPUid bit del registro de FLAGS
    pushfd ;Pusheo el registro FLAGS en el stack
    pop eax ;pop hace que eax tome el valor del registro FLAGS
    mov ecx, eax ; Hago una copia de eax en ecx para luego poder comparar si el bit cambio
    xor eax, 1 << 21 ; Hago el flip en el bit 21 del registro FLAGS
    push eax 
    popfd 
    pushfd 
    pop eax 
    ; Transfiero de nuevo el valor de eax al registro ecx asi el registro de flags sigue con normalidad
    push ecx
    popfd
    cmp eax, ecx ; Si son iguales es porque el bit no cambio y por lo tanto que el cpuid no esta disponible
    je .no_cpuid
    ret

.no_cpuid:
    mov al, "C"
    jmp error

check_long_mode:
    ;Esta subrutina sirve para ver si el cpuid soporta extended processor info
    mov eax, 0x80000000 
    cpuid ; Ejecuta el codigo de cpuid en el eax
    cmp eax, 0x80000001 ; Si el eax es menor a 0x80000001 es porque el cpu no soporta extended processor info y tampoco long mode
    jb .no_long_mode

    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29 ; Si el bit 29 del registro edx es 1 es porque el cpu soporta long mode
    jz .no_long_mode ;jz = jump if zero

    ret

.no_long_mode:
    mov al, "L"
    jmp error

setup_page_tables:
    ;La idea es hacer Identity mapping para matchear la direccion de memoria fisica con la misma direccion de memoria virtual
    mov eax, page_table_l3
    ; Como el tamaño de page table es 4096 bytes, entonces los primeros logbase2(4096) bits de la direccion de memoria fisica son iguales a los primeros logbase2(4096) bits de cada pagina van a ser flags
    or eax, 0b11 ; Esto es para habilitar los flags present y writable que se encuentran en el primer y ultimo bit
    mov [page_table_l4], eax ;Ponemos esta entrada como la primera entrada de la tabla de 4to nivel
    
    mov eax, page_table_l2
    or eax, 0b11
    mov [page_table_l3], eax 

    mov ecx, 0; Contador

.loop:
    ; En cada iteracion, se va a mapear una pagina de 2mb
    mov eax, 0x200000 ; 2MiB
    mul ecx ; Multiplica el valor de ecx por eax entonces se obtiene la direccion de la proxima pagina
    or eax, 0b10000011 ; ADemas de present y writable, se habilita el flag huge page
    mov [page_table_l2 + ecx * 8], eax; Ponemos la entrada en la tabla de 2do nivel con el offset que es ecx * 8

    inc ecx ; Incrementamos el contador
    cmp ecx, 512 ; Chequea si toda la tabla esta mapeada
    jne .loop ; Si no esta mapeada, siguee con el ciclo

    ret

enable_paging:
    ;Esta subrutina sirve para habilitar la paginacion 
    ; Hay que pasar ubicacion de la tabla de paginas al cpu
    mov eax, page_table_l4
    mov cr3, eax ; El registro cr3 contiene la direccion fisica de la direccion base de la tabla del directorio de paginas

    ;ENABLE PAE
    mov eax, cr4 
    or eax, 1 << 5 ; Habilita la paginacion extendida
    mov cr4, eax

    ;Habilitar long mode
    mov ecx, 0xC0000080 
    rdmsr ; Leer el registro del msr
    or eax, 1 << 8 ; Habilita el long mode flag
    wrmsr

    ;Habilitar paginacion
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret

error:
    ;print "ERR: X" where X is the error code
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f3a4f52
    mov dword [0xb8008], 0x4f204f20
    mov byte [0xb800a], al
    hlt


section .bss
align 4096
page_table_l4:
    resb 4096
page_table_l3:
    resb 4096
page_table_l2:
    resb 4096
stack_bottom:
    resb 4096 * 4
stack_top:

section .rodata
gdt64:
   dq 0 ; zero entry
.code_segment: equ $ - gdt64
   dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53) 
.pointer:
   dw $ - gdt64 - 1 ; length
   dq gdt64 ; address