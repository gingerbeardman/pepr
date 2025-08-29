# Makefile for PEP CLI on macOS
# Usage:
#   make            # build pepr
#   make demo       # build and write demo.pep
#   make png2pep_all_mod     # convert all images/*.png with pepr_mod (timed per file)
#   make png2pep_all_orig    # convert all images/*.png with pepr_orig (timed per file)
#   make bench_pngs          # run both of the above and join results
#   make clean

CC := clang
# More aggressive optimization defaults; override via environment if needed
CFLAGS ?= -std=c11 -Ofast -march=native -mtune=native -flto=thin -funroll-loops -ffast-math -ffp-contract=fast -fstrict-aliasing -fomit-frame-pointer -fno-math-errno -fno-trapping-math -DNDEBUG -DPEP_NO_STRING_H -pipe
LDFLAGS ?= -flto=thin -Wl,-O3 -Wl,-dead_strip -Wl,-x
FRAMEWORKS := -framework CoreFoundation -framework CoreGraphics -framework ImageIO
CSV := timings.csv
TMP_MOD := .timings_mod.csv
TMP_ORIG := .timings_orig.csv

# Timing controls
RUNS ?= 50
WARMUP ?= 3
PYTHON ?= python3
BENCH := ./bench.py
# Delay between benchmark runs to prevent thermal buildup (in seconds)
BENCH_DELAY ?= 0.001

# Build directories to control which PEP header is used
BUILD_DIR := .build
MOD_DIR := $(BUILD_DIR)/mod
ORIG_DIR := $(BUILD_DIR)/orig
PGO_DIR := $(BUILD_DIR)/pgo

# PGO-specific flags
PGO_GENERATE_FLAGS := -fprofile-generate=$(PGO_DIR)
PGO_USE_FLAGS := -fprofile-use=$(PGO_DIR)

all: pepr_mod pepr_orig demo

$(MOD_DIR)/PEP.h: PEP.h
	mkdir -p "$(MOD_DIR)" && cp PEP.h "$(MOD_DIR)/PEP.h"

$(ORIG_DIR)/PEP.h: PEP.original.h
	mkdir -p "$(ORIG_DIR)" && cp PEP.original.h "$(ORIG_DIR)/PEP.h"

pepr_mod: pepr.c $(MOD_DIR)/PEP.h
	$(CC) $(CFLAGS) -I "$(MOD_DIR)" pepr.c -o $@ $(LDFLAGS) $(FRAMEWORKS)

pepr_orig: pepr.c $(ORIG_DIR)/PEP.h
	$(CC) $(CFLAGS) -I "$(ORIG_DIR)" pepr.c -o $@ $(LDFLAGS) $(FRAMEWORKS)

# PGO build targets
.PHONY: pgo-generate pgo-train pgo-use pgo-clean pepr_pgo

# Step 1: Build with profile generation
pgo-generate: pepr.c $(MOD_DIR)/PEP.h
	mkdir -p "$(PGO_DIR)"
	$(CC) $(CFLAGS) $(PGO_GENERATE_FLAGS) -I "$(MOD_DIR)" pepr.c -o pepr_pgo_gen $(LDFLAGS) $(FRAMEWORKS)

