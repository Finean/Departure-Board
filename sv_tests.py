import os, glob
import pytest
import subprocess
import cocotb, cocotb_tools

from cocotb_tools import runner

BASE_DIR = os.path.dirname(os.path.realpath(__file__))
PROJ_PATH = os.path.join(BASE_DIR, "hardware")

sv_srcs = [f for f in glob.glob(os.path.join(PROJ_PATH, "*.sv"), recursive=False)]

dut_configs = [
    #dict(top="ledmatrix", sources=sv_srcs, testmodule="tb_ledmatrix"),
    dict(top="spi_test_wrapper", sources=["interfaces/spi_peripheral.sv", "interfaces/spi_test.sv"], testmodule="tb_spi"),
]

# Ignore config.sby (created on run without -t flag)
sby_files = [f for f in glob.glob(os.path.join(PROJ_PATH, "**", "*.sby"), recursive=True) if os.path.basename(f) != "config.sby"]

"""
Can be run using 'uv run pytest -m sim'
Individual modules can be tested with 'uv run pytest -k [top_name]'
"""
@pytest.mark.sim
@pytest.mark.parametrize("cfg", dut_configs, ids=[c["top"] for c in dut_configs])
def test_cocotb_runner(cfg):
    worker_id = os.environ.get("PYTEST_XDIST_WORKER", "master")

    base_path = os.path.dirname(os.path.realpath(__file__))

    srcs_path = os.path.join(base_path, "hardware")
    sim_path  = os.path.join(base_path, "hardware", "tests")
    sources = cfg["sources"]
    sources = [os.path.join(srcs_path, source) for source in sources]

    build_path = os.path.join(base_path, f"sim_build/{cfg["top"]}")

    runner = cocotb_tools.runner.get_runner("icarus")
    runner.build(
        sources=sources,
        hdl_toplevel=cfg["top"],
        always=True,
        build_dir=build_path,
        clean=True,
        waves=True,
    )
    runner.test(
        hdl_toplevel=cfg["top"],
        test_module=cfg["testmodule"], 
        build_dir=build_path,
        test_dir=sim_path,
        results_xml=os.path.join(build_path, "results.xml"),
        waves=True
    )


"""
Can be run using 'uv run pytest -m formal'
Individual modules can be tested with 'uv run pytest -k fpu.sby'
"""
@pytest.mark.formal
@pytest.mark.parametrize("sby_file", sby_files, ids=lambda p: os.path.basename(p))
def test_sby(sby_file):
    dir = os.path.dirname(sby_file)
    sby_name = os.path.basename(sby_file)

    cmd = ["sby", "-t", sby_name]

    result = subprocess.run(    
        cmd,
        cwd=dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"SBY failed for {sby_file}:\n{result.stdout}\n{result.stderr}"