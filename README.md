# nobuffr-libmpv

The libmpv build used by the NoBuffr Windows app: **libmpv 0.42.0** (`libmpv-2.dll`), x64.

Release version: `0.42.0-nobuffr-windows.1` (mpv 0.42.0, build script revision 1).

## What is in this repository

| File | What it is |
| --- | --- |
| `build-libmpv-windows.sh` | The script that downloads mpv 0.42.0 and every library it needs, checks each against a pinned sha256, builds them and links them statically into one `libmpv-2.dll`. |
| `test-libmpv.c` | A small program that loads the built libmpv and checks it starts. |
| `MANIFEST.txt` | The record of the shipped build: every source with its checksum and license, toolchain, mpv and FFmpeg feature flags, checksum of the output DLL. |
| `COPYING.LGPL` | mpv's license text (LGPL-2.1), from the mpv 0.42.0 source. |
| `third-party-licenses/` | The license files of mpv and of every library built into the DLL, taken from their sources. |
| `LICENSE`, `LICENSES/` | License of the script and documentation. |

mpv and all libraries are **unmodified upstream sources**. We apply no patches. The script
only chooses which components to build and how.

## Rebuilding

Cross build on Linux with Ubuntu mingw-w64. Build tools (nothing from them is linked):
`mingw-w64 g++-mingw-w64-x86-64-posix cmake meson ninja-build nasm yasm pkg-config python3 xz-utils curl autoconf automake libtool make`.

```
./build-libmpv-windows.sh
```

Options: `WORK=<dir>` (build tree, default `./work`), `OUT=<dir>` (result, default `./out`),
`JOBS=<n>`. The script downloads each upstream tarball and refuses any that does not match its
pinned sha256. The result is `out/libmpv-2.dll`, `out/libmpv.dll.a`, `out/include/mpv`,
`out/LICENSES/` and `out/MANIFEST.txt`. The absolute work path ends up in the binaries; the
shipped build used `/opt/libmpv-windows`.

The release page also carries the exact upstream sources the shipped build used, so you can
rebuild without network access to the upstream sites: the mpv tarball, and one archive of
every other source tarball. Place them in `<WORK>/dl/` before running the script.

## Components and licenses

mpv is built with `-Dgpl=false` (the official LGPL-2.1-or-later configuration), and FFmpeg
without `--enable-gpl`, `--enable-version3` or `--enable-nonfree`. Everything is linked
statically into `libmpv-2.dll`, which imports only Windows system DLLs.

| Library | License |
| --- | --- |
| mpv 0.42.0 | LGPL-2.1-or-later |
| FFmpeg 9.1 | LGPL-2.1-or-later |
| libplacebo 7.387.0 | LGPL-2.1-or-later |
| FriBidi 1.0.18 | LGPL-2.1-or-later |
| libiconv 1.19 (library only) | LGPL-2.1-or-later |
| libass 0.17.5 | ISC |
| FreeType 2.15.0 | FreeType License (FTL) |
| HarfBuzz 15.2.0 | MIT |
| dav1d 1.5.5 | BSD-2-Clause |
| zlib 1.3.2 | Zlib |
| SPIRV-Cross 1.4.363.0, shaderc 2026.4, SPIRV-Tools | Apache-2.0 |
| glslang | BSD-3-Clause, Apache-2.0, MIT |
| SPIRV-Headers | MIT-style (Khronos) |
| Vulkan-Headers, fast_float | Apache-2.0 / MIT (headers) |

`MANIFEST.txt` is the authoritative list.

Portions of this software are copyright © The FreeType Project (www.freetype.org). All rights reserved.

## Replacing the library

`libmpv-2.dll` is a dynamic library, so you can build your own with the script and replace the
one in the app's folder.

## Contact and copyright

Questions about this build, or a request for the corresponding source: hello@nobuffr.com

Copyright for the build script and documentation: 24 Ventures, LLC. mpv and the other
libraries remain under their own licenses and copyrights.
