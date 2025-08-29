#!/bin/bash
# Comprehensive benchmarking script using thermal-aware methodology
# This script will generate accurate timing comparisons for all test images

set -e

SCRIPT_DIR="/Users/matt/Downloads/2025-08-25/PEP"
BENCH_SCRIPT="$SCRIPT_DIR/ultra_stable_bench.py"

# Select which optimized binary to benchmark against the baseline.
# Set to either: pepr_mod or pepr_pgo
ACTIVE_MOD_BIN="pepr_mod"

# Resolved paths
PEPR_MOD="$SCRIPT_DIR/$ACTIVE_MOD_BIN"
PEPR_ORIG="$SCRIPT_DIR/pepr_orig"
IMAGES_DIR="$SCRIPT_DIR/images"
OUTPUT_FILE="benchmark_results_${ACTIVE_MOD_BIN}.csv"

# Benchmarking parameters  
RUNS=5           # Optimal balance of accuracy vs time
WARMUP=2         # More warmup for stability
USE_STATS=true   # Get detailed statistics

# Ultra-stable tuning for comprehensive run (further relaxed for speed)
MAX_CPU=60.0
MAX_LOAD=6.0
STABILITY_TIMEOUT=3.0
POLL_INTERVAL=0.5
WARMUP_SLEEP=0.5
BETWEEN_SLEEP=0.5
QUICK_RUNS=0
QUICK_SLEEP=0.1

# Portable file size helper
filesize() {
  local path="$1"
  if command -v stat >/dev/null 2>&1; then
    # macOS uses -f%z, GNU uses -c%s
    size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo "")
    echo "$size"
  else
    wc -c < "$path" 2>/dev/null | tr -d ' '
  fi
}

echo "=== $ACTIVE_MOD_BIN Comprehensive Benchmark ==="
echo "Comparing $ACTIVE_MOD_BIN vs original baseline."
echo "This will provide accurate performance measurements."
echo ""
echo "Parameters:"
echo "- Runs per test: $RUNS"
echo "- Warmup runs: $WARMUP" 
# shellcheck disable=SC2016

echo "- Thermal management: Enabled"
echo "- Statistical analysis: Enabled"
echo ""

# Create output file with header
echo "file,bmp_size,pep_size,mod_median,orig_median,diff,speedup_pct,mod_stddev_pct,orig_stddev_pct,confidence" > "$OUTPUT_FILE"

# Get list of BMP images
images=($(find "$IMAGES_DIR" -name "*.bmp" | sort))

