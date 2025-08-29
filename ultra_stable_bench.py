#!/usr/bin/env python3
"""
Ultra-stable benchmarking with system monitoring and outlier detection.
This version addresses remaining variance sources beyond thermal management.
"""

import argparse
import subprocess
import time
import sys
import tempfile
import os
import statistics
import platform
try:
    import psutil
except Exception:
    psutil = None

def get_system_load():
    """Get current system CPU load and memory usage"""
    # CPU percent
    if psutil is not None:
        try:
            cpu_percent = psutil.cpu_percent(interval=0.1)
        except Exception:
            cpu_percent = 0.0
    else:
        cpu_percent = 0.0
    # Memory percent
    if psutil is not None:
        try:
            memory_percent = psutil.virtual_memory().percent
        except Exception:
            memory_percent = 0.0
    else:
        memory_percent = 0.0
    # Load average
    try:
        load_avg = os.getloadavg()[0]
    except Exception:
        load_avg = 0.0
    return cpu_percent, memory_percent, load_avg

def wait_for_system_stability(max_cpu=10.0, max_load=1.0, max_wait=30.0, poll_interval=2.0):
    """Wait for system to be idle enough for stable benchmarking"""
    print("Waiting for system stability...", file=sys.stderr)
    start_wait = time.time()
    
    while time.time() - start_wait < max_wait:
        cpu_pct, mem_pct, load_avg = get_system_load()
        
        if cpu_pct < max_cpu and load_avg < max_load:
            print(f"System stable: CPU={cpu_pct:.1f}%, Load={load_avg:.2f}", file=sys.stderr)
            return True
            
        print(f"Waiting... CPU={cpu_pct:.1f}%, Load={load_avg:.2f}", file=sys.stderr)
        time.sleep(poll_interval)
    
    print(f"Warning: System stability timeout. Proceeding anyway.", file=sys.stderr)
    return False

