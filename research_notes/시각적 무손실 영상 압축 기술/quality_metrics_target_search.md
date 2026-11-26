# Objective Video Quality Metrics and Automated Target-Quality Search (state as of 2026-11-26)

Scope: metrics for "visually lossless" encoding and tools that search for the most compressive encoder setting meeting a quality target, for a personal macOS (Apple Silicon, macOS 14+) app built on ffmpeg.

Source labels used below:
- **[primary]** = official repo docs, source code, release notes, ffmpeg docs, or peer-reviewed/arXiv paper read directly in this session.
- **[snippet]** = seen only through a search-engine summary. The full page was not read (for example, the Netflix tech blog returned HTTP 403 to fetches).
- **[community]** = GitHub issue reports, blogs, or forum posts. These are anecdotes, not controlled studies.
- **Inferences** sections contain my own reasoning and are not sourced facts.

---

## 1. VMAF: current version, models, "transparent" score, weaknesses, pooling

### Takeaway
VMAF changed a lot in 2026. libvmaf v3.2.0 (2026-06-20) shipped a new **VMAF v1** model family (`vmaf_v1.0.16_*`): 1080p@3H, phone@5H, 4K@1.5H, 4K@3H, plus HFR variants. An HDR-VMAF v1 (`hdr_vmaf_v1.1.8`) followed on 2026-10-26, and v3.2.1 (2026-09-14) is the current libvmaf release. No primary source defines a "visually lossless" VMAF score. ab-av1 defaults to 95, and a widely repeated heuristic says 6 VMAF points is about 1 JND. Mean pooling hides bad scenes, so you need per-frame or percentile checks.

### Cited Findings

