org 0x100
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
 
    call DispMsg
    jmp $
 
DispMsg:
    mov ax, Message
    mov bp, ax
    mov cx, 0x0a
    mov dx, 0x1500
    mov bx, 0x000c
    mov ax, 0x1301
    int 0x10
    ret
 
Message:    db  "In the Loader.bin"
