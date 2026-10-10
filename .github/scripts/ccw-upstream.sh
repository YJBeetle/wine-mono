#!/usr/bin/env bash
set -euo pipefail
test_root="$PWD/ccw-upstream"
mkdir -p "$test_root/runtime"
curl -fL --retry 3 https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.tar.xz -o "$test_root/runtime.tar.xz"
tar -xf "$test_root/runtime.tar.xz" -C "$test_root/runtime"
runtime=$(dirname "$(dirname "$(find "$test_root/runtime" -name libmono-2.0-x86_64.dll -print -quit)")")
test -f "$runtime/lib/mono/4.5/mscorlib.dll"
mcs -platform:x64 -main:FocusedRunner -out:"$test_root/focused.exe" mono/mono/tests/cominterop.cs .github/fixtures/ccw-release/FocusedRunner.cs
export WINEPREFIX="$test_root/prefix" WINEARCH=win64 WINEDEBUG=-all WINE_MONO_AOT=none
trap 'wineserver -k || true' EXIT
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$(winepath -w "$runtime")" /f
exe=$(winepath -w "$test_root/focused.exe")
set +e
timeout -k 5 60 wine "$exe" > "$test_root/baseline.log" 2>&1
code=$?
set -e
cat "$test_root/baseline.log"
test "$code" -ne 124 && test "$code" -ne 137
grep -Fq 'ccw->ref_count > 0' "$test_root/baseline.log"
! grep -Fq CCW_TEST_PASS "$test_root/baseline.log"
wineserver -k || true
wineserver -w
cp image/bin/libmono-2.0-x86_64.dll "$runtime/bin/libmono-2.0-x86_64.dll"
for case in over-release leak; do
    args=()
    test "$case" != leak || args=(leak)
    timeout -k 5 60 wine "$exe" "${args[@]}" > "$test_root/$case.log" 2>&1
    cat "$test_root/$case.log"
    tr -d '\r' < "$test_root/$case.log" | grep -Fxq CCW_TEST_PASS
    ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$test_root/$case.log"
done
echo CCW_UPSTREAM_PASS
