# Thermal-Aware Benchmarking Guide

## Problem Summary

Your original issue: **"More runs = worse timing accuracy"** was caused by **CPU thermal throttling**.

### What Was Happening:
- Short delays (0.001s) between runs
- CPU heating up during sustained computation
- Progressive performance degradation
- Inconsistent relative performance measurements
- Artificially inflated speedup percentages with more runs

## Solution: Enhanced Thermal-Aware Benchmarking

### Key Improvements:
1. **Thermal Management**: 2.0s delays between runs (vs 0.001s)
2. **Individual Run Timing**: Each run timed separately (vs bulk timing)
3. **Statistical Analysis**: Mean, median, std dev, min/max reporting
4. **Temperature Monitoring**: Adaptive cooling delays when available

## Usage Examples

### Recommended Approach (Thermal-Managed):
```bash
# Basic thermal-managed benchmarking
python3 bench.py pepr_mod images/castle.bmp output.pep 5 2 --dry-run --stats

# With custom delays
python3 bench.py pepr_mod images/castle.bmp output.pep 5 2 --dry-run --stats --delay 3.0
```

### Legacy Approach (For Comparison Only):
```bash
# Fixed-delay (not recommended for accurate measurements)
python3 bench.py pepr_mod images/castle.bmp output.pep 5 2 --dry-run --no-thermal --delay 0.1
```

## Test Results Analysis

Your test results proved the thermal issue:

| Approach | Speedup | Consistency | Recommendation |
|----------|---------|-------------|----------------|
| **Thermal-Managed** | **+4.97%** | ✅ Low variance (4-8%) | **Use this** |
| Fixed-Delay | -1.45% | ❌ High variance (11%) | Avoid |

## Best Practices

### For Accurate Measurements:
1. **Use fewer runs with proper spacing** (5-10 runs with 2s+ delays)
2. **Always use `--stats` flag** to monitor variance
3. **Use `--dry-run`** to eliminate I/O noise
4. **Look for <10% standard deviation** as quality indicator
5. **Use median instead of mean** for outlier resistance

### For Development Workflow:
```bash
# Quick development test (single run)
python3 bench.py pepr_mod images/castle.bmp /dev/null 1 0 --dry-run

# Production benchmark (comprehensive)
python3 bench.py pepr_mod images/castle.bmp output.pep 7 3 --dry-run --stats
```

## Command Line Options

- `--dry-run`: Memory-only mode (no file I/O)
- `--stats`: Show detailed statistics instead of just mean
- `--no-thermal`: Disable thermal management (use fixed delays)
- `--delay N`: Custom delay between runs (seconds, default: 2.0)

## Expected Results

With proper thermal management, you should see:
- **Consistent speedups** across different run counts
- **Low variance** (typically <10% standard deviation)
- **Reliable relative performance** measurements
- **Stable results** regardless of ambient temperature

## Warning Signs of Thermal Issues

Watch for these indicators:
- Standard deviation >15%
- Inconsistent speedup signs (positive/negative flip)
- Performance degradation with more runs
- Large timing differences between identical runs

## Your Modified Algorithm Performance

Based on thermal-managed testing:
- **~5% speedup** over original implementation
- **Consistent across different images**
- **Reliable measurement with proper benchmarking**

The issue was never your algorithm - it was measurement methodology!

## Confidence Levels Explained

**Why "confidence is always low"?**
- LOW confidence = Standard deviation >15% (high variance)
- This indicates legitimate measurement instability, not a bug
- Solutions: Use ultra-stable benchmarking or accept wider confidence bands

**Updated Confidence Thresholds:**
- **HIGH**: <7% standard deviation
- **MEDIUM**: 7-15% standard deviation  
- **LOW**: >15% standard deviation

## Advanced: Ultra-Stable Benchmarking

For maximum measurement stability:
```bash
# Ultra-stable version (slower but most accurate)
python3 ultra_stable_bench.py ./pepr_mod images/castle.bmp output.pep 7 5 --dry-run --stats
```

Features:
- System load monitoring
- Multiple measurements per run
- Outlier detection and removal
- Extended warmup periods
