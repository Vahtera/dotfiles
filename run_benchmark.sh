#!/usr/bin/env bash
######################################################################
# 📊 CPU Benchmarking Utility
######################################################################

TMP_FILE="/tmp/benchmark_results_$USER.tmp"
rm -f "$TMP_FILE"

echo "==========================================" > "$TMP_FILE"
echo "        SYSTEM BENCHMARK REPORT           " >> "$TMP_FILE"
echo "==========================================" >> "$TMP_FILE"

if command -v fastfetch &>/dev/null; then
    fastfetch --pipe 2>/dev/null | grep -E "OS|Host|Kernel|CPU" >> "$TMP_FILE"
elif command -v neofetch &>/dev/null; then
    neofetch model cpu distro 2>/dev/null | cut -d':' -f2 | sed 's/ //' >> "$TMP_FILE"
else
    echo "OS/Kernel: $(uname -sr)" >> "$TMP_FILE"
    echo "Architecture: $(uname -m)" >> "$TMP_FILE"
fi

echo "" >> "$TMP_FILE"
echo "--- CPU Benchmarks (sysbench) ---" >> "$TMP_FILE"

if ! command -v sysbench &>/dev/null; then
    echo "Error: sysbench is not installed. Run debian-apt.sh to install it." >> "$TMP_FILE"
else
    echo "Single-Core:" >> "$TMP_FILE"
    echo "Running single-core benchmark..."
    SINGLE_SCORE=$(sysbench cpu run 2>/dev/null | grep "events per second:" | awk '{print $4}')
    echo "  Score: ${SINGLE_SCORE:-N/A} events/sec" >> "$TMP_FILE"

    echo "" >> "$TMP_FILE"
    echo "Multi-Core ($(nproc) threads):" >> "$TMP_FILE"
    echo "Running multi-core benchmark..."
    MULTI_SCORE=$(sysbench --threads="$(nproc)" cpu run 2>/dev/null | grep "events per second:" | awk '{print $4}')
    echo "  Score: ${MULTI_SCORE:-N/A} events/sec" >> "$TMP_FILE"
fi

echo "==========================================" >> "$TMP_FILE"
echo ""

if command -v batcat &>/dev/null; then
    batcat "$TMP_FILE"
elif command -v bat &>/dev/null; then
    bat "$TMP_FILE"
else
    cat "$TMP_FILE"
fi

rm -f "$TMP_FILE"