**Versions and release timeline**
- libvmaf releases: v3.0.0 (2023-12-07), v3.1.0 (2026-04-02, adds `--aom_ctc v7.0`), v3.2.0 (2026-06-20, "Initial public release for VMAF v1"), v3.2.1 (2026-09-14, a small fix release) [primary] — [Netflix/vmaf releases](https://github.com/Netflix/vmaf/releases)
- v3.2.1 changes relevant to Apple Silicon: "Add ARM NEON implementation for 8-bit integer motion feature", a thread-pool backpressure fix, and a CUDA fix for wrong >8-bit motion scores [primary] — [v3.2.1 release](https://github.com/Netflix/vmaf/releases/tag/v3.2.1)
- v3.2.0 also added experimental `VMAF_BATCH_THREADING` and `VMAF_PICTURE_POOL` threading modes, a CAMBI speedup, and "2160p@1.5H CSF support" [primary] — [v3.2.0 release](https://github.com/Netflix/vmaf/releases/tag/v3.2.0)
- README news: "(2026-06) We are releasing a new set of VMAF models (v1)… The previous generation of models (v0) remains documented in models_v0.md." It also says: "(2026-10-26) We are releasing an HDR version for VMAF-v1" [primary] — [VMAF README](https://github.com/Netflix/vmaf/blob/master/README.md)
- Homebrew currently ships `libvmaf` 3.2.1 with arm64 bottles for recent macOS, and its `ffmpeg` 9.1 formula depends on `libvmaf` and `svt-av1` [primary] — [Homebrew libvmaf](https://formulae.brew.sh/formula/libvmaf), [Homebrew ffmpeg](https://formulae.brew.sh/formula/ffmpeg)

**VMAF v1 models (June 2026)** [primary] — [models_v1.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md)
- "These models have demonstrated better accuracy compared to the previous set of models (VMAF v0)." No correlation numbers for SDR v1 appear in the repo doc.
- Model files:

| Scenario | Model | Range |
|---|---|---|
| Standard 1080p@3H | `model/vmaf_v1.0.16/vmaf_v1.0.16_3d0h.json` | [0, 100] |
| Phone 1080p@5H | `vmaf_v1.0.16_5d0h.json` | [0, 100] |
| 4K default @1.5H | `vmaf_v1.0.16_1d5h_2160.json` | [0, 100] |
| 4K consumer TV @3H | `vmaf_v1.0.16_3d0h_2160.json` | **[0, 110]** |

- "VMAF v1 should ideally be applied at 10-bit precision for SDR, which helps more accurately capture the presence of banding. Even if the encoded video is 8-bit, VMAF can still be measured at 10 bits by appropriately preprocessing both video inputs."
- Encode-side params can be passed to CAMBI, for example `:cambi.enc_width=1280:cambi.enc_height=720:cambi.enc_bitdepth=8`.
- The HFR variants (`model/vmaf_v1.0.16_hfr/`) target about 50/60 fps. They use a five-frame motion window (i-2, i, i+2), and the doc says "HFR handling remains an area of active improvement".
- Features in the v1 1080p model JSON: `Cambi_feature_cambi_score`, `Speed_chroma_feature_speed_chroma_uv_score`, `VMAF_integer_feature_adm3_score`, `VMAF_integer_feature_motion3_score`. The model is NU-SVR, `score_clip [0,100]`, and the ADM options include `adm_enhn_gain_limit: 1.0` [primary] — [vmaf_v1.0.16_3d0h.json](https://github.com/Netflix/vmaf/blob/master/model/vmaf_v1.0.16/vmaf_v1.0.16_3d0h.json)
- The Netflix blog post "VMAF v1: Good Is Not Good Enough" (Bampis, Li et al.) reportedly adds CAMBI as a feature for banding and an AIM (additive impairment) component that complements DLM. It also reportedly says the v1 scale was calibrated to match v0 [snippet] — [Netflix Tech Blog](https://netflixtechblog.com/vmaf-v1-good-is-not-good-enough-60d7e4244ea8). Wikipedia says NEG is now on by default [snippet] — [Wikipedia VMAF](https://en.wikipedia.org/wiki/Video_Multimethod_Assessment_Fusion). One secondary blog says v0 and v1 scores are "not interchangeable" [snippet] — [Inverity](https://www.inverity.ai/posts/vmaf-explained-2026). **These two claims conflict.**

**HDR-VMAF v1 (2026-10-26)** [primary] — [models_v1.md#hdr-models](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md)
- Model `model/hdr_vmaf_v1.1.8/hdr_vmaf_v1.1.8_3d0h.json`; HFR variants also exist (`hdr_vmaf_v1.1.8_hfr`).
- Inputs are converted to PQ, BT.2020, ICtCp, 4:2:0, 16-bit (`yuv420p16le`). libvmaf must be built with `-Denable_zimg=true`, and colorimetry must be given for both inputs (`--color_range_ref`, `--color_primaries_ref`, `--color_trc_ref`, `--color_matrix_ref`, and the `_dist` equivalents). If colorimetry is missing, the library errors instead of guessing.
- "If you select an SDR model for HDR inputs, no conversion is applied and no warning is shown… the result is not meaningful."
- HDR models rescale both pictures so the short side equals 1080 or 2160. Aspect ratios wider than 4:1 are rejected.
- Reported SRCC for HDR-VMAF v1.1.8 4K@1.5H: LIVE-HDR-VQA 0.8471, ICME-2025 (HDR) 0.7420, LIVE-HDR-SDR (HDR) 0.9316.

**v0 models (still the ffmpeg default)** [primary] — [models_v0.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v0.md)
- `vmaf_v0.6.1` was trained for 1080p HDTV at 3H, with 10 s Netflix clips, 6 resolutions × 3 encoding params. "Bad" maps to about 20 and "excellent" to 100.
- `vmaf_4k_v0.6.1` targets 4KTV at 1.5H (added June 2018). The phone model scores higher than the default model.
- NEG variants (`vmaf_v0.6.1neg`, `vmaf_4k_v0.6.1neg`) disable "enhancement gain" from sharpening or contrast pre-processing, for codec comparison. v0.6.2 and v0.6.3 show "no material differences" from 0.6.1, but add bootstrap confidence intervals.
- The ffmpeg `libvmaf` filter's documented default is still `model` = `"version=vmaf_v0.6.1"` [primary] — [ffmpeg-filters libvmaf](https://ffmpeg.org/ffmpeg-filters.html#libvmaf)

**Thresholds and the "transparent" score**
- ab-av1's default target is `DEFAULT_MIN_VMAF: f32 = 95.0` [primary] — [ab-av1 crf_search.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/crf_search.rs). Av1an's first doc example is `--target-quality 95` [primary] — [Av1an target_quality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Cli/target_quality.md)
- Jan Ozer reports that Netflix told him "6 VMAF points ~ 1 JND" for ladder steps [community/secondary] — [Streaming Learning Center](https://streaminglearningcenter.com/blogs/finding-the-just-noticeable-difference-with-netflix-vmaf.html). An academic framework maps ΔVMAF to the probability of JND instead of a fixed point count [primary abstract] — [arXiv 2205.07565](https://arxiv.org/abs/2205.07565)
- A search across JND literature found no primary source that names 93, 95 or 97 as the VMAF "visually lossless" threshold [snippet] — [arXiv 2401.15343](https://arxiv.org/pdf/2401.15343) (treats "100 − JND" as perceptually lossless)
- Self-comparison does not give 100: "you should get a score close enough", for example 98.7 [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md)

**Known weaknesses**
- Viewing-condition dependence: VMAF computed at native 480p behaves like viewing from 6.75H and "is going to hide a lot of artifacts". Upscale the distorted video to the reference or model resolution, using bicubic as recommended [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md), [VMAF ffmpeg.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/ffmpeg.md)
- Scope: VMAF "only considers compression artifact and scaling artifact". Other artifacts "MAY be predicted inaccurately" [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md)
- Banding: CAMBI was open-sourced in 2021 as a separate banding detector, and it is now a v1 model feature [primary] — [VMAF README](https://github.com/Netflix/vmaf/blob/master/README.md), [cambi.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/cambi.md). Streaming Media reports that "VMAF has shown insensitivity to banding and to grain retention" for v0-era use [snippet] — [Streaming Media](https://www.streamingmedia.com/Articles/Post/Blog/Challenges-of-New-Encoding-Scenarios-Reflections-on-Measuring-Perceived-Quality-166721.aspx)
- Film-grain synthesis: an IBC 2023 subjective study says synthesized grain is "perceptually pleasant" but leads to "underestimation of quality in full-reference metrics like PSNR, SSIM, and to a minor extent VMAF". It also says VMAF/AVQT lack consideration of "statistical naturalness of the grain" [snippet] — [IBC 2023 paper](https://ibc.org/technical-papers/ibc2023-tech-papers-a-subjective-study-of-film-grain-synthesis-for-the-preservation-of-creative-intent-/10283.article)
- Gaming: some contrast and color distortions raise VMAF ("Hacking VMAF") [snippet] — [arXiv 1907.04807](https://arxiv.org/pdf/1907.04807). NEG exists to counter enhancement gain [primary] — [models_v0.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v0.md)
- In a high-fidelity *image* benchmark (JPEG AIC-3, 2025), plain VMAF ranked 15th of 27 metrics by SROCC and VMAF-NEG ranked 6th. The authors also say VMAF "performs worse" at capturing contrast masking than SSIM/MS-SSIM/LPIPS/DISTS [primary] — [arXiv 2509.13150](https://arxiv.org/html/2509.13150)

**Pooling**
- Default aggregate = arithmetic mean of per-frame scores. "Human opinions tend to weigh more heavily towards the worst-quality frames". The Python tools support `--pool` with `mean`, `harmonic_mean`, `median`, `min`, `perc5`, `perc10`, `perc20` [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md)
- ffmpeg `libvmaf` filter `pool` option: `min`, `harmonic_mean`, or `mean` (default). Per-frame scores are available through `log_path`/`log_fmt` (xml/json/csv/sub) [primary] — [ffmpeg-filters libvmaf](https://ffmpeg.org/ffmpeg-filters.html#libvmaf)
- Av1an's documented default probing statistic is the 1st percentile of per-frame scores (`percentile=1`). Its text also lists `auto`, which in source returns `statistics.percentile(1)` in at least one branch [primary] — [Av1an target_quality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Cli/target_quality.md), [target_quality.rs](https://github.com/rust-av/Av1an/blob/master/av1an-core/src/target_quality.rs)

### Inferences
- For this app, select VMAF v1 explicitly: `model=version=vmaf_v1.0.16_3d0h` for ≤1080p and `vmaf_v1.0.16_1d5h_2160` for 4K, with `_hfr` variants for ≥50 fps. The ffmpeg filter default is still v0.6.1. ab-av1 v0.12.0 does the same thing and falls back to v0 when the libvmaf build lacks v1. Your app should detect this case and do the same.
- `adm_enhn_gain_limit: 1.0` in the v1 JSON is the setting that NEG models use. This supports the "NEG by default" claim, so v1 should be harder to inflate with sharpening. I have not checked this against a primary text statement.
- 95 (ab-av1 default) is a pragmatic target, not a validated transparency point. For a "visually lossless" feature, a mean target of about 95–97 with a per-frame low-percentile floor is a reasonable starting design. Validate it with your own A/B flicker checks. Treat v0 thresholds as not directly transferable to v1 until Netflix's calibration claim is verified.
- Do not run SDR VMAF on HDR (iPhone HLG/Dolby Vision) sources. Use HDR-VMAF if your libvmaf build has zimg, or skip metric targeting for HDR.
- If the encoder uses film-grain synthesis (`film-grain=` in svt-av1), VMAF and other full-reference metrics will under-score. Either disable synthesis during probing or don't use a VMAF target for grain-synth encodes.

### Gaps
- Netflix's v1 blog (403) was not read in full. Numeric SDR v1 vs v0 accuracy gains, the exact calibration claim, and v1 compute cost relative to v0 are unverified.
- No primary subjective study found that maps a VMAF (v0 or v1) score to "transparent". The 93/95/97 folklore remains folklore. A commonly cited claim, usually attributed to Jan Ozer or Real Networks, that "VMAF ≥93 means indistinguishable or not annoying" was not verified in this session.
- Not verified whether Homebrew's libvmaf 3.2.1 is built with zimg (needed for HDR-VMAF) or embeds the v1 built-in models (`model=version=...`). Check this locally with `ffmpeg -h filter=libvmaf` and a test run.

---

## 2. Alternative metrics: SSIMULACRA2, XPSNR, Butteraugli, CVVDP, PSNR-HVS

### Takeaway
In the one recent near-transparent benchmark found (2025, still images, JPEG AIC-3), CVVDP ranked best. SSIMULACRA2 and Butteraugli were mid-pack, and VMAF ranked low. No equivalent video-specific near-lossless benchmark was found. On macOS with stock ffmpeg, only VMAF (+PSNR/PSNR-HVS/SSIM/MS-SSIM/CIEDE via libvmaf), XPSNR, SSIM and PSNR run natively. SSIMULACRA2, Butteraugli and CVVDP need extra tooling. GPU acceleration exists for CUDA/HIP/Vulkan (Vship) and for PyTorch MPS (CVVDP), with no native Metal path found.

### Cited Findings

**Accuracy near transparency**
- JPEG AIC-3 high-fidelity image study (Mohammadi, Jenadeleh, Sneyers, Saupe, Ascenso; arXiv 2025-09-16): "many widely used metrics, while effective at lower quality levels, struggle to distinguish subtle perceptual differences… CVVDP consistently has higher performance across multiple evaluation criteria and statistical tests… IW-SSIM emerged as the next best-performing metric." SROCC order of 27 metrics: 1 CVVDP, 2 IW-SSIM, 3 HDR-VDP-3, 4 MS-SSIM, 5 NLPD, 6 VMAF-NEG, 7 SSIM, … 12 SSIMULACRA2, 13 Butteraugli, … 15 VMAF, 16 PSNR-HVS, … 23 PSNR-Y [primary] — [arXiv 2509.13150](https://arxiv.org/html/2509.13150)
- SSIMULACRA 2.1 self-reported correlations: CID22 SRCC 0.8805, TID2013 0.8445, KADID-10k 0.8133, KonFiG(F) 0.9194. All are *image* datasets [primary] — [cloudinary/ssimulacra2](https://github.com/cloudinary/ssimulacra2)

**SSIMULACRA2 score scale (images)** [primary] — [cloudinary/ssimulacra2](https://github.com/cloudinary/ssimulacra2)
- 70 = high quality ("artifacts perceptible, but not annoying", about cjxl -d 2.5).
- 80 = very high quality ("not noticeable … side-by-side comparison at 1:1", about cjxl -d 1.5).
- 85 = excellent ("not noticeable … in-place comparison", about cjxl -d 1 / jpeg q90 4:4:4).
- **90 = visually lossless** ("not noticeable … in a flicker test at 1:1", about cjxl -d 0.5 / jpeg q95 4:4:4).
- 100 = mathematically lossless.
- Method: MS-SSIM-like comparison in XYB, plus blockiness/ringing and blur maps at 6 scales; 108 weighted norms. Usage: `ssimulacra2 original.png distorted.png`, which is image-only.

**CVVDP (ColorVideoVDP)** [primary] — [gfxdisp/ColorVideoVDP](https://github.com/gfxdisp/ColorVideoVDP)
- Full-reference, video-aware, SDR and HDR. It needs a display model (`--display standard_fhd`, `standard_4k`, `standard_hdr_pq`, `standard_hdr_hlg`) because it models display size, resolution, peak luminance, viewing distance and ambient light.
- Output is in JOD units: 10 = no difference. A 1-JOD difference means 75% of the population prefers the higher one.
- Implemented in PyTorch. "Can be run efficiently on a CUDA-enabled GPU… on a CPU… processing times will be much longer, especially for video." "To use MPS on a Mac, please install torch>=2.1.0." Install with `pip install cvvdp`. It reads video through ffmpeg. Latest release tag v0.5.7 (2026-08-02).

**XPSNR** [primary]
- In ffmpeg as the `xpsnr` filter, added 2024-08-28 ("avfilter: add XPSNR filter") — [FFmpeg commit history](https://github.com/FFmpeg/FFmpeg/commits/master/libavfilter/vf_xpsnr.c)
- It is a "low-complexity" blockwise perceptually weighted PSNR. **Input order: first = reference, second = distorted.** This is the opposite of `libvmaf`, which takes the distorted input first. The inputs must share pixel format except bit depth. Docs suggest reporting the minimum of the per-plane averages. `stats_file` gives per-frame values — [ffmpeg-filters xpsnr](https://ffmpeg.org/ffmpeg-filters.html#xpsnr)
- ab-av1 supports `--min-xpsnr` as an alternative to VMAF, with default `--xpsnr-fps` 60 and `--xpsnr-pix-format` as a 10-bit workaround [primary] — [ab-av1 README](https://github.com/alexheretic/ab-av1/blob/main/README.md), [CHANGELOG](https://github.com/alexheretic/ab-av1/blob/main/CHANGELOG.md). Av1an supports `xpsnr` (min of Y/U/V) and `xpsnr-weighted` ((4Y+U+V)/6) [primary] — [Av1an target_quality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Cli/target_quality.md)

**PSNR-HVS, SSIM, MS-SSIM, CIEDE2000**
- Bundled in libvmaf: "PSNR, PSNR-HVS, SSIM, MS-SSIM and CIEDE2000". You can add them through the ffmpeg `libvmaf` `feature=` option, for example `feature=name=psnr|name=ciede` [primary] — [VMAF README](https://github.com/Netflix/vmaf/blob/master/README.md), [ffmpeg-filters libvmaf](https://ffmpeg.org/ffmpeg-filters.html#libvmaf)
- libvmaf PSNR is capped at 60 dB (8-bit) or 72 dB (10-bit). libvmaf SSIM includes empirical downsampling, so it differs from ffmpeg's `ssim` filter [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md)

**Tooling and acceleration**
- Vship (Codeberg; GitHub repo now only a "moved" notice): GPU SSIMULACRA2, Butteraugli and CVVDP via "HIP/CUDA or Vulkan", with the `FFVship` CLI, a VapourSynth plugin and a C API. Release v5.1.2 (2026-10-06) ships NVIDIA and Vulkan builds (Windows DLL); no macOS binary is listed [primary] — [Vship](https://codeberg.org/Line-fr/Vship)
- Av1an's `ssimulacra2`/`butteraugli` targets need VapourSynth + Vship (GPU, "recommended") or vszip / vapoursynth-julek-plugin (CPU). They also need a VapourSynth chunk method (`lsmash`, `ffms2`, `bestsource`, `dgdecnv`). Av1an's Butteraugli uses a 203-nit target intensity, with `butteraugli-inf` and `butteraugli-3` (3-norm) variants [primary] — [Av1an target_quality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Cli/target_quality.md)
- libvmaf GPU support: only CUDA (`libvmaf_cuda` ffmpeg filter, needs `--enable-nonfree --enable-ffnvcodec`). libvmaf has `arm64` NEON kernels for `adm`, `motion`, `speed` and `vif`, but **none for `cambi`**, which has only x86 AVX2. No Metal or Vulkan backend exists in the tree [primary] — [libvmaf feature tree](https://github.com/Netflix/vmaf/tree/master/libvmaf/src/feature), [ffmpeg-filters libvmaf_cuda](https://ffmpeg.org/ffmpeg-filters.html#libvmaf_005fcuda)

### Inferences
- For a near-transparent target, CVVDP has the best evidence, but it is image-domain evidence. CVVDP is also the only option that models display and viewing distance and handles HDR. Its cost is a PyTorch dependency, with MPS on Mac and unknown video speed. A pragmatic stack: VMAF v1 (fast, in ffmpeg) as the search metric, plus an optional CVVDP or SSIMULACRA2 spot-check of the chosen CRF.
- VMAF v1 uses CAMBI and drops VIF. VIF was the slowest v0 feature on x86 according to NVIDIA. CAMBI has no NEON path, so v1's relative speed on Apple Silicon may differ from x86. **Benchmark it locally.**
- Vship's Vulkan backend might run on macOS through MoltenVK. I found no evidence that anyone has built or tested this, so treat it as unsupported.
- XPSNR is the cheapest perceptual-ish option in stock ffmpeg. It is good for fast coarse search, but it has no published "transparent" threshold here.

### Gaps
- No video-specific (not image) subjective benchmark of metric accuracy at near-transparent quality was found for 2024–2026, including SSIMULACRA2-on-video or VMAF v1.
- No published Butteraugli "visually lossless" threshold was verified this session. The libjxl "distance 1.0 ≈ visually lossless" convention is unverified here. Only the SSIMULACRA2 README mapping (cjxl -d 1 ≈ SSIMU2 85) was seen.
- No Apple Silicon speed numbers were found for SSIMULACRA2, Butteraugli, CVVDP-on-MPS or XPSNR.
- Not verified whether Homebrew packages `ssimulacra2_rs`, the libjxl `butteraugli_main`/`ssimulacra2` tools, VapourSynth+vszip, or `cvvdp`.

---

## 3. Target-quality search tools: ab-av1, Av1an; sample-estimation failure modes

### Takeaway
ab-av1 (v0.12.0, 2026-11-20) works like this:
- Sampling: it cuts evenly spaced 20 s stream-copy samples, one per 12 min of input (at least 1).
- Search: an interpolated binary search over CRF scores the **arithmetic mean** of the per-sample mean VMAF.
- Default target: VMAF 95 at ≤80% of input size.

Av1an (v0.6.0, 2026-10-26) runs a per-scene-chunk search with up to 4 probes, scored by default at the 1st percentile of per-frame scores. The main failure modes of sampling: samples miss hard scenes, mean pooling hides bad scenes, and VFR or timestamp desync makes scores collapse. Users have reported sample overestimates of about 1.5–2.7 VMAF points vs full-file VMAF.

### Cited Findings

**ab-av1 defaults (source, main branch)** [primary]
- Release v0.12.0 (2026-11-20) defaults to VMAF v1 models: `vmaf_v1.0.16_3d0h` replaces `vmaf_v0.6.1`, and `vmaf_v1.0.16_1d5h_2160` replaces `vmaf_4k_v0.6.1`. It uses the `hfr` variant for distorted ≥50 fps, falls back to v0 if v1 is unsupported, and adds `--score-tolerance` — [CHANGELOG](https://github.com/alexheretic/ab-av1/blob/main/CHANGELOG.md), [args/vmaf.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/args/vmaf.rs)
- Sampling flags — [args.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/args.rs):
  - `--sample-every` default `12m` ("with an input 25-36 minutes long, 3 samples would be used").
  - `--samples N` overrides it.
  - `--min-samples` sets a floor.
  - `--sample-duration` default `20s`.
  - Count = ceil(duration / sample_every), at least 1.
- Placement is evenly spaced and content-agnostic: `start = (duration − sample_duration×samples)/(samples+1) × n + sample_duration × idx` — [sample_encode.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/sample_encode.rs)
  - If total sample time ≥85% of duration, it encodes the whole file as one "full pass".
  - Samples are cut with `-c:v copy`, `-ss` before `-i` and `-frames:v`, always into `.mkv` — [sample.rs](https://github.com/alexheretic/ab-av1/blob/main/src/sample.rs)
- Score aggregation: `mean_vmaf_score` = sum of the per-sample VMAF scores / number of samples. Each sample score is ffmpeg's pooled "VMAF score", which is a mean by default. Size prediction = encoded/sample size ratio applied to the input — [sample_encode.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/sample_encode.rs)
- Search parameters — [crf_search.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/crf_search.rs):
  - Default `--min-vmaf` 95.
  - `--max-encoded-percent` default 80.
  - "Interpolated binary search" with linear VMAF interpolation (`vmaf_lerp_q`). The code itself comments: "Crf values do not linearly map to VMAF changes… this is a flawed method, though it seems to work better than a binary search."
  - 2nd iteration narrows to a 20%/80% subrange.
  - Acceptance tolerance starts at +0.1 above target and doubles per run (0.1, 0.2, 0.4, 0.8 for crf-increment 1). `--thorough` = tolerance 0.05.
  - CRF ranges: min 10 (5 for svt-av1); max 55 (46 for x264/x265).
- Encoder specifics — [CHANGELOG](https://github.com/alexheretic/ab-av1/blob/main/CHANGELOG.md):
  - svt-av1: default range [5, 70], quarter-step CRF (`--crf-increment` 0.25, needs svt-av1 ≥4.0.0).
  - x264/x265: increment 0.1.
  - `hevc_videotoolbox` (macOS hardware HEVC) is supported: `--crf` maps to `-q:v`, with "high crf means HQ".
- VMAF invocation — [args/vmaf.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/args/vmaf.rs):
  - `n_threads` defaults to all system threads.
  - lavfi uses `setpts=PTS-STARTPTS,settb=AVTB` and `libvmaf=shortest=true:ts_sync_mode=nearest`.
  - Sample encodes use `-fps_mode passthrough`.
  - The v0 path forces `--vmaf-fps 25`; the v1 path does not override fps.
  - Auto-upscale to 1080p when w<1728 and h<972 (2160p models: w<3456 and h<1944).
- Safety flags (v0.11.7): `--verify` (full decode + duration within 2 s) and `--fail-fast`. v0.11.5 encodes to a temp file and then renames — [README](https://github.com/alexheretic/ab-av1/blob/main/README.md), [CHANGELOG](https://github.com/alexheretic/ab-av1/blob/main/CHANGELOG.md)

**Av1an** [primary] — [target_quality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Cli/target_quality.md), [TargetQuality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Features/TargetQuality.md), [target_quality.rs](https://github.com/rust-av/Av1an/blob/master/av1an-core/src/target_quality.rs)
- "For each chunk, Target Quality searches for the quantizer/crf needed to achieve a certain metric score… much slower than normal encoding, but can improve the consistency of quality."
- Flags:
  - `--probes` default 4.
  - `--probing-rate` 1–4 (frame-rate divisor for probes).
  - `--probe-res` (default input resolution).
  - `--probing-speed` default `veryfast` unless `--probe-slow`.
  - `--probing-stat`: mean, median, harmonic, rms, `percentile=X`, `standard-deviation=X`, mode, min, max, auto. The table default is `percentile=1`.
  - `--min-q`/`--max-q` early exit.
- Metrics: vmaf, ssimulacra2, butteraugli-inf, butteraugli-3, xpsnr, xpsnr-weighted.
- Interpolation methods in source: linear, quadratic, natural cubic spline, PCHIP, Akima, Catmull-Rom, cubic polynomial.
- The feature doc still says VMAF defaults to 1920x1080 scoring with `vmaf_v0.6.1.pkl`. This may be stale.
- Release v0.6.0 dated 2026-10-26 — [Av1an releases](https://github.com/rust-av/Av1an/releases)
- The ab-av1 author on its scope: "ab-av1 is aimed at being fast by sampling to find a suitable crf and then purely relying on the encoder to provide consistent quality". He points per-scene needs to Av1an [community, maintainer] — [ab-av1 #202](https://github.com/alexheretic/ab-av1/issues/202)

**Failure modes (reported)**
- Overestimation (2024-09): with x265 CRF 17, `--sample-every=5m`, and target 93, projected vs full-file VMAF was 93.24 vs 91.70 (4096×2160), 94.99 vs 93.35 (1080p), and 92.69 vs 90.01 (3840×2160). The reporter said the gap was "minimal" for AV1. Maintainer: "Sampling accuracy depends on the source video… Full pass is accurate but slow." Note that a misapplied `x265-params` string was later found in the same thread [community] — [ab-av1 #220](https://github.com/alexheretic/ab-av1/issues/220)
- Hidden bad scenes: a user argues that averaging "will hide the bad scenes where, locally, VMAF might be way lower (>10) than the overall average". The maintainer said sampling predicts the *average* and suggested more samples or full pass + harmonic mean. A `--sample-aggregate=worst` idea was proposed but not implemented as of that thread [community] — [ab-av1 #202](https://github.com/alexheretic/ab-av1/issues/202)
- VFR sources: on a phone VFR HEVC source, crf-search gave VMAF of about 12–35 because of "desynchronized samples". The workaround discussed was `--vmaf-fps` or converting to CFR [community] — [ab-av1 #311](https://github.com/alexheretic/ab-av1/issues/311)
- Timestamp sync is mandatory: "FFmpeg filters synchronize based on timestamps instead of frames"; use `setpts=PTS-STARTPTS` when a clip does not start at PTS 0 [primary] — [VMAF ffmpeg.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/ffmpeg.md)
- Two-input framesync defaults matter. `eof_action` defaults to `repeat`, `repeatlast` to 1, and `shortest` to 0, so a shorter distorted stream can silently repeat frames. `ts_sync_mode=nearest` picks the frame with the nearest timestamp [primary] — [ffmpeg-filters framesync](https://ffmpeg.org/ffmpeg-filters.html#framesync)

### Inferences
- Stream-copy cutting with `-ss` before `-i` starts each sample at a keyframe at or before the requested time. So in long-GOP sources, samples cluster around keyframes and can include leading frames the encoder treats as an IDR start. This is minor, but it biases samples toward post-cut content.
- Evenly spaced 20 s samples cover only about 2.8% of a film's runtime at the defaults (20 s per 12 min). Dark scenes, gradients prone to banding, and high-motion action can be missed. A personal app could cheaply improve on this:
  1. Run scene detection (ffmpeg `select='gt(scene,X)'` or scdet) or a fast complexity pre-pass, such as first-pass bitrate or a quick low-preset encode.
  2. Pick samples stratified by complexity, including the hardest one or two.
  3. Gate on min(per-sample 1st percentile) as well as the mean.
- iPhone and screen recordings are often VFR. Normalize timestamps and verify the frame count matches between reference and distorted before trusting any score. A score far below expected is more likely a sync bug than real quality.
- A 1.5–2.7 point overestimate is comparable to a quarter to half of the "6 points ≈ 1 JND" heuristic. That suggests adding a safety margin of about 1–2 VMAF points above the target, or verifying with a full-file VMAF pass after the final encode, which ab-av1 does not do.

### Gaps
- No systematic study was found of ab-av1 or Av1an sample-predicted vs full-file VMAF error distributions. The evidence is single user reports.
- The typical number of crf-search iterations to converge was not documented. From the code it is likely about 3–6, but this is unmeasured.
- Av1an's exact default probe-result statistic is inconsistent between its docs table (`percentile=1`) and prose (`auto`).

---

## 4. Scene-based chunking / per-shot encoding: savings vs single CRF

### Takeaway
Netflix's Dynamic Optimizer is a per-shot, multi-resolution, convex-hull optimization. The commonly cited saving is about 30% average bitrate at equal quality vs traditional fixed-ladder streaming. That baseline is not "one good CRF for the whole file", and the 30% comes from secondary or patent sources. No primary measurement was found of per-scene CRF targeting vs a well-chosen single CRF, so the benefit for a single-file personal app is unquantified. It is likely much smaller than 30%, and it multiplies compute.

### Cited Findings
- The Dynamic Optimizer framework "was shown to provide an additional ~30% savings in average bitrate for the same quality as compared to traditional adaptive streaming". A Meta (Facebook) SVT-AV1 VOD paper cites "bit rate savings of up to 30% as compared to the conventional AS approach" [snippet] — [Meta research PDF](https://research.facebook.com/file/619891492563319/Towards-Much-Better-SVT-AV1-Quality-Cycles-Tradeoffs-for-VOD-Applications.pdf), [Intel SVT-AV1 VOD blog](https://networkbuilders.intel.com/blog/svt-av1-enables-highly-efficient-large-scale-video-on-demand-vod-services)
- Mechanism: each shot is encoded at several resolutions and QPs, and points on each shot's rate-distortion convex hull are combined into a global hull. Compute grows roughly with the number of rate points tried per shot. A cheaper variant uses a fast preset to find hull points and then re-encodes at a slow preset. The method was proposed by Netflix in 2018 [snippet] — [Netflix patent 10742708](https://patents.justia.com/patent/10742708), [PoliTo thesis](https://webthesis.biblio.polito.it/26705/1/tesi.pdf)
- Av1an's own claimed benefits of per-chunk target quality are qualitative only: better visual consistency, "enough bitrate to complex segments", and "not overspending on scenes". It reports no percentage [primary] — [Av1an TargetQuality.md](https://github.com/rust-av/Av1an/blob/master/site/src/Features/TargetQuality.md)
- The ab-av1 maintainer's position: a single sampled CRF, then "purely relying on the encoder to provide consistent quality" [community, maintainer] — [ab-av1 #202](https://github.com/alexheretic/ab-av1/issues/202)

### Inferences
- CRF is already a constant-quality rate control that adapts bits per scene. The extra gain from per-scene CRF over one global CRF comes from metric-vs-encoder disagreement and from equalizing the *worst* scenes. A global CRF chosen to make the worst scene pass overspends on easy scenes; that is where per-scene targeting helps. If the global target is a mean, per-scene targeting mostly *raises* the floor rather than saving bits. I would guess single-digit to low-double-digit percent savings at an equal worst-scene floor, but this is unverified.
- The Dynamic Optimizer's 30% includes per-shot *resolution* selection and a fixed-ladder baseline. A personal "visually lossless" app keeps native resolution, so most of that gain does not apply.
- On one Mac, per-scene targeting costs (probes per scene) × (scenes) extra encodes plus metric passes, and it needs a concatenation step: encode chunks with closed GOPs and concat demux. That is a large complexity increase. A reasonable middle ground: one global CRF from complexity-stratified samples, gated on worst-sample percentile, plus an optional post-encode full VMAF verification with a retry at a lower CRF if the 1st-percentile floor fails.

### Gaps
- No primary Netflix tech-blog number was read (blog fetches returned 403).
- No study was found comparing "per-scene CRF to a VMAF target" vs "single CRF to the same target" for AV1/HEVC at near-transparent quality, the regime this app needs.

---

## 5. Compute cost, subsampling, threading, and alignment in ffmpeg `libvmaf`

### Takeaway
No Apple Silicon VMAF benchmarks were found, and none could be run (no ffmpeg on this machine). The x86 reference points: CPU VMAF scales with threads, VIF was the bottleneck in v0, and NVIDIA cites about 176 fps single-stream 1080p CPU VMAF. Use `n_threads` = cores and `n_subsample` 2–5 for search probes. Score at the model's display resolution (upscale lower-res distorted video with bicubic), at 10-bit for v1, with timestamps normalized (`setpts=PTS-STARTPTS`, `settb=AVTB`) and `shortest=1`.

### Cited Findings
- ffmpeg `libvmaf` options [primary] — [ffmpeg-filters libvmaf](https://ffmpeg.org/ffmpeg-filters.html#libvmaf):
  - `model` (default `version=vmaf_v0.6.1`, `|`-delimited multi-model), `feature`, `log_path`, `log_fmt` (xml/json/csv/sub), `pool` (min/harmonic_mean/mean).
  - `n_threads`: "Default value: 0, no threads".
  - `n_subsample`: "frame subsampling interval".
  - It supports the framesync options. **First input = distorted, second = reference.**
  - Example with containers: `[0:v]settb=AVTB,setpts=PTS-STARTPTS[main];[1:v]settb=AVTB,setpts=PTS-STARTPTS[ref];[main][ref]libvmaf=log_fmt=json:log_path=output.json`.
- Netflix example: `-r 24` before `-i`, `setpts=PTS-STARTPTS` on both inputs, `scale=W:H:flags=bicubic` on the distorted input when resolutions differ, `n_threads=4`. "It is important to set the frame rate and the PTS right" [primary] — [VMAF ffmpeg.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/ffmpeg.md)
- Netflix guidance on resolution: upsample the distorted video to the reference (1080) resolution. Comparing native-resolution scores across resolutions is "apples-to-oranges" [primary] — [VMAF FAQ](https://github.com/Netflix/vmaf/blob/master/resource/doc/faq.md)
- ab-av1's defaults as a working reference: `n_threads` = system threads, `shortest=true:ts_sync_mode=nearest`, `settb=AVTB`, `-fps_mode passthrough`, and test fixtures using `n_subsample=4` [primary] — [ab-av1 args/vmaf.rs](https://github.com/alexheretic/ab-av1/blob/main/src/command/args/vmaf.rs). A user reported full-file ground truth with `--vmaf n_subsample=5` on a 1 h+ 1080p60 file [community] — [ab-av1 #220](https://github.com/alexheretic/ab-av1/issues/220)
- NVIDIA (2023/2024): CPU VMAF "can distribute the computation… over multiple threads", "VIF generally requires more time to compute, making it the limiting feature extractor". VMAF-CUDA on an L4 gave "up to 37x lower per-frame latency at 4K and up to 4.4x higher throughput" vs a dual Xeon 8480 (56C/112T) node [snippet] — [NVIDIA VMAF-CUDA blog](https://developer.nvidia.com/blog/calculating-video-quality-using-nvidia-gpus-and-vmaf-cuda). A secondary page attributes "about 176 fps at 1080p" single-stream CPU VMAF to NVIDIA (2024) [snippet, secondary] — [forasoft](https://www.forasoft.com/learn/video-quality/articles-vqm/integrating-quality-measurement-ci-cd). MainConcept logged 18.6 fps CPU libvmaf vs 90.2 fps CUDA at 1080p inside an encode pipeline [snippet] — [MainConcept blog](https://blog.mainconcept.com/vscore-fast-and-easy-video-quality-measurement-for-mainconcept-hevc-encoding)
- libvmaf on arm64 has NEON for `adm`, `motion`, `speed` and `vif`. `cambi` has x86 AVX2 only. GPU support is CUDA only (no Metal) [primary] — [libvmaf feature tree](https://github.com/Netflix/vmaf/tree/master/libvmaf/src/feature). v3.2.1 added NEON 8-bit integer motion [primary] — [v3.2.1 release](https://github.com/Netflix/vmaf/releases/tag/v3.2.1). The v1 model sets `cambi_high_res_speedup: 1080` [primary] — [vmaf_v1.0.16_3d0h.json](https://github.com/Netflix/vmaf/blob/master/model/vmaf_v1.0.16/vmaf_v1.0.16_3d0h.json)
- HDR-VMAF rescales internally to the model's 1080 or 2160 display resolution and requires both inputs to be the same size [primary] — [models_v1.md](https://github.com/Netflix/vmaf/blob/master/resource/doc/models_v1.md)
- The test machine for this session is an Apple M5 Pro (15 cores: 5 performance + 10 efficiency, from `sysctl`) with no ffmpeg installed. No local benchmark was run [own observation].

### Inferences
- Example 1080p graph (v1 model, 10-bit as the models_v1 doc recommends):
  ```
  ffmpeg -i dist.mkv -i ref.mkv -lavfi "[0:v]scale=1920:1080:flags=bicubic,format=yuv420p10le,settb=AVTB,setpts=PTS-STARTPTS[d];[1:v]format=yuv420p10le,settb=AVTB,setpts=PTS-STARTPTS[r];[d][r]libvmaf=model=version=vmaf_v1.0.16_3d0h:n_threads=N:n_subsample=4:shortest=1:ts_sync_mode=nearest:log_fmt=json:log_path=vmaf.json" -f null -
  ```
  Keep the distorted input first. Read per-frame scores from the JSON for percentile and min gating. Reconstruct 10-bit from 8-bit sources by upconversion; this is the "appropriate preprocessing" the doc mentions, but the exact recommended method is not documented.
- Cost model: each CRF probe = encode samples + decode both + VMAF. On Apple Silicon, the encode (svt-av1 slow presets) will likely dominate, not VMAF. `n_subsample=4` roughly quarters VMAF cost per probe. Temporal features compare neighboring frames, so subsampling changes scores slightly; use subsampling for search and full sampling for a final verification. None of this was measured.
- With ~176 fps at 1080p on many-core x86 as a loose reference, a 2-hour 24 fps film (~173k frames) would take about 16 min for full-file 1080p VMAF. 4K costs about 4× the pixels. On a 10–15-core M-series CPU, expect the same order of magnitude, but measure it. Decoding the source (especially 4K HEVC/AV1) can bottleneck the pipeline; VideoToolbox hardware decode (`-hwaccel videotoolbox`) for the reference may help, but this is untested.
- Pin frame counts: compare `nb_read_frames` (ffprobe `-count_frames`) of the reference sample and the encoded sample before scoring. With `eof_action=repeat` defaults, a short distorted stream would silently repeat its last frame.

### Gaps
- No published libvmaf fps on Apple M-series (M1–M5), with or without NEON, v0 vs v1, at 1080p or 4K.
- No measured speedup or score-bias curve for `n_subsample` values.
- Not verified that `ts_sync_mode=nearest` plus `-fps_mode passthrough` fully fixes VFR sources. The ab-av1 #311 report suggests it does not always.
