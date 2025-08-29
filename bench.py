#!/usr/bin/env python3
import argparse
import subprocess
import time
import sys
import tempfile
import os
import statistics
import platform

def get_cpu_temp():
    """Get CPU temperature if available (macOS/Linux)"""
    try:
        if platform.system() == "Darwin":  # macOS
            # Try alternative temperature sensors that don't require sudo
            try:
                # Try iostat for thermal pressure (doesn't require sudo)
                result = subprocess.run(["iostat", "-c", "1"], capture_output=True, text=True, timeout=3)
                # If iostat works, we'll use load-based thermal estimation
                # This is a fallback - not as accurate but doesn't need sudo
                pass
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                pass
            
            # For now, disable sudo requirement and use load-based estimation
            # Users can enable proper temp monitoring by running: sudo powermetrics in background
            return None  # Fallback to fixed delays
        elif platform.system() == "Linux":
            # Try thermal_zone sensors
            for i in range(10):
                try:
                    with open(f"/sys/class/thermal/thermal_zone{i}/temp") as f:
                        temp = int(f.read()) / 1000.0
                        return temp
                except (OSError, ValueError):
                    continue
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError, FileNotFoundError):
        pass
    return None

def wait_for_thermal_stability(target_temp_diff=5.0, max_wait=60.0):
    """Wait for CPU to cool down to avoid thermal throttling"""
    initial_temp = get_cpu_temp()
    if initial_temp is None:
        # Fallback to adaptive delay based on system load
        time.sleep(3.0)  # More conservative delay without temperature monitoring
        return
    
    print(f"Initial CPU temp: {initial_temp:.1f}°C", file=sys.stderr)
    start_wait = time.time()
    
    while time.time() - start_wait < max_wait:
        time.sleep(1.0)
        current_temp = get_cpu_temp()
        if current_temp is None:
            break
        
        temp_diff = initial_temp - current_temp
        if temp_diff >= target_temp_diff:
            print(f"CPU cooled to {current_temp:.1f}°C (Δ{temp_diff:.1f}°C)", file=sys.stderr)
            return
    
    current_temp = get_cpu_temp()
    if current_temp:
        print(f"Timeout waiting for cooling. Current temp: {current_temp:.1f}°C", file=sys.stderr)

