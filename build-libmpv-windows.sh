#!/bin/bash
# Builds an LGPL-only libmpv (libmpv-2.dll) for Windows x64, for bundling inside the
# NoBuffr desktop app, which embeds it through mpv's `wid` option (native HWND).
# Cross build on Linux with Ubuntu
# mingw-w64, every upstream tarball pinned by sha256, every dependency built from source,
# a licence/GPL check on every build, MANIFEST.txt, LICENSES/ and the corresponding sources.
#
# mpv is built with -Dgpl=false (the official LGPL-2.1+ configuration) and FFmpeg without
# --enable-gpl/--enable-version3/--enable-nonfree. Everything is linked statically into
# libmpv-2.dll (the output is that one DLL); it imports only Windows system DLLs.
#
# Usage: scripts/mpv/build-libmpv-windows.sh
#   WORK=<dir>  build tree (default ./work)   OUT=<dir>  result (default ./out)
#   JOBS=<n>    parallel jobs (default: CPU count)
# Build tools (nothing from them is linked): mingw-w64 g++-mingw-w64-x86-64-posix cmake meson
# ninja-build nasm yasm pkg-config python3 xz-utils curl autoconf automake libtool make.
# The absolute WORK path ends up in the binaries; build releases under /opt/libmpv-windows.
#
# Output: $OUT/libmpv-2.dll, $OUT/libmpv.dll.a + $OUT/include/mpv (to build against),
# $OUT/LICENSES/, $OUT/MANIFEST.txt. Upstream tarballs and SHA256SUMS go to $OUT-sources/.
set -euo pipefail
#
HOST=x86_64-w64-mingw32
WORK=${WORK:-$PWD/work}
OUT=${OUT:-$PWD/out}
JOBS=${JOBS:-$(nproc)}
#
# name | file | url | sha256 | license | needed by. The license is read from the project's own
# COPYING/LICENSE (copied into LICENSES/). Every tarball in this table needs a decision here.
# mpv's tarball is GitHub's tag archive (stable in practice, pinned by hash); mpv 0.42.0.
SOURCES="
mpv|mpv-0.42.0.tar.gz|https://github.com/mpv-player/mpv/archive/refs/tags/v0.42.0.tar.gz|bcfebbfa2b65a6d88dc97ea18117831072373e38b5785a2afb874ed4df5070dd|LGPL-2.1-or-later (built with -Dgpl=false)|listed
ffmpeg|ffmpeg-9.1.tar.xz|https://ffmpeg.org/releases/ffmpeg-9.1.tar.xz|1a4d394ae63d190a526cd052eb4415c156b5c5e2df37efab41a7de0b8fde2433|LGPL-2.1-or-later (no --enable-gpl/--enable-version3/--enable-nonfree)|mpv
libplacebo|libplacebo-7.387.0.tar.gz|https://github.com/haasn/libplacebo/archive/refs/tags/v7.387.0.tar.gz|f9e62d3774a9c4cfd198ec3abaa88294aaade2e31c04d5ab02bcf4abc98b1df5|LGPL-2.1-or-later|mpv (gpu-next)
fast_float|fast_float-97b54ca.tar.gz|https://github.com/fastfloat/fast_float/archive/97b54ca9e75f5303507699d27c6b4f4efe4641a1.tar.gz|2b132274539286e41f37857cac22aa8441d21bd86d55de825a3342b149f66801|Apache-2.0 OR MIT OR BSL-1.0 (header only; libplacebo submodule at its pinned commit)|libplacebo
Vulkan-Headers|Vulkan-Headers-74d8a6c.tar.gz|https://github.com/KhronosGroup/Vulkan-Headers/archive/74d8a6cb930c68ef617b202c3ff3c59d919e086b.tar.gz|75967a8288ff16044a86d1af462b96d2e75c435937efb75f2bb4102ab0382f29|Apache-2.0 OR MIT (headers only; libplacebo submodule commit, compiled for its Vulkan stubs, no Vulkan code in the build)|libplacebo
dav1d|dav1d-1.5.5.tar.xz|https://downloads.videolan.org/pub/videolan/dav1d/1.5.5/dav1d-1.5.5.tar.xz|ca96b1d0ba3f01f55de7231d775892b64994ba061aaeeaaa4f662a390b3abf9e|BSD-2-Clause|ffmpeg (AV1)
libass|libass-0.17.5.tar.xz|https://github.com/libass/libass/releases/download/0.17.5/libass-0.17.5.tar.xz|2dca25c0e0c837ddf00b52011b3f82cac1e4ddd3ad018227806b0c2288864acc|ISC|mpv
freetype|freetype-2.15.0.tar.xz|https://download.savannah.gnu.org/releases/freetype/freetype-2.15.0.tar.xz|93cd47eb719c325107f2d3cf087d06299e944c3b48a40b55537302304dea1dd5|FTL (BSD-style with credit clause; chosen from the FTL/GPL-2.0 dual license)|libass, harfbuzz
harfbuzz|harfbuzz-15.2.0.tar.xz|https://github.com/harfbuzz/harfbuzz/releases/download/15.2.0/harfbuzz-15.2.0.tar.xz|e2ec49090744383cdbe7df808c1cedaafba06a97be8dc4211fe546ba585f12cb|MIT|libass
fribidi|fribidi-1.0.18.tar.xz|https://github.com/fribidi/fribidi/releases/download/v1.0.18/fribidi-1.0.18.tar.xz|1de5e8073d035388b71d0b2d452b1da1f8caeea8a7702997b401fe1b6250727f|LGPL-2.1-or-later|libass
zlib|zlib-1.3.2.tar.xz|https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.xz|d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3|Zlib|ffmpeg, mpv, freetype
libiconv|libiconv-1.19.tar.gz|https://ftp.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz|88dd96a8c0464eca144fc791ae60cd31cd8ee78321e67397e25fc095c4a19aa6|LGPL-2.1-or-later (library only; the GPL iconv tool is not built)|ffmpeg, mpv
SPIRV-Cross|SPIRV-Cross-1.4.363.0.tar.gz|https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz|f708982e88b763ef5b0394ed468fc2c3628f68cdab89f2e7a946cd628c04e721|Apache-2.0|mpv, libplacebo (GLSL to HLSL for d3d11)
shaderc|shaderc-2026.4.tar.gz|https://github.com/google/shaderc/archive/refs/tags/v2026.4.tar.gz|f06ce5bcca94e5df7f34e115743597d0ad2e13c5fe9213c67dc8c76031241947|Apache-2.0|mpv, libplacebo (GLSL to SPIR-V)
glslang|glslang-e1b562a.tar.gz|https://github.com/KhronosGroup/glslang/archive/e1b562a8bed273a02f30b59b66a5d499793cede5.tar.gz|907174a24713c6202c146f164bf81783f1fbc79c8cb821a30f18f159eb980312|BSD-3-Clause, Apache-2.0, MIT (GPL-3.0 only in bison output under the Bison exception)|shaderc (commit pinned by shaderc v2026.4 DEPS)
SPIRV-Tools|SPIRV-Tools-ef96ed7.tar.gz|https://github.com/KhronosGroup/SPIRV-Tools/archive/ef96ed763b43b59b33b31b362f09a02b729fa1c9.tar.gz|82c62146083fd558735a3171cf97cfc47903ca7d368482e87f94bd44883c0f00|Apache-2.0|shaderc (pinned by shaderc DEPS)
SPIRV-Headers|SPIRV-Headers-04fd3ca.tar.gz|https://github.com/KhronosGroup/SPIRV-Headers/archive/04fd3caa1e8267e4d95c806cad901181728e1006.tar.gz|392f4801409aad9c4f1b77745f179952fd6264e4c8bd0fc1bc45dfa6807bf6d0|MIT-style (Khronos)|shaderc (pinned by shaderc DEPS)
"
#
log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
field() { echo "$SOURCES" | awk -F'|' -v n="$1" -v c="$2" '$1 == n {print $c}'; }
#
for tool in $HOST-gcc-posix $HOST-g++-posix $HOST-windres $HOST-strip $HOST-objdump \
  cmake meson ninja nasm pkg-config python3 xz curl make autoconf; do
  command -v "$tool" >/dev/null || die "missing build tool: $tool"
