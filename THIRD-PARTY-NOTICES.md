# Third-party notices

This project produces a patched rebuild of two upstream projects, distributed under their own licenses:

| Project                                                    | Used under the terms of |
| ------------------------------------------------------------ | ------------------------ |
| [sharp](https://github.com/lovell/sharp)                     | Apache License 2.0      |
| [sharp-libvips](https://github.com/lovell/sharp-libvips) / [libvips](https://github.com/libvips/libvips) | LGPL-2.1-or-later |

`sharp-libvips`'s own build pulls in a further set of third-party libraries (glib, cairo, pango, libjpeg, etc.) — see [`sharp-libvips`'s own `THIRD-PARTY-NOTICES.md`](https://github.com/lovell/sharp-libvips/blob/main/THIRD-PARTY-NOTICES.md) for that full list; this project doesn't change any of those licensing terms, only how `libvips-cpp.so` exports (or hides) `glib`/`gobject` symbols from its own public API (see `README.md` for why).

## What this project adds on top

- `vendor/sharp-libvips/extra/glib_wrapper.c`/`.h` — original code written for this project (not derived from upstream `sharp`/`libvips`/`glib` source), released under the same license as the rest of this repository (see `LICENSE`).
- `patches/*.patch` — diffs against the above upstream projects, distributed here as patches (not as a modified copy of their source) specifically so the unmodified upstream license terms continue to apply to the code being patched.
