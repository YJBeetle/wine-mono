#!/usr/bin/env bash
# Deliberately keep running after each native crash so all controls produce evidence.
set -euo pipefail
architecture=${1:?architecture required}
case "$architecture" in
    x86) platform=x86; native_dir=x86 ;;
    x86_64) platform=x64; native_dir=x86_64 ;;
    *) exit 2 ;;
esac
root="$PWD/btls-test"
mkdir -p "$root/runtime"
curl -fL --retry 3 https://github.com/wine-mono/wine-mono/releases/download/wine-mono-11.3.0/wine-mono-11.3.0-x86.tar.xz -o "$root/runtime.tar.xz"
tar -xf "$root/runtime.tar.xz" -C "$root/runtime"
runtime=$(dirname "$(dirname "$(find "$root/runtime" -name "libmono-2.0-$architecture.dll" -print -quit)")")
test -f "$runtime/lib/mono/4.5/System.dll"
# Baseline and candidate share EXACT System.dll, BTLS DLL, mscorlib and test data.
cp "$runtime/bin/libmono-2.0-$architecture.dll" "$root/official-engine.dll"
native=$(find "$runtime/lib/$native_dir" -name libmono-btls-shared.dll -print -quit)
test -s "$native"
sha256sum "$root/official-engine.dll" "image/bin/libmono-2.0-$architecture.dll" \
    "$runtime/lib/mono/4.5/System.dll" "$runtime/lib/mono/4.5/mscorlib.dll" "$native" > "$root/checksums.txt"
# Put the original ABI library alongside the probe, avoiding search-path ambiguity.
cp "$native" "$root/libmono-btls-shared.dll"
objdump -p "$native" > "$root/native-exports.txt"
objdump -d "$native" > "$root/native-disassembly.txt"
mcs -platform:"$platform" -out:"$root/btls.exe" .github/fixtures/btls/BtlsProbe.cs
mcs -platform:"$platform" -r:System.Core -r:System.Xml -out:"$root/runtime.exe" .github/fixtures/btls/RuntimeProbe.cs
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$root/key.pem" -out "$root/certificate.pem" -days 1 -subj '/CN=WineMonoBtlsProbe'
openssl x509 -in "$root/certificate.pem" -outform DER -out "$root/certificate.der"
openssl pkcs12 -export -legacy -inkey "$root/key.pem" -in "$root/certificate.pem" -out "$root/certificate.pfx" -passout pass:
export WINEPREFIX="$root/prefix" WINEARCH=win64 WINEDEBUG=-all
WINEDLLOVERRIDES='mscoree,mshtml=' timeout -k 5 120 wine wineboot -u
wine reg add 'HKCU\Software\Wine\Mono' /v RuntimePath /t REG_SZ /d "$(winepath -w "$runtime")" /f
btls_exe=$(winepath -w "$root/btls.exe")
runtime_exe=$(winepath -w "$root/runtime.exe")
# Avoid File.ReadAllBytes: original x86 interp crashes earlier in
# BCryptGenRandom during PathInternal initialization. Memory fixtures allow
# the BTLS comparison to actually reach the native certificate functions.
der=$(base64 -w 0 "$root/certificate.der")
pfx=$(base64 -w 0 "$root/certificate.pfx")
printf 'engine\tmode\ttest\texit\tresult\n' > "$root/summary.txt"
failures=0
for engine in official built; do
    wineserver -k || true
    wineserver -w
    dll="$root/official-engine.dll"
    test "$engine" != built || dll="$PWD/image/bin/libmono-2.0-$architecture.dll"
    cp "$dll" "$runtime/bin/libmono-2.0-$architecture.dll"
    for mode in none interp; do
        for probe in managed-der managed-pkcs12 native-cdecl native-default internal-calls compression crypto xml oid socket; do
            exe="$btls_exe"; fixture="$der"
            case "$probe" in
                managed-pkcs12) fixture="$pfx" ;;
                internal-calls|compression|crypto|xml|oid|socket) exe="$runtime_exe"; fixture="" ;;
            esac
            log="$root/$engine-$mode-$probe.log"
            set +e
            WINE_MONO_AOT="$mode" timeout -k 5 45 wine "$exe" "$probe" "$fixture" "$der" > "$log" 2>&1
            code=$?
            set -e
            tr -d '\r' < "$log" > "$log.normalized"
            result=FAIL
            if [ "$code" -eq 0 ] && grep -Fxq "PROBE_PASS=$probe" "$log.normalized" &&
               ! grep -Eq 'Assertion at|Unhandled Exception|Native Crash Reporting' "$log"; then
                result=PASS
            elif [ "$probe" = native-default ] && grep -Fxq "PROBE_ENTER=$probe" "$log.normalized" &&
                 grep -Eq 'Native Crash Reporting|Unhandled page fault' "$log" &&
                 grep -Fq 'BtlsProbe:ParseDefault' "$log"; then
                # Deliberately ambiguous ABI: record as a diagnostic negative control,
                # never mask failures of real managed APIs or the explicit cdecl control.
                result=ABI_MISMATCH_OBSERVED
            else
                failures=$((failures + 1))
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$engine" "$mode" "$probe" "$code" "$result" >> "$root/summary.txt"
            cat "$log"
            wineserver -k || true
            wineserver -w
        done
    done
done
cat "$root/summary.txt"
test "$failures" -eq 0
echo BTLS_RUNTIME_MATRIX_PASS
