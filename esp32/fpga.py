from machine import Pin, UART
from time import sleep_ms

import machine, time, re

uart = UART(1, 38400)
uart.init(38400, bits = 8, parity = 0, stop = 2, tx = Pin(21), rx = Pin(20))


def clear():
    uart.write(b'\x00')
    time.sleep_ms(10)


def update():
    uart.write(b'\xFF')
    print("FPGA Updating...")
    time.sleep_ms(10)
    
    
def set_head(val):
    send_text(b'\xA1', val)
    
    
def set_head_alt(val):
    send_text(b'\xA2', val)
    
    
def set_etd(val):
    send_text(b'\xA3', val)
    
    
def set_mid(val):
    send_text(b'\xB4', val)
    
  
def set_mid_alt(val):
    send_text(b'\xB5', val)
    
  
def set_fst(val):
    send_text(b'\xC6', val)
    
    
def set_fst_alt(val):
    send_text(b'\xC7', val)
    
    
def set_fst_etd(val):
    send_text(b'\xC8', val)
    
  
def set_scd(val):
    send_text(b'\xC9', val)
    
 
def set_scd_alt(val):
    send_text(b'\xCA', val)
    
    
def set_scd_etd(val):
    send_text(b'\xCB', val)


def send_text(head, val):
    res = re.sub(r'[^a-zA-Z0-9 :,+]', '', val)
    print("Res: " + res)
    if len(res) > 170:
        print("Err: Input too long")
        res = res[0:170]
    
    uart.write(head)
    uart.write(b'\xFF')
    for i in range(len(res)):
        uart.write(res[len(res) - 1 - i].encode("ascii"))
    uart.write(b'\x00')
    time.sleep_ms(10)
    
    
def set_brightness(val):
    val4 = val & 0xF          # reduce to 4 bits
    out_byte = (0x1 << 4) | val4
    uart.write(bytes([out_byte]))
    
    
def set_colour(r, g, b):
    uart.write(b'\x20')
    uart.write(bytes([r & 0xFF]))
    uart.write(bytes([g & 0xFF]))
    uart.write(bytes([b & 0xFF]))


