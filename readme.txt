

**Project: Custom NES/Famicom-based operating system, built from scratch in 6502 assembly (kernel-in-ROM, self-hosted).**

## Hardware & Memory Map
- Clone Famicom-on-chip board, PAL region. Custom (non-standard) memory map, not off-the-shelf NROM:
  - `$6000-$9FFF`: fixed 16KB RAM (code/data workspace)
  - `$A000-$DFFF`: bank-switched 16KB window backed by 3× 16KB physical banks (48KB), for loaded software — requires custom discrete-logic bank-select hardware (a latch chip gating SRAM address lines), since standard NROM can't bank-switch
  - `$E000-$FFFF`: fixed 8KB kernel ROM, always resident, holds reset/NMI/IRQ vectors and core OS routines
  - CHR: moving from CHR-ROM to CHR-RAM (8KB, one chip, mapped to PPU bus) so fonts/graphics can be loaded at runtime, not just baked into the cartridge

## PPU/NMI packet protocol (built and reviewed extensively)
- "Dumb NMI, smart kernel" principle: NMI is a pure packet-format streamer with zero cross-call state; all complexity (buffering, multi-frame flushing, cluster-chain logic) lives in kernel code.
- Universal buffer packet format: `[PPU_HI][PPU_LO][LEN|FLAGS][DATA...]`, `$FF`-terminated. Bit7=Fill mode, bit6=Vertical mode, bits0-4=length (0=960/full-screen special case).
- Full-screen writes (nametable+attribute, 1024 bytes) do NOT fit in one VBlank (~11 cycles/byte for literal reads via `(zp),Y` vs PAL's ~7,459-7,957-cycle VBlank budget) — resolved by bypassing NMI entirely for full-screen writes: a direct kernel routine (`os_drawUI`) that forces rendering off and blasts data straight to `$2007` with no VBlank timing constraint, since forced blank has no timing limit at all.
- `os_printblock` (text-row rendering) uses row/cycle-budget capping (~9 full-width rows or ~205-215 payload bytes per VBlank, derived from actual instruction cycle counts) and flushes via a blocking `ppu_update` call, looping until done — same "cap, flush, resume" pattern used elsewhere.
- Decided NOT to build "extended length" packets (>31 bytes) — kept deferring until a concrete need arose, and eventually concluded it's now moot since full-screen writes bypass NMI and buffers stay under 256 bytes.
- `os_printblock`'s destination buffer uses `abs,X` addressing (buffer proven ≤255 bytes); NMI's general packet reads use `(zp),Y` (must stay flexible/relocatable, and can exceed one page for the 960-byte special case).

## Font
- Hand-authored 2bpp CHR data as inline `.byte` tables (not `.incbin`), ASCII-aligned: tile index = ASCII code directly, no offset/lookup table needed. 32 reserved UI tiles + 96 ASCII glyphs = 128 tiles used of 256 available in the background pattern table; sprite pattern table (256 tiles) completely separate and unused so far.

## Storage stack (9 layers, SD card via bit-banged SPI)
1-2: SPI byte send/receive. 3: SD command/response framing. 4: `sd_init`, `sd_read_block`, `sd_write_block`. 5: `read_mbr` (partition offset). 6: `read_bootsector` (FAT16 geometry: `fat_start`, `root_start`, `data_start`, assumes standard 2-FAT/512-root-entry defaults). 7: `ClusterToLBA`, `get_next_cluster` (FAT chain-walking, cluster 0 = sentinel for "root, not a real cluster"). 8: `list_directory` (one sector at a time, packs valid entries into 18-byte records: name+ext+attr+cluster+size, skips deleted/`$E5`, long-name/`$0F`, dot-entries/`$2E`), `search_directory` (same skip rules, 11-byte name compare, early-exit on match). 9: `load_file` (walks cluster chain, streams sectors to a destination pointer, relies on `sd_read_block` restoring the caller's pointer so `load_file` alone tracks destination advancement).
- Root vs. subfolder unified into shared low-level "scan this sector" logic; only the "how do I reach the next sector" step differs (root: fixed 32-sector range; subfolder: FAT chain-following), selected via the cluster=0 sentinel, no separate flag needed.
- Parent-folder navigation: NOT read from disk (`..` entries are skipped uniformly with `.`) — instead a kernel-side navigation stack (push cluster on folder-enter, pop on back) tracks history in RAM.

## App/file model (fully designed, not yet built)
- Apps are folders (not single bundled files): `EXE` (pure code, size read directly from the FAT directory entry, no in-file size header needed) + `MAIN.CHR`/extra `.CHR` files (background+sprite graphics, own small header with two length fields, no padding on disk or in transit) + `ICON.CHR` (one 16-byte tile).
- No installer file/step. Auto-registration on first launch: the first time the file manager opens any `.EXE`, it appends a record (path, icon bytes copied inline, display name) to `INSTALLED.SYS` if not already present — unifying "run" and "install" into one action, avoiding a missable separate step.
- Three-tier discoverability: filesystem (ground truth, always fully browsable) → `INSTALLED.SYS` (auto-populated complete app list, Start-Menu-equivalent) → desktop shortcut file (small, user-curated subset, explicit "create shortcut" action, icon copied at creation time so the desktop never has to open app folders at boot).
- Multi-screen CHR swapping mid-run: app code calls kernel's `load_chr` routine directly (same syscall convention as everything else — fixed-address `JSR`, no dispatch table), which forces blank, streams new CHR data straight from SD to `$2007`, resumes rendering — same mechanism as full-screen nametable writes, applied to pattern-table data instead.
- Boot sequence: hardware init → clear RAM/registers → SD init/mount → load `SYSCONF.SYS` (system settings, e.g. default vs custom font) → load desktop into the RAM window.

## Status
- Nothing has been assembled or run yet — the person's monitor is broken, blocking Mesen testing. All of tonight's work (NMI, `os_printblock`, `os_drawUI`, all 9 storage layers, the memory map) is paper-reviewed only, not empirically verified. This is explicitly flagged as the top-priority next step once testing is possible again — the person has been encouraged repeatedly to freeze new design work and test before extending further, and has acknowledged this directly.

This is a lot to fold in — let me condense rather than sprawl, since the file's already got good bones and tonight added a huge amount.

Saved and condensed. The full write-up above covers everything in detail — copy that to whatever AI or notes you're handing this off to. Good project to look back on; get that monitor fixed and go prove it out.