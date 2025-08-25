# Makefile for PEP CLI on macOS
# Usage:
#   make            # build pepr
#   make demo       # build and write demo.pep
#   make png2pep    # convert mushroom.png → mushroom.pep
#   make tif2pep    # convert mushroom.tif → mushroom.pep
#   make png2pep_all         # convert all png/*.png with pepr (timed per file)
#   make png2pep_all_noopt   # convert all png/*.png with pepr_noopt (timed per file)
#   make bench_pngs          # run both of the above
#   make pep2bmp    # convert mushroom.pep → mushroom.bmp
#   make clean

CC := clang
CFLAGS ?= -std=c11 -O3 -march=native -mtune=native -flto -funroll-loops -ffast-math -DNDEBUG
LDFLAGS ?= -flto
FRAMEWORKS := -framework CoreFoundation -framework CoreGraphics -framework ImageIO
CSV := timings.csv
TMP_OPT := .timings_opt.csv
TMP_NOOPT := .timings_noopt.csv

all: pepr pepr_noopt demo png2pep pep2bmp

pepr: pepr.c PEP.h
	$(CC) $(CFLAGS) pepr.c -o $@ $(LDFLAGS) $(FRAMEWORKS)

# No-optimization build (separate binary)
NOOPT_CFLAGS := -std=c11 -O0 -g
NOOPT_LDFLAGS :=
.PHONY: pepr_noopt noopt

pepr_noopt: pepr.c PEP.h
	$(CC) $(NOOPT_CFLAGS) pepr.c -o $@ $(NOOPT_LDFLAGS) $(FRAMEWORKS)

noopt: pepr_noopt

# Demo target using built-in generator
DEMO_OUT := demo.pep
.PHONY: demo

demo: pepr
	./pepr --demo $(DEMO_OUT)
	@echo "Wrote $(DEMO_OUT)"

# PNG → PEP conversion target
PNG := images/mushroom.png
PEP_OUT := images/mushroom.pep
.PHONY: convert

png2pep: pepr $(PNG)
	./pepr --png $(PNG) $(PEP_OUT)
	@echo "Wrote $(PEP_OUT)"

# TIFF → PEP using --image (generic ImageIO)
TIF := images/mushroom.tif
.PHONY: tif2pep

tif2pep: pepr $(TIF)
	./pepr --image $(TIF) $(PEP_OUT)
	@echo "Wrote $(PEP_OUT) from TIFF"

