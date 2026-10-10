#!/usr/bin/env bash
set -euo pipefail
architecture=${1:?architecture required}
case "$architecture" in
    x86) platform=x86 ;;
    x86_64) platform=x64 ;;
    *) exit 2 ;;
esac
test_root="$PWD/ccw-test"
mkdir -p "$test_root/runtime"
curl -fL --retry 3 https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.tar.xz -o "$test_root/runtime.tar.xz"
tar -xf "$test_root/runtime.tar.xz" -C "$test_root/runtime"
runtime=$(dirname "$(dirname "$(find "$test_root/runtime" -name "libmono-2.0-$architecture.dll" -print -quit)")")
test -f "$runtime/lib/mono/4.5/mscorlib.dll"
baseline="$test_root/baseline-$architecture.dll"
candidate="$PWD/image/bin/libmono-2.0-$architecture.dll"
cp "$runtime/bin/libmono-2.0-$architecture.dll" "$baseline"
sha256sum "$baseline" "$candidate" > "$test_root/engine-checksums.txt"
for variant in baseline candidate; do
    dll=$baseline
    test "$variant" != candidate || dll=$candidate
    objdump -p "$dll" | awk '/\[Ordinal\/Name Pointer\] Table/ { table=1; next } table && /^\[ / { exit } table && /^[[:space:]]*\[[[:space:]]*[0-9]+\]/ { print $NF }' | LC_ALL=C sort -u > "$test_root/$variant-exports.txt"
    test -s "$test_root/$variant-exports.txt"
    grep -qx mono_marshal_get_vtfixup_ftnptr "$test_root/$variant-exports.txt"
    grep -q '^wine_mono_' "$test_root/$variant-exports.txt"
done
LC_ALL=C comm -23 "$test_root/baseline-exports.txt" "$test_root/candidate-exports.txt" > "$test_root/missing-exports.txt"
test ! -s "$test_root/missing-exports.txt"
mcs -platform:"$platform" -out:"$test_root/ccw.exe" .github/fixtures/ccw-release/ReleaseProbe.cs
if [ "$architecture" = x86_64 ]; then
    mcs -platform:"$platform" -out:"$test_root/btls.exe" .github/fixtures/ccw-release/BtlsProbe.cs
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$test_root/key.pem" -out "$test_root/certificate.pem" -days 1 -subj '/CN=WineMonoCCWLocalProbe'
    openssl x509 -in "$test_root/certificate.pem" -outform DER -out "$test_root/certificate.der"
    printf '%s\n' 'BTLS=x64-enabled-preserved' > "$test_root/btls-scope.txt"
else
    printf '%s\n' 'BTLS=x86-disabled-v3-baseline; x86 BTLS investigation deferred' > "$test_root/btls-scope.txt"
fi
export WINEPREFIX="$test_root/prefix"
export WINEARCH=win64 WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$(winepath -w "$runtime")" /f
exe=$(winepath -w "$test_root/ccw.exe")
if [ "$architecture" = x86_64 ]; then
    btls_exe=$(winepath -w "$test_root/btls.exe")
    certificate=$(winepath -w "$test_root/certificate.der")
fi
printf 'variant\tmode\texit\tresult\n' > "$test_root/summary.txt"
for variant in baseline candidate; do
    wineserver -k || true
    wineserver -w
    dll=$baseline
    test "$variant" != candidate || dll=$candidate
    cp "$dll" "$runtime/bin/libmono-2.0-$architecture.dll"
    for mode in none interp; do
        log="$test_root/$variant-$mode.log"
        set +e
        WINE_MONO_AOT="$mode" timeout -k 5 60 wine "$exe" > "$log" 2>&1
        code=$?
        set -e
        tr -d '\r' < "$log" > "$log.normalized"
        cat "$log"
        if [ "$variant" = baseline ]; then
            # abort() may report exit zero: require the exact known assertion,
            # not a loader failure, generic crash or timeout.
            test "$code" -ne 124 && test "$code" -ne 137
            grep -Fxq 'release-to-zero=0' "$log.normalized"
            grep -Fq 'ref_count > 0' "$log.normalized"
            ! grep -Fxq CCW_RELEASE_PROBE_PASS "$log.normalized"
            outcome=EXPECTED_ASSERTION
        else
            test "$code" -eq 0
            grep -Fxq CCW_RELEASE_PROBE_PASS "$log.normalized"
            ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$log.normalized"
            outcome=PASS
            if [ "$architecture" = x86_64 ]; then
                btls_log="$test_root/btls-$mode.log"
                WINE_MONO_AOT="$mode" timeout -k 5 60 wine "$btls_exe" "$certificate" > "$btls_log" 2>&1
                cat "$btls_log"
                tr -d '\r' < "$btls_log" | grep -Fxq MONO_BTLS_PROBE_PASS
                ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$btls_log"
            fi
        fi
        printf '%s\t%s\t%s\t%s\n' "$variant" "$mode" "$code" "$outcome" >> "$test_root/summary.txt"
        wineserver -k || true
        wineserver -w
    done
done
cat "$test_root/summary.txt"
cat "$test_root/btls-scope.txt"
echo CCW_WINE_MATRIX_PASS