done
mkdir -p "$WORK" "$OUT" "$OUT-sources"
WORK=$(cd "$WORK" && pwd); OUT=$(cd "$OUT" && pwd)
DL="$WORK/dl"; SRC="$WORK/src"; PREFIX="$WORK/prefix"
mkdir -p "$DL" "$SRC" "$PREFIX/lib/pkgconfig" "$WORK/tc"
#
log "Fetching and verifying sources"
for n in $(echo "$SOURCES" | cut -d'|' -f1); do
  f=$(field "$n" 2); [ -f "$DL/$f" ] || curl -fL --retry 3 -o "$DL/$f" "$(field "$n" 3)"
  echo "$(field "$n" 4)  $DL/$f" | sha256sum -c --quiet - || die "$f: sha256 mismatch"
done
# Unpacks source $1 into $SRC/$1 (once); further arguments are extracted into it too.
unpack() { [ -d "$SRC/$1" ] || { mkdir -p "$SRC/$1" && tar -xf "$DL/$(field "$1" 2)" -C "$SRC/$1" --strip-components=1; }; }
#
# Toolchain: posix-thread mingw-w64 (shaderc/glslang need std::mutex), as plain $HOST-gcc names.
for t in gcc g++ c++ cpp; do ln -sf "$(command -v $HOST-$t-posix)" "$WORK/tc/$HOST-$t"; done
# libplacebo looks for a plain dlltool (the build host is arm64, so name the target).
rm -f "$WORK/tc/dlltool"
printf '#!/bin/sh\nexec %s -m i386:x86-64 --as %s "$@"\n' "$(command -v $HOST-dlltool)" "$(command -v $HOST-as)" > "$WORK/tc/dlltool"
chmod +x "$WORK/tc/dlltool"
export PATH="$WORK/tc:$PATH"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" PKG_CONFIG_PATH=
# -static: the linker takes libwinpthread, libstdc++ and libgcc from the .a files, so the
# result needs no mingw runtime DLL next to it.
export CFLAGS="-O2 -I$PREFIX/include" CXXFLAGS="-O2 -I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -static"
cat > "$WORK/cross.ini" <<EOT
[binaries]
c = '$HOST-gcc'
cpp = '$HOST-g++'
ar = '$HOST-ar'
strip = '$HOST-strip'
windres = '$HOST-windres'
pkg-config = 'pkg-config'
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
[built-in options]
c_args = ['-O2', '-I$PREFIX/include']
cpp_args = ['-O2', '-I$PREFIX/include']
c_link_args = ['-L$PREFIX/lib', '-static']
cpp_link_args = ['-L$PREFIX/lib', '-static']
[properties]
needs_exe_wrapper = true
EOT
cat > "$WORK/tc.cmake" <<EOT
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $HOST-gcc)
set(CMAKE_CXX_COMPILER $HOST-g++)
set(CMAKE_RC_COMPILER $HOST-windres)
set(CMAKE_FIND_ROOT_PATH $PREFIX)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOT
#
# Build helpers; each dependency leaves a stamp so a re-run only builds what is missing.
msn() { # name [meson options]: static library into the prefix
  local n=$1; shift; unpack "$n"
  meson setup "$WORK/b-$n" "$SRC/$n" --cross-file "$WORK/cross.ini" --prefix "$PREFIX" --libdir lib \
    --buildtype release --default-library static "$@"
  ninja -C "$WORK/b-$n" -j"$JOBS" install
}
cmk() { # name [cmake options]
  local n=$1; shift; unpack "$n"
  cmake -S "$SRC/$n" -B "$WORK/b-$n" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$WORK/tc.cmake" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF "$@"
  cmake --build "$WORK/b-$n" -j"$JOBS" && cmake --install "$WORK/b-$n"
}
dep() { [ -f "$PREFIX/.done-$1" ] || { log "Building $1"; "build_$1"; touch "$PREFIX/.done-$1"; }; }
#
build_zlib() { cmk zlib -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_MINIZIP=OFF
  # zlib's cmake names the static library libzs.a; everything else asks for -lz.
  cp "$PREFIX/lib/libzs.a" "$PREFIX/lib/libz.a"; }