def run_ultra_stable(cmd, runs, warmup=5, *,
                     max_cpu=10.0,
                     max_load=1.0,
                     stability_timeout=30.0,
                     poll_interval=2.0,
                     warmup_sleep=4.0,
                     between_runs_sleep=4.0,
                     quick_runs=3,
                     quick_sleep=0.5):
    """Run with maximum stability measures"""
    devnull = subprocess.DEVNULL
    all_times = []
    
    # Extended warmup with system monitoring
    print(f"Running {warmup} warmup iterations with system monitoring...", file=sys.stderr)
    for i in range(warmup):
        wait_for_system_stability(max_cpu=max_cpu, max_load=max_load, max_wait=stability_timeout, poll_interval=poll_interval)
        subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
        time.sleep(warmup_sleep)
    
    # Main timing runs with outlier detection
    print(f"Running {runs} timing iterations with outlier detection...", file=sys.stderr)
    
    for i in range(runs):
        wait_for_system_stability(max_cpu=max_cpu, max_load=max_load, max_wait=stability_timeout, poll_interval=poll_interval)
        
        # Take multiple quick measurements and use median
        quick_times = []
        for _ in range(max(1, int(quick_runs))):  # quick runs per measurement
            t0 = time.perf_counter()
            subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
            t1 = time.perf_counter()
            quick_times.append(t1 - t0)
            time.sleep(quick_sleep)
        
        # Use median of quick runs as the measurement
        median_time = statistics.median(quick_times)
        all_times.append(median_time)
        
        print(f"Run {i+1}: {median_time:.9f}s (range: {min(quick_times):.9f}-{max(quick_times):.9f})", file=sys.stderr)
        time.sleep(between_runs_sleep)
    
    # Outlier detection using IQR method
    if len(all_times) >= 5:
        sorted_times = sorted(all_times)
        n = len(sorted_times)
        q1 = sorted_times[n//4]
        q3 = sorted_times[3*n//4]
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        
        filtered_times = [t for t in all_times if lower_bound <= t <= upper_bound]
        
        if len(filtered_times) != len(all_times):
            outliers = [t for t in all_times if t < lower_bound or t > upper_bound]
            print(f"Removed {len(outliers)} outliers: {outliers}", file=sys.stderr)
            all_times = filtered_times
    
    return all_times

def main():
    parser = argparse.ArgumentParser(description="Ultra-stable benchmarking")
    parser.add_argument("binary")
    parser.add_argument("image")
    parser.add_argument("out")
    parser.add_argument("runs", type=int)
    parser.add_argument("warmup", type=int)
    parser.add_argument("--dry-run", action="store_true",
                      help="Use memory-only mode")
    parser.add_argument("--stats", action="store_true",
                      help="Show detailed statistics")
    # Tuning flags
    parser.add_argument("--max-cpu", type=float, default=10.0)
    parser.add_argument("--max-load", type=float, default=1.0)
    parser.add_argument("--stability-timeout", type=float, default=30.0)
    parser.add_argument("--poll-interval", type=float, default=2.0)
    parser.add_argument("--warmup-sleep", type=float, default=4.0)
    parser.add_argument("--between-runs-sleep", type=float, default=4.0)
    parser.add_argument("--quick-runs", type=int, default=3)
    parser.add_argument("--quick-sleep", type=float, default=0.5)
    args = parser.parse_args()

    runs = max(args.runs, 1)
    warmup = max(args.warmup, 5)
    
    if args.dry_run:
        cmd = [args.binary, "--dry-run", args.image]
        times = run_ultra_stable(
            cmd,
            runs,
            warmup,
            max_cpu=args.max_cpu,
            max_load=args.max_load,
            stability_timeout=args.stability_timeout,
            poll_interval=args.poll_interval,
            warmup_sleep=args.warmup_sleep,
            between_runs_sleep=args.between_runs_sleep,
            quick_runs=args.quick_runs,
            quick_sleep=args.quick_sleep,
        )
        
        # Create output file for compatibility
        if args.out != "/dev/null":
            devnull = subprocess.DEVNULL
            final_cmd = [args.binary, "--image", args.image, args.out]
            subprocess.run(final_cmd, stdout=devnull, stderr=devnull, check=False)
    else:
        print("File I/O mode not implemented in ultra-stable version", file=sys.stderr)
        return 1
    
    if not times:
        print("No valid timing data collected", file=sys.stderr)
        return 1
    
    # Calculate statistics
    mean_time = statistics.mean(times)
    median_time = statistics.median(times)
    stdev = statistics.stdev(times) if len(times) > 1 else 0.0
    min_time = min(times)
    max_time = max(times)
    cv = (stdev / mean_time * 100) if mean_time > 0 else 0.0  # Coefficient of variation
    
    if args.stats:
        print(f"Ultra-Stable Results:", file=sys.stderr)
        print(f"Mean: {mean_time:.9f}s", file=sys.stderr)
        print(f"Median: {median_time:.9f}s", file=sys.stderr)
        print(f"StdDev: {stdev:.9f}s ({cv:.1f}%)", file=sys.stderr)
        print(f"Min: {min_time:.9f}s", file=sys.stderr)
        print(f"Max: {max_time:.9f}s", file=sys.stderr)
        print(f"Range: {max_time - min_time:.9f}s", file=sys.stderr)
        print(f"Samples: {len(times)} (after outlier removal)", file=sys.stderr)
        
        # Quality assessment
        if cv < 3.0:
            quality = "EXCELLENT"
        elif cv < 5.0:
            quality = "GOOD"  
        elif cv < 10.0:
            quality = "FAIR"
        else:
            quality = "POOR"
        print(f"Quality: {quality}", file=sys.stderr)
        
        sys.stdout.write(f"{median_time:.9f}\n")
    else:
        sys.stdout.write(f"{mean_time:.9f}\n")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