# Step 2: Run training workload to generate profile data
pgo-train: pgo-generate
	@echo "=== Running PGO Training Workload ==="
	@echo "Training on all images in images/ ..."
	@for img in images/*.bmp; do \
		if [ -f "$$img" ]; then \
			echo "Training on $$img..."; \
			./pepr_pgo_gen --dry-run "$$img" >/dev/null 2>&1 || true; \
			./pepr_pgo_gen "$$img" "/tmp/pgo_train.pep" >/dev/null 2>&1 || true; \
		fi; \
	done
	@echo "Converting profile data..."
	@if command -v llvm-profdata >/dev/null 2>&1; then \
		llvm-profdata merge -output=$(PGO_DIR)/default.profdata $(PGO_DIR)/*.profraw; \
	elif command -v xcrun >/dev/null 2>&1; then \
		xcrun llvm-profdata merge -output=$(PGO_DIR)/default.profdata $(PGO_DIR)/*.profraw; \
	else \
		echo "Warning: llvm-profdata not found, trying direct merge..."; \
		cat $(PGO_DIR)/*.profraw > $(PGO_DIR)/default.profdata; \
	fi
	@echo "PGO training complete. Profile data generated in $(PGO_DIR)"

# Step 3: Build final optimized binary using profile data
pgo-use: pgo-train $(MOD_DIR)/PEP.h
	@echo "=== Building PGO-Optimized Binary ==="
	$(CC) $(CFLAGS) $(PGO_USE_FLAGS) -I "$(MOD_DIR)" pepr.c -o pepr_pgo $(LDFLAGS) $(FRAMEWORKS)
	@echo "PGO-optimized binary built: pepr_pgo"

# Convenience target for full PGO build
pepr_pgo: pgo-use

# Clean PGO artifacts
pgo-clean:
	rm -rf "$(PGO_DIR)" pepr_pgo_gen pepr_pgo

# Back-compat: provide 'pepr' as a symlink to pepr_mod for targets expecting it
.PHONY: pepr
pepr: pepr_mod
	@ln -sf pepr_mod pepr

# Removed noopt build
.PHONY: noopt
noopt:
	@echo "'noopt' build removed. Use pepr_mod and pepr_orig instead." && false

# Demo target using built-in generator
DEMO_OUT := demo.pep
.PHONY: demo

demo: pepr_mod
	./pepr_mod --demo $(DEMO_OUT)
	@echo "Wrote $(DEMO_OUT)"

# ---------- Batch convert all PNGs in png/ directory ----------
PNGS := $(wildcard images/*.png)
.PHONY: png2pep_all_mod png2pep_all_orig bench_pngs bench_pngs_dry pep2bmp_all pep2rle_all

png2pep_all_mod: 
	@rm -f "$(TMP_MOD)" && echo "file,time" > "$(TMP_MOD)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="$${f%.png}.pep"; \
			echo "[MOD] $$f -> $$out"; \
			tmp=`mktemp -t pepbench.XXXXXX`; \
			$(PYTHON) $(BENCH) ./pepr_mod "$$f" "$$out" $(RUNS) $(WARMUP) > "$$tmp"; \
			R=`cat "$$tmp"`; rm -f "$$tmp"; \
			echo "$$f,$$R" >> "$(TMP_MOD)"; \
			echo "    time=$$R"; \
		done; \
	fi

png2pep_all_orig: 
	@rm -f "$(TMP_ORIG)" && echo "file,time" > "$(TMP_ORIG)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="$${f%.png}.pep"; \
			echo "[ORIG] $$f -> $$out"; \
			tmp=`mktemp -t pepbench.XXXXXX`; \
			$(PYTHON) $(BENCH) ./pepr_orig "$$f" "$$out" $(RUNS) $(WARMUP) > "$$tmp"; \
			R=`cat "$$tmp"`; rm -f "$$tmp"; \
			echo "$$f,$$R" >> "$(TMP_ORIG)"; \
			echo "    time=$$R"; \
		done; \
	fi

bench_pngs: png2pep_all_mod png2pep_all_orig

# Dry-run benchmarking (memory-only, no file I/O)
png2pep_all_mod_dry: 
	@rm -f "$(TMP_MOD)" && echo "file,time" > "$(TMP_MOD)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="/dev/null"; \
			echo "[MOD-DRY] $$f"; \
			tmp=`mktemp -t pepbench.XXXXXX`; \
			$(PYTHON) $(BENCH) ./pepr_mod "$$f" "$$out" $(RUNS) $(WARMUP) --dry-run > "$$tmp"; \
			R=`cat "$$tmp"`; rm -f "$$tmp"; \
			echo "$$f,$$R" >> "$(TMP_MOD)"; \
			echo "    time=$$R (memory-only)"; \
		done; \
	fi

png2pep_all_orig_dry: 
	@rm -f "$(TMP_ORIG)" && echo "file,time" > "$(TMP_ORIG)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="/dev/null"; \
			echo "[ORIG-DRY] $$f"; \
			tmp=`mktemp -t pepbench.XXXXXX`; \
			$(PYTHON) $(BENCH) ./pepr_orig "$$f" "$$out" $(RUNS) $(WARMUP) --dry-run > "$$tmp"; \
			R=`cat "$$tmp"`; rm -f "$$tmp"; \
			echo "$$f,$$R" >> "$(TMP_ORIG)"; \
			echo "    time=$$R (memory-only)"; \
		done; \
	fi

bench_pngs_dry: png2pep_all_mod_dry png2pep_all_orig_dry
	@echo "file,mod_dry,orig_dry,diff,speedup_pct" > "$(CSV)"
	@tail -n +2 "$(TMP_MOD)" | sort -t, -k1,1 > .mod.sorted || true
	@tail -n +2 "$(TMP_ORIG)" | sort -t, -k1,1 > .orig.sorted || true
	@join -t, -a1 -a2 -e '' -o 1.1,1.2,2.2 .mod.sorted .orig.sorted > .joined || true
	@while IFS=, read -r f rn ro; do \
		bn=$$(basename "$$f" ".png"); \
		awk -v f="$$bn" -v rn="$$rn" -v ro="$$ro" 'BEGIN{ \
		  drn = (rn==""? "" : sprintf("%.9f", rn)); \
		  dro = (ro==""? "" : sprintf("%.9f", ro)); \
		  dt  = (ro!="" && rn!=""? sprintf("%.9f", ro-rn) : ""); \
		  sp  = (rn!="" && ro!="" && rn+0>0? sprintf("%.2f", (ro-rn)/rn*100) : ""); \
		  printf "%s,%s,%s,%s,%s\n", f, drn, dro, dt, sp; \
		}' >> "$(CSV)"; \
	done < .joined
	@rm -f "$(TMP_MOD)" "$(TMP_ORIG)" .mod.sorted .orig.sorted .joined
	@echo "Created $(CSV) with dry-run timings (memory-only, no file I/O)"

# ---------- Batch convert all images/*.pep to images/*.bmp & rle ----------
IMAGES_PEPS := $(wildcard ./images/*.pep)

pep2bmp_all: pepr_mod
	@if [ -z "$(IMAGES_PEPS)" ]; then \
		echo "No PEP files found in images/"; \
	else \
		set -e; \
		for f in $(IMAGES_PEPS); do \
			out="$${f%.pep}.bmp"; \
			echo "[PEP→BMP] $$f -> $$out"; \
			./pepr_mod --to-bmp "$$f" "$$out" >/dev/null; \
		done; \
	fi

pep2rle_all: pepr_mod
	@if [ -z "$(IMAGES_PEPS)" ]; then \
		echo "No PEP files found in images/"; \
	else \
		set -e; \
		for f in $(IMAGES_PEPS); do \
			out="$${f%.pep}.rle"; \
			echo "[PEP→RLE] $$f -> $$out"; \
			./pepr_mod --to-rle-bmp "$$f" "$$out" >/dev/null; \
		done; \
	fi

pep2bmp: pepr_mod $(PEP_OUT)
	./pepr_mod --to-bmp $(PEP_OUT) $(BMP_OUT)
	@echo "Wrote $(BMP_OUT)"

.PHONY: clean
clean:
	rm -f pepr pepr_mod pepr_orig pepr_pgo pepr_pgo_gen $(DEMO_OUT) $(PEP_OUT) $(BMP_OUT) "$(CSV)" "$(TMP_MOD)" "$(TMP_ORIG)" .mod.sorted .orig.sorted .joined
	rm -rf "$(BUILD_DIR)"