build_libiconv() {
  unpack libiconv; mkdir -p "$WORK/b-libiconv" && cd "$WORK/b-libiconv"
  "$SRC/libiconv/configure" --host=$HOST --prefix="$PREFIX" --disable-shared --enable-static --disable-nls
  make -j"$JOBS" install-lib; cd "$WORK"
  # libiconv ships no .pc file; meson finds it through one.
  printf 'Name: iconv\nDescription: libiconv\nVersion: 1.19\nCflags: -I%s/include\nLibs: -L%s/lib -liconv\n' "$PREFIX" "$PREFIX" > "$PREFIX/lib/pkgconfig/iconv.pc"
}
build_dav1d() { msn dav1d -Denable_tools=false -Denable_tests=false -Denable_examples=false; }
build_freetype() { msn freetype -Dzlib=system -Dbzip2=disabled -Dpng=disabled -Dharfbuzz=disabled -Dbrotli=disabled; }
build_harfbuzz() {
  msn harfbuzz -Dfreetype=enabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dicu=disabled \
    -Dgdi=disabled -Ddirectwrite=disabled -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled
}
build_fribidi() { msn fribidi -Ddocs=false -Dtests=false -Dbin=false; }
build_libass() {
  unpack libass; mkdir -p "$WORK/b-libass" && cd "$WORK/b-libass"
  "$SRC/libass/configure" --host=$HOST --prefix="$PREFIX" --disable-shared --enable-static \
    --disable-fontconfig --enable-directwrite --disable-require-system-font-provider
  make -j"$JOBS" install; cd "$WORK"
}
build_spirv_cross() {
  # mpv asks pkg-config for spirv-cross-c-shared; the static C API library answers to it.
  cmk SPIRV-Cross -DSPIRV_CROSS_SHARED=OFF -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=OFF \
    -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_ENABLE_MSL=OFF -DSPIRV_CROSS_ENABLE_CPP=OFF \
    -DSPIRV_CROSS_ENABLE_REFLECT=OFF -DSPIRV_CROSS_ENABLE_C_API=ON -DSPIRV_CROSS_FORCE_PIC=OFF
  cat > "$PREFIX/lib/pkgconfig/spirv-cross-c-shared.pc" <<EOT
Name: spirv-cross-c-shared
Description: SPIRV-Cross C API (static)
Version: 1.4.363
Cflags: -I$PREFIX/include/spirv_cross
Libs: -L$PREFIX/lib -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-core -lstdc++
EOT
}
build_shaderc() {
  unpack shaderc; mkdir -p "$SRC/shaderc/third_party"
  for p in glslang:glslang SPIRV-Tools:spirv-tools SPIRV-Headers:spirv-headers; do
    unpack "${p%%:*}"; ln -sfn "$SRC/${p%%:*}" "$SRC/shaderc/third_party/${p##*:}"
  done
  cmk shaderc -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSPIRV_SKIP_TESTS=ON -DSPIRV_SKIP_EXECUTABLES=ON -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_OPT=ON \
    -DSPIRV_TOOLS_BUILD_STATIC=ON
  # The shipped shaderc.pc names the DLL; point it at the static combined library.
  cat > "$PREFIX/lib/pkgconfig/shaderc.pc" <<EOT
Name: shaderc
Description: shaderc (static, combined)
Version: 2026.4
Cflags: -I$PREFIX/include
Libs: -L$PREFIX/lib -lshaderc_combined -lstdc++
EOT
}
build_ffmpeg() {
  unpack ffmpeg; mkdir -p "$WORK/b-ffmpeg" && cd "$WORK/b-ffmpeg"
  # --disable-autodetect: only what is listed. w32threads: no winpthread. Hardware decoding
  # through D3D11VA/DXVA2, https through Windows schannel, AV1 through dav1d.
  "$SRC/ffmpeg/configure" --prefix="$PREFIX" --arch=x86_64 --target-os=mingw32 --cross-prefix=$HOST- \
    --pkg-config=pkg-config --pkg-config-flags=--static --disable-autodetect --disable-shared --enable-static \
    --disable-programs --disable-doc --disable-debug --disable-avdevice \
    --disable-encoders --disable-muxers --disable-pthreads --enable-w32threads \
    --enable-zlib --enable-iconv --enable-libdav1d --enable-schannel --enable-d3d11va --enable-dxva2 \
    --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib"
  make -j"$JOBS" install; cd "$WORK"
}
build_libplacebo() {
  unpack libplacebo; unpack fast_float; rm -rf "$SRC/libplacebo/3rdparty/fast_float"
  ln -sfn "$SRC/fast_float" "$SRC/libplacebo/3rdparty/fast_float"
  unpack Vulkan-Headers; rm -rf "$SRC/libplacebo/3rdparty/Vulkan-Headers"
  ln -sfn "$SRC/Vulkan-Headers" "$SRC/libplacebo/3rdparty/Vulkan-Headers"
  msn libplacebo -Dd3d11=enabled -Dvulkan=disabled -Dopengl=disabled -Dshaderc=enabled -Dglslang=disabled \
    -Dlcms=disabled -Ddovi=disabled -Dlibdovi=disabled -Dxxhash=disabled -Dunwind=disabled -Ddemos=false -Dtests=false
}
for d in zlib libiconv dav1d freetype harfbuzz fribidi libass spirv_cross shaderc ffmpeg libplacebo; do dep $d; done
#
log "FFmpeg license check"
FFCFG="$WORK/b-ffmpeg/config.h"
grep -q '#define FFMPEG_LICENSE "LGPL version 2.1 or later"' "$FFCFG" || die "FFmpeg is not LGPL-2.1-or-later"
for flag in CONFIG_GPL CONFIG_NONFREE CONFIG_VERSION3; do
  grep -q "#define $flag 0" "$FFCFG" || die "FFmpeg: $flag is not 0"