def run_with_stats(cmd, runs, warmup=7, use_thermal_management=True):
    """Run command multiple times and return timing statistics"""
    devnull = subprocess.DEVNULL
    
    # Warmup runs
    print(f"Running {warmup} warmup iterations...", file=sys.stderr)
    for i in range(warmup):
        subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
        if use_thermal_management and i < warmup - 1:
            wait_for_thermal_stability()
    
    # Main timing runs
    print(f"Running {runs} timing iterations...", file=sys.stderr)
    times = []
    
    for i in range(runs):
        if use_thermal_management:
            wait_for_thermal_stability()
        
        t0 = time.perf_counter()
        subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
        t1 = time.perf_counter()
        
        elapsed = t1 - t0
        times.append(elapsed)
        print(f"Run {i+1}: {elapsed:.9f}s", file=sys.stderr)
    
    return times

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("image")
    parser.add_argument("out")
    parser.add_argument("runs", type=int)
    parser.add_argument("warmup", type=int)
    parser.add_argument("--delay", type=float, default=3.0, 
                      help="Delay between runs in seconds (default: 3.0 for thermal management)")
    parser.add_argument("--dry-run", action="store_true",
                      help="Use memory-only mode (no file I/O) for pure computation timing")
    parser.add_argument("--no-thermal", action="store_true",
                      help="Disable thermal management (use fixed delays)")
    parser.add_argument("--stats", action="store_true",
                      help="Output detailed statistics instead of just mean")
    args = parser.parse_args()
    
    use_thermal_mgmt = not args.no_thermal
    runs = max(args.runs, 1)
    warmup = max(args.warmup, 0)
    
    if args.dry_run:
        # Pure computation timing - no file I/O at all
        cmd = [args.binary, "--dry-run", args.image]
        
        if use_thermal_mgmt:
            times = run_with_stats(cmd, runs, warmup, use_thermal_management=True)
        else:
            # Fallback to original simple approach with fixed delays
            devnull = subprocess.DEVNULL
            for _ in range(warmup):
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                if args.delay > 0:
                    time.sleep(args.delay)
            
            times = []
            for _ in range(runs):
                t0 = time.perf_counter()
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                t1 = time.perf_counter()
                times.append(t1 - t0)
                if args.delay > 0:
                    time.sleep(args.delay)
        
        # Still create the final output file for compatibility if needed
        if args.out != "/dev/null":
            devnull = subprocess.DEVNULL
            final_cmd = [args.binary, "--image", args.image, args.out]
            subprocess.run(final_cmd, stdout=devnull, stderr=devnull, check=False)
    else:
        # File I/O mode with temp files to avoid cache pollution
        def make_file_cmd():
            tf = tempfile.NamedTemporaryFile(suffix=".pep", delete=False)
            temp_out = tf.name
            tf.close()  # Close immediately to avoid conflicts
            cmd = [args.binary, "--image", args.image, temp_out]
            return cmd, temp_out
        
        if use_thermal_mgmt:
            # Thermal-managed approach
            devnull = subprocess.DEVNULL
            
            # Warmup runs
            print(f"Running {warmup} warmup iterations...", file=sys.stderr)
            for i in range(warmup):
                cmd, temp_out = make_file_cmd()
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                try:
                    os.unlink(temp_out)
                except OSError:
                    pass
                if use_thermal_mgmt and i < warmup - 1:
                    wait_for_thermal_stability()
            
            # Timing runs
            print(f"Running {runs} timing iterations...", file=sys.stderr)
            times = []
            for i in range(runs):
                if use_thermal_mgmt:
                    wait_for_thermal_stability()
                
                cmd, temp_out = make_file_cmd()
                t0 = time.perf_counter()
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                t1 = time.perf_counter()
                
                try:
                    os.unlink(temp_out)
                except OSError:
                    pass
                
                elapsed = t1 - t0
                times.append(elapsed)
                print(f"Run {i+1}: {elapsed:.9f}s", file=sys.stderr)
        else:
            # Original approach with fixed delays
            devnull = subprocess.DEVNULL
            for _ in range(warmup):
                cmd, temp_out = make_file_cmd()
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                try:
                    os.unlink(temp_out)
                except OSError:
                    pass
                if args.delay > 0:
                    time.sleep(args.delay)
            
            times = []
            for _ in range(runs):
                cmd, temp_out = make_file_cmd()
                t0 = time.perf_counter()
                subprocess.run(cmd, stdout=devnull, stderr=devnull, check=False)
                t1 = time.perf_counter()
                
                try:
                    os.unlink(temp_out)
                except OSError:
                    pass
                
                times.append(t1 - t0)
                if args.delay > 0:
                    time.sleep(args.delay)
        
        # Create the final output file for compatibility
        devnull = subprocess.DEVNULL
        final_cmd = [args.binary, "--image", args.image, args.out]
        subprocess.run(final_cmd, stdout=devnull, stderr=devnull, check=False)
    
    # Output statistics
    if args.stats:
        mean_time = statistics.mean(times)
        median_time = statistics.median(times)
        stdev = statistics.stdev(times) if len(times) > 1 else 0.0
        min_time = min(times)
        max_time = max(times)
        
        print(f"Mean: {mean_time:.9f}s", file=sys.stderr)
        print(f"Median: {median_time:.9f}s", file=sys.stderr)
        print(f"StdDev: {stdev:.9f}s ({stdev/mean_time*100:.1f}%)", file=sys.stderr)
        print(f"Min: {min_time:.9f}s", file=sys.stderr)
        print(f"Max: {max_time:.9f}s", file=sys.stderr)
        print(f"Range: {max_time - min_time:.9f}s", file=sys.stderr)
        
        # Use median instead of mean for more robust results
        sys.stdout.write(f"{median_time:.9f}")
    else:
        avg = statistics.mean(times)
        sys.stdout.write(f"{avg:.9f}")
    
    return 0

if __name__ == "__main__":
    raise SystemExit(main())


