# HEVC encoding on Apple Silicon: VideoToolbox (`hevc_videotoolbox`) vs x265, and HEVC/AV1/VVC playback compatibility

Research date: 2026-11-26. Researcher machine: Apple M5 Pro (ffmpeg not installed, so no local encode tests were run).
Labels used below: **[PRIMARY]** = Apple / FFmpeg source code / official project docs; **[COMMUNITY]** = blog posts, forums, vendor blogs; **[SEARCH-SNIPPET]** = seen only in a search-result summary, page not fetched (weaker); **Inference** = my own reasoning.

## Q1. VideoToolbox HEVC vs x265 at equal perceptual quality (VMAF / BD-rate, file size, chip generations)

### Takeaway
No rigorous public BD-rate study of Apple's VideoToolbox HEVC encoder vs x265 was found. Every available measurement points the same way: VideoToolbox is about 3x to 25x faster, and x265 gets the same VMAF with a much smaller file. In the few matched-quality data points, VideoToolbox files are about 1.1x to 4x larger. No data separates encoder quality across M1/M2/M3/M4/M5. Apple specs only show more encode engines on Max chips, which adds throughput, not quality.

### Cited Findings
**Speed and size (community benchmarks):**
- **[COMMUNITY] M1 Pro, 4K (3840x2160), 1548 frames, ffmpeg (version not stated):**
  - `hevc_videotoolbox` with default settings: 52 fps (1.72x realtime), 3,642.7 kbit/s. Visually "noticeably hazy".
  - `hevc_videotoolbox -q:v 50`: 52 fps, 27,703.6 kbit/s. "Clean output with no noticeable artifacts."
  - `libx265 -crf 28 -preset fast`: 3.5 fps (0.116x), 3,945.5 kbit/s. Visually "excellent across the board".
  - Hardware was about 15x faster. No VMAF was measured. At visually similar "clean" quality, the VT q:v 50 file was about 7x the bitrate of x265 CRF 28 fast (subjective match only). CPU load stayed at 30–50% during the hardware encode. Page last updated 2026-10-17. — [yre.jp M1 Pro benchmark](https://yre.jp/en/post/m1mac_h265/)
- **[COMMUNITY] M2 Pro, macOS 27.0, ffmpeg 8.1.1, HandBrakeCLI 1.11.2, tested 2026-09-26.** Source: Big Buck Bunny 1080p30, 300 frames, VMAF model `vmaf_v0.6.1`.
  - ffmpeg `hevc_videotoolbox` with default settings (no q:v or b:v disclosed): 3,641,139 B, 2.0 s (~150 fps), VMAF 75.01.
  - `libx265 -crf 28 -preset medium`: 3,193,370 B, 6.4 s (~47 fps), VMAF 90.03. That is 12% smaller than the VT file and 15 VMAF points higher.
  - HandBrake preset "H.265 Apple VideoToolbox 1080p": 8,604,671 B, 3.8 s (~79 fps), VMAF 82.30. That is 2.7x the size of x265 CRF 28 medium, at lower VMAF.
  - `libx265 -crf 23 -preset medium`: 7,156,484 B, VMAF 94.30.
  - x265 CRF 28 preset sweep (VMAF): ultrafast 80.01, veryfast 87.80, medium 90.03, slow 92.36 (16.0 s), veryslow 93.01 (126.9 s).
  - — [Smol: Compress a Video on Mac, tested](https://smolmac.com/blog/compress-video-mac) (vendor blog of a compression app)
- **[COMMUNITY] Same vendor, M2 Pro, macOS 27.0, 2026-09-27, "calm" clip:**
  - `hevc_videotoolbox -b:v 4500k`: VMAF 98.01.
  - x265 CRF 28: VMAF 98.19 "in about a quarter of the hardware file's size". This implies about 4x larger files for VT at equal VMAF on low-motion content.
  - `h264_videotoolbox -b:v 4500k`: VMAF 93.57.
  - — [Smol: H.265 vs H.264](https://smolmac.com/blog/h265-vs-h264)
- **[COMMUNITY] M2 Pro, ffmpeg 6.0, 30 s clip, 2023-09-03:**
  - `hevc_videotoolbox -q:v 55 -tag:v hvc1`: 8,647.5 kbit/s at about 64 fps.
  - `libx265 -crf 22` (default preset): 7,813.58 kbit/s at 2.52 fps. VT was about 11% larger and about 25x faster.
  - Quality was judged by eye only. Differences between q:v 35 and 45 were minor. Some frames differed between 45 and 50. Only close inspection showed changes between 50 and 55.
  - q:v 100 gave about 1.73 GB from a 317 MB source. "Quality above roughly 80%" produced files larger than the source.
  - — [b.27p.de Apple silicon H.265 encoding](https://b.27p.de/p/00016-ffmpeg-apple-silicon-h265-encoding/)

**Forum reports:**
- **[COMMUNITY] Apple Developer Forums thread, 2021–2024:** VideoToolbox (mainly H.264) quality on M1 is worse than x264/NVENC at the same bitrate or CQ. One M1 Max user (Jan 2024) reports "MASSIVE artifacts on CQ<50" and says that matching source quality "roughly doubles file size". No Apple engineer responded. — [Apple Developer Forums 678210](https://developer.apple.com/forums/thread/678210)
- **[SEARCH-SNIPPET] MacRumors HandBrake threads:** one user found VT files "on average, over twice the file size" of x265 across 132 videos. Another M1 user found VT CQ 35 about the same size as x265 RF 20. These threads are about 5 years old. — [MacRumors M1 HandBrake H.265 benchmark thread](https://forums.macrumors.com/threads/someone-please-try-this-h-265-encoding-benchmark-in-handbrake-on-their-m1-mac.2277014/)
- **[COMMUNITY]** A user reports about 288 fps for 4K-to-1080p hardware H.265 on a base M4 Mac mini, with no quality data. — [MacRumors M4 Mac mini thread](https://forums.macrumors.com/threads/m4-mac-mini-nearly-30-slower-at-hardware-encoding-than-2020-intel-i5-imac.2448179/page-2) (via search summary)

**Chip generations:**
- **[PRIMARY]** Apple's MacBook Pro tech specs (fetched 2026-11-26) list:
  - M6 and M5 Pro: "Video encode engine" (one).
  - M5 Max: "Two video encode engines" and "Two ProRes encode and decode engines".
  - All three: "Hardware-accelerated H.264, HEVC, ProRes, and ProRes RAW".
  - No statement anywhere about encoder quality changes between generations. — [Apple MacBook Pro Tech Specs](https://www.apple.com/macbook-pro/specs/)

### Inferences
- Cross-checking all data points (different clips, chips and settings): at equal VMAF, expect `hevc_videotoolbox` files to be about 1.2x to 4x larger than x265 medium/slow. The gap is largest on low-motion or "calm" content, where x265's rate-distortion tools gain most. Low confidence on the exact multiplier, because no controlled BD-rate curve exists.
- VideoToolbox's default rate control (no `-q:v`, no `-b:v`) is bitrate-starved. It gave VMAF 75 at 1080p and a "hazy" 4K result. A fast mode must always set `-q:v` (or `-b:v`).
- For a "shrink but keep visually lossless" goal, VT at transparent settings (q:v around 55–70) may produce files *larger* than an already-efficient source, such as phone HEVC or a good H.264 encode. The b.27p.de data shows output exceeding the source at q:v of roughly 80 or more. The app needs an "output must be smaller than input, else keep original" guard.
- Two encode engines on M5 Max point to higher parallel throughput (for example, two files at once), not better quality per bit.

### Gaps
- No published BD-rate (VMAF or PSNR) curve for `hevc_videotoolbox` vs `libx265` medium/slow on any Apple Silicon chip was found.
- No evidence was found on whether M3/M4/M5/M6 media engines encode HEVC more efficiently than M1/M2. Apple publishes no such claim.
- No VMAF-vs-q:v table from a controlled test was found (see Q2 for the only tier claim). A local calibration (VMAF sweep of q:v 50–75 vs x265 CRF 18–24 on the user's M5 Pro) is the only way to get trustworthy numbers.

## Q2. ffmpeg `hevc_videotoolbox` options (7.x / 8.x / 9.x), q:v behavior, transparent values, pitfalls

### Takeaway
As of Nov 2026, FFmpeg's latest releases are n9.1 / n9.0.2 / n8.1.3 / n8.0.3 / n7.1.5. The `hevc_videotoolbox` private option set has been the same from n8.0 through n9.1. `-q:v N` maps linearly to Apple's `kVTCompressionPropertyKey_Quality = N/100` (clamped to 1.0). It is Apple-Silicon-only: on Intel it errors out rather than being ignored. Read from the source code, ffmpeg defaults have two easy-to-miss traps: no B-frames unless `-bf` > 0, and a 12-frame keyframe interval unless `-g` is set. ffmpeg also does not write HDR10 mastering/CLL metadata.

### Cited Findings
**Releases and documentation:**
- **[PRIMARY]** FFmpeg release tags include n9.1, n9.0.2, n9.0.1, n9.0, n8.1.3 … n8.0, n7.1.5. — [FFmpeg GitHub tags](https://github.com/FFmpeg/FFmpeg/tags)
- **[PRIMARY]** `doc/encoders.texi` on master (the source of ffmpeg-codecs.html) has no VideoToolbox section. The reference is the source code, or `ffmpeg -h encoder=hevc_videotoolbox`. — [FFmpeg doc/encoders.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/encoders.texi)

**Private options** (master, verified in [libavcodec/videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c); the same option names exist in n8.0, n8.1, n9.0 and n9.1):
- **[PRIMARY]** Each option, its range or default, and what it sets in VideoToolbox:
  - `-profile`: `main` | `main10` | `main42210` (alias `rext`, Main 4:2:2 10).
  - `-alpha_quality`: double 0.0–1.0, default 0. Sets HEVC alpha-channel quality.
  - `-constant_bit_rate`: bool, "macOS 13 or newer". Errors with "-constant_bit_rate true is not supported by the encoder." if the encoder rejects it.
  - `-allow_sw`: bool, default 0. `-require_sw`: bool, default 0.
  - `-realtime`: bool, default 0 (range -1..1).
  - `-frames_before`, `-frames_after`: bool. Help with concatenation.
  - `-prio_speed`: bool, default -1 (unset). Sets `kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality`. If unsupported, ffmpeg logs a warning and ignores it.
  - `-power_efficient`: -1..1. Sets `MaximizePowerEfficiency`.
  - `-spatial_aq`: -1..1. Sets `SpatialAdaptiveQPLevel` (1 = default level, 0 = disabled).
  - `-max_ref_frames`: int. Sets `ReferenceBufferCount`.
  - HEVC has no `-level` or `-coder` options. Those exist for H.264 only.
- **[PRIMARY]** `spatial_aq` and `main42210` are absent from n7.1 and present from n8.0. — [n7.1 videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/n7.1/libavcodec/videotoolboxenc.c), [n8.0 videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/n8.0/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** Hardware selection: by default (`allow_sw=0`) ffmpeg sets `RequireHardwareAcceleratedVideoEncoder=true`, so a missing hardware encoder fails instead of silently falling back to software. `allow_sw=1` enables hardware but permits fallback. `require_sw=1` disables hardware. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** Accepted pixel formats for HEVC: `videotoolbox` (hardware frames), `nv12`, `yuv420p`, `bgra`, `ayuv`, `p010le`, `p210`. 10-bit input = `p010le` with `-profile main10`. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)

**`-q:v` constant quality:**
- **[PRIMARY]** The code has a comment "constant quality only on Macs with Apple Silicon". `vtenc_qscale_enabled()` returns `!TARGET_OS_IPHONE && TARGET_CPU_ARM64`.
- **[PRIMARY]** With `-q:v` on a non-ARM64 Mac, init fails with "-q:v qscale not available for encoder. Use -b:v bitrate instead." So q:v is rejected on Intel, not ignored. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** Mapping: `quality = fminf(global_quality / (FF_QP2LAMBDA*100), 1.0)` for `-q:v`. So `-q:v 65` → `kVTCompressionPropertyKey_Quality = 0.65`. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** Since the commit "support global_quality without qscale" (Sep 2025, in n8.1+), `-global_quality N` also maps to N/100. Note that this path is *not* guarded by the Apple-Silicon check. — [commit fc45127bcc](https://github.com/FFmpeg/FFmpeg/commit/fc45127bcc)
- **[PRIMARY]** The "fix the loss of precision when calculating quality" commit (Sep 2025, n8.1+) replaced integer math. n7.1/n8.0 compute `global_quality / FF_QP2LAMBDA` with integer division, which truncates fractional q:v values. — [commit 73750489a6](https://github.com/FFmpeg/FFmpeg/commit/73750489a6)
- **[PRIMARY]** Apple's doc for `kVTCompressionPropertyKey_Quality`: "a number in the range of 0.0 to 1.0, where low = 0.25, normal = 0.50, high = 0.75, and 1.0 implies lossless compression for encoders that support it". Available since macOS 10.8. — [Apple: kVTCompressionPropertyKey_Quality](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_quality)
- **[PRIMARY]** Apple: `kVTCompressionPropertyKey_SpatialAdaptiveQPLevel` is available from macOS 15.0, so `-spatial_aq` has no effect on macOS 14. `PrioritizeEncodingSpeedOverQuality` is available from macOS 11.0. — [Apple: SpatialAdaptiveQPLevel](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_spatialadaptiveqplevel), [Apple: PrioritizeEncodingSpeedOverQuality](https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_prioritizeencodingspeedoverquality)

**Rate control, B-frames, keyframes:**
- **[PRIMARY]** Codec defaults are `b=0`, `qmin=-1`, `qmax=-1`. With no `-q:v` and no `-b:v`, ffmpeg sets `AverageBitRate` to 0 and VideoToolbox picks its own rate. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** B-frames:
  - `has_b_frames = max_b_frames > 0 ? REORDER_DELAY : 0`. When `has_b_frames == 0`, ffmpeg sets `kVTCompressionPropertyKey_AllowFrameReordering = false`.
  - The global default for `-bf` (`max_b_frames`) is 0 (`DEFAULT 0` in options_table.h), and vtenc does not override it.
  - The source notes that VT reorders "with a two level b-pyramid" (measured on macOS 15, Apple Silicon).
  - — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c), [options_table.h](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/options_table.h), [commit 2da55bf59a](https://github.com/FFmpeg/FFmpeg/commit/2da55bf59a)
- **[PRIMARY]** Keyframes: ffmpeg sets `kVTCompressionPropertyKey_MaxKeyFrameInterval = gop_size` when `gop_size > 0`. The global default for `-g` is 12, and vtenc's defaults table does not override `g`. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c), [options_table.h](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/options_table.h)
- **[PRIMARY]** Low-latency mode (`-flags low_delay`) uses `EnableLowLatencyRateControl`. It requires an explicit `-b:v`. HEVC has been allowed on Apple Silicon since Sep 2025 (n8.1+). — [commit d87210745e](https://github.com/FFmpeg/FFmpeg/commit/d87210745e)

**Color and HDR:**
- **[PRIMARY]** Color: ffmpeg maps `color_primaries` / `color_trc` / `colorspace` to VT `ColorPrimaries` / `TransferFunction` / `YCbCrMatrix` (BT.2020 supported). The source has no code for `MasteringDisplayColorVolume` or `ContentLightLevelInfo` (grep: zero hits). Only A53 closed-caption SEI is handled. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[PRIMARY]** Apple HLS spec 1.35: "For HDR10 content, the Mastering Display Color Volume and Content Light Level Information SEI messages SHOULD be present." — [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)

**MP4 sample entry tag:**
- **[PRIMARY]** In ffmpeg's MOV/MP4 tag table, HEVC's first entry is `hev1` ("parameter sets may be in ES"), followed by `hvc1`. The muxer therefore writes `hev1` unless `-tag:v hvc1` is given. — [libavformat/isom_tags.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/isom_tags.c)

**Community q:v values:**
- **[COMMUNITY]** Werner Robitza's VBR-settings page (updated January 2026) lists for VideoToolbox: `-q:v` 1–100, 100 highest. "Constant quality only available on Apple Silicon (ffmpeg 4.4+)". Recommended 45–65. "Quality tiers: 55–65 excellent (VMAF ~95–98), 45–50 good (VMAF ~90–93)". No test methodology is shown for the VMAF tiers. — [slhck.info FFmpeg VBR Settings](https://slhck.info/video/2017/02/24/vbr-settings.html)
- **[COMMUNITY]** Other reported "sweet spots": 45–55 (M2 Pro, 2023, by eye) — [b.27p.de](https://b.27p.de/p/00016-ffmpeg-apple-silicon-h265-encoding/). q:v 50 "clean" at 4K (M1 Pro) — [yre.jp](https://yre.jp/en/post/m1mac_h265/). 65 for 4K HDR archival — [compresto.app](https://compresto.app/blog/hevc-codec-explained) ([SEARCH-SNIPPET]).

### Inferences
- **Trap 1, B-frames:** with ffmpeg's defaults (`-bf` unset = 0), `hevc_videotoolbox` encodes **without B-frames**. This is inferred from the source, with high confidence. Verify with `ffprobe -show_frames -select_streams v -show_entries frame=pict_type`. Add `-bf 2` or any value > 0 to allow VT's B-pyramid.
- **Trap 2, keyframes:** with `-g` unset, VT gets `MaxKeyFrameInterval = 12`, i.e. an IDR roughly every 12 frames. That costs bitrate. This is inferred from the source, with medium-high confidence; verify with ffprobe. Set `-g` to roughly 2–10 s of frames (e.g. `-g 240` at 24–30 fps).
- Both traps likely contributed to the poor size efficiency of ffmpeg's VT in some community tests. HandBrake enables reference B-frames by default (see Q3).
- **HDR:** ffmpeg + `hevc_videotoolbox` keeps PQ/HLG color tags but drops HDR10 static metadata (MDCV/CLL). Dolby Vision RPU and HDR10+ dynamic metadata are not carried either, since there is no code path for them. This is inference from the source. A fast mode should either skip HDR sources or treat them as "color-tagged only, metadata lost".
- **Suggested baseline command** for a fast mode (inference; it combines verified option names and is not benchmarked):
  `ffmpeg -i in.mkv -map 0 -c:v hevc_videotoolbox -q:v 65 -bf 2 -g 240 -profile:v main10 -pix_fmt p010le -tag:v hvc1 -c:a copy -c:s copy out.mp4`
  - Add `-spatial_aq 1` on macOS 15+.
  - Keep `-prio_speed 0` (or leave it unset). Leave `-realtime` at 0.
  - For 8-bit SDR sources, `-profile:v main -pix_fmt nv12` is the conservative alternative. 10-bit output from 8-bit input is commonly used to reduce banding, but that was not verified in this research.
  - Subtitle copy into MP4 works only for mov_text. Image subs (PGS) cannot go into MP4.
- `-q:v` 55–65 is the most commonly cited "visually transparent" band. It is not validated by a controlled VMAF study, so treat it as a starting point for calibration.

### Gaps
- No controlled VMAF-vs-`q:v` mapping on a known chip/macOS/ffmpeg version was found. The slhck tiers have no published method.
- I could not empirically confirm the B-frame and GOP defaults (ffmpeg not installed locally). They are source-derived.
- `-spatial_aq` and `-prio_speed` have no measured quality/speed effect in any found source.
- `ffmpeg.org/ffmpeg-codecs.html` itself was not fetched. Its contents are inferred from `encoders.texi`.

## Q3. HandBrake docs and community testing: VideoToolbox "constant quality" vs x265 for archival/transparent encodes

### Takeaway
HandBrake's official docs make no quality claim about VideoToolbox vs x265 and give no recommended VT quality range. They only document that the VT quality scale is reversed (higher = better) and list a small option set. Community tests consistently show HandBrake's VT presets producing larger files at lower VMAF than x265. That makes VT a speed option, not an archival or transparency choice.

### Cited Findings
**HandBrake docs [PRIMARY]:**
- Quality scale: for x264/x265 a lower RF is higher quality, but "This is reversed for other encoders, such as Apple VideoToolbox, where a higher number produces higher quality." Also: "quality values are not comparable between encodes across multiple encoders." — [HandBrake docs: Adjusting quality](https://handbrake.fr/docs/en/latest/workflow/adjust-quality.html)
- Recommended RF for x264/x265 (no VT equivalent is given): 18–22 for SD, 19–23 for 720p, 20–24 for 1080p, 22–28 for 2160p. — [HandBrake docs: Adjusting quality](https://handbrake.fr/docs/en/latest/workflow/adjust-quality.html)
- VideoToolbox page:
  - Encoders: H.264, H.265 and H.265 10-bit (VideoToolbox).
  - Presets: "H.265 Apple VideoToolbox 2160p 4K" and "H.265 Apple VideoToolbox 1080p".
  - Advanced options: `keyint`, `bframes`, `vbv-bufsize`, `vbv-maxrate`, `qpmin`, `qpmax`, `ref`, `max-frame-delay`, `look-ahead-frame-count`, `disable-spatial-adaptive-qp`, `gpu-registryid`.
  - "Reference B-frames are enabled by default" (`bframes=0` disables them).
  - The VideoToolbox scaler output "will be less sharp" than HandBrake's software scaler.
  - Only encoding runs on hardware. Decoding and filters stay on the CPU unless hardware decoders are enabled (macOS 13+).
  - — [HandBrake docs: VideoToolbox](https://handbrake.fr/docs/en/latest/technical/video-videotoolbox.html)

**Community [COMMUNITY]:**
- On M2 Pro, HandBrake "H.265 Apple VideoToolbox 1080p" gave 8,604,671 B at VMAF 82.30 (~79 fps). HandBrake x264 "Fast 1080p30" gave 7,604,595 B at VMAF 82.33. ffmpeg x265 CRF 28 medium reached VMAF 90.03 at 3,193,370 B. — [Smol: compress video on Mac](https://smolmac.com/blog/compress-video-mac)
- [SEARCH-SNIPPET] Older MacRumors/HandBrake anecdotes conflict. Some found VT files "over twice the file size" of x265 across 132 videos. Others report HandBrake x265 RF 21 ≈ VT CQ 40. — [MacRumors M1 HandBrake thread](https://forums.macrumors.com/threads/someone-please-try-this-h-265-encoding-benchmark-in-handbrake-on-their-m1-mac.2277014/)

### Inferences
- HandBrake's VT presets are tuned for speed and compatibility. Even with B-frames on, they do not reach x265 efficiency.
- For a personal "shrink, visually lossless" app, VT is a reasonable *fast mode* if the user accepts roughly 1.5–3x larger output than x265 at equal quality. It is not a substitute for x265 CRF ~18–22 slow/medium as an "archival / best size" mode.
- HandBrake exposes `look-ahead-frame-count` and `max-frame-delay`. ffmpeg's `hevc_videotoolbox` has no equivalent options, so HandBrake's VT may be somewhat better tuned than plain ffmpeg's VT. This is unverified.

### Gaps
- No HandBrake developer statement or official test on VT quality vs x265 was found.
- No VMAF data exists for HandBrake VT at high CQ values (60–75).

## Q4. AV1 hardware encode on Apple Silicon (M4, M5, M5 Pro/Max, M6) via VideoToolbox

### Takeaway
No. As of 2026-11-26, Apple's own specs list "AV1 decode" only, for M5, M5 Pro, M5 Max and M6. VideoToolbox in FFmpeg exposes only H.264, HEVC and ProRes encoders. No Apple newsroom, tech-spec or WWDC source found claims AV1 encode on any Apple chip. One third-party claim of M5 Pro/Max AV1 encode contradicts Apple's specs.

### Cited Findings
- **[PRIMARY]** MacBook Pro tech specs (fetched 2026-11-26): M6, M5 Pro and M5 Max all list "Hardware-accelerated H.264, HEVC, ProRes, and ProRes RAW" plus "AV1 decode". There is no AV1 encode line. — [Apple MacBook Pro Tech Specs](https://www.apple.com/macbook-pro/specs/)
- **[PRIMARY]** M5 Pro/M5 Max newsroom (2026-03-03): "Apple's latest Media Engine with support for hardware-accelerated H.264 and HEVC, AV1 decode, and ProRes encode and decode engines." — [Apple Newsroom, M5 Pro/M5 Max](https://www.apple.com/newsroom/2026/03/apple-debuts-m5-pro-and-m5-max-to-supercharge-the-most-demanding-pro-workflows/)
- **[PRIMARY, SEARCH-SNIPPET]** The MacBook Air (13-inch, M5) tech specs likewise list AV1 under decode only. — [Apple Support: MacBook Air M5 specs](https://support.apple.com/en-us/126320)
- **[PRIMARY]** FFmpeg master `videotoolboxenc.c` defines encoders only for H.264, HEVC and ProRes (option tables `h264_options`, `hevc_options`, `prores_options`). There is no `av1_videotoolbox` encoder. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **[COMMUNITY]**
  - Fora Soft's AV1 state report (Nov 2026) says no Apple chip, including the M5 Ultra, has an AV1 encoder. — [Fora Soft AV1 hardware support 2026](https://www.forasoft.com/learn/video-encoding/articles/av1-state-2026) ([SEARCH-SNIPPET])
  - videoconverterfactory.com claims the M5 Pro/Max added AV1 encoding. This contradicts Apple's specs and is treated as unreliable. — [videoconverterfactory Apple AV1](https://www.videoconverterfactory.com/multimedia-solution/apple-av1.html) ([SEARCH-SNIPPET])
- No WWDC 2026 / macOS 27 announcement of AV1 encoding in VideoToolbox was found (search, 2026-11-26).

### Inferences
- An AV1 "small file" mode on Apple Silicon must use software encoders (SVT-AV1 / libaom / rav1e via ffmpeg). It cannot be a hardware fast mode.

### Gaps
- I did not check Apple's M5 Ultra or Mac Studio spec page directly. The claim about it comes from a third-party snippet.
- I did not retrieve Apple's VideoToolbox codec list (e.g., `VTCopyVideoEncoderList` output) on macOS 27. Running `ffmpeg -encoders | grep videotoolbox` or a small Swift `VTCopyVideoEncoderList` call on the target Mac would confirm this definitively.

## Q5. Playback compatibility on macOS/iOS: HEVC in MP4 vs MKV (hvc1/hev1), AV1 decode, VVC/H.266

### Takeaway
For QuickTime/Finder/iOS compatibility, write HEVC into **MP4/MOV with the `hvc1` tag**. ffmpeg's MP4 default is `hev1`, which AVFoundation may refuse. MKV is not natively playable in QuickTime at all. AV1 plays natively only on chips with hardware AV1 decode (M3+, A17 Pro+). M1/M2 need third-party players. No Apple support for VVC/H.266 decoding was found.

### Cited Findings
**HEVC tag and container:**
- **[PRIMARY]** Apple HLS spec item 1.10: "You SHOULD use video formats in which the parameter sets are stored in the sample descriptions, rather than the samples. (That is, use 'avc1', 'hvc1', or 'dvh1' rather than 'avc3', 'hev1', or 'dvhe'.)" The CODECS table marks `hev1` as "Use not recommended". — [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
- **[PRIMARY]** ffmpeg's default MP4 tag for HEVC is `hev1` (first table entry). `-tag:v hvc1` selects `hvc1`, and movenc filters parameter sets for `hvc1`. — [isom_tags.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/isom_tags.c), [movenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)
- **[COMMUNITY]** An MP4 tagged `hev1` (ffmpeg default) was reported not playable by AVFoundation, while the same file tagged `hvc1` played. — [Smol: H.265 vs H.264](https://smolmac.com/blog/h265-vs-h264)
- **[PRIMARY]** HLS spec HEVC limits: Profile/Level/Tier "MUST be less than or equal to Main 10 Profile, Level 5.1, High Tier". HDR "MUST be HDR10, HLG, or Dolby Vision". — [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
- **[COMMUNITY]** QuickTime Player does not natively open MKV (Matroska) on macOS, including Tahoe-era guides. Users rely on VLC/IINA/Elmedia. No Apple source was found either way. — [QuickTime MKV search results, e.g. salivity](https://salivity.github.io/mkv/article/does-quicktime-player-support-mkv) ([SEARCH-SNIPPET])
- **[COMMUNITY]** macOS 15 Media Extensions can host third-party format readers and decoders, which is a possible MKV/AV1 path. Behavior is unresolved. — [framejob issue #216](https://github.com/kpgalligan/framejob/issues/216) ([SEARCH-SNIPPET])

**AV1:**
- **[PRIMARY]** Current Mac specs list "AV1 decode" in the Media Engine and "Supported formats include HEVC, H.264, AV1, and ProRes" for playback. — [Apple MacBook Pro Tech Specs](https://www.apple.com/macbook-pro/specs/)
- **[COMMUNITY]** Hardware AV1 decode starts at M3 (Mac) and A17 Pro (iPhone). M1/M2 lack it. — [Bitmovin: Apple AV1 support](https://bitmovin.com/blog/apple-av1-support/), [Hazen Studio: AV1 on Mac](https://www.hazenstudio.com/maclc/blog/av1-on-mac/) ([SEARCH-SNIPPET])
- **[COMMUNITY]** MacRumors thread, May 26–31, 2026:
  - An M4 Mac mini plays AV1 in QuickTime.
  - An M1 Mac mini, an M2 MacBook Air and an older Air on Sonoma show "format is not supported".
  - An M1 Air plays 4K AV1 only in IINA/mpv.
  - Posters report that macOS ships an AV1 software decoder used for AVIF images, but "QuickTime/AVFoundation will playback AV1 only if there is an hardware decoder available".
  - — [MacRumors AV1 QuickTime thread](https://forums.macrumors.com/threads/av1-format-plays-in-quicktime-on-m4-mac-mini-but-not-m1-mac-mini-or-older-macbook-air.2482907/)
- **[COMMUNITY]** VideoToolbox has an undocumented decoder-spec key `EnableAppleOnlySWAV1` that enables Apple's software AV1 decoder. Without it, session creation fails with -12906. Tested on macOS 27.2 / M1 Pro: 1500 frames of 2560x1440 decoded in 13.6 s (~110 fps). The PR was closed in favor of dav1d (2026-11-02). Undocumented and not used by QuickTime per available evidence. — [nxnative PR #992](https://github.com/seedds/nxnative/pull/992)
- **[PRIMARY]** FFmpeg has an AV1 VideoToolbox hwaccel decoder (`libavcodec/videotoolbox_av1.c` exists on master), so ffmpeg can hardware-decode AV1 input on M3+. — [videotoolbox_av1.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolbox_av1.c)
- **[PRIMARY]** Apple HLS spec: "The container format for AV1 video MUST be fMP4" (added 2025-06-24). Dolby Vision Profile 10 (AV1) is allowed on iOS. — [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)

**VVC / H.266:**
- **[PRIMARY]** Apple's MacBook Pro spec playback list and the HLS Authoring Spec do not mention VVC/H.266. — [Apple MacBook Pro Tech Specs](https://www.apple.com/macbook-pro/specs/), [Apple HLS Authoring Specification](https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices)
- **[COMMUNITY]** Apple offers no VVC support, "not in hardware via VideoToolbox, not in software through QuickTime or the system frameworks". — [Compresto: What is H.266](https://compresto.app/blog/what-is-h266-vvc-codec) ([SEARCH-SNIPPET])
- **[COMMUNITY]** iDownloadBlog (2023) says Apple platforms don't support H.266, so third-party players such as Elmedia are needed. — [iDownloadBlog](https://www.idownloadblog.com/?p=967187) ([SEARCH-SNIPPET])
- **[COMMUNITY]** Infuse added software-only H.266 decoding in version 8.4 (2026). — [Firecore community: H.266 support](https://community.firecore.com/t/h-266-vvc-support/46651.md) ([SEARCH-SNIPPET])

### Inferences
- HEVC output for a macOS app should default to MP4 (or MOV) + `-tag:v hvc1`. MKV output is fine for VLC/IINA users but will not preview in QuickTime/Finder.
- Matroska has no hvc1/hev1 fourcc concept: it uses CodecID `V_MPEGH/ISO/HEVC`. So `-tag:v hvc1` matters only for MP4/MOV. This comes from general Matroska knowledge and was not fetched this session.
- An AV1 output mode would break native playback on M1/M2 Macs and pre-A17 Pro iPhones. VVC output would break native playback everywhere on Apple platforms. For "re-encode for my Mac library", HEVC/hvc1/MP4 is the only universally native modern choice across all Apple Silicon Macs on macOS 14+.

### Gaps
- No Apple primary source states the QuickTime MKV position or the AV1 software-fallback policy. Both rest on community evidence.
- The exact AV1 decode cutoff (M3 vs M4) is supported by community sources and an M4 user report, not by an Apple M3 page fetched this session.
- I did not verify whether ffmpeg's native VVC decoder or VideoToolbox expose any VVC path on macOS 27. There is no Apple evidence of one.
