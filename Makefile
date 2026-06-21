IVERILOG ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
YOSYS     ?= yosys
PYTHON    ?= python3
SBY       ?= sby
VIVADO    ?= vivado

BUILD_DIR := build
RTL_FILES := rtl/files.f
RTL_SOURCES := $(shell cat $(RTL_FILES))
TEST_FILES := \
	test/tb_reset_sync.sv \
	test/tb_fifo_basic.sv \
	test/tb_fifo_stream.sv \
	test/tb_fifo_random.sv \
	test/fifo_assertions.sv \
	test/stream_assertions.sv

TESTS := \
	tb_async_reset_sync \
	tb_equal_width \
	tb_almost_flags \
	tb_pack_16_to_32 \
	tb_split_32_to_16 \
	tb_width_conv_pack_buffer \
	tb_stream_pack_16_to_32 \
	tb_stream_split_32_to_16 \
	tb_fifo_boundary \
	tb_reset_access_gate \
	tb_fifo_random \
	tb_stream_random \
	tb_stream_write_throughput \
	tb_stream_read_throughput \
	tb_stream_split_read_throughput \
	tb_stream_random_pack_16_to_32 \
	tb_stream_random_split_32_to_16

.PHONY: all check test params lint cdc release-check xilinx-cdc xilinx-runner-check synth formal formal-matrix pynq-z2 clean help $(TESTS)

all: check

help:
	@echo "Available targets:"
	@echo "  make test   - run all Icarus Verilog simulations"
	@echo "  make params - verify invalid parameters fail clearly"
	@echo "  make lint   - lint all public top-level modules with Verilator"
	@echo "  make cdc    - run source-level synchronizer structure checks"
	@echo "  make release-check - verify release metadata consistency"
	@echo "  make xilinx-cdc - synthesize and validate the scoped Vivado XDC template"
	@echo "  make xilinx-runner-check - validate a licensed Vivado CI runner"
	@echo "  make synth  - run Yosys hierarchy and synthesis checks"
	@echo "  make formal - prove pointer/core, reset release, and wrapper properties"
	@echo "  make formal-matrix - sweep wrapper widths, ratios, and address sizes"
	@echo "  make pynq-z2 - build the PYNQ-Z2 Vivado validation design"
	@echo "  make check  - run test, lint, CDC, synthesis, and formal checks"
	@echo "  make clean  - remove generated files"

check: test params lint cdc release-check synth formal

test: $(TESTS)

params:
	bash scripts/check_parameters.sh

$(TESTS): %: $(BUILD_DIR)/%.out
	$(VVP) $<

$(BUILD_DIR)/%.out: $(TEST_FILES) $(shell sed 's|^|./|' $(RTL_FILES))
	@mkdir -p $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s $* -o $@ -f $(RTL_FILES) $(TEST_FILES)

lint:
	$(VERILATOR) --lint-only -Wall -f $(RTL_FILES) \
		--top-module async_reset_sync
	$(VERILATOR) --lint-only -Wall -f $(RTL_FILES) \
		--top-module async_fifo
	$(VERILATOR) --lint-only -Wall -f $(RTL_FILES) \
		--top-module async_fifo_width_conv
	$(VERILATOR) --lint-only -Wall -f $(RTL_FILES) \
		--top-module async_fifo_stream

cdc:
	$(PYTHON) scripts/check_cdc.py

release-check:
	$(PYTHON) scripts/check_release.py

xilinx-cdc:
	$(VIVADO) -mode batch -nojournal -nolog -notrace \
		-source scripts/validate_xilinx_template.tcl
	$(VIVADO) -mode batch -nojournal -nolog -notrace \
		-source scripts/validate_xilinx_multi.tcl

xilinx-runner-check:
	bash scripts/check_xilinx_runner.sh

synth:
	$(YOSYS) -q -p 'read_verilog -sv $(RTL_SOURCES); hierarchy -check -top async_reset_sync; proc; check'
	$(YOSYS) -q -p 'read_verilog -sv $(RTL_SOURCES); hierarchy -check -top async_fifo; proc; check'
	$(YOSYS) -q -p 'read_verilog -sv $(RTL_SOURCES); hierarchy -check -top async_fifo_width_conv; proc; check'
	$(YOSYS) -q -p 'read_verilog -sv $(RTL_SOURCES); hierarchy -check -top async_fifo_stream; proc; check'