if [ ${#images[@]} -eq 0 ]; then
    echo "Error: No BMP images found in $IMAGES_DIR"
    exit 1
fi

echo "Found ${#images[@]} images to benchmark"
echo ""

total_tests=$((${#images[@]} * 2))
current_test=0

for img_path in "${images[@]}"; do
    img_name=$(basename "$img_path" .bmp)
    echo "=== Testing: $img_name ==="
    
    # Test modified version
    echo "[$((current_test + 1))/$total_tests] Running $ACTIVE_MOD_BIN version..."
    mod_output=$(python3 "$BENCH_SCRIPT" "$PEPR_MOD" "$img_path" "/tmp/out.pep" "$RUNS" "$WARMUP" --dry-run --stats \
      --max-cpu "$MAX_CPU" --max-load "$MAX_LOAD" --stability-timeout "$STABILITY_TIMEOUT" \
      --poll-interval "$POLL_INTERVAL" --warmup-sleep "$WARMUP_SLEEP" --between-runs-sleep "$BETWEEN_SLEEP" \
      --quick-runs "$QUICK_RUNS" --quick-sleep "$QUICK_SLEEP" 2>&1)
    mod_median=$(echo "$mod_output" | tail -1)
    
    # Extract statistics from output (more robust)
    mod_stddev_pct=$(echo "$mod_output" | grep "StdDev:" | grep -o '([0-9.]*%)' | tr -d '()')
    
    # Debug output
    echo "  $ACTIVE_MOD_BIN result: $mod_median (±$mod_stddev_pct)"
    
    current_test=$((current_test + 1))
    
    # Test original version  
    echo "[$((current_test + 1))/$total_tests] Running orig version..."
    orig_output=$(python3 "$BENCH_SCRIPT" "$PEPR_ORIG" "$img_path" "/tmp/out.pep" "$RUNS" "$WARMUP" --dry-run --stats \
      --max-cpu "$MAX_CPU" --max-load "$MAX_LOAD" --stability-timeout "$STABILITY_TIMEOUT" \
      --poll-interval "$POLL_INTERVAL" --warmup-sleep "$WARMUP_SLEEP" --between-runs-sleep "$BETWEEN_SLEEP" \
      --quick-runs "$QUICK_RUNS" --quick-sleep "$QUICK_SLEEP" 2>&1)
    orig_median=$(echo "$orig_output" | tail -1)
    
    # Extract statistics from output
    orig_stddev_pct=$(echo "$orig_output" | grep "StdDev:" | grep -o '([0-9.]*%)' | tr -d '()')
    
    current_test=$((current_test + 1))
    
    # Calculate sizes
    bmp_size=$(filesize "$img_path")
    pep_size=""
    if [ -f "/tmp/out.pep" ]; then
      pep_size=$(filesize "/tmp/out.pep")
    fi
    
    # Calculate difference and speedup
    diff=$(python3 -c "print(f'{float(\"$orig_median\") - float(\"$mod_median\"):.9f}')")
    speedup_pct=$(python3 -c "print(f'{(float(\"$orig_median\") - float(\"$mod_median\")) / float(\"$orig_median\") * 100:.2f}')")
    
    # Determine confidence level based on standard deviation (with error handling)
    if [[ -n "$mod_stddev_pct" && -n "$orig_stddev_pct" ]]; then
        # Remove % symbols for calculation
        mod_num="${mod_stddev_pct%\%}"
        orig_num="${orig_stddev_pct%\%}"
        
        # Calculate max stddev using Python for better error handling
        max_stddev=$(python3 -c "
try:
    mod_val = float('$mod_num') if '$mod_num' else 999.0
    orig_val = float('$orig_num') if '$orig_num' else 999.0  
    print(max(mod_val, orig_val))
except ValueError:
    print(999.0)  # Default to high value if parsing fails
")
        
        # Determine confidence based on max stddev (more realistic thresholds)
        if (( $(echo "$max_stddev < 7.0" | bc -l) )); then
            confidence="HIGH"
        elif (( $(echo "$max_stddev < 15.0" | bc -l) )); then
            confidence="MEDIUM"
        else
            confidence="LOW"
        fi
        
        echo "  Max StdDev: $max_stddev% -> Confidence: $confidence"
    else
        confidence="UNKNOWN"
        echo "  Warning: Could not extract standard deviation percentages"
        echo "  mod_stddev_pct='$mod_stddev_pct', orig_stddev_pct='$orig_stddev_pct'"
    fi
    
    # Write to CSV
    echo "$img_name,$bmp_size,$pep_size,$mod_median,$orig_median,$diff,$speedup_pct,$mod_stddev_pct,$orig_stddev_pct,$confidence" >> "$OUTPUT_FILE"
    
    echo "  BMP size: ${bmp_size} bytes"
    echo "  PEP size: ${pep_size} bytes"
    echo "  Modified: ${mod_median}s (±${mod_stddev_pct})"
    echo "  Original: ${orig_median}s (±${orig_stddev_pct})"
    echo "  Speedup: ${speedup_pct}% (confidence: $confidence)"
    echo ""
done

echo "=== Benchmark Complete ==="
echo "Results written to: $OUTPUT_FILE"
echo ""
echo "Summary statistics:"
python3 - "$OUTPUT_FILE" << 'PY'
import csv, sys, statistics
path = sys.argv[1]
rows = []
with open(path, newline='') as f:
    r = csv.DictReader(f)
    for row in r:
        try:
            rows.append({
                'speedup': float(row['speedup_pct']),
                'confidence': row['confidence'],
            })
        except Exception:
            pass
n = len(rows)
vals = [x['speedup'] for x in rows]
print(f'Total images tested: {n}')
if n:
    avg = sum(vals)/n
    med = statistics.median(vals)
    hi = max(vals)
    lo = min(vals)
    high_conf = sum(1 for x in rows if x['confidence'] == 'HIGH')
    positives = sum(1 for v in vals if v > 0)
    print(f'Average speedup: {avg:.2f}%')
    print(f'Median speedup: {med:.2f}%')
    print(f'High confidence results: {high_conf}')
    print(f'Positive speedups: {positives}')
    print(f'Max speedup: {hi:.2f}%')
    print(f'Min speedup: {lo:.2f}%')
PY

echo ""
echo "$ACTIVE_MOD_BIN results saved to: $OUTPUT_FILE"
echo "This compares $ACTIVE_MOD_BIN vs pepr_orig (baseline)"
