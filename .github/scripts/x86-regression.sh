#!/usr/bin/env bash
set -euo pipefail
export WINEPREFIX="$PWD/regression/prefix"
export WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
runtime=$(cat regression/runtime-path.txt)
runtime_win=$(winepath -w "$runtime")
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$runtime_win" /f
test_exe="$PWD/regression/tests/tests-x86/pinvoke2.exe"
failures=0
summary="$PWD/regression/results-summary.log"
printf 'variant\tmode\ttest\texit\tresult\n' > "$summary"

for variant in baseline candidate; do
    wineserver -k || true
    wineserver -w
    if [ "$variant" = baseline ]; then
        cp regression/baseline-x86.dll "$runtime/bin/libmono-2.0-x86.dll"
    else
        cp image/bin/libmono-2.0-x86.dll "$runtime/bin/libmono-2.0-x86.dll"
    fi
    for mode in interp none; do
        # Exercise the replacement through Wine's mscoree, as in the application.
        export WINE_MONO_AOT="$mode"
        for test_name in internal_call_signatures native_pointer_call_conventions; do
            log="regression/$variant-$mode-$test_name.log"
            set +e
            timeout -k 5 60 wine "$test_exe" --run-only "$test_name" -v > "$log" 2>&1
            result=$?
            set -e
            cat "$log"
            outcome=FAIL
            if grep -q "Running 'test_0_$test_name'" "$log"; then
                if [ "$variant-$mode-$test_name" = baseline-interp-native_pointer_call_conventions ]; then
                    # Require the known native crash, not an arbitrary timeout or loader failure.
                    if [ "$result" -ne 0 ] &&
                        grep -q 'Native Crash Reporting' "$log" &&
                        grep -q 'Unhandled page fault' "$log" &&
                        ! grep -q 'Regression tests: 1 ran, 0 failed' "$log"; then
                        outcome=EXPECTED_FAILURE
                    fi
                elif [ "$result" -eq 0 ] && grep -q 'Regression tests: 1 ran, 0 failed' "$log"; then
                    outcome=PASS
                fi
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$variant" "$mode" "$test_name" "$result" "$outcome" >> "$summary"
            echo "$variant $mode $test_name exit=$result $outcome"
            if [ "$outcome" = FAIL ]; then
                failures=$((failures + 1))
            fi
            wineserver -k || true
            wineserver -w
        done
    done
done
cat "$summary"
test "$failures" -eq 0
