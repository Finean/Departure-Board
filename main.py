import framebuf
import gc
import json
import uasyncio as asyncio
import utils

from pimoroni import BREAKOUT_GARDEN_I2C_PINS, RGBLED 
from picographics import PicoGraphics, DISPLAY_PICO_DISPLAY_2, PEN_RGB565
from machine import Pin, RTC

#Telem
import time

#Allow USB to initialise
time.sleep(0.5)

lcd = PicoGraphics(display = DISPLAY_PICO_DISPLAY_2, pen_type = PEN_RGB565) #320 x 240 pixels
display_width, display_height = lcd.get_bounds()
lcd.set_backlight(1.0)
lcd.set_font("bitmap8")

#GPIO vars
button_a = Pin(12, Pin.IN, Pin.PULL_UP)
button_b = Pin(13, Pin.IN, Pin.PULL_UP)
button_x = Pin(14, Pin.IN, Pin.PULL_UP)
button_y = Pin(15, Pin.IN, Pin.PULL_UP)
led = RGBLED(26, 27, 28)
led.set_rgb(0, 0, 0)


start_time = time.time()
data = utils.get_station_data("MAN")

font_colour = lcd.create_pen(255, 165, 0)
BLACK = lcd.create_pen(0, 0, 0)
lcd.set_pen(BLACK)
lcd.clear()
lcd.set_pen(font_colour)
service_data = None
cur_service_id = None

"""
if not(data["areServicesAvailable"]):
    lcd.text("No Services Available", 0, 0, 320, scale = 1)
else:
    srv = data["trainServices"][0]
    dest = srv["destination"][0]["locationName"]
    plat = srv["platform"]
    std = srv["std"]
    etd = srv["etd"]
    op = srv["operator"]
    s_id = srv["serviceID"]
    service_data = utils.get_service_data(s_id)
    stops = service_data["subsequentCallingPoints"][0]["callingPoint"]
    length = service_data["length"]
    lcd.text(f"{std}    Platform {plat}", 0, 0, 320, scale = 1)
    lcd.text(f"{dest}", 0, 10, 320, scale = 1)
    #11 per page
    pages = len(stops) // 11
    page_num = 1
    if len(stops) % 11 != 0:
        pages += 1
    lcd.text(f"Calling at:    Page {page_num} of {pages}", 0, 20, 320, scale = 1)
    if len(stops) == 1:
        name = stops[0]["locationName"]
        lcd.text(f"{name}", 0, 28, 320, scale = 1)
        lcd.text("only", 0, 36, 320, scale = 1)
    else:
        for ix, stop in enumerate(stops):
            name = stop["locationName"] if ix < (len(stops) - 1) else "& " + stop["locationName"]
            if ix > 10:
                break
            lcd.text(f"{name}", 0, 28 + 8 * ix, 320, scale = 1)
    
    lcd.text(f"{op}", 0, 20 + 8 * 12, 320, scale = 1)
    if int(length) > 0:
        lcd.text(f"{length} Carriages", 0, 20 + 9 * 12, 320, scale = 1)
"""
lcd.update()
print(time.time() - start_time, " seconds")
time.sleep(1)

disp_dim = (192, 32)
platform_num = 13


def draw_plat(data, platform_num, disp_dim = (192, 32), scroll = 0):
    global service_data
    global cur_service_id
    lcd.set_pen(BLACK)
    lcd.clear()
    lcd.set_pen(font_colour)
    if len(data["trainServices"]) == 0:
        lcd.text("No services", 0, 0, 320, scale = 1)
        lcd.update()
        return
    service_found = False
    queue = []
    for service in data["trainServices"]:
        if "platform" in service and service["platform"] == str(platform_num):
            if service_found:
                queue.append((service["destination"][0]["locationName"], service["std"], service["etd"]))
            else:
                service_found = True
                dest, std, etd, cancel, length, plat, op, s_id, msg = utils.parse_service(service)
    
    if not(service_found):
        lcd.text("No services at this platform found", 0, 0, 320, scale = 1)
        lcd.update()
        return
    stops_string = " "
    
    if cur_service_id is None or cur_service_id != s_id:
        service_data = utils.get_service_data(s_id)
        cur_service_id = s_id
        
    stops = service_data["subsequentCallingPoints"][0]["callingPoint"]
    if len(stops) == 1:
        stops_string = stops[0]["locationName"] + " only"
    else:
        for ix, stop in enumerate(stops):
            if ix > 0:
                stops_string += ", "
            if ix == len(stops) - 1:
                stops_string += " & "
            stops_string += stop["locationName"]
        
    lcd.text(f"{std} {dest}", 0, 0, 320, scale = 1)
    lcd.text(f"{etd}", 192 - lcd.measure_text(etd, scale = 1), 0, 320, scale = 1)
    if len(stops) > 1:
        stop_ctr = ctr % (len(stops_string) + 5)
    else:
        stop_ctr = 0
    lcd.text(f"Calling at:{stops_string[stop_ctr:stop_ctr + 37]}", 0, 10, 320, scale = 1)
    
    if ctr % 200 >= 100 and len(queue) > 1:
        lcd.text(f"3 {queue[1][1]} {queue[1][0]}", 0, 20, 320, scale = 1)
        lcd.text(f"{queue[1][2]}", 192 - lcd.measure_text(queue[1][2], scale = 1), 20, 320, scale = 1)
    else:
        lcd.text(f"2 {queue[0][1]} {queue[0][0]}", 0, 20, 320, scale = 1)
        lcd.text(f"{queue[0][2]}", 192 - lcd.measure_text(queue[0][2], scale = 1), 20, 320, scale = 1)
    lcd.set_pen(BLACK)
    lcd.rectangle(193, 0, 320, 240)
    lcd.update()

ctr = 0
#Run for ~1 minute
for i in range(1000):
    draw_plat(data, 13, scroll = ctr)
    ctr += 1

    time.sleep(0.05)