formal:
	rm -rf build/formal-pointer
	$(SBY) -f -d build/formal-pointer formal/pointer.sby
	rm -rf build/formal-core-bmc build/formal-core-cover
	$(SBY) -f -d build/formal-core-bmc formal/core.sby bmc
	$(SBY) -f -d build/formal-core-cover formal/core.sby cover
	rm -rf build/formal-anyclock-a1 build/formal-anyclock-a2
	$(SBY) -f -d build/formal-anyclock-a1 formal/anyclock_core.sby a1
	$(SBY) -f -d build/formal-anyclock-a2 formal/anyclock_core.sby a2
	rm -rf build/formal-reset-write-first build/formal-reset-read-first \
		build/formal-reset-write-first-cover build/formal-reset-read-first-cover
	$(SBY) -f -d build/formal-reset-write-first formal/reset_skew.sby write_first
	$(SBY) -f -d build/formal-reset-read-first formal/reset_skew.sby read_first
	$(SBY) -f -d build/formal-reset-write-first-cover formal/reset_skew.sby write_first_cover
	$(SBY) -f -d build/formal-reset-read-first-cover formal/reset_skew.sby read_first_cover
	rm -rf build/formal-stream-reset-write-first build/formal-stream-reset-read-first \
		build/formal-stream-reset-write-first-cover \
		build/formal-stream-reset-read-first-cover
	$(SBY) -f -d build/formal-stream-reset-write-first formal/stream_reset_skew.sby write_first
	$(SBY) -f -d build/formal-stream-reset-read-first formal/stream_reset_skew.sby read_first
	$(SBY) -f -d build/formal-stream-reset-write-first-cover formal/stream_reset_skew.sby write_first_cover
	$(SBY) -f -d build/formal-stream-reset-read-first-cover formal/stream_reset_skew.sby read_first_cover
	rm -rf build/formal-width-pack build/formal-width-split \
		build/formal-width-pack-cover build/formal-width-split-cover
	$(SBY) -f -d build/formal-width-pack formal/width_conv.sby pack
	$(SBY) -f -d build/formal-width-split formal/width_conv.sby split
	$(SBY) -f -d build/formal-width-pack-cover formal/width_conv.sby pack_cover
	$(SBY) -f -d build/formal-width-split-cover formal/width_conv.sby split_cover
	rm -rf build/formal-stream-pack build/formal-stream-split \
		build/formal-stream-pack-cover build/formal-stream-split-cover
	$(SBY) -f -d build/formal-stream-pack formal/stream.sby pack
	$(SBY) -f -d build/formal-stream-split formal/stream.sby split
	$(SBY) -f -d build/formal-stream-pack-cover formal/stream.sby pack_cover
	$(SBY) -f -d build/formal-stream-split-cover formal/stream.sby split_cover
	$(MAKE) formal-matrix

formal-matrix:
	rm -rf build/formal-matrix-*
	@for task in req_eq_a2 req_eq_a3 req_eq_a5 req_eq16_a3 \
		req_pack2_a3 req_pack4_a4 req_pack8_a4 \
		req_split2_a3 req_split4_a4 req_split8_a4 \
		stream_eq_a2 stream_eq_a3 stream_eq_a5 stream_eq16_a3 \
		stream_pack2_a3 stream_pack4_a4 stream_pack8_a4 \
		stream_split2_a3 stream_split4_a4 stream_split8_a4; do \
		$(SBY) -f -d build/formal-matrix-$$task formal/matrix.sby $$task || exit $$?; \
	done
	@for task in req_pack4 req_split4 stream_pack4 stream_split4; do \
		$(SBY) -f -d build/formal-matrix-cover-$$task formal/matrix_cover.sby $$task || exit $$?; \
	done

pynq-z2:
	$(VIVADO) -mode batch -source examples/pynq_z2/build_vivado.tcl

clean:
	rm -rf $(BUILD_DIR) obj_dir
