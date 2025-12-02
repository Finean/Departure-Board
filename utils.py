import json
import machine
import ntptime
import network
import os
import ssl
import time
import urequests

rtc = machine.RTC()
connection = None

NET_SSID = "NET_SSID"
NET_PSK = "NET_PSK"

NRE_USN = ""
NRE_PSK = ""

API_KEY = "API_KEY"


headers = {
    "Authorization": "Basic " + API_KEY
}

def network_connect(SSID, PSK):
    global connection
    # Enable the Wireless
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)

    # Number of attempts to make before timeout
    max_wait = 10

    # Sets the Wireless LED pulsing and attempts to connect to your local network
    wlan.config(pm=0xa11140)  # Turn WiFi power saving off for some slow APs
    wlan.connect(SSID, PSK)

    while max_wait > 0:
        if wlan.status() < 0 or wlan.status() >= 3:
            break
        max_wait -= 1
        print("Attempting to connect...")
        time.sleep(1)
    if wlan.status() != 3:
        print("Connection error")
        return(False)
    else:
        print("Connected to ", SSID)
        connection = SSID
        return(True)
        
    
def sync_time():
    global time_string
    global connection
    if connection is None:
        print("No network connection, unable to sync NTC time")
        return False
    try:
        ntptime.settime()
    except OSError:
        print("Unable to contact NTP server")
        return False
    
    print("Time synced with NTP server")
    current_t = rtc.datetime()
    return True
    
#Config functions
std_colours = ["WHITE", "BLACK", "RED", "GREEN", "BLUE", "YELLOW"]
invert = {"BLACK":"WHITE", "WHITE":"BLACK"}
#Default config
config = {"platform": None}


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
    
"""
if file_exists("/config.json"):
    load_cfg()
    print("Config loaded from config.json")
else:
    new_cfg()
    print("Using default config, saved to config.json")
"""

network_connect(NET_SSID, NET_PSK)


#Api ref
#https://realtime.nationalrail.co.uk/LDBWS/docs/documentation.html
def get_station_data(CRS, num_rows = 20, filter_crs = "", filter_type = "to", time_offset = 0, time_window = 120):
    base_url = "https://lite.realtime.nationalrail.co.uk/OpenLDBWS/api/20220120/GetDepartureBoard/"
    query = f"{CRS}?numRows={int(num_rows)}&filterCrs={filter_crs}&filterType={filter_type}&timeOffset={time_offset}&timeWindow={time_window}"
    url = base_url + query
    resp = urequests.get(url, headers = headers)
    print(resp.status_code)
    station_data = resp.json()
    resp.close()
    return(station_data)


def get_service_data(serviceID):
    url = f"https://lite.realtime.nationalrail.co.uk/OpenLDBWS/api/20220120/GetServiceDetails/{serviceID}"
    resp = urequests.get(url, headers = headers)
    print(resp.status_code)
    service_data = resp.json()
    resp.close()
    return(service_data)
    
    
def parse_service(srv):
    dest = srv["destination"][0]["locationName"]
    std = srv["std"]
    etd = srv["etd"]
    cancel = srv["isCancelled"]
    length = srv["length"]
    if cancel:
        etd = "Cancelled"
    elif std == etd:
        etd = "On time"
    if "platform" in srv:
        plat = srv["platform"]
    else:
        plat = False
    op = srv["operator"]
    s_id = srv["serviceID"]
    msg = None
    if "cancelReason" in srv:
        msg = srv["cancelReason"]
    if "delayReason" in srv:
        msg = srv["delayReason"]
    return (dest, std, etd, cancel, length, plat, op, s_id, msg)