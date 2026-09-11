#!/usr/bin/env bash
set -euo pipefail
export WINEPREFIX="$PWD/regression/prefix"
export WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
runtime=$(cat regression/runtime-path.txt)
runtime_win=$(winepath -w "$runtime")
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$runtime_win" /f
test_exe="$PWD/regression/tests/tests-x86/pinvoke2.exe"
for mode in interp none; do
    export WINE_MONO_AOT="$mode"
    timeout -k 5 60 wine "$test_exe" --run-only native_pointer_call_conventions -v > "regression/$mode.log" 2>&1
    cat "regression/$mode.log"
    grep -q 'test_0_native_pointer_call_conventions' "regression/$mode.log"
    wineserver -k || true
    wineserver -w
done
