import esp32.utils as utils
import esp32.fpga as fpga

data = utils.get_departure_data(utils.config["station"])
print(data)
utils.update_display(data)

fpga.set_colour(0xFF, 0x4F, 0x00)
fpga.set_brightness(0xF)

print("Done")
