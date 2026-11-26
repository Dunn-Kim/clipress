# Software encoders for maximum compression at visually-lossless quality: SVT-AV1 (and forks), libaom, VVC/vvenc (state as of Nov 2026)

Evidence labels used throughout:
- **[PRIMARY]** = project changelog/docs/official paper.
- **[COMMUNITY]** = wiki, forum, Reddit, user benchmark.
- **[SECONDARY]** = press or aggregator reporting on a primary source.
- Everything under "Inferences" is the researcher's own reasoning, not a sourced fact.

## Q1. Latest SVT-AV1 release, recent changes, ffmpeg exposure, practitioner CRF/preset ranges

### Takeaway
The latest mainline release is **SVT-AV1 v4.3.0 (2026-11-01)**. The 4.x line (4.0.0, 2026-01-13) absorbed nearly all SVT-AV1-PSY perceptual features, including `--tune 0` (VQ) improvements, IQ tune, AC bias, quarter-step CRF and variance boost. 4.2.0 added a VMAF tune. Arm Neon work has continued every release. In ffmpeg, use `-c:v libsvtav1 -preset N -crf N -svtav1-params key=val:key=val`. The tested mainline presets for archival VOD are roughly 2–6.

### Cited Findings
**Release timeline [PRIMARY: CHANGELOG.md]**
- **4.3.0 (2026-11-01):**
  - About 5–8% better cycle efficiency at similar quality.
  - About 10–11% lower multi-threaded run time across all presets.
  - Timed film-grain tables (`--fgs-table`) and a per-picture film-grain `FILM_GRAIN_EVENT` API.
  - Fixed "bitrate inversion at fractional CRF/QP above 63".
  - New Arm Neon kernels: fwht4x4, highbd variance, k-means, OBMC, interpolate_core.
  - Neon and SVE2 Hadamard SATD and psy distortion.
  - Fixed an "Apple teardown SIGTRAP".
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **4.2.0 (2026-07-14):**
  - TUNE-VMAF mode, targeting about 15% VMAF BD-rate improvement at minimal PSNR loss.
  - RA tuning for M3–M5.
  - New options `--cqp`, `--enable-intrabc`, `--hbd-mds`, `--enable-kf-tf`.
  - Arm: Neon lowbd forward transforms, Neon SAD/quantize/SSIM/VMAF/variance, SVE2 VMAF.
  - macOS universal binaries.
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **4.1 (2026-03-23):** MD, EncDec and entropy-coding refactor; still-image gains; Arm subpixel variance and 16b SAD optimizations — [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **4.0.1 (2026-01-27)** and **4.0.0 (2026-01-13):** 4.0.0 is a major API release. Items the changelog credits to SVT-AV1-PSY:
  - dynamic delta-q res switching
  - intraBC hash search
  - toggleable adaptive film grain
  - Image Quality (IQ) tune
  - option to restrict transform selection
  - extended quarter-step CRF
  - `--scm 3`
  - AC Bias

  Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- Release-date discrepancy: Phoronix reported the 4.0 release on 25 Jan 2026 and said it "completed porting all SVT-AV1-PSY applicable features for --tune vq for video and --tune iq for avif". The changelog dates 4.0.0 to 2026-01-13 (tag date vs announcement) — [Phoronix](https://phoronix.com/news/SVT-AV1-4.0) [SECONDARY]
- **3.1.0 (2025-07-24):**
  - "Variance boost ported from SVT-AV1-PSY".
  - `--chroma-qm-min/max` added.
  - Fast-decode 0 gave about 15–25% speedup at M1–M5 with equal quality.
  - M0 gained 1–1.5% BD-rate.
  - Arm geomean speedup vs 3.0.2 on Graviton4: +3% to +8% depending on resolution.
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **3.0.0 (2025-02-18):**
  - Max preset is now M10 (one preset removed).
  - Perceptual features from PSY brought into tune 0.
  - Neon/SVE2 gains of 10–25% at 480p–1080p.
  - Not API backward compatible.
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **2.3.0 (2024-10-28):** Arm uplift vs v2.2 on Graviton4 (`--lp 1`):
  - 1080p 8-bit: 1.15x to 1.61x per preset.
  - 2160p 10-bit: 1.16x to 1.95x per preset.
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)
- **2.1.0 (2024-05-17):** "Variance boost added for the tune VQ mode" — [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md)

**Option reference [PRIMARY: Docs/Parameters.md, current master]**
Source for all rows: [SVT-AV1 Parameters.md](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/Docs/Parameters.md)

| Option | Range | Default | Notes |
|---|---|---|---|
| `--preset` | -1–13 | 8 | Higher is faster |
| `--crf` | 1–70 | 35 | 0.25 steps allowed |
| `--tune` | 0–5 | 1 | 0=VQ, 1=PSNR, 2=SSIM, 3=IQ (still image only), 4=MS-SSIM, 5=VMAF (video only) |
| `--enable-variance-boost` | 0–1 | **0 (off in mainline)** | |
| `--variance-boost-strength` | 1–4 | 2 | |
| `--variance-octile` | 1–8 | 5 | |
| `--sharpness` | -7–7 | 0 | |
| `--film-grain` | 0–50 | 0 | |
| `--film-grain-denoise` | 0–1 | **0** | 0 = grain params only, no denoised output |
| `--adaptive-film-grain` | 0–1 | 1 | |
| `--enable-qm` | 0–1 | 0 | |
| `--qm-min` / `--qm-max` | 0–15 | 8 / 15 | |
| `--luminance-qp-bias` | 0–100 | 0 | |
| `--ac-bias` | 0.0–8.0 | 0 | Docs suggest about 1.0–1.5 moderate, 4.0–6.0 for grain retention |
| `--enable-tf` | 0–2 | 1 | |
| `--tf-strength` | 0–4 | 3 | |
| `--enable-overlays` | 0–1 | 0 | |
| `--scd` | 0–1 | 0 | |
| `--keyint` | -2 or more | -2 | -2 is about 5 s |
| `--input-depth` | 8 / 10 | | |
| `--fast-decode` | 0–3 | | |
| `--lp` | 0–6 | | |
| `--lookahead` | -1, 0–120 | | |
| `--qp-scale-compress-strength` | 0–3 | | |
| `--max-tx-size` | 32 / 64 | | |

**ffmpeg `libsvtav1` [PRIMARY: ffmpeg-codecs docs]**
- AVOptions: `preset` (0–13), `crf` (0–63), `qp`, `profile`, `level`, `tier`, `hielevel`, `qmin`/`qmax`, `sc_detection`, `la_depth`, `tile_rows`, `tile_columns`, `qpfile`.
- `svtav1-params` passes ":"-separated key=value pairs to SVT-AV1.
- Source: [FFmpeg codecs documentation](https://ffmpeg.org/ffmpeg-codecs.html)

**Community preset/tune guidance [COMMUNITY: codecs.wiki, formerly wiki.x266.mov]**
- Presets 2–8 suit non-realtime encoding. Preset -1 and 13 are not recommended.
- CRF is the recommended rate control.
- Tune 0 (VQ) is "a safe bet". Leaning away from the PSNR tune is common practice.
- 10-bit output is "always desirable for coding efficiency, even from an 8-bit source".
- Suggested `--keyint` is about FPS×10.
- `--enable-qm 1` with `--qm-min 0` unless grain is extremely heavy.
- Source: [codecs.wiki SVT-AV1](https://codecs.wiki/docs/encoders/SVT-AV1). The page is marked "Under Maintenance" and parts predate PSY's merge.

**Fork-tuned starting points [COMMUNITY: SVT-AV1-HDR README, fork-specific]**
- VQ: `--tune 0`, start at CRF 35, preset 2–6.
- Film grain: `--tune 6`, CRF 20–40 (start at 30), preset 1–2.
- The README notes its CRF scale is not equivalent to mainline.
- Source: [SVT-AV1-HDR GitHub](https://github.com/juliobbv-p/svt-av1-hdr)

### Inferences
- Mainline defaults are PSNR-tuned (`tune=1`, variance boost off, QM off). A "max compression, visually lossless" mode should therefore set these explicitly. Suggested starting point (not validated):
  - `-c:v libsvtav1 -preset 3..5 -crf ~20..30 -pix_fmt yuv420p10le -svtav1-params tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0:keyint=<fps*10>:scd=1`
  - The CRF range is inferred. The only sourced anchors are the mainline default (35) and the HDR-fork "start at 35/30". Lower CRF means higher quality.
  - Calibrate the CRF per content class with VMAF/SSIMULACRA2 and eyeballing.
- The ffmpeg doc lists `crf` as 0–63 integer. Native SVT-AV1 accepts 1–70 in 0.25 steps. Fractional or >63 CRF probably needs `-svtav1-params crf=24.5`. Unverified.
- `tune=5` (VMAF) optimizes for a metric rather than appearance. Treat it as a size/metric lever, not a "visually lossless" lever.
- Apple M1–M4 implement Neon but, to the researcher's knowledge, not general-purpose SVE/SVE2. SVE/SVE2 kernels in the changelog likely do not apply on Macs; Neon kernels do. Unverified for M5.

### Gaps
- No primary source gives CRF values for "transparent" 1080p/4K with mainline 4.x. Treat all CRF numbers as content-dependent.
- No primary-source Apple Silicon fps per preset. See Q4/Q6 for community data.
- No official BD-rate of SVT-AV1 4.x vs x265 was found in the changelog. The changelog reports intra-SVT deltas only.

## Q2. Community forks: SVT-AV1-PSY, -HDR, -Essential, others — maintenance and upstreaming

### Takeaway
**SVT-AV1-PSY is archived (Feb 12, 2026).** Its applicable features were upstreamed into mainline 3.0–4.0. **SVT-AV1-HDR** is now the officially designated continuation. **SVT-AV1-Essential** (QoL defaults) and **SVT-AV1-Tritium** (HDR + Essential + PSYEX) exist, but their 2026 maintenance status is unclear. For an app that bundles ffmpeg, mainline 4.x is the low-risk default. HDR is the choice only if you want its extra psy tunes, notably `--tune 6` for grain.

### Cited Findings
- **SVT-AV1-PSY:**
  - psy-ex repo archived by the owner on Feb 12, 2026, now read-only.
  - README says the work was set aside to focus on SVT-AV1-HDR, "the official recommended continuation of SVT-AV1-PSY".
  - Source: [psy-ex/svt-av1-psy](https://github.com/psy-ex/svt-av1-psy) (via search snippet) [PRIMARY]
- **PSY maintainer post (2024-11-26):**
  - The fork "was always meant to be a temporary project". The goal is to "merge our features into SVT-AV1".
  - From Jan 2025 the author stopped writing new perceptual changes.
  - Source: [Gianni Rosato, "The End of SVT-AV1-PSY"](https://giannirosato.com/blog/post/end-of-psy/) [PRIMARY, dated 2024]
- **Upstreamed into mainline:**
  - Variance boost (2.1.0 / 3.1.0).
  - Chroma QM (3.1.0).
  - Perceptual tune-0 features (3.0.0).
  - IQ tune, AC bias, quarter-step CRF, adaptive film grain toggle, tx restriction, `--scm 3`, intraBC hash, dynamic delta-q res switching (4.0.0).
  - Source: [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md) [PRIMARY]
- **SVT-AV1-HDR (juliobbv):**
  - **Psy defaults:** variance boost **on by default**; `--sharpness 1` default; `--ac-bias` default 1.0 with `--sharp-tx 1`; `--noise-norm-strength` 0–4 (default 1); QMs on by default; `--tf-strength 1`; `--kf-tf-strength 1`; default preset 4; `--keyint -2` gives about a 10 s GOP.
  - **HDR:** PQ-optimized variance-boost curve via `--variance-boost-curve 3` or `--transfer-characteristics 16`.
  - **Film-grain tune `--tune 6`:** equals `--tune 0 --enable-tf 0 --enable-restoration 0 --enable-cdef 0 --complex-hvs 1 --tx-bias 1 --ac-bias 4.00`.
  - **Grain table:** `--noise` 0–200, where 50 is about `--film-grain 50`.
  - **Releases:** "New versions are only used for source code tagging"; no first-party binaries (community HandBrake/ffmpeg builds are linked); rebases onto mainline only guaranteed at major versions (4.0, 5.0).
  - Source: [SVT-AV1-HDR GitHub](https://github.com/juliobbv-p/svt-av1-hdr) [PRIMARY]
- **SVT-AV1-Essential:** "sensible defaults and Quality of Life improvements", borrowing psy settings from PSY and HDR — [nekotrix/SVT-AV1-Essential](https://github.com/nekotrix/SVT-AV1-Essential) [PRIMARY]. No 2026 status found.
- **SVT-AV1-Tritium:** a fork of SVT-AV1-HDR with PSYEX + Essential features, packaged in AUR — [AUR svt-av1-tritium-git](https://aur.archlinux.org/packages/svt-av1-tritium-git?all_reqs=1) [COMMUNITY]
- A community changelog page compares "-HDR v4.0.1" with -Essential, which suggests HDR rebased onto mainline 4.0.x — [rentry comparison](https://rentry.co/bhcdh2nn) [COMMUNITY, unverified]

### Inferences
- Shipping a fork means building and bundling your own ffmpeg linked against it. Homebrew ffmpeg links mainline `svt-av1`. That maintenance cost is the main argument against forks for a personal app.
- The HDR fork changes CRF semantics. App presets tuned for mainline CRF should not be reused with it unchanged.

### Gaps
- Exact latest tag/date of SVT-AV1-HDR and Essential: the Releases sections are empty or were not retrieved.
- No independent BD-rate or subjective comparison of HDR/Essential vs mainline 4.x was found.

## Q3. Film grain synthesis: size reduction, perceived quality, interaction with VMAF

### Takeaway
Film grain synthesis (FGS) can cut bitrate by **about 30–50% on grainy film sources**. Netflix production reports an average of about 36% at 1080p and above, but only about 10% below 1080p. Clean sources barely change. VMAF and other full-reference pixel metrics are unreliable judges of synthesized grain, because the grain is not pixel-identical. Validate FGS settings visually, not with VMAF.

### Cited Findings
- The original AV1 film-grain tool paper (DCC 2018, Norkin/Birkbeck) reports up to 50% bitrate savings on heavy-grain sequences — [DCC 2018 AV1 film grain](https://norkin.org/pdf/DCC_2018_AV1_film_grain.pdf) [PRIMARY]
- Netflix deployed AV1 FGS streams in July 2025 [SECONDARY, multiple reports]:
  - One report: average bitrate cut of about 36% at 1080p and above; below 1080p only about 10% — [Broadband TV News](https://www.broadbandtvnews.com/2025/07/04/netflix-film-grain-synthesis-saves-on-the-bitrate/)
  - Another report cites a 31.6% average bitrate reduction — [TV Technology](https://www.tvtechnology.com/news/netflix-rolls-out-av1-film-grain-synthesis-streams-for-film-content); [IBC](https://ibc.org/content-management/news/netflix-rolls-out-av1-film-grain-synthesis-for-classic-movies/22018)
  - Exact attribution of 36% vs 31.6% between these articles is not verified.
- VMAF "may not correctly assess these enhancements and might even penalize them as degradations" when grain retention is involved — [Streaming Media](https://www.streamingmedia.com/Articles/Post/Blog/Challenges-of-New-Encoding-Scenarios-Reflections-on-Measuring-Perceived-Quality-166721.aspx) [SECONDARY/industry opinion]
- Practitioner guide: noisy film scans shrink dramatically, lightly grainy content shifts modestly, clean content barely moves — [DEV Community](https://dev.to/masonwritescode/turn-on-av1-film-grain-synthesis-and-measure-what-it-saves-on-your-own-footage-37bb) [COMMUNITY]
- **SVT-AV1 options:**
  - `--film-grain` 0–50 and `--film-grain-denoise` 0/1, default 0. With 0, grain params are signalled but the encoded picture is not denoised.
  - `--adaptive-film-grain` default 1.
  - `--fgs-table` (pre-generated tables).
  - 4.3.0 added timed tables and per-picture grain params.
  - Sources: [SVT-AV1 Parameters.md](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/Docs/Parameters.md); [SVT-AV1 CHANGELOG](https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/CHANGELOG.md) [PRIMARY]
- **Community SVT-AV1 values:**
  - `--film-grain` about 8 for live action with normal grain, about 4 for animation or smooth sources.
  - Denoising removes fine detail, so use `--film-grain` alone in most cases.
  - Source: [codecs.wiki SVT-AV1](https://codecs.wiki/docs/encoders/SVT-AV1) [COMMUNITY]
- **aomenc:**
  - `--denoise-noise-level=8`; values above 12 create noticeable grain patterns.
  - Photon-noise tables via `--film-grain-table` are an alternative.
  - Source: [codecs.wiki aomenc](https://codecs.wiki/docs/encoders/aomenc) [COMMUNITY]
  - ffmpeg exposes this as `denoise-noise-level` / `denoise-block-size` — [FFmpeg codecs documentation](https://ffmpeg.org/ffmpeg-codecs.html) [PRIMARY]

### Inferences
- With `film-grain-denoise=0` (the mainline default), the encoder still codes the grainy picture and adds synthetic grain on top. Size savings are smaller, but detail loss is lower.
- With `film-grain-denoise=1`, the encoder codes a denoised picture. This gives the biggest savings but risks losing fine texture. Grain look depends on the decoder applying FGS: all compliant AV1 decoders must, but some players/hardware paths have had bugs (unverified).
- For a "visually lossless" app mode, the safest design is to make FGS opt-in, or to enable it only when a grain/noise detector fires. Do not let an automatic VMAF-targeting loop judge FGS output.

### Gaps
- No controlled measurement of how much VMAF drops for FGS encodes at equal perceived quality.
- No measured size delta for SVT-AV1 `--film-grain 8` with denoise 0 vs 1 on Blu-ray film sources.

## Q4. libaom (aomenc) vs SVT-AV1 in 2026

### Takeaway
SVT-AV1 is the practical choice. It scales across cores far better, while its efficiency is competitive with mainline aomenc. aomenc keeps an edge mainly in intra/still-image coding and 4:4:4. Its perceptual community forks are now mostly unmaintained. For long-form video in an ffmpeg app, aomenc's poor threading makes it impractical unless you add chunked parallel encoding (Av1an-style).

### Cited Findings
- SVT-AV1 scales across cores far better than aomenc, with coding efficiency competitive with mainline aomenc. Well-tuned aomenc forks were perceptually ahead, but the gap was closing via SVT-AV1-PSY — [codecs.wiki SVT-AV1](https://codecs.wiki/docs/encoders/SVT-AV1) [COMMUNITY, pre-2026 wording]
- **aomenc notes [COMMUNITY]** — [codecs.wiki aomenc](https://codecs.wiki/docs/encoders/aomenc)
  - aomenc "doesn't parallelize well"; Av1an is recommended.
  - Preset (cpu-used) 4 is the "sweet spot"; 3 is more efficient; 2 is for people with lots of time.
  - libaom has put more effort into intra coding.
  - SVT-AV1 supports only 4:2:0.
  - Suggested HQ settings: `--bit-depth=10 --end-usage=q --cq-level=24 --tune=ssim --deltaq-mode=0 --enable-qm=1 --enable-chroma-deltaq=1`.
  - Fork status: aom-av1-psy unmaintained since 2023-01-13; aom-av1-lavish unmaintained since 2024-06-04.
- **ffmpeg `libaom-av1`:**
  - `cpu-used` 0–8, default 1.
  - `crf` 0–63; `row-mt` disabled by default.
  - `tiles` / `tile-columns` / `tile-rows`.
  - `tune` psnr/ssim, default psnr.
  - `denoise-noise-level`, `aom-params`.
  - Source: [FFmpeg codecs documentation](https://ffmpeg.org/ffmpeg-codecs.html) [PRIMARY]
- MSU 2023–2024 4K comparison (report dated 06.04.2025) [PRIMARY test, numbers not extracted]:
  - Included aom v3.10.0 (Slow/Medium) and SVT-AV1 v2.2.1 (Slow/Medium/Fast), vs Reference x265 v3.5, on an i7-12700K.
  - Leaderboard scores appear only as chart images; the full numbers are in the paid report.
  - Source: [MSU Video Codecs Comparison 2023–2024, 4K](https://compression.ru/video/codec_comparison/2023/4k_report.html)

### Inferences
- The ffmpeg default `cpu-used=1` with `row-mt` off would be extremely slow on long 4K files. Any aomenc mode needs at least `-cpu-used 4 -row-mt 1 -tiles 2x1`, plus chunked parallelism.
- Given SVT-AV1's upstreamed psy features and continued Arm Neon work, aomenc offers little for this app beyond niche 4:4:4 needs.

### Gaps
- No 2025–2026 primary BD-rate of SVT-AV1 4.x vs libaom 3.1x at matched encode time.
- MSU numbers are locked in images or the paid report.

## Q5. VVC/H.266 (vvenc): maturity, ffmpeg support, gains, speed, macOS playback, practicality

### Takeaway
vvenc is mature and fast for a VVC encoder.
- Latest is **v1.14.0** (21 Jan; year very likely 2026), with Arm Neon/SVE SIMD.
- ffmpeg has had `libvvenc` since **7.1 (late Sept 2024)** and a stable native VVC decoder since 7.1.
- Fraunhofer reports −35% (medium) to −42% (slower) PSNR BD-rate vs HEVC reference HM.
- Older reference-encoder studies put VVC about 25–29% ahead of AV1.

The blocker is playback: Apple has no native VVC, VLC's MP4 demux has had VVC gaps, and mpv/IINA support depends on the bundled FFmpeg. For a personal archive whose files must play everywhere, VVC is a risky default in 2026. It is viable only as an opt-in "experimental max compression" mode.

### Cited Findings
- **vvenc releases [PRIMARY: GitHub releases; page shows day/month only]** — [vvenc releases](https://github.com/fraunhoferhhi/vvenc/releases)
  - v1.14.0 (21 Jan):
    - Many ARM SIMD optimizations (NEON and SVE), with SVE enabled by default where supported.
    - VUI enabled automatically.
    - Colour range setting.
    - LMCS deprecated.
  - v1.13.1 (21 Mar): fixed ARM unaligned loads/stores; requires SSE4.1 on x86.
  - v1.13.0 (13 Dec):
    - More ARM optimizations; GOP-adaptive QP cascade.
    - Experimental film-grain analysis.
    - 5% speedup for medium, 2% for slow/slower.
  - v1.12.0 (27 Jun): capped constant-quality mode (CQF) with QPA; about 5% speedup for faster.
- **vvenc BD-rate [PRIMARY: Fraunhofer wiki, v1.14.0, page edited 2026-03-30]** — [vvenc Encoder Performance wiki](https://github.com/fraunhoferhhi/vvenc/wiki/Encoder-Performance)
  - Hardware: AMD EPYC 7502P, 8 threads, HD+4K test set.
  - The page shows x265 (v3.5/v3.4) only in figures, with no numeric BD-rate.

  PSNR-YUV BD-rate vs HM-17.0 (speedup vs HM in brackets):

  | Preset | BD-rate vs HM | Speedup vs HM |
  |---|---|---|
  | faster | −13.3% | 380x |
  | fast | −25.8% | 180x |
  | medium | −35.1% | 53x |
  | slow | −39.1% | 14x |
  | slower | −42.1% | "03x" as printed |

  MS-SSIM BD-rate with perceptual QPA vs HM-16.24:

  | Preset | BD-rate vs HM |
  |---|---|
  | faster | −21.0% |
  | fast | −31.9% |
  | medium | −39.4% |
  | slow | −43.2% |
  | slower | −45.6% |
- **VVC vs AV1 (reference encoders, dated 2021) [PRIMARY paper]** — [Nguyen & Marpe, APSIPA Trans. 2021](https://www.cambridge.org/core/journals/apsipa-transactions-on-signal-and-information-processing/article/compression-efficiency-analysis-of-av1-vvc-and-hevc-for-random-access-applications/D2345DDC3750055AB0AA3D24FCF743BE)
  - JVET CTC random access, PSNR: AV1 (libaom commit 85a9314) about 10–15% savings vs HM-16.21.
  - VTM-8.0 about 36–37% vs HM.
  - VTM vs AV1: about 25–29% in VTM's favor.
  - Reference encoders only; not vvenc vs SVT-AV1.
- A 2025 academic comparison (LCEVC vs open-source codecs, 10-bit UHD/HD, VMAF, random access) finds "VVenC exhibits strong compression performance at the expense of high complexity", while SVT-AV1 is "a more balanced compromise" — [UMH paper](https://dspace.umh.es/bitstream/11000/39590/1/Comparing_V-Nova_LCEVC_SDK_with_Practical_Open-Source_Video_Codecs.pdf) [PRIMARY, numbers not extracted]
- MSU 2023–2024 4K included VVenC v1.13.0 (Slow/Medium) alongside SVT-AV1 v2.2.1 and aom v3.10.0. Scores are not in the HTML text — [MSU 4K report](https://compression.ru/video/codec_comparison/2023/4k_report.html)
- **ffmpeg support:**
  - libvvenc encoder patch merged 15 June 2024; requires libvvenc ≥1.6.1; shipped in FFmpeg 7.1.
  - Native VVC decoder: experimental in 7.0, stable in 7.1.
  - Sources: [vvenc FFmpeg Integration wiki](https://github.com/fraunhoferhhi/vvenc/wiki/FFmpeg-Integration); [J-B Kempf, FFmpeg 7.1](https://jbkempf.com/blog/2024/ffmpeg-7.1.0); [Phoronix FFmpeg 7.0](https://phoronix.com/news/FFmpeg-7.0-Released) [PRIMARY/SECONDARY]
- **ffmpeg `libvvenc` options [PRIMARY]** — [FFmpeg codecs documentation](https://ffmpeg.org/ffmpeg-codecs.html)
  - `b`, `g` (only intra-only g=1 or default), `preset`, `levelidc`, `tier`, `qp`.
  - `subopt` (subjective optimization, default 1), `bitdepth8` (default 0), `period` (intra refresh in seconds).
  - `vvenc-params` (":"-separated key=value).
  - **VVenC accepts only 10-bit input** (feed `yuv420p10le`); internal coding depth is 8 or 10.
  - **No `crf` option:** quality mode is `qp` with QPA.
- **macOS playback:**
  - Apple does not natively support H.266/VVC.
  - Elmedia Player added VVC via Fraunhofer VVdeC in 2023, later up to 8K.
  - Sources: [iDownloadBlog](https://www.idownloadblog.com/?p=967187); [Fraunhofer HHI news 2023-08-21](https://hhi.fraunhofer.de/en/news/nachrichten/2023/fraunhofer-hhi-and-electronic-team-demonstrate-how-vvc-technology-provides-a-greatly-enhanced-multimedia-experience.html) [PRIMARY/SECONDARY, 2023]
- A VideoLAN issue reports VLC does not play VVC inside MP4 because the MP4 demuxer lacked handling (issue date not retrieved) — [VLC issue #27055](https://code.videolan.org/videolan/vlc/-/issues/27055) [PRIMARY]
- No source was found confirming VVC playback in mpv or IINA.

### Inferences
- mpv/IINA builds linked against FFmpeg ≥7.1 should decode VVC through FFmpeg's native decoder. MKV is likely the safer container than MP4. Unverified: test with the actual Homebrew mpv and IINA builds.
- No hardware VVC decode exists on Apple Silicon, so 4K VVC playback is CPU decode. This was not measured here.
- Encode speed: vvenc `medium` is about 53x faster than single-threaded HM, but that is still far slower than SVT-AV1 preset 4–6. No Apple Silicon fps was found.
- The rule of thumb that VVC is about 10–25% more efficient than AV1 is consistent with the 2021 reference-encoder study. It does not apply directly to vvenc-vs-SVT-AV1 at practical presets.
- Practicality verdict for a personal archive app (inference):
  - AV1 (SVT-AV1) should be the "max compression" default: hardware decode on newer Macs and broad player support.
  - VVC fits only as an opt-in experimental mode for users who accept slow encodes and limited playback (mpv/IINA/Elmedia only, no QuickTime/Photos/iOS).

### Gaps
- vvenc release years are not shown on the releases page. "v1.14.0 = Jan 2026" is inferred from the wiki using v1.14.0 (edited Mar 2026) and MSU using v1.13.0 in April 2025.
- No numeric vvenc vs x265 or vvenc vs SVT-AV1 BD-rate at practical presets.
- No Apple Silicon vvenc fps.
- 2026 status of VLC 3.x/4.x, mpv and IINA VVC playback is unconfirmed.

## Q6. Typical size reduction converting H.264 sources to AV1 at transparent quality

### Takeaway
No controlled, citable benchmark of H.264 to AV1 at "transparent" quality was found. Community reports put AV1 outputs at about **50–70% of the H.264 source size** (about 30–50% reduction). Savings depend heavily on how bloated the source is: bigger for Blu-ray remuxes and phone recordings, smaller for already-efficient web encodes. Generation loss is unavoidable, since re-encoding lossy sources is always lossy.

### Cited Findings
- Emby user: AV1 outputs "roughly 50-65% the original file size with little to no discernible difference". Another user moving from H.264 estimated about 30% reduction — [Emby forum](https://emby.media/community/topic/138471-av1-question/) [COMMUNITY]
- ffmpeg-user list: re-encoding an already-lossy file adds "losses on top of losses" — [FFmpeg-user 2023-10](https://ffmpeg.org/pipermail/ffmpeg-user/2023-October/056936.html) [COMMUNITY, 2023]
- Codec-generation context: AV1 (libaom) about 10–15% better than HEVC reference and VVC about 36–37% better, under PSNR/CTC conditions. These are codec-vs-codec numbers on pristine sources, not transcode-from-H.264 numbers — [Nguyen & Marpe 2021](https://www.cambridge.org/core/journals/apsipa-transactions-on-signal-and-information-processing/article/compression-efficiency-analysis-of-av1-vvc-and-hevc-for-random-access-applications/D2345DDC3750055AB0AA3D24FCF743BE)
- **Apple Silicon throughput [COMMUNITY]:**
  - M4 Mac mini, SVT-AV1 preset 6, 1080p 10-bit via HandBrake: about 38 fps. Ryzen 5800X on the same test: about 33 fps.
  - M2 Ultra, preset 6: about 32.4 fps. i9-14900K: about 31.7 fps.
  - Both in a Feb 2025 thread, i.e. SVT-AV1 2.x/3.0 era — [r/AV1 thread](https://red.ks32.dev/r/AV1/comments/1imnxzu/svtav1_on_arm_specifically_apple_silicon_m4)
  - HandBrake default SVT-AV1 settings, roughly 79-minute movie (2023–24):
    - M3 Max: 12m50s (8-bit), 13m46s (10-bit).
    - M2 Max: 17m35s / 21m13s.
    - M1 Max: 21m18s / 22m34s.
    - Source: [MacRumors AV1 encoding test](https://forums.macrumors.com/threads/av1-encoding-test.2411996)
  - The same thread notes the M3 has hardware AV1 decode, while encoding stays software.

### Inferences
- **Source-dependent savings (rough):**
  - Blu-ray remux (H.264 at about 20–40 Mbps): savings likely far exceed 50%, because the source bitrate is far above what transparency needs.
  - Phone recordings (high-bitrate H.264/HEVC): likely similar large savings.
  - Web downloads (already about 2–8 Mbps H.264): likely about 20–40%, with higher generation-loss risk.

  These are reasoning, not measurements. The app should measure per file (e.g. trial-encode a sample and compare size and VMAF/SSIMULACRA2) and keep the original if savings fall below a threshold.
- From the MacRumors times, the HandBrake default implies roughly 140–150 fps for a 24 fps film on the M3 Max. That suggests a fast SVT preset and/or lower resolution, not an archival preset. At archival presets (2–4), expect single-digit to low-tens fps at 1080p and lower at 4K. Not measured; benchmark on target Macs.
- Post-2025 Arm optimizations should make current Apple Silicon numbers better than the 2025 community figures: 3.1: +3–8%; 4.2/4.3: Neon kernels and about 10–11% lower MT runtime. This holds only to the extent the Neon (not SVE) paths apply.

### Gaps
- No controlled Blu-ray/web/phone H.264 to AV1 size study at matched perceptual quality was found.
- No per-preset Apple Silicon fps for SVT-AV1 4.x, libaom or vvenc.
