#!/usr/bin/env bash
set -euo pipefail
export WINEPREFIX="$PWD/regression/prefix"
export WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
runtime=$(cat regression/runtime-path.txt)
runtime_win=$(winepath -w "$runtime")
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$runtime_win" /f
test_exe="$PWD/regression/tests/tests-x86/pinvoke2.exe"
for variant in baseline candidate; do
    wineserver -k || true
    wineserver -w
    if [ "$variant" = baseline ]; then
        cp regression/baseline-x86.dll "$runtime/bin/libmono-2.0-x86.dll"
    else
        cp image/bin/libmono-2.0-x86.dll "$runtime/bin/libmono-2.0-x86.dll"
    fi
    for mode in interp none; do
        log="regression/$variant-$mode.log"
        if [ "$variant" = baseline ]; then
            export WINE_MONO_AOT="$mode"
            command=(wine "$test_exe")
        else
            unset WINE_MONO_AOT
            command=(wine "$runtime/bin/mono-sgen-main.exe")
            if [ "$mode" = interp ]; then
                command+=(--interp)
            fi
            command+=("$test_exe")
        fi
        set +e
        timeout -k 5 60 "${command[@]}" --run-only native_pointer_call_conventions -v > "$log" 2>&1
        result=$?
        set -e
        cat "$log"
        echo "$variant $mode exit=$result"
        grep -q "Running 'test_0_native_pointer_call_conventions'" "$log"
        if [ "$variant-$mode" = baseline-interp ]; then
            # A generic timeout or loader failure is not a successful negative control.
            test "$result" -ne 0
            grep -q 'Native Crash Reporting' "$log"
            grep -q 'Unhandled page fault' "$log"
            if grep -q 'Regression tests: 1 ran, 0 failed' "$log"; then
                echo 'Baseline unexpectedly passed' >&2
                exit 1
            fi
        else
            test "$result" -eq 0
            grep -q 'Regression tests: 1 ran, 0 failed' "$log"
        fi
        wineserver -k || true
        wineserver -w
    done
done
