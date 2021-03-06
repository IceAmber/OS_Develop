org 0x7c00
	
	jmp		LABEL_START		;跳转	
	nop
	BS_OEMName		db		'FreeDos '		;OEM string，8个字节
	BPB_BytePerSec	dw		512				;每扇区字节数
	BPB_SecPerClus	db		1				;每簇扇区数
	BPB_RsvdSecCnt	dw		1				;保留扇区数
	BPB_NumFATs		db		2				;FAT表数
	BPB_RootEntCnt	dw		224				;根目录文件数最大值
	BPB_TotSec16	dw		2880			;逻辑扇区总数
	BPB_Media		db		0xf0			;媒体描述符
	BPB_FATsz16		dw		9				;每FAT扇区数
	BPB_SecPerTrk	dw		18				;每磁道扇区数
	BPB_NumHeads	dw		2				;磁头数
	BPB_HideSec		dd		0				;隐藏扇区数
	BPB_TotSec32	dd		0				;如果BPB_TotSec16为0，这里记录扇区总数
	BS_DrvNum		db		0				;中断13的驱动器号
	BS_Reserved1	db		0				;未使用
	BS_BootSig		db		0x29			;扩展引导标记
	BS_VolID		dd		0				;卷序列号
	BS_VolLab		db		'Orange OS  '	;卷标，11个字节
	BS_FileSysType	db		'FAT12   '		;文件系统类型

LABEL_START:
	mov ax, cs
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov sp, BaseOfStack

	; 清屏
	mov	ax, 0600h		; AH = 6,  AL = 0h
	mov	bx, 0700h		; 黑底白字(BL = 07h)
	mov	cx, 0			; 左上角: (0, 0)
	mov	dx, 0184fh		; 右下角: (80, 50)
	int	10h			; int 10h

	;显示Booting  
	mov dh, 0
	call DispStr

	;软驱复位
	xor ah, ah
	xor dl, dl
	int 0x13

	mov word [wRootCurSecNum], RootDirSecNum
LABEL_SEARCH_IN_ROOT_DIR_BEGIN:
	cmp word [wRootSecCnt], 0
	jz	LABEL_SEARCH_IN_ROOT_DIR_END	;这里跳转表示整个根目录都搜索完毕，没有找到Loader.bin
	
	dec word [wRootSecCnt]
	mov	ax, BaseOfLoader
	mov es, ax
	mov bx, OffsetOfLoader
	mov ax, word [wRootCurSecNum]
	mov cl, 1
	call ReadSector				;读取扇区数据
	mov di, OffsetOfLoader
	cld
	mov dl, 0x10				;每个扇区中目录个数为16

LABEL_CMP_NEXT_FILE_NAME:
	mov si, LoaderFileName
	mov cl, 0x0b				;文件名长度为11个字节

LABEL_CMP_FILE_NAME:
	test cl, cl
	jz LABEL_FOUND_LOADER
	dec cl
	lodsb
	test al, al
	jz LABEL_CMP_NAME_END		;文件名比较完毕
	cmp al, [es:di]
	jz LABEL_GO_ON		;从根目录中读取到的文件名字符和目标文件名字符相等，则继续比较下一个字符

	jmp LABEL_CMP_NAME_END

LABEL_GO_ON:
	inc di
	jmp LABEL_CMP_FILE_NAME

LABEL_CMP_NAME_END:
	dec dl
	jz LABEL_GO_TO_NEXT_SECTOR	;16组目录都比较完毕，则读取下一个扇区
	and di, 0xffe0				;这里把di指针重置到当前目录的起始处
	add di, 0x20				;指针指向下一组目录(每组目录长度为32个字节)
	jmp	LABEL_CMP_NEXT_FILE_NAME	;比较下一组文件名

LABEL_GO_TO_NEXT_SECTOR:
	inc word [wRootCurSecNum]
	jmp LABEL_SEARCH_IN_ROOT_DIR_BEGIN

LABEL_SEARCH_IN_ROOT_DIR_END:	;没找到LOADER.BIN
	mov dh, 2
	call DispStr

	jmp $

