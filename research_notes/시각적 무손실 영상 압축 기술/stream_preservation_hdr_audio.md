# Preserving everything except video bitrate when re-encoding MP4/MKV with ffmpeg (HDR, Dolby Vision, audio, subtitles, chapters, attachments), as of Nov 2026

Research method note: most claims below were checked against FFmpeg's own source and docs. I fetched these from `github.com/FFmpeg/FFmpeg` master on 2026-11-26, plus release tags n6.1, n7.0, n7.1 and n8.0. The master Changelog already contains sections for **8.1, 9.0 and 9.1**. I did not verify the release dates of 8.1/9.0/9.1. "Source code" citations show what the current master and the named tags do. They do not show what a particular Homebrew build does. Community forum claims are labeled **[community]**. My own reasoning is labeled **[inference]**. trac.ffmpeg.org blocked automated fetches (Anubis), so trac tickets are cited via the ffmpeg-trac mailing-list archive or search snippets.

---

## 1. HDR10 / HLG static metadata (primaries, transfer, matrix, range, mastering display, CLL) with libsvtav1, libx265, hevc_videotoolbox

### Takeaway
Since **FFmpeg 7.0**, the ffmpeg CLI passes these to the encoder automatically: VUI colour tags plus mastering display (ST 2086) and content light level (MaxCLL/MaxFALL) from the decoded frames, for **libx265 and libsvtav1**. No extra options are needed beyond keeping 10-bit (`-pix_fmt yuv420p10le`). **hevc_videotoolbox writes only the colour tags, and drops mastering display and CLL.** This is still true in master (Nov 2026), so VT output is "HDR10 without static metadata".

