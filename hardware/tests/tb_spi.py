import cocotb
import random

from cocotb.triggers import Timer, RisingEdge;
from cocotb.clock import Clock

n_samples = 8 * 10

def bits_to_hex(bit_list):
    """Converts a list of logic bits into a list of 8-byte (64-bit) hex strings.
    Fails on non-0/1 values via standard integer conversion.
    """
    bits = [int(b) for b in bit_list]
    chunk_size = 8
    hex_list = []
    
    for i in range(0, len(bits), chunk_size):
        chunk = bits[i:i + chunk_size]
        
        # Pad the final chunk with leading zeros if it's less than 64 bits
        if len(chunk) < chunk_size:
            chunk = [0] * (chunk_size - len(chunk)) + chunk
            
        val = 0
        for bit in chunk:
            val = (val << 1) | bit
            
        hex_list.append(f"0x{val:02x}")
        
    return hex_list


def chunks(lst, n) -> list[list]:
    for i in range(0, len(lst), n):
        yield lst[i:i+n]


async def reset(dut):
    await RisingEdge(dut.sysclk)
    dut.rst_btn.value = 1

    for _ in range(5):
        await RisingEdge(dut.sysclk)

    dut.rst_btn.value = 0
    await RisingEdge(dut.sysclk)


async def xmit_bits(dut, bits: list[int], pad: int = 8, period: int = 1_000, CPOL: int = 0, CPHA: int = 0) -> list:
    pad_bits = bits + [1] * pad
    recd_bits = []
    hperiod = period / 2

    dut.sclk.value = CPOL

    await Timer(period, "ns")

    dut.cs.value = 0

    for bit in pad_bits:
        dut.sclk.value = 0
        dut.pico.value = bit & 1
        await Timer(hperiod, "ns")
        dut.sclk.value = 1
        recd_bits.append(dut.poci.value)
        await Timer(hperiod, "ns")

    dut.sclk.value = 0
    await Timer(period, "ns")

    dut.cs.value = 1
    await Timer(period, "ns")

    return [bits_to_hex(x) for x in chunks(recd_bits, 8)]

@cocotb.test
async def test_packet(dut):
    # 10 Mhz sysclk
    clock = Clock(dut.sysclk, 100, "ns")
    cocotb.start_soon(clock.start())

    dut.cs.value = 1
    dut.sclk.value = 0
    dut.initial_reset.value = 0
    dut.pico.value = 0
    dut.poci.value = 1

    await reset(dut)

    sclk_period = 1000
    samples = [random.randint(0, 1) for _ in range(n_samples)]

    recd_bits = await xmit_bits(dut, samples, 8, sclk_period)

    sent = [bits_to_hex(x) for x in chunks(samples, 8)]
    recd_bits = recd_bits [1:]

    assert sent == recd_bits, f"Mismatched return\nSent: {sent}\nRecd:{recd_bits}"