done
#
log "Configuring and building mpv"
unpack mpv
# Meson's iconv probe links without -liconv, and <iconv.h> renames iconv_open to libiconv_open;
# forcing that symbol and listing the library before the probe's objects lets it resolve.
cat > "$WORK/mpv-cross.ini" <<EOT
[built-in options]
c_link_args = ['-L$PREFIX/lib', '-static', '-Wl,-u,libiconv_open', '-liconv']
cpp_link_args = ['-L$PREFIX/lib', '-static', '-Wl,-u,libiconv_open', '-liconv']
EOT
[ -d "$WORK/b-mpv" ] || meson setup "$WORK/b-mpv" "$SRC/mpv" --cross-file "$WORK/cross.ini" --cross-file "$WORK/mpv-cross.ini" --prefix "$PREFIX" \
  --buildtype release --prefer-static -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false \
  -Dlua=disabled -Djavascript=disabled -Duchardet=disabled -Drubberband=disabled -Dlcms2=disabled \
  -Dzimg=disabled -Dvapoursynth=disabled -Dlibarchive=disabled -Dlibbluray=disabled -Ddvdnav=disabled \
  -Dcdda=disabled -Dvulkan=disabled -Degl-angle-win32=disabled -Dwin32-smtc=disabled -Dsdl2-audio=disabled \
  -Dsdl2-video=disabled -Dsdl2-gamepad=disabled -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled \
  -Dd3d11=enabled -Dshaderc=enabled -Dspirv-cross=enabled -Dwasapi=enabled -Diconv=enabled -Dzlib=enabled
ninja -C "$WORK/b-mpv" -j"$JOBS"
MPVB="$WORK/b-mpv"
#
log "Collecting output"
rm -rf "$OUT/libmpv-2.dll" "$OUT/libmpv.dll.a" "$OUT/include" "$OUT/LICENSES" "$OUT/MANIFEST.txt"
mkdir -p "$OUT/LICENSES" "$OUT/include"
cp "$MPVB/libmpv-2.dll" "$OUT/"
cp "$MPVB/libmpv.dll.a" "$OUT/" 2>/dev/null || cp "$MPVB/libmpv-2.dll.a" "$OUT/libmpv.dll.a"
cp -r "$SRC/mpv/include/mpv" "$OUT/include/"
$HOST-strip --strip-unneeded "$OUT/libmpv-2.dll"
#
log "License and dependency checks"
# 1. mpv itself is built as LGPL.
grep -q '#define HAVE_GPL 0' "$MPVB/config.h" || die "mpv was not configured with -Dgpl=false"
# 2. Required features are really in (a silent 'auto' downgrade must fail the build).
for f in D3D11 SHADERC SPIRV_CROSS WASAPI LIBASS LIBPLACEBO ICONV ZLIB; do
  grep -q "#define HAVE_$f 1" "$MPVB/config.h" || die "mpv feature missing: $f"
done
for f in LUA JAVASCRIPT UCHARDET RUBBERBAND LIBARCHIVE LIBBLURAY DVDNAV; do
  grep -q "#define HAVE_$f 1" "$MPVB/config.h" && die "unexpected mpv feature: $f"