LABEL_FOUND_LOADER:				;找到LOADER.BIN文件
	xor cx, cx
	and di, 0xffe0				;这里把di设置为指向目录项的首地址
	add di, 0x1a				;目录项中偏移0x1a处为初始簇号
	mov cx, word [es:di]		;将初始簇号存入cx
	mov word [wReadOffset], OffsetOfLoader

LABEL_GO_ON_LOADING:
	push ax
	push bx
	mov ah, 0x0e
	mov al, '.'
	mov bl, 0x0f
	int 0x10
	pop bx
	pop ax

	push cx
	mov ax, cx
	sub ax, 2
	xor cx, cx
	mov cl, [BPB_SecPerClus]
	mul cl
	mov bx, DataOffsetSec
	add ax, bx						;得到当前簇号的数据偏移(单位：扇区)
	push ax
	mov ax, BaseOfLoader
	mov es, ax					;存放数据的段地址
	pop ax
	mov bx, word [wReadOffset]		;存放数据的偏移
	mov cl, 1
	call ReadSector				;读取数据
	
	pop ax						;取出当前簇号
	mov bx, 3					
	mul bx						;簇号 * 3
	mov bx, 2
	div bx						;再除2，这里得到簇号的偏移(单位：字节)				
	test dx, dx
	jz LABEL_IN_HIGH_BYTE
	mov byte [bInHighByte], 1	;该簇号的在当前字节的高4位

LABEL_IN_HIGH_BYTE:
	xor dx, dx
	mov bx, [BPB_BytePerSec]
	add word [wReadOffset], bx	
	div bx
	inc ax						;FAT	
	push dx
	push ax
	mov ax, BaseOfLoader
	sub ax, 0x100
	mov es, ax					;设置读的位置的段地址
	pop ax						;ax中存放要读取的扇区号
	xor bx, bx
	mov cl, 2					;一次读取2个扇区
	call ReadSector
	pop dx
	add bx, dx
	mov ax, word [es:bx]
	cmp byte [bInHighByte], 0		;看簇号是不是在当前字节的高4位
	jz LABEL_EVEN
	shr ax, 4					;如果是则ax右移4位
LABEL_EVEN:
	and ax, 0xfff
	cmp ax, 0xfff				;如果ax的值为0xfff表示文件结束
	jz	LABEL_FILE_LOADED
	mov cx, ax
	jmp LABEL_GO_ON_LOADING

LABEL_FILE_LOADED:
	mov dh, 1
	call DispStr
	jmp BaseOfLoader:OffsetOfLoader	;跳转到Loader.bin

ReadSector:
	push bp
	mov bp, sp
	sub sp, 2
	mov byte [bp - 2], cl
	push bx
	mov bl, [BPB_SecPerTrk]			
	div bl						;计算出当前扇区所处的磁道
	inc ah						;除得的商放在al,余数放在ah(al中放的是磁道号，ah中放的是扇区号)
	mov cl, ah
	mov dh, al
	shr al, 1					;磁道号除以2得到磁头号
	mov ch, al
	and ch, 1
	pop bx
	mov dl, [BS_DrvNum]
.GoOnReading:
	mov ah, 2					;读扇区
	mov al, byte [bp - 2]		;要读的扇区数
	int 0x13
	jc .GoOnReading				;读扇区失败则继续读
	add sp, 2
	pop bp, 
	ret

DispStr:
	mov ax, MessageLength
	mul dh
	add ax, BootMessage
	mov bp, ax
	mov ax, ds
	mov es, ax
	mov cx, MessageLength
	mov ax, 0x1301
	mov bx, 0x0007
	mov dl, 0
	int 0x10
	ret

	BaseOfStack		equ		0x7c00
	BaseOfLoader	equ		0x9000
	OffsetOfLoader	equ		0x100
	RootDirSecNum	equ		19			;根目录起始扇区号=FAT扇区数(2个) + 引导扇区数
	wRootSecCnt		dw		14			;根目录所占的扇区数
	wRootCurSecNum	dw		0
	wFileNameCnt	db		0
	LoaderFileName	db		'LOADER  BIN', 0	;LOADER.BIN (文件名)
	MessageLength	equ		9
	BootMessage:	db		"Booting  "
	Message1:		db		"Ready.   "
	Message2:		db		"No LOADER"
	times	510-($-$$) db 0
	dw		0xaa55