# ---------- Batch convert all PNGs in png/ directory ----------
PNGS := $(wildcard images/*.png)
.PHONY: png2pep_all png2pep_all_noopt bench_pngs pep2bmp_all

png2pep_all: 
	@rm -f "$(TMP_OPT)" && echo "file,real" > "$(TMP_OPT)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="$${f%.png}.pep"; \
			echo "[OPT] $$f -> $$out"; \
			total=0; \
			for i in 1 2 3 4 5 6 7 8 9 10 11 12; do \
				T=$$( ( /usr/bin/time -p ./pepr --image "$$f" "$$out" 1>/dev/null ) 2>&1 || true ); \
				r=$$(echo "$$T" | awk '/^real /{print $$2}'); \
				[ -z "$$r" ] && r=0; \
				total=$$(awk -v a="$$total" -v b="$$r" 'BEGIN{printf "%.6f", (a+0)+(b+0)}'); \
			done; \
			R=$$(awk -v s="$$total" 'BEGIN{printf "%.6f", (s+0)/10.0}'); \
			echo "$$f,$$R" >> "$(TMP_OPT)"; \
			echo "    real=$$R"; \
		done; \
	fi

png2pep_all_noopt: 
	@rm -f "$(TMP_NOOPT)" && echo "file,real" > "$(TMP_NOOPT)"
	@if [ -z "$(PNGS)" ]; then \
		echo "No PNGs found in images/"; \
	else \
		set -e; \
		for f in $(PNGS); do \
			out="$${f%.png}.pep"; \
			echo "[NOOPT] $$f -> $$out"; \
			total=0; \
			for i in 1 2 3 4 5 6 7 8 9 10; do \
				T=$$( ( /usr/bin/time -p ./pepr_noopt --image "$$f" "$$out" 1>/dev/null ) 2>&1 || true ); \
				r=$$(echo "$$T" | awk '/^real /{print $$2}'); \
				[ -z "$$r" ] && r=0; \
				total=$$(awk -v a="$$total" -v b="$$r" 'BEGIN{printf "%.6f", (a+0)+(b+0)}'); \
			done; \
			R=$$(awk -v s="$$total" 'BEGIN{printf "%.6f", (s+0)/10.0}'); \
			echo "$$f,$$R" >> "$(TMP_NOOPT)"; \
			echo "    real=$$R"; \
		done; \
	fi

bench_pngs: png2pep_all png2pep_all_noopt
	@echo "file,noopt,opt,diff,speedup,bmp,%bmp,rle,%rle,%png,png,pep" > "$(CSV)"
	@tail -n +2 "$(TMP_OPT)" | sort -t, -k1,1 > .opt.sorted || true
	@tail -n +2 "$(TMP_NOOPT)" | sort -t, -k1,1 > .noopt.sorted || true
	@join -t, -a1 -a2 -e '' -o 1.1,1.2,2.2 .opt.sorted .noopt.sorted > .joined || true
	@while IFS=, read -r f ro rn; do \
		pngb=$$(stat -f%z "$$f" 2>/dev/null || echo ""); \
		bn=$$(basename "$$f" ".png"); \
		pepf="$${f%.png}.pep"; \
		pepb=$$(stat -f%z "$$pepf" 2>/dev/null || echo ""); \
		bmpf="$${f%.png}.bmp"; \
		if [ ! -f "$$bmpf" ] && [ -f "$$pepf" ]; then ./pepr --to-bmp "$$pepf" "$$bmpf" >/dev/null 2>&1 || true; fi; \
		bmpb=$$(stat -f%z "$$bmpf" 2>/dev/null || echo ""); \
		rlef="$${f%.png}.rle"; \
		if [ ! -f "$$rlef" ] && [ -f "$$pepf" ]; then ./pepr --to-rle-bmp "$$pepf" "$$rlef" >/dev/null 2>&1 || true; fi; \
		rleb=$$(stat -f%z "$$rlef" 2>/dev/null || echo ""); \
		awk -v f="$$bn" -v rn="$$rn" -v ro="$$ro" -v pngb="$$pngb" -v pepb="$$pepb" -v bmpb="$$bmpb" -v rleb="$$rleb" 'BEGIN{ \
		  dro = (ro==""? "" : sprintf("%.2f", ro)); \
		  drn = (rn==""? "" : sprintf("%.2f", rn)); \
		  dt  = (ro!="" && rn!=""? ((rn-ro)>0? (rn-ro):0) : ""); \
		  sp  = (rn!="" && rn+0>0 && ro!=""? (rn-ro)/rn*100 : ""); \
		  szp_png = (pngb!="" && pngb+0>0 && pepb!=""? (pepb/pngb)*100 : ""); \
		  szp_bmp = (bmpb!="" && bmpb+0>0 && pepb!=""? (pepb/bmpb)*100 : ""); \
		  szp_rle = (rleb!="" && rleb+0>0 && pepb!=""? (pepb/rleb)*100 : ""); \
		  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", f, drn, dro, (dt==""? "": sprintf("%.2f", dt)), (sp==""? "": sprintf("%.2f", sp)), bmpb, (szp_bmp==""? "": sprintf("%.2f", szp_bmp)), rleb, (szp_rle==""? "": sprintf("%.2f", szp_rle)), (szp_png==""? "": sprintf("%.2f", szp_png)), pngb, pepb; }' >> "$(CSV)"; \
	done < .joined
	@rm -f "$(TMP_OPT)" "$(TMP_NOOPT)" .opt.sorted .noopt.sorted .joined

# ---------- Batch convert all images/*.pep to images/*.bmp & rle ----------
IMAGES_PEPS := $(wildcard images/*.pep)

pep2bmp_all: pepr
	@if [ -z "$(IMAGES_PEPS)" ]; then \
		echo "No PEP files found in images/"; \
	else \
		set -e; \
		for f in $(IMAGES_PEPS); do \
			out="$${f%.pep}.bmp"; \
			echo "[PEP→BMP] $$f -> $$out"; \
			./pepr --to-bmp "$$f" "$$out" >/dev/null; \
		done; \
	fi

pep2rle_all: pepr
	@if [ -z "$(IMAGES_PEPS)" ]; then \
		echo "No PEP files found in images/"; \
	else \
		set -e; \
		for f in $(IMAGES_PEPS); do \
			out="$${f%.pep}.rle"; \
			echo "[PEP→RLE] $$f -> $$out"; \
			./pepr --to-rle-bmp "$$f" "$$out" >/dev/null; \
		done; \
	fi

# PEP → BMP conversion target
BMP_OUT := png/mushroom.bmp
.PHONY: pep2bmp

pep2bmp: pepr $(PEP_OUT)
	./pepr --to-bmp $(PEP_OUT) $(BMP_OUT)
	@echo "Wrote $(BMP_OUT)"

.PHONY: clean
clean:
	rm -f pepr $(DEMO_OUT) $(PEP_OUT) $(BMP_OUT) "$(CSV)" "$(TMP_OPT)" "$(TMP_NOOPT)" .opt.sorted .noopt.sorted