done
# 3. Self-contained: the DLL may import only Windows system DLLs.
SYSDLL='^(kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|msvcrt|ucrtbase|api-ms-win-.*|bcrypt|crypt32|shlwapi|winmm|mmdevapi|d3d11|d3d9|dxgi|d3dcompiler_[0-9]+|dxva2|comctl32|comdlg32|iphlpapi|propsys|version|imm32|setupapi|dwmapi|secur32|ncrypt|rpcrt4|winhttp|usp10|msimg32|avrt|powrprof|psapi|dnsapi|wtsapi32|userenv|netapi32|uxtheme|cfgmgr32|ntdll|dbghelp|dwrite|d2d1|windowscodecs|opengl32|mf|mfplat|mfuuid|uuid|shcore|dcomp|winspool\.drv|wsock32|mswsock|ntmarta|sspicli|cryptsp)\.dll$'
BAD=$($HOST-objdump -p "$OUT/libmpv-2.dll" | awk '/DLL Name:/ {print tolower($3)}' | grep -v -E "$SYSDLL" || true)
[ -z "$BAD" ] || die "libmpv-2.dll imports non-system DLLs: $BAD"
# 4. Every source tarball has a licence row (the table above), and no GPL-only code is linked:
#    none of the GPL-only mpv/FFmpeg dependencies is among them.
for g in x264 x265 rubberband uchardet libdvd postproc libcdio fftw; do
  echo "$SOURCES" | grep -qi "^$g" && die "GPL-only dependency in SOURCES: $g"
done
EXPORTS=$($HOST-objdump -p "$OUT/libmpv-2.dll")
case "$EXPORTS" in *" mpv_create"*) ;; *) die "libmpv-2.dll does not export mpv_create" ;; esac
#
log "License texts and source release material"
cp "$SRC/mpv/LICENSE.LGPL" "$OUT/LICENSES/mpv-LICENSE.LGPL"
for n in $(echo "$SOURCES" | cut -d'|' -f1); do
  mkdir -p "$OUT/LICENSES/$n"
  for f in "$SRC/$n"/COPYING* "$SRC/$n"/LICENSE* "$SRC/$n"/LICENCE* "$SRC/$n"/docs/FTL.TXT "$SRC/$n"/docs/LICENSE.TXT \
    "$SRC/$n"/Copyright* "$SRC/$n"/COPYRIGHT* "$SRC/$n"/README; do [ -f "$f" ] && cp "$f" "$OUT/LICENSES/$n/"; done
  rmdir "$OUT/LICENSES/$n" 2>/dev/null || true
done
for n in $(echo "$SOURCES" | cut -d'|' -f1); do cp "$DL/$(field "$n" 2)" "$OUT-sources/"; done
(cd "$OUT-sources" && sha256sum ./*.tar.* > SHA256SUMS)
#
log "Writing MANIFEST.txt"
{
  echo "libmpv for Windows x64 (mpv $(cat "$SRC/mpv/MPV_VERSION"), LGPL-2.1-or-later, -Dgpl=false)"
  echo "Toolchain: $($HOST-gcc-posix --version | head -1); $(dpkg-query -W -f='mingw-w64 ${Version}' mingw-w64-x86-64-dev 2>/dev/null || true)"
  echo
  echo "== Sources (name | file | sha256 | license | needed by) =="
  for n in $(echo "$SOURCES" | cut -d'|' -f1); do
    echo "$n | $(field "$n" 2) | $(field "$n" 4) | $(field "$n" 5) | $(field "$n" 6)"
  done
  echo
  echo "All libraries above are statically linked into libmpv-2.dll. The app must credit the"
  echo "FreeType Project (FTL clause) and supply the sources/relinking material for the LGPL parts."
  echo "== System components (not redistributed) =="
  echo "Audio: WASAPI. Video: Direct3D 11 (d3dcompiler_47.dll). Hardware decoding: D3D11VA/DXVA2. TLS: schannel."
  echo
  echo "== mpv features (config.h) =="
  grep -E '^#define HAVE_[A-Z0-9_]+ 1$' "$MPVB/config.h" | awk '{print $2}' | sort | tr '\n' ' '; echo
  echo
  echo "== FFmpeg config =="
  grep -E '^#define (FFMPEG_LICENSE|CONFIG_(GPL|NONFREE|VERSION3|SCHANNEL|D3D11VA|DXVA2|LIBDAV1D|ZLIB|ICONV)) ' "$FFCFG"
  echo
  echo "== sha256 / size =="
  (cd "$OUT" && sha256sum libmpv-2.dll && stat -c '%s bytes' libmpv-2.dll)
} > "$OUT/MANIFEST.txt"
#
log "Done in $((SECONDS / 60)) min $((SECONDS % 60)) s"
du -sh "$OUT" "$OUT-sources"
