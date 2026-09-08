import gc
import json
import machine
import ntptime
import network
import os
import ssl
import time
import urequests as requests

import esp32.fpga as fpga


def set_headers(cfg):
    headers = {
        "Authorization": "Basic " + cfg["API_KEY"],
        "Connection": "close",        # force server to close after response
        "Accept": "application/json"
    }
    return headers

config = {"station": "EUS", "NET_SSID": "", "NET_PSK": "", "NRE_USN": "", "NRE_PSK": "", "API_KEY": "", "brightness": 3, "led_colour": [0xFF, 0x4F, 0x00]}
station_data = None


def file_exists(filename):
    try:
        return (os.stat(filename)[0] & 0x4000) == 0
    except OSError:
        return False


def new_cfg():
    global config
    save_cfg(config)
    print("New config saved")

    
def load_cfg():
    global config
    cfg_data = json.loads(open("/config.json", "r").read())
    if type(cfg_data) is dict:
        config = cfg_data
    else:
        print("config.json not a dict type")
        
        
def save_cfg(data):
    with open("/config.json", "w") as f:
        f.write(json.dumps(data))
        f.flush()
      
      
def update_cfg(field, value):
    global config
    try:
        config[field] = value
        save_cfg(config)
    except:
        print("Error updating config")


def network_connect(SSID, PSK):
    global connection
    # Enable the Wireless
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)

    # Number of attempts to make before timeout
    max_wait = 10

    # Sets the Wireless LED pulsing and attempts to connect to your local network
    #wlan.config(pm=0xa11140)  # Turn WiFi power saving off for some slow APs
    wlan.connect(SSID, PSK)

    while max_wait > 0:
        if wlan.isconnected():
            break
        max_wait -= 1
        print("Attempting to connect...")
        time.sleep_ms(500)
    if wlan.isconnected():
        print("Connected to ", SSID)
        connection = SSID
        return(True)
    else:
        print("Connection error")
        return(False)

#Api reference
#https://realtime.nationalrail.co.uk/LDBWS/docs/documentation.html
    
def get_station_data(CRS, num_rows = 20, filter_crs = "", filter_type = "to", time_offset = 0, time_window = 120):
    base_url = "https://lite.realtime.nationalrail.co.uk/OpenLDBWS/api/20220120/GetDepartureBoard/"
    query = f"{CRS}?numRows={int(num_rows)}&filterCrs={filter_crs}&filterType={filter_type}&timeOffset={time_offset}&timeWindow={time_window}"
    url = base_url + query
    
    resp = requests.get(url, headers = headers)
    print(resp.status_code)
    station_data = resp.json()
    resp.close()
    gc.collect()
    return station_data


def get_service_data(serviceID):
    url = f"https://lite.realtime.nationalrail.co.uk/OpenLDBWS/api/20220120/GetServiceDetails/{serviceID}"
    
    resp = requests.get(url, headers = headers)
    print(resp.status_code)
    service_data = resp.json()
    resp.close()
    gc.collect()
    return service_data


def get_departure_data(CRS, num_rows = 5, filter_crs = "", filter_type = "to", time_offset = 0, time_window = 120):
    print(f"Free memory: {gc.mem_free()} bytes")
    base_url = "http://lite.realtime.nationalrail.co.uk/OpenLDBWS/api/20220120/GetDepBoardWithDetails/"
    query = f"{CRS}?numRows={int(num_rows)}&filterCrs={filter_crs}&filterType={filter_type}&timeOffset={time_offset}&timeWindow={time_window}"
    url = base_url + query
    
    resp = requests.get(url, headers=headers)
    print(resp.status_code)
    station_data = resp.json()
    resp.close()
    gc.collect()
    return station_data


def fpga_etd(text):
    if text == "On time":
        return ((7 * "+") + "On time")
    elif text == "Cancelled":
        return text
    else:
        return ((18 * "+") + text)


def update_display(station_data):
    main = None
    second = None
    third = None
    
    display_text = [""] * 11
    
    for service in station_data["trainServices"]:
        if main is None:
            main = service
        elif second is None:
            second = service
        elif third is None:
            third = service
                
    if main is None:
        display_text[0] = "No services available"
        display_text[3] = "Station: " + config["station"]
    else:
        dest = main["destination"][0]["locationName"]
        display_text[0] = main["std"] + " " + main["destination"][0]["locationName"]
        display_text[2] = fpga_etd(main["etd"])
        stops = "Calling at: "
        for (idx, stop) in enumerate(main["subsequentCallingPoints"][0]["callingPoint"]):
            if stop["locationName"] == dest:
                if idx == 0:
                    stops += stop["locationName"] + " only"
                else:
                    stops += "and " + stop["locationName"]
            else:
                stops += stop["locationName"] + ", "
        display_text[3] = stops
        if "operator" in main:
            if main["operator"][0] in ["A", "E", "I", "O", "U"]:
                display_text[4] = "An " + main["operator"] + " service"
            else:
                display_text[4] = "A " + main["operator"] + " service"
                
    if second is not(None):
        display_text[5] = "2nd " + second["std"] + " " + second["destination"][0]["locationName"]
        display_text[7] = fpga_etd(second["etd"])
    if third is not(None):
        display_text[8] = "3rd " + third["std"] + " " + third["destination"][0]["locationName"]
        display_text[10] = fpga_etd(third["etd"])        
    
    time.sleep_ms(10)
    fpga.clear()
    fpga.set_head(display_text[0])
    fpga.set_head_alt(display_text[1])
    fpga.set_etd(display_text[2])
    fpga.set_mid(display_text[3])
    fpga.set_mid_alt(display_text[4])
    fpga.set_fst(display_text[5])
    fpga.set_fst_alt(display_text[6])
    fpga.set_fst_etd(display_text[7])
    fpga.set_scd(display_text[8])
    fpga.set_scd_alt(display_text[9])
    fpga.set_scd_etd(display_text[10])
    time.sleep_ms(10)
    fpga.update()
    return True


def settings_display(net_ssid, net_psk, ip):
    fpga.clear()
    time.sleep_ms(10)
    fpga.set_head("Connect to network: " + net_ssid)
    fpga.set_mid("Password: " + net_psk)
    fpga.set_fst("Then connect to: " + ip)
    time.sleep_ms(10)
    fpga.update()
    return True
   
   
if file_exists("/config.json"):
    load_cfg()
    print("Config loaded from config.json")
else:
    new_cfg()
    print("Using default config, saved to config.json")

headers = set_headers(config)    
    
#Connect to wifi
print("\nConnecting to " + config["NET_SSID"] + "...")
network_connect(config["NET_SSID"], config["NET_PSK"])
print("Config: " + str(config))
gc.collect()

fpga.set_colour(config["led_colour"][0], config["led_colour"][1], config["led_colour"][2])
fpga.set_brightness(hex(config["brightness"]))


