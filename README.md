# clipress

해상도와 화질(VMAF 기준)을 유지하면서 영상 파일 용량을 줄이는 개인용 macOS 앱.
원본은 건드리지 않고 옆에 `이름-pressed.확장자`로 저장한다.

## 준비

```sh
brew install ffmpeg        # 8.1 이상 (libsvtav1, libvmaf 포함)
cargo install ab-av1       # 목표 VMAF를 만족하는 품질값 탐색
```

## 빌드·실행

```sh
./scripts/bundle.sh && open Clipress.app
```

SwiftUI 매크로 플러그인이 Command Line Tools에 없어서 Xcode 툴체인(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`)으로 빌드한다.
테스트: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

## 동작

| 모드 | 인코더 | 비고 |
|---|---|---|
| 빠름 | `hevc_videotoolbox` (Main 10, B-frame 2, 키프레임 10초) | 이미 효율적인 소스는 대부분 "절감 부족"으로 스킵된다 |
| 고압축 | `libsvtav1` preset 4, tune VQ, variance boost, QM | 느리다. 4K 영화는 몇 시간 걸릴 수 있다 |

1. **분석**: ffprobe로 스트림을 읽는다. 다음은 스킵한다: HDR(PQ/HLG), Dolby Vision, 비디오 스트림이 1개가 아닌 파일, 알 수 없는 스트림, 이름이 `-pressed`로 끝나는 파일(이미 압축한 결과물).
2. **탐색**: `ab-av1 crf-search`로 샘플(6분마다 20초)의 평균 VMAF v1 ≥ 96(목표 95 + 마진 1)을 만족하는 가장 압축된 값을 찾는다.
3. **크기 기준**: 비디오 외 스트림은 그대로라고 보고 파일 전체 크기를 예측한다. 원본의 80%를 넘으면 인코딩하지 않는다.
4. **인코딩**: 비디오만 재인코딩하고 오디오·자막·챕터·첨부·커버 아트는 copy한다. 컨테이너는 입력과 같다(MOV+AV1만 MP4). 데이터 스트림(타임코드 등)은 버리고 결과에 표시한다.
5. **검증**: 전체 디코드 오류, 화면상 해상도(회전 반영), 프레임 수, 길이(±2초), 스트림 수, 실제 크기 ≤ 80%를 확인한다. 통과하면 `.part`를 최종 이름으로 바꾸고 원본의 생성·수정 날짜를 복사한다.

실패하거나 취소하면 임시 파일을 지운다. 인코딩 중에는 Mac의 유휴 잠자기를 막는다.

## 한계

- VMAF 96은 검증된 "눈으로 구분 불가" 기준이 아니다. 자기 콘텐츠로 원본과 비교해 보고 조정할 것 (`Sources/ClipressCore/Plan.swift`의 `minVMAF`).
- HDR·Dolby Vision 파일은 품질 검증 수단이 없어 처리하지 않는다.
- MOV 입력의 커버 아트는 ffmpeg mov muxer가 쓰지 못해 검증에서 실패하고 원본이 유지된다.

조사 근거: `reports/시각적 무손실 영상 압축 기술.md`
