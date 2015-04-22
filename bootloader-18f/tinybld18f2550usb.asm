	radix DEC
	LIST      P=18F46k80


xtal EQU 16000000		; 16 MHz
baud EQU 115200			; the desired baud rate

;
spbrg_value EQU 34

#include "p18f46k80.inc"
IdTypePIC = 0x4F
#define max_flash 0x10000



	CONFIG	DEBUG = OFF
	CONFIG CP0 = ON
	CONFIG CP1 = ON
	CONFIG CP2 = ON
	CONFIG CPB = ON
	CONFIG CPD = ON

	CONFIG WRTB = ON ; Write protect boot block
	CONFIG WRTC = ON ; Write protect configuration registers

	; protect all blocks against table reads; this prevents someone loading
	; firmware with the sole purpose of reading out the current firmware
	CONFIG EBTR0 = ON
	CONFIG EBTR1 = ON
	CONFIG EBTR2 = ON
	CONFIG EBTR3 = ON
	CONFIG EBTRB = ON


;----------------------------- PROGRAM ---------------------------------
	cblock 0
	crc
	i
	cnt1
	cnt2
	cnt3
	counter_hi
	counter_lo
	flag
	endc
	cblock 10
	buffer:64
	endc
	
SendL macro car
	movlw car
	movwf TXREG
	endm

	
;0000000000000000000000000 RESET 00000000000000000000000000
	ORG	0x0000			; Re-map Reset vector
	bra	IntrareBootloader
	

	ORG	0x0008
VIntH
	bra	RVIntH			; Re-map Interrupt vector

	ORG	0x0018
VIntL
	bra	RVIntL			; Re-map Interrupt vector


;view with TabSize=4
;&&&&&&&&&&&&&&&&&&&&&&&   START     &&&&&&&&&&&&&&&&&&&&&&
;----------------------  Bootloader  ----------------------
;PC_flash:		C1h				U		H		L		x  ...  <64 bytes>   ...  crc	
;PC_eeprom:		C1h			   	40h   EEADR   EEDATA	0		crc					
;PC_cfg			C1h			U OR 80h	H		L		1		byte	crc
;PIC_response:	   type `K`
	
IntrareBootloader

	; FIX for UART2 with High speed mode!

	;skip TRIS to 0 C6			;init serial port
	movlw b'00100100'
	movwf TXSTA

	;use only SPBRG (8 bit mode default) not using BAUDCON
	movlw spbrg_value
	movwf SPBRG



	movlw b'10010000'
	movwf RCSTA
						;wait for computer
	rcall Receive			
	sublw 0xC1				;Expect C1h
	bnz way_to_exit
	SendL IdTypePIC				;send PIC type
MainLoop
	SendL 'K'				; "-Everything OK, ready and waiting."
mainl
	clrf crc
	rcall Receive			;Upper
	movwf TBLPTRU
		movwf flag			;(for EEPROM and CFG cases)
	rcall Receive			;Hi
	movwf TBLPTRH
		movwf EEADR			;(for EEPROM case)
	rcall Receive			;Lo
	movwf TBLPTRL
		movwf EEDATA		;(for EEPROM case)

	rcall Receive			;count
	movwf i
	incf i
	lfsr FSR0, (buffer-1)
rcvoct						;read 64+1 bytes
		movwf TABLAT		;prepare for cfg; => store byte before crc
	rcall Receive
	movwf PREINC0
	decfsz i
	bra rcvoct
	
	tstfsz crc				;check crc
	bra ziieroare
		btfss flag,6		;is EEPROM data?
		bra noeeprom
		movlw b'00000100'	;Setup eeprom
		rcall Write
		bra waitwre
noeeprom
		btfss flag,7		;is CFG data?
		bra noconfig
		tblwt*				;write TABLAT(byte before crc) to TBLPTR***
		movlw b'11000100'	;Setup cfg
		rcall Write
		bra waitwre
noconfig
							;write
eraseloop
	movlw	b'10010100'		; Setup erase
	rcall Write
	TBLRD*-					; point to adr-1
	
writebigloop	
	movlw 2					; 2groups
	movwf counter_hi
	lfsr FSR0,buffer
writesloop
	movlw 32				; 32bytes = 4instr
	movwf counter_lo
writebyte
	movf POSTINC0,w			; put 1 byte
	movwf TABLAT
	tblwt+*
	decfsz counter_lo
	bra writebyte
	
	movlw	b'10000100'		; Setup writes
	rcall Write
	decfsz counter_hi
	bra writesloop
waitwre	
	;btfsc EECON1,WR		;for eeprom writes (wait to finish write)
	;bra waitwre			;no need: round trip time with PC bigger than 4ms
	
	bcf EECON1,WREN			;disable writes
	bra MainLoop
	
ziieroare					;CRC failed
	SendL 'N'
	bra mainl
	  
;******** procedures ******************

Write
	movwf EECON1
	movlw 0x55
	movwf EECON2
	movlw 0xAA
	movwf EECON2
	bsf EECON1,WR			;WRITE
	nop
	;nop
	return


Receive
	movlw xtal/2000000/5+1	; for 20MHz => 11/5 => 1/5 second delay
	movwf cnt1
rpt2						
	clrf cnt2
rpt3
	clrf cnt3
rptc
		btfss PIR1,RCIF			;test RX
		bra notrcv
	    movf RCREG,w			;return read data in W
	    addwf crc,f				;compute crc
		return
notrcv
	decfsz cnt3
	bra rptc
	decfsz cnt2
	bra rpt3
	decfsz cnt1
	bra rpt2
	;timeout:
way_to_exit
	bcf	RCSTA,	SPEN			; deactivate UART
	bra RVReset
;*************************************************************
; After reset
; Do not expect the memory to be zero,
; Do not expect registers to be initialised like in catalog.

; remapped reset & interrupt handler locations for user code
; to be written into
	ORG	0x800
RVReset					

	ORG	0x808
RVIntH

	ORG	0x818
RVIntL

            END