### Cited Findings
- The FFmpeg 7.0 changelog entry reads: "HDR10 metadata passthrough when encoding with libx264, libx265, and libsvtav1". — [FFmpeg Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- Mechanism: when an encoder opens, the ffmpeg CLI clones the first frame's side data into `enc_ctx->decoded_side_data` (`clone_side_data(... AV_FRAME_SIDE_DATA_FLAG_UNIQUE)`). It also copies `color_primaries`, `color_trc`, `color_range`, `colorspace` and `chroma_sample_location` from the frame into the encoder context. — [fftools/ffmpeg_enc.c (master, lines ~249–278, ~342–345)](https://github.com/FFmpeg/FFmpeg/blob/master/fftools/ffmpeg_enc.c)
- In `handle_side_data()`, libx265 reads `AV_FRAME_DATA_CONTENT_LIGHT_LEVEL` and `AV_FRAME_DATA_MASTERING_DISPLAY_METADATA` from `decoded_side_data`. It writes primaries, transfer and matrix into the x265 VUI whenever any of them is specified, and writes the range flag. For HLG (`arib-std-b67`) it also sets `preferredTransferCharacteristics` (x265 build ≥159). — [libavcodec/libx265.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libx265.c)
- libsvtav1 does the same: `handle_side_data()` maps CLL and MDCV into `param->mastering_display` / content light. It also maps `color_primaries`, `transfer_characteristics`, `matrix_coefficients` and `color_range` from the codec context. — [libavcodec/libsvtav1.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libsvtav1.c)
- Version check (grep of tagged sources, `decoded_side_data` occurrences): n6.1 = 0, and n7.0 / n7.1 / n8.0 = 4 in both libx265.c and libsvtav1.c. Passthrough therefore requires **FFmpeg ≥ 7.0**. — [n6.1 libx265.c](https://github.com/FFmpeg/FFmpeg/blob/n6.1/libavcodec/libx265.c), [n7.0 libx265.c](https://github.com/FFmpeg/FFmpeg/blob/n7.0/libavcodec/libx265.c)
- hevc_videotoolbox sets only `kVTCompressionPropertyKey_TransferFunction`, `_YCbCrMatrix` and `_ColorPrimaries`, mapped from `avctx->color_trc/colorspace/color_primaries`. A grep of master `videotoolboxenc.c` for "Mastering", "ContentLight", "HDR" and "dovi" finds **no** mastering-display, CLL or Dolby Vision code. — [libavcodec/videotoolboxenc.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- Ticket #10844, "VideoToolBox HEVC encoding does work not for HDR", is dated Feb 2024, git-master, status *new*, with no developer replies. The reporter's command was `-c:v hevc_videotoolbox -q:v 40 -pix_fmt yuv420p10le -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020_ncl -tag:v hvc1`. The output kept BT.2020/PQ tags, but the mastering display and the MaxCLL/MaxFALL of 1000/400 were missing. — [ffmpeg-trac archive #10844](https://ffmpeg.org/pipermail/ffmpeg-trac/2024-February/068457.html)
- Ticket #11036 (VideoToolbox HEVC HDR main10 colours corrupt) is reported as fixed in FFmpeg 7.0. — [ffmpeg-trac #11036 (search snippet)](https://ffmpeg.org/pipermail/ffmpeg-trac/2024-July/070158.html)
- A lossless post-fix via the `hevc_metadata` BSF is not possible. Master `hevc_metadata` options cover `aud`, `sample_aspect_ratio`, `video_format`, `video_full_range_flag`, `colour_primaries`, `transfer_characteristics`, `matrix_coefficients`, `chroma_sample_loc_type`, `tick_rate`, `crop_*`, `width/height`, `level`, and no master_display/max_cll. The proposed patch in ticket #7756 is therefore **not merged**. — [doc/bitstream_filters.texi (master)](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi); [trac #7756 (search snippet)](https://trac.ffmpeg.org/ticket/7756)
- Manual override syntax, if passthrough must be forced or corrected:
  - **x265:** `--master-display` takes ST 2086 values, with primaries and white point in 0.00002 units and luminance in 0.0001 cd/m². `--max-cll "1000,400"` sets MaxCLL,MaxFALL. `--hdr10` is auto-enabled when either of those is set. `--hdr10-opt` gives block-level QP optimization for 10-bit 4:2:0 BT.2020/PQ. `--repeat-headers` and `--colorprim/--transfer/--colormatrix/--range` are also available. In ffmpeg, pass these as `-x265-params master-display=...:max-cll=...`. — [x265 CLI docs](https://x265.readthedocs.io/en/master/cli.html)
  - **SVT-AV1:** `--mastering-display "G(x,y)B(x,y)R(x,y)WP(x,y)L(max,min)"`, `--content-light "max_cll,max_fall"`, `--color-primaries`, `--transfer-characteristics`, `--matrix-coefficients`, `--color-range [0 studio, 1 full]` and `--chroma-sample-position`. The ffmpeg example in the docs is `-svtav1-params "...:mastering-display=G(0.2649,0.6900)B(0.1500,0.0600)R(0.6800,0.3200)WP(0.3127,0.3290)L(1000.0,1)"`. — [SVT-AV1 Docs/Parameters.md](https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/master/Docs/Parameters.md)
- 7.1 added "Mastering Display and Content Light Level metadata support in hevc_nvenc and av1_nvenc" (not relevant on Mac). Also in 7.1: "YUV colorspace negotiation for codecs and filters, obsoleting the YUVJ pixel format". — [FFmpeg Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- 7.0 also added "Support for Ambient Viewing Environment metadata in MP4/ISOBMFF". 9.0 adds "SMPTE 2094-50 metadata support and passthrough". — [FFmpeg Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)

### Inferences
- [inference] Minimal correct HDR10/HLG re-encode on FFmpeg ≥7.0: `-c:V libx265 -pix_fmt yuv420p10le -crf N -preset P`, or `-c:V libsvtav1 -pix_fmt yuv420p10le -crf N -preset P`. There is no need for `-color_*` flags or `master-display` unless the source is mis-tagged. The audit should confirm with `ffprobe -show_streams -show_frames -read_intervals %+#1` that the output frame side data lists "Mastering display metadata" and "Content light level metadata".
- [inference] Any filter that changes colour (zscale/tonemap/colorspace, or a pixel-format conversion to 8-bit) breaks the passthrough or makes it wrong. For HDR the app must not let ffmpeg auto-insert a conversion to 8-bit. The pix_fmt must be set explicitly, because x265 and svtav1 accept 8-bit and would silently downconvert if asked.
- [inference] Because the side data is cloned once at encoder open (from the first frame), a source whose static metadata changes mid-stream would keep only the first values. This is rare.
- [inference] For hevc_videotoolbox on HDR10 sources, the app has two choices. (a) Accept missing MDCV/CLL; most displays then fall back to a default mastering assumption. (b) Use libx265/libsvtav1 for HDR content. (c) Write MDCV/CLL at container level. ffmpeg's MP4/MOV muxer writes `mdcv`/`clli` boxes from stream side data, but VT-encoded streams carry no such side data. I did not verify whether `-c:v hevc_videotoolbox` output gets the boxes from the input stream's coded side data.
- [inference] HLG has no mandatory static metadata. The tags (BT.2020 + arib-std-b67) are enough, and VT does write those. HLG is therefore the "safe" HDR case for VT.

### Gaps
- Apple's VideoToolbox has its own HDR metadata properties (`kVTCompressionPropertyKey_MasteringDisplayColorVolume`, `_ContentLightLevelInfo`, `_HDRMetadataInsertionMode`). I did not fetch Apple's documentation in this session. Whether VT auto-generates HDR10 SEI when ffmpeg does not set them is unverified. The ticket evidence above says the output lacks them.
- I did not test on a local build (ffmpeg not installed on this machine).

---

## 2. HDR10+ dynamic metadata

### Takeaway
On re-encode, ffmpeg preserves HDR10+ only with **libaom-av1 (FFmpeg ≥8.0)**. **libx265, libsvtav1 and hevc_videotoolbox drop it**: master has no HDR10+ code in those wrappers. With x265 it can be re-injected from a JSON file (`dhdr10-info`). Stream copy (`-c:v copy`) keeps it. Dropping HDR10+ leaves a valid HDR10 stream, as long as the static metadata in Q1 survives.

### Cited Findings
- 8.0 changelog: "HDR10+ metadata passthrough when decoding/encoding with libaom-av1". — [FFmpeg Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- The HEVC decoder exports HDR10+ as `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` frame side data. — [libavcodec/hevc/hevcdec.c (master, ~line 3990)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/hevc/hevcdec.c)
- A grep for `DYNAMIC_HDR`, `hdr10plus`, `HDR_PLUS` and `dhdr10` in master libx265.c and libsvtav1.c returns **no hits**. Neither wrapper consumes HDR10+ frame side data. — [libx265.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libx265.c), [libsvtav1.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libsvtav1.c)
- x265 `--dhdr10-info <file>` inserts dynamic tone-mapping SEI from a JSON file of Creative Intent Metadata. `--dhdr10-opt` limits insertion to IDR frames and frames where the info changes. — [x265 CLI docs](https://x265.readthedocs.io/en/master/cli.html)
- The Matroska muxer has an HDR10+ ITU-T T.35 BlockAdditionMapping, used for codecs that carry HDR10+ out-of-band (VP9/AV1 in MKV). — [libavformat/matroskaenc.c (master, ~line 1720)](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/matroskaenc.c)

### Inferences
- [inference] Through ffmpeg, `-x265-params dhdr10-info=hdr10plus.json` would work, using a JSON extracted from the source with quietvoid's `hdr10plus_tool extract`. This needs an x265 build compiled with HDR10+ support. I could not confirm the build flag from the fetched docs, or whether Homebrew's x265 has it. The JSON is indexed per frame, so the frame count and order must be unchanged (no fps conversion, no trimming).
- [inference] For an automated app, the pragmatic policy is to warn that HDR10+ will be dropped (detect via ffprobe frame side data "HDR Dynamic Metadata SMPTE2094-40 (HDR10+)") and keep HDR10 static metadata. Offer the x265+JSON path only as an advanced option. AV1 via libaom preserves it, but libaom is much slower than SVT-AV1 (speed claim not sourced here).

### Gaps
- No verified data on whether SVT-AV1 (the library itself) accepts HDR10+ metadata through any API, or plans to.
- hdr10plus_tool README was not fetched in this session.

---

## 3. Dolby Vision: preserving the RPU, profile differences, failure modes, and app policy

### Takeaway
**FFmpeg ≥7.1** can carry Dolby Vision through a re-encode with **libx265 and libsvtav1**. A `dolbyvision` option (default `auto`) regenerates the RPU from the decoder's per-frame DOVI metadata. This works for **profile 8.x (HEVC→HEVC P8, or HEVC→AV1 P10) and profile 5**. **Profile 7 (dual-layer / FEL/MEL) is not supported**: in auto mode DV is silently dropped, leaving the HDR10 base layer. **hevc_videotoolbox has no DV support at all.** Dropping DV from **profile 5** is destructive (IPTPQc2 base layer, no HDR10 fallback, green/purple picture). An automated app should therefore skip or refuse P5 unless the RPU is provably preserved.

### Cited Findings
- **Version:** a grep for the `"dolbyvision"` AVOption finds 0 hits in n7.0 and 1 hit in n7.1 / n8.0 / master, for both libx265.c and libsvtav1.c. The option reads `{ "dolbyvision", "Enable Dolby Vision RPU coding", ..., {.i64 = FF_DOVI_AUTOMATIC }, -1, 1 }` with `auto` as the default. — [n7.1 libx265.c](https://github.com/FFmpeg/FFmpeg/blob/n7.1/libavcodec/libx265.c), [n7.1 libsvtav1.c](https://github.com/FFmpeg/FFmpeg/blob/n7.1/libavcodec/libsvtav1.c), [master libx265.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libx265.c)
- **Auto logic:** if `enable == FF_DOVI_AUTOMATIC` and the frames carry no DOVI RPU header, DV is skipped (`goto skip`). — [libavcodec/dovi_rpuenc.c (master, ff_dovi_configure)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpuenc.c)
- **Profile selection** (same file): AV1 → profile 10, H.264 → profile 9. For HEVC with an RPU, the profile is guessed from the RPU header. Without an RPU, IPT_C2 or unspecified colour → profile 5, otherwise profile 8. Under normal strictness, the pix_fmt must be `yuv420p10` (yuv420p for P9), otherwise the profile becomes 0 and DV is skipped. — [dovi_rpuenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpuenc.c)
- **Profile 4/7 (enhancement layer):** forced on gives the error `"Coding of Dolby Vision enhancement layers is currently unsupported."` (AVERROR_PATCHWELCOME). In auto mode → skip. The profile guess returns 7 for `vdr_rpu_profile==1`, EL spatial resampling with residual, and 12-bit VDR; it returns 4 for non-12-bit; otherwise 8. Profile 5 is `vdr_rpu_profile==0` with full-range BL. — [dovi_rpuenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpuenc.c); [libavcodec/dovi_rpu.c ff_dovi_guess_profile_hevc](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpu.c)
- **BL signal compatibility ID** is derived from output colour tags. Profile 5 → 0. Profile 8 / AV1-10 with BT.2020nc + BT.2020 + PQ → **1 (8.1)**, BT.2020 + HLG → **4 (8.4)**, BT.709 → **2 (8.2)**. If the profile or compat ID cannot be determined, forced-on fails with "Dolby Vision enabled, but could not determine profile and compatibility mode". AV1 with a full-range BL RPU flag → IPTPQc2-style compat 0. — [dovi_rpuenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpuenc.c)
- **Metadata compression:** this is not permitted for profiles ≤7, and profile 8 gets a warning. The `dovi_rpu` BSF options are `strip` (removes the configuration record and RPU) and `compression` = none / limited (default) / extended (currently behaves like limited). — [dovi_rpuenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/dovi_rpuenc.c); [doc/bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- **Wrapping:** libx265 emits the RPU as a NAL (`FF_DOVI_WRAP_NAL`) and sets x265 `dolbyProfile = dv_profile*10 + compat_id`. libsvtav1 emits it as an ITU-T T.35 OBU (`FF_DOVI_WRAP_T35`). If DV is configured but a frame lacks `AV_FRAME_DATA_DOVI_METADATA`, the encoders log a warning about frames "without AV_FRAME_DATA_DOVI_METADATA". — [libx265.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libx265.c), [libsvtav1.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libsvtav1.c)
- **Decoders:** the HEVC decoder attaches `AV_FRAME_DATA_DOVI_RPU_BUFFER` plus parsed DOVI metadata to frames, and reads the stream's DOVI configuration record. libdav1d defaults its DOVI context to profile 10 for AV1 input. — [hevcdec.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/hevc/hevcdec.c), [libdav1d.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/libdav1d.c)
- **Containers:** the MP4 muxer writes `dvcC`/`dvvC` from `AV_PKT_DATA_DOVI_CONF`. The Matroska muxer writes the DOVI BlockAdditionMapping (dvcC/dvvC); DOVI code is present in matroskaenc since at least n5.1. — [movenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c), [matroskaenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/matroskaenc.c)
- 7.0 changelog: "Dolby Vision profile 10 support in AV1". 9.0 changelog: "Bitstream filter to split Dolby Vision multi-layer HEVC" (`dovi_split`). Its modes are `bl` (default: plain HEVC, EL and RPU dropped), `bl_rpu`, `el`, and `el_rpu`, operating on P7 UNSPEC63 (EL) / UNSPEC62 (RPU) NALs. — [Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog); [bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- **hevc_videotoolbox:** master `videotoolboxenc.c` contains no `dovi` code (grep), so it cannot emit DV. — [videotoolboxenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
- **Standalone x265:** `--dolby-vision-profile` supports **only 5, 8.1, 8.2, 8.4**. `--dolby-vision-rpu <file>` interleaves an RPU file (CLI only). — [x265 CLI docs](https://x265.readthedocs.io/en/master/cli.html)
- **dovi_tool (quietvoid):**
  - Conversion modes: `-m 0` parses and rewrites the RPU untouched. `-m 1` converts to MEL-compatible. `-m 2` converts to profile 8.1 and, for P7 FEL, also removes the luma/chroma mapping. `-m 3` converts profile 5 to 8.1. `-m 4` converts to 8.4. `-m 5` converts to 8.1 while preserving the mapping (this was the old mode 2).
  - Commands: `extract-rpu` (HEVC or MKV; profiles 4/5/7/8; `-t` MKV track), `inject-rpu` (interleaves the RPU between slices of an HEVC bitstream), `remove` (removes the EL and RPU → `BL.hevc`), `convert --discard`, `demux`/`mux`, and `editor` (JSON edits). `-c/--crop` zeroes active-area offsets.
  - The README does not mention AV1. — [dovi_tool README](https://github.com/quietvoid/dovi_tool)
- **[community]** Profile 5 is single-layer with no HDR10/SDR-compatible base. Players without full DV support show green/purple distortion. Profiles 7 and 8.1 have a fallback. Converting P5 to an HDR10-compatible 8.1 requires re-encoding and re-inserting metadata. — [Emby: Dolby Vision Profile 5](https://emby.media/learn/articles/video/hdr/formats/dolby-vision/profiles-and-compatibility/Dolby-Vision-Profile-5.html); [Plex forum (P5 purple image)](https://forums.plex.tv/t/switched-from-infuse-to-plex-now-struggling-with-dolby-vision-profile-5-purple-image-no-playbac/933859); [Jellyfin forum (purple/green transcoding DoVi)](https://forum.jellyfin.org/t-purple-green-transcoding-dovi?pid=41824)

### Inferences
- [inference] **Detection:** `ffprobe -show_streams` prints stream side data "DOVI configuration record" with `dv_profile`, `dv_level`, `rpu_present_flag`, `el_present_flag` and `dv_bl_signal_compatibility_id`. Use these to route.
- [inference] **Policy matrix for the app:**
  - **P8.1 / P8.4 HEVC, or AV1 P10, with libx265/libsvtav1 on FFmpeg ≥7.1:** re-encode with `-pix_fmt yuv420p10le`. Leave `dolbyvision=auto`, or set `-dolbyvision 1` to fail loudly instead of silently dropping. Verify the output stream has the DOVI record and frame RPUs. HEVC→AV1 becomes DV profile 10.x, which Apple devices may not play as DV. Device support is unverified here.
  - **P8.x with hevc_videotoolbox:** DV is dropped. The result is HDR10 (P8.1) or HLG (P8.4) without DV, and for 8.1 it also lacks MDCV/CLL (see Q1). This is visually acceptable but a metadata loss. Warn the user or route to libx265.
  - **P7 (UHD BD remux, dual-layer):** ffmpeg drops DV (auto skip) and decodes only the BL. The result is HDR10 and FEL detail is lost. For DV retention, use dovi_tool: `extract-rpu -m 2` (→8.1), encode with x265, then `inject-rpu` (or x265 `--dolby-vision-profile 8.1 --dolby-vision-rpu`), then remux with mkvmerge/MP4Box. ffmpeg 9.0+ `dovi_split=mode=bl_rpu` could also feed BL+RPU into a decode. Whether the HEVC decoder then exports P7 RPU metadata that the encoder would accept is untested; the encoder rejects profile 7, so the RPU would have to be converted to P8 first.
  - **P5 (streaming rips):** default = **skip**. If the RPU is lost, the output is an IPT-encoded stream that every player mis-renders. libx265/libsvtav1 auto mode keeps P5 if the decoder exports the RPU and the output is 10-bit. The app must still hard-verify that output has `dv_profile=5` and refuse to replace the original otherwise. Never send P5 to hevc_videotoolbox.
- [inference] dovi_tool `-m 3` (P5→8.1) only rewrites the RPU. It does not convert the IPTPQc2 pixels of the base layer to PQ BT.2020. A real HDR10 fallback from P5 needs a DV-aware tone-map or reshape of the pixels during the re-encode, for example a libplacebo-based pipeline, which is outside this research. This matches the community statement that P5→8.1 "involves re-encoding".
- [inference] The RPU carries per-frame L1 stats and an L5 active area. Cropping, scaling, frame-rate conversion or trimming makes the RPU inaccurate. The app's "keep resolution, keep frames" stance (`-fps_mode passthrough`, `-apply_cropping none`, see Q6) matters here.
- [inference] Container muxing of DV: with FFmpeg's own muxer, re-encoded DV in both MP4 and MKV gets the config record automatically from the encoder's coded side data. External tools (mkvmerge, MP4Box) are needed only in the dovi_tool inject workflow.

### Gaps
- Not verified: whether the hevc decoder sets IPT_C2 colourspace on P5 frames. A grep of hevcdec.c for `IPT_C2` found no hits, so it probably passes the VUI through. Whether the P5 auto path works end-to-end is therefore uncertain; it needs a real test file.
- Apple playback support for DV profile 10 (AV1), and for ffmpeg-generated P8.1 RPUs (compression=limited), was not verified.
- Dolby's official profiles/levels document was not fetched (search did not surface it). Profile semantics here come from ffmpeg source and community sources.

---

## 4. Audio: size share, transparent bitrates, whether optional audio re-encode is worthwhile, and downsides

### Takeaway
In Blu-ray/UHD remuxes, a lossless main track is typically **~3–7 Mbps** (TrueHD Atmos ~4 Mbps average, peaks 7–10+). Over a 2 h film that is roughly **2–4 GiB per track**, a modest share of a 40–80 GB UHD remux. After the video is re-encoded to ~10–20 Mbps, audio can become **20–40 % of the output** [inference, arithmetic]. Re-encoding lossless tracks to Opus (5.1 at 256–384 kbps) or AAC (`aac_at`) saves gigabytes, but **Atmos objects are lost**: no open-source Atmos/JOC encoder exists. ffmpeg's E-AC-3 encoder is 5.1 max. It is reasonable as an *opt-in* mode that touches only lossless tracks. Never re-encode lossy tracks.

### Cited Findings
- Dolby TrueHD can reach up to 18 Mbps on Blu-ray Disc. — [Dolby Professional: TrueHD](https://professional.dolby.com/tv/dolby-truehd/) (via search snippet)
- [community] A disc's Atmos TrueHD track measured "around 4000 kbps / max 7000 kbps". — [MakeMKV forum](https://forum.makemkv.com/forum/viewtopic.php?p=84902)
- [community] A MediaInfo paste shows a TrueHD 7.1 Atmos track of 3.40 GiB, and another shows 2.08 GiB. — [VideoHelp forum (search-snippet derived; exact post attribution uncertain)](https://forum.videohelp.com/showthread.php?p=2702389)
- Opus recommended settings: stereo music storage 96–128 kbps, with "Opus at 128 KB/s (VBR) is pretty much transparent". 5.1 surround 128–256 kbps, 7.1 256–450 kbps. Archiving → use FLAC. — [Xiph wiki: Opus Recommended Settings](https://wiki.xiph.org/Opus_Recommended_Settings)
- ffmpeg libopus `mapping_family`: the default -1 uses family 0 for mono/stereo and family 1 otherwise. The default **disables surround masking and LFE bandwidth optimizations** and requires ≤8 channels. `-mapping_family 1` enables those optimizations, and 255 means independent streams. `apply_phase_inv` requires libopus ≥1.2. — [doc/encoders.texi (libopus)](https://github.com/FFmpeg/FFmpeg/blob/master/doc/encoders.texi)
- `aac_at` (AudioToolbox) options:
  - VBR quality `-q:a 0..14`, mapped to `kAudioCodecPropertySoundQualityForVBR = 127 - 9*q`, so **0 = best**.
  - `-aac_at_mode auto|cbr|abr|cvbr|vbr`: auto = VBR if global quality is given, otherwise CBR.
  - `-aac_at_quality 0..2` (quality vs speed, mapped to `96 - 32*q`, 0 = best).
  - Channel layout map includes 7.1 (`kAudioChannelLayoutTag_AAC_7_1`, `MPEG_7_1_C`). — [libavcodec/audiotoolboxenc.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/audiotoolboxenc.c)
- The ffmpeg (E-)AC-3 encoder channel layout table includes 5.1/5.1(back) and no 7.1 layouts (grep `7POINT1` = 0). — [libavcodec/ac3enc.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/ac3enc.c)
- Hydrogenaudio public multiformat test at 96 kbps (July 2014; Apple AAC iTunes 11.2.2, Opus 1.1, Vorbis aoTuV, LAME 3.99.5): Opus 1.1 was the clear winner on average and Apple AAC clearly second. The summary notes these "are not reliably transparent at 96 kbps" under close headphone listening. **Dated 2014.** — [Hydrogenaudio results thread](https://hydrogenaud.io/index.php/topic,106911.msg875036.html); [HA listening tests index](https://wiki.hydrogenaudio.org/index.php/Hydrogenaudio_Listening_Tests)
- [community] There is no open-source audio encoder that supports Atmos. TrueHD→E-AC-3 is a re-encode, and objects/JOC cannot be produced without Dolby's tools and master audio. ffmpeg `-c:a eac3` re-encodes drop JOC and leave plain DD+. — [HandBrake forum](https://forum.handbrake.fr/viewtopic.php?p=183145) (c. 2019–2020); [Firecore/Infuse forum](https://community.firecore.com/t/infuse-6-3-and-dolby-atmos-eac-3/19284); [Emby forum (2024)](https://emby.media/community/topic/134275-convert-dolby-truehd-71-atmos-to-eac3-atmosdd-atmos-joc); [VideoHelp](https://forum.videohelp.com/showthread.php?p=2606444)
- [community/ticket] A 2025 ffmpeg-trac ticket concerns writing `joc_complexity_index` into the MP4 `dec3` box for E-AC-3 Atmos playback on Windows/Android. Stream-copied E-AC-3 JOC in MP4 may therefore need a recent build to be recognized as Atmos. — [ffmpeg-trac archive 2025-April](https://ffmpeg.org/pipermail/ffmpeg-trac/2025-April/073371.html) (search snippet; resolution not verified)
- MP4 muxing of lossless audio: the movenc code path allows FLAC (`dfLa`), Opus (`dOps`) and TrueHD (`mlpa`). **TrueHD in MP4 requires `-strict experimental`**; the muxer errors unless strict ≤ experimental. — [libavformat/movenc.c (master, ~lines 1550–1620, 9169–9181)](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)
- The `dca_core` BSF "Extract[s] the core from a DCA/DTS stream, dropping extensions such as DTS-HD". This gives a lossless-to-the-core, no-re-encode reduction. — [doc/bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- 9.1 changelog: "extensively improved AAC encoder" (native `aac`). I did not evaluate its quality. — [Changelog](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)

### Inferences
- [inference, arithmetic] PCM bitrates: 5.1 at 24-bit/48 kHz is 6 × 48 000 × 24 = **6.912 Mbps** (≈6.2 GB per 2 h). 7.1 at 24/48 is **9.216 Mbps** (≈8.3 GB per 2 h). TrueHD at 4 Mbps × 7200 s ≈ **3.6 GB (3.35 GiB)**, which matches the 3.40 GiB anecdote.
- [inference, arithmetic] Share example: a UHD remux with 60 Mbps video plus 4 Mbps TrueHD, plus a 640 kbps AC-3 compatibility track and a 224 kbps commentary track, has audio at ≈7 % of the total. Re-encode the video to 15 Mbps and the same audio is ≈24 % of the output. Converting TrueHD 7.1 to Opus 7.1 at 384 kbps saves ≈3.3 GB per 2 h.
- [inference] Recommended optional "audio slim" mode:
  - Touch only lossless codecs (truehd, dts with DTS-HD MA profile, pcm_*, flac, alac).
  - **MKV** → `libopus -b:a 256k–384k -mapping_family 1` for 5.1/7.1, or 128–160k for stereo.
  - **MP4/Apple-compat** → `aac_at -q:a 0..2` (VBR) or `-b:a 384k–640k` for 5.1. AAC 5.1/7.1 is the most universally playable in Apple players.
  - Never touch AC-3/E-AC-3/DTS core/AAC/Opus/MP3: generation loss, small savings.
  - Treat Atmos (TrueHD with Atmos, E-AC-3 JOC) as "keep by default"; downgrading drops object metadata to a channel bed.
- [inference] A cheaper alternative for DTS-HD MA is `-bsf:a dca_core` with `-c:a copy`. This keeps the 1.5 Mbps (or 768 kbps) DTS core bit-exact and avoids a new encode generation. DTS playback on Apple devices is limited (not verified here), so AAC/Opus may still be preferable for MP4.
- [inference] PCM → FLAC is mathematically lossless and typically substantially smaller. That is a safe "free" saving for PCM tracks in MKV; movenc also supports FLAC in MP4. I have no sourced compression ratio.
- [inference, unverified community knowledge] libopus via ffmpeg may refuse some layouts such as `5.1(side)` with mapping family -1/1 unless remapped (`-af aformat=channel_layouts=5.1`, or `-ac 6`). Verify on target builds.
- [inference] Downsides of audio re-encode:
  - Atmos object loss.
  - Loss of lossless archival value. This is mitigated by the app keeping the original file.
  - AVR/receiver passthrough compatibility: Opus/AAC multichannel are decoded to PCM by the player and not bitstreamed. Many TVs and AVRs cannot accept Opus.
  - DRC/dialnorm metadata of Dolby tracks is lost.

### Gaps
- No authoritative statistics on the "typical" audio share of remux libraries. The figures are anecdotes plus arithmetic.
- No current (2024–2026) listening test for Apple AAC vs Opus at multichannel bitrates. The 2014 HA test is stereo and dated.
- The trac Encode/AAC wiki (quality ranking of libfdk_aac / aac_at / native aac) was inaccessible (Anubis block).
- No sourced data on E-AC-3 "transparent" bitrates. Commercial streaming uses 640–768 kbps for 5.1/Atmos, but I have no citation.

---

## 5. Subtitles, attachments, chapters, metadata and data streams: what fits in MP4 vs MKV

### Takeaway
MKV takes everything (SRT, ASS/SSA, PGS, VobSub, DVB, TextST, ARIB, attachments such as fonts). **MP4 via ffmpeg takes only mov_text (tx3g), dvd_subtitle (VobSub, `mp4s`) and TTML.** PGS and ASS cannot be copied into MP4, and attachments cannot either. `-map 0` maps every stream, including attachments, data streams and unknown streams. Unknown streams make ffmpeg fail fatally unless `-copy_unknown` or `-ignore_unknown` is set. Chapters and global metadata are copied by default.

### Cited Findings
- The MP4 subtitle codec tag table contains `AV_CODEC_ID_DVD_SUBTITLE → 'mp4s'`, `AV_CODEC_ID_MOV_TEXT → 'tx3g'` and `AV_CODEC_ID_TTML`. There is no HDMV_PGS, ASS, SUBRIP or WEBVTT entry. MOV (QuickTime) also accepts mov_text with the `'text'` tag. — [libavformat/movenc.c (master, ~lines 9842–9930)](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)
- Matroska subtitle codec IDs: `S_TEXT/UTF8` (SubRip/text), `S_TEXT/ASS`, `S_TEXT/SSA`, `S_ASS`, `S_SSA`, `S_VOBSUB`, `S_DVBSUB`, `S_HDMV/PGS`, `S_HDMV/TEXTST`, `S_ARIBSUB`. mov_text is not among them; it needs `-c:s srt` (or ass) going MP4→MKV. — [libavformat/matroska.c (master)](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/matroska.c)
- The `text2movsub` BSF converts text subtitles to mov_text, with the inverse `mov2textsub`. — [doc/bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- Attachments: `-attach` "is supported by a few formats like Matroska for e.g. fonts used in rendering subtitles. Attachments are implemented as a specific type of stream". The Matroska muxer handles `AVMEDIA_TYPE_ATTACHMENT`. The MP4 muxer has no attachment handling (grep). — [ffmpeg.html (-attach)](https://ffmpeg.org/ffmpeg.html); [matroskaenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/matroskaenc.c); [movenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)
- Stream specifier types: `v`/`V` video, `a` audio, `s` subtitle, `d` data, `t` attachments. `v` matches all video streams, while **`V` only matches video streams that are not attached pictures, video thumbnails or cover arts**. FFmpeg 7.1 added matching by disposition: `disp:<dispositions>[:spec]`, joined with `+`. — [fftools-common-opts.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/fftools-common-opts.texi); [Changelog 7.1](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- 7.1 stream specifier syntax changes:
  - Metadata matching needs backslash-escaped colons.
  - Optional maps with metadata need `:m:key:val:?`.
  - Multiple stream types in one specifier (e.g. `:s:s:0`) are now an error. — [Changelog 7.1](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- `-map_metadata`: "By default, global metadata is copied from the first input file, per-stream and per-chapter metadata is copied along with streams/chapters. These default mappings are disabled by creating any mapping of the relevant type." `-map_chapters`: if not specified, chapters come from the first input with at least one chapter; a negative index disables. — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html)
- `-dn` (output): "disables data recording i.e. automatic selection or mapping of any data stream". `-vn` has parallel wording ("automatically selected or mapped"). — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html)
- `-copy_unknown`: "Allow input streams with unknown type to be copied instead of failing". Without it the muxer setup logs `"Cannot map stream #%d:%d - unsupported type."` fatally, unless `-ignore_unknown` is set. — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html); [fftools/ffmpeg_mux_init.c (~line 1975)](https://github.com/FFmpeg/FFmpeg/blob/master/fftools/ffmpeg_mux_init.c)
- MP4/MOV muxer `write_tmcd`: `auto` (default) writes a timecode track only for mov and mp4 output. `use_metadata_tags` uses the mdta atom for metadata (needed to carry arbitrary/Apple `com.apple.quicktime.*` keys). — [doc/muxers.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/muxers.texi)
- iPhone MOV `mebx` timed-metadata tracks: an ffmpeg-devel PR (#20738, 2025) proposes a "mebx" data codec ID for the MOV muxer. A grep of master `movenc.c`/`mov.c` for "mebx" returns 0, so it was **not merged** as of 2026-11-26. [community] Users report "Unsupported codec with id 0" for extra iPhone streams. — [ffmpeg-devel PR #20738](https://mid.mail-archive.com/ffmpeg-devel@ffmpeg.org/msg186058.html); [KDE discuss (iPhone MOV transcoder error)](https://discuss.kde.org/t/transcoder-error-with-mov-files/42671)
- MP4 cover art: the muxer writes a `covr` atom (from attached-picture streams). — [movenc.c mov_write_covr](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)

### Inferences
- [inference] Container-preserving rule: **output container = input container** (MKV→MKV, MP4→MP4, MOV→MOV), so every stream type that existed can be represented again. Changing MKV→MP4 forces lossy decisions: PGS dropped, ASS flattened to mov_text, fonts lost, possibly TrueHD only with `-strict experimental`. That conflicts with "copy other streams".
- [inference] Robust mapping for MKV output: `-map 0 -c copy -c:V <video encoder> ... -map_metadata 0 -map_chapters 0`. Attachments (`t`) and cover-art (`v` with attached_pic) are copied, and only real video is re-encoded.
- [inference] Robust mapping for MP4/MOV output: `-map 0:V -map 0:a? -map 0:s? -map 0:v:disp:attached_pic? -c copy -c:V <enc> -map_metadata 0 -movflags +use_metadata_tags`, and decide on data streams explicitly. Either keep them with `-map 0:d? -copy_unknown` and verify the muxer accepts them, or drop them. Incompatible subtitle codecs (e.g. a PGS/ASS track in an MP4 source is impossible anyway) would need `-c:s mov_text`. Exact optional-map syntax for `disp` combined with `?` should be tested on the target ffmpeg version.
- [inference] Apple QuickTime-style metadata (location, make/model, creationdate in mdta `keys`) is not written unless `-movflags use_metadata_tags` is set. Without it, phone videos lose GPS/device tags even with `-map_metadata 0`.

### Gaps
- I did not capture the exact error text when an MKV font attachment is mapped into MP4. Community memory says "Could not find tag for codec ttf ... codec not currently supported in container", but this is unverified.
- Whether WebVTT can be muxed into MP4 by ffmpeg (`wvtt`) was not confirmed. It is absent from the tag table grep.

---

## 6. Pitfalls of `-map 0 -c copy` (plus `-c:v <encoder>`): cover art, VFR, timestamps, rotation, cropping, creation dates

### Takeaway
The biggest traps:
- `-c:v` also hits **cover-art/attached-pic** streams. Use `-c:V`, or override with `disp:attached_pic`.
- The default `-fps_mode auto` may drop or duplicate frames. Use `-fps_mode passthrough`.
- **autorotate** (default on) physically rotates phone video on re-encode.
- **apply_cropping** (default `all` since 7.1) applies container crop metadata and changes the output resolution.
- `-map 0` pulls in data and unknown streams that MP4 rejects.
- File-system dates are never preserved by ffmpeg.

### Cited Findings
- `v` matches attached pictures and cover art, and `V` excludes them. A plain `-c:v libx265` therefore applies to an MKV cover-art attachment or MP4 `covr` stream that ffmpeg exposes as a video stream. — [fftools-common-opts.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/fftools-common-opts.texi)
- `-fps_mode` values:
  - `passthrough`: "Each frame is passed with its timestamp from the demuxer to the muxer".
  - `cfr`: duplicates/drops frames to hit an exact rate.
  - `vfr`: passes frames through, or drops them so no two frames share a timestamp.
  - `auto`: "Chooses between cfr and vfr depending on muxer capabilities. This is the default method." Timestamps may be further modified by the muxer (e.g. `avoid_negative_ts`). — [ffmpeg.html (-fps_mode)](https://ffmpeg.org/ffmpeg.html)
- `-copyts`: "Do not process input timestamps ... In particular, do not remove the initial start time offset value." — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html)
- `-autorotate`: "Automatically rotate the video according to file metadata. Enabled by default, use -noautorotate to disable it." `-display_rotation[:spec] <deg>` (input, per-stream) sets rotation metadata, counter-clockwise degrees. — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html)
- 9.1 adds a `side_data` BSF, e.g. `-c copy -bsf:v side_data=remove=displaymatrix+replaygain`, to remove stream/packet side data. — [bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi); [Changelog 9.1](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog)
- `-apply_cropping[:spec] <source>` (input): "Automatically crop the video after decoding according to file metadata. Default is all", with `none (0)` to disable. 7.1 added "Cropping metadata parsing and writing in Matroska and MP4/MOV de/muxers". The CLI decoder applies `av_frame_apply_cropping` when enabled. — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html); [Changelog 7.1](https://github.com/FFmpeg/FFmpeg/blob/master/Changelog); [fftools/ffmpeg_dec.c](https://github.com/FFmpeg/FFmpeg/blob/master/fftools/ffmpeg_dec.c)
- `-max_muxing_queue_size`: when transcoding, ffmpeg buffers other streams' packets until each transcoded stream has one packet. The default "should be high enough for most uses". — [ffmpeg.html](https://ffmpeg.org/ffmpeg.html)
- Unknown-type streams under `-map 0` → fatal "Cannot map stream ... unsupported type" unless `-copy_unknown`/`-ignore_unknown` is set. — [ffmpeg_mux_init.c](https://github.com/FFmpeg/FFmpeg/blob/master/fftools/ffmpeg_mux_init.c)
- `write_tmcd` defaults to writing a timecode track for mov/mp4 output. — [doc/muxers.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/muxers.texi)
- The Apple-player HEVC tag is shown in the ticket command as `-tag:v hvc1`. — [ffmpeg-trac #10844](https://ffmpeg.org/pipermail/ffmpeg-trac/2024-February/068457.html)

### Inferences
- [inference] **Recommended baseline command** (MKV):
  ```
  ffmpeg -hide_banner -apply_cropping none -i in.mkv -map 0 -c copy -c:V libsvtav1 -pix_fmt yuv420p10le -crf 30 -preset 6 \
         -fps_mode passthrough -map_metadata 0 -map_chapters 0 out.mkv
  ```
  For MP4 add `-tag:V hvc1` for HEVC (Apple), `-movflags +faststart+use_metadata_tags`, and an explicit data-stream decision (`-dn`, or a negative map like `-map -0:d`).
  - `-apply_cropping none` is an **input** option, so it must come before `-i`.
  - `-c:V` re-encodes only real video. Cover art and attachments stay copied.
- [inference] `-apply_cropping` default `all` in ≥7.1 means MKV/MP4 files with container crop fields (e.g. MKV `PixelCrop*`) would be **decoded cropped**. The output resolution would then differ from the source's coded size. For a "keep resolution" app, either set `-apply_cropping none` (keep full frame; crop metadata is copied only if the muxer re-writes it, which is unverified), or accept cropping deliberately. Note that HEVC SPS conformance-window cropping (codec-level) is normal and always applied.
- [inference] Rotation: with autorotate (default), re-encoded phone video is physically rotated. Dimensions swap, the display matrix is not written, and it looks identical, but the pixel count is the same. With `-noautorotate` the pixels stay in sensor orientation, and the display matrix must be carried to the output; I did not verify that ffmpeg copies it automatically in that case. The audit should check output with `ffprobe -show_streams` (side_data "Display Matrix", rotation) on a real iPhone file.
- [inference] VFR: phone and screen recordings are VFR. With `auto`→`vfr`, ffmpeg drops frames that collide on timestamps and can renumber. With a CFR guess it duplicates or drops. `passthrough` preserves the exact frame count, which also keeps DV/HDR10+ per-frame metadata aligned.
- [inference] B-frames and negative timestamps: re-encoding with B-frames into MP4 creates an edit list or `avoid_negative_ts` shifts. Audio/subtitle sync stays correct, but the start_time may change slightly. Compare durations and stream start times in the audit.
- [inference] Creation dates:
  - Global `creation_time` is copied by default metadata mapping, and MP4's `mvhd` creation time comes from it.
  - Per-stream `creation_time` is copied with streams.
  - Apple `com.apple.quicktime.creationdate` needs `use_metadata_tags`.
  - File-system timestamps (mtime/birthtime/Finder tags/xattrs such as `com.apple.metadata:kMDItemWhereFroms`) are never touched by ffmpeg. The macOS app must copy them itself (e.g. `FileManager.setAttributes` for `.creationDate`/`.modificationDate`).
- [inference] Subtitle-only streams that start late can trigger "Too many packets buffered for output stream". Raise `-max_muxing_queue_size 9999` for robustness on remuxes with many sparse subtitle tracks.

### Gaps
- No empirical verification (no local ffmpeg) of: displaymatrix propagation with `-noautorotate`; whether crop metadata is re-emitted with `-apply_cropping none`; the exact behaviour of `-c:v` on an MKV image attachment exposed as a video stream versus a `t` attachment. In MKV, fonts are `t` streams; cover JPEGs with image mimetype are exposed as attached_pic video.

---

## 7. Near-free savings without re-encoding video

### Takeaway
- **Container overhead:** M2TS→MKV saves roughly 5–8 % [community]. MKV↔MP4 is ~0–1 %.
- **Stream pruning** (unwanted dubs, commentary, duplicate compatibility tracks, image subtitles) often saves more than that.
- **Lossless/bit-exact audio tricks:** PCM→FLAC, DTS-HD MA→DTS core via `dca_core`.

All of these are trivial compared with the video re-encode, but they are lossless for what is kept.

### Cited Findings
- [community] Typical overhead: M2TS 5–8 % (one moderator: 6–7 %) versus MKV 0.5–1 %. Example: a 4.24 GB file shrank to 3.95 GB after mkvmerge remux (~7 %). Part of the reduction comes from mkvmerge removing filler NALUs. — [VideoHelp: m2ts vs mkv pros and cons](https://forum.videohelp.com/threads/328284-m2ts-vs-mkv-Pros-and-Cons); [VideoHelp thread](https://forum.videohelp.com/showthread.php?p=2063945) (exact attribution of the example per thread uncertain; from search summary)
- `dca_core` BSF extracts the DTS core and drops DTS-HD extensions without re-encoding. — [bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- The `dovi_rpu` BSF `strip` removes DV metadata without re-encoding (minor size), and `dovi_split=mode=bl` (9.0+) drops a P7 EL. — [bitstream_filters.texi](https://github.com/FFmpeg/FFmpeg/blob/master/doc/bitstream_filters.texi)
- MP4 supports FLAC (`dfLa`) and Opus (`dOps`) audio; MKV supports both natively. — [movenc.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/movenc.c)

### Inferences
- [inference, arithmetic] Pruning examples per 2 h film:
  - Each extra AC-3 5.1 640 kbps dub ≈ 576 MB.
  - Each extra DTS-HD MA dub ≈ 2–3 GB.
  - A commentary AC-3 2.0 224 kbps ≈ 200 MB.
  - A P7 FEL enhancement layer is often 5–15 % of the video stream (unsourced estimate; do not rely on it).
  
  An optional "keep languages: [ja, en, ko]" filter using `-map 0:a:m:language:jpn` etc. is lossless and may save several GB on multi-dub BD remuxes. Mind the 7.1 metadata-specifier escaping rules.
- [inference] PGS subtitles are bitmap: typically tens of MB per track. Text subtitles are KB. Subtitle pruning rarely matters.
- [inference] `-movflags +faststart` saves nothing; it only relocates moov. Matroska Cues/void elements are negligible.
- [inference] For the audit: measure per-stream sizes before deciding. `ffprobe -show_entries stream=index,codec_name,bit_rate:stream_tags=language,BPS,NUMBER_OF_BYTES` gives this; mkvmerge-written MKVs carry `NUMBER_OF_BYTES`/`BPS` statistics tags per track. Report "video share" versus "non-video share" to the user before re-encoding.
- [inference] TrueHD on Blu-ray is accompanied by an AC-3 core/compatibility stream. Whether MakeMKV/remuxes keep it as a separate track (droppable for ~640 kbps savings) was not verified here.

### Gaps
- No authoritative measurement of container overhead (only forum figures).
- No sourced FLAC-vs-PCM compression ratios for film soundtracks.
- No sourced size of P7 FEL/MEL enhancement layers.
