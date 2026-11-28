# Magic Clip

해상도와 화질(VMAF 기준)을 유지하면서 영상 파일 용량을 줄이는 개인용 macOS 앱.

- 파일이나 폴더를 창에 끌어다 놓고 "시작"을 누르면 된다.
- 결과는 원본 옆에 `이름-pressed.확장자`로 저장한다.
- 검증까지 통과한 경우에만 원본을 휴지통으로 옮긴다. 창 아래 토글로 끌 수 있다. 휴지통을 비워야 디스크가 비워진다.
- 충분히 줄지 않거나(원본의 85% 초과) 검증에 실패하면 원본을 그대로 둔다.

## 요구 사항

- Apple Silicon Mac, macOS 27 이상
- Xcode (빌드용. SwiftUI 매크로 플러그인이 Command Line Tools에 없다)
- ffmpeg 8.1 이상 (`libsvtav1`, `libvmaf` 포함. 9.1에서 테스트)
- ab-av1 (목표 VMAF를 만족하는 품질값 탐색)

## 설치

```sh
brew install ffmpeg
cargo install ab-av1
./scripts/bundle.sh && cp -R "Magic Clip.app" /Applications/
```

앱은 `/opt/homebrew/bin/ffmpeg`, `/opt/homebrew/bin/ffprobe`, `~/.cargo/bin/ab-av1`을 그대로 호출한다. 다른 곳에 설치했다면 `Sources/MagicClipCore/Tools.swift`의 경로를 고친다.

배포용 바이너리는 없다. 서명·공증하지 않은 개인용 앱이라 직접 빌드해서 쓴다.

## 사용법

1. 모드를 고른다. 모드 옆 `!` 아이콘에 마우스를 올리면 그 모드의 변환 손실을 볼 수 있다.
2. 파일이나 폴더를 창에 끌어다 놓거나 "파일 추가…"(⌘O)로 고른다. 폴더는 안의 영상 파일(하위 폴더 포함)로 펼쳐진다.
3. "시작"을 누른다. 목록 위에 대기·완료 수와 전체 진행률이, 파일마다 진행률 막대와 속도계(초당 프레임 수, 실시간 대비 배속, 남은 시간)가 나온다.
4. "기록 지우기"는 끝난 항목을 목록에서만 지운다. 파일은 건드리지 않는다.

| 모드 | 인코더 | 비고 |
|---|---|---|
| 빠름 | `hevc_videotoolbox` (Main 10, B-frame 2, 키프레임 10초) | 두 파일을 함께 처리한다. 이미 효율적인 소스는 대부분 "절감 부족"으로 스킵된다 |
| 고압축 | `libsvtav1` preset 4, tune VQ, variance boost, QM | 하나씩 처리한다. 느리다. 4K 영화는 몇 시간 걸릴 수 있다 |

빠름 모드의 하드웨어 인코딩은 CPU를 1코어쯤만 써서, 남는 코어로 다음 파일의 탐색·검증을 돌린다. SVT-AV1은 혼자서 모든 코어를 쓴다.

## 동작

1. **분석**: ffprobe로 스트림을 읽는다. 다음은 스킵한다: HDR(PQ/HLG), Dolby Vision, 비디오 스트림이 1개가 아닌 파일, 알 수 없는 스트림, 이름이 `-pressed`로 끝나는 파일(이미 압축한 결과물).
2. **탐색**: `ab-av1 crf-search`로 샘플(12분마다 20초)의 평균 VMAF v1(4프레임마다 계산) ≥ 96(목표 95 + 마진 1)을 만족하는 가장 압축된 값을 찾는다.
3. **크기 기준**: 비디오 외 스트림은 그대로라고 보고 파일 전체 크기를 예측한다. 원본의 85%를 넘으면 인코딩하지 않는다.
4. **인코딩**: 비디오만 재인코딩하고 오디오·자막·챕터·첨부·커버 아트는 copy한다. 컨테이너는 입력과 같다(MOV+AV1만 MP4, MP4/MOV가 아닌 입력은 MKV). 데이터 스트림(타임코드 등)은 버리고 결과에 표시한다.
5. **검증**: 전체 디코드 오류, 화면상 해상도(회전 반영), 프레임 수, 길이(±2초), 스트림 수, 실제 크기 ≤ 85%를 확인한다. 통과하면 임시 파일을 최종 이름으로 바꾸고 원본의 생성·수정 날짜를 복사한 뒤, 토글이 켜져 있으면 원본을 휴지통으로 옮긴다.

실패하거나 취소하면 임시 파일을 지운다. 인코딩 중에는 Mac의 유휴 잠자기를 막는다.

## 한계

- VMAF 96은 검증된 "눈으로 구분 불가" 기준이 아니다. 자기 콘텐츠로 원본과 비교해 보고 조정할 것 (`Sources/MagicClipCore/Encoding.swift`의 `minVMAF`).
- HDR·Dolby Vision 파일은 품질 검증 수단이 없어 처리하지 않는다.
- MOV 입력의 커버 아트는 ffmpeg mov muxer가 쓰지 못해 검증에서 실패하고 원본이 유지된다.
- 디스크 공간 검사는 파일별이다. 두 파일을 함께 처리하다 공간이 모자라면 한쪽이 실패하고 원본은 그대로 남는다.

조사 근거: `reports/시각적 무손실 영상 압축 기술.md`

## 개발

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test                 # ffmpeg·ab-av1이 있으면 실제 인코딩 테스트도 돈다
./scripts/bundle.sh        # Magic Clip.app 생성. 버전은 이 스크립트의 Info.plist에 있다
```

## 라이선스

[MIT](LICENSE). 저작권 표시와 라이선스 문구만 남기면 상업적 사용·수정·재배포 모두 자유롭다.

Magic Clip은 ffmpeg·ab-av1을 포함하지 않고, 사용자가 설치한 실행 파일을 호출만 한다. 각 도구는 자기 라이선스를 따른다: ab-av1은 MIT, ffmpeg는 빌드 구성에 따라 LGPL 또는 GPL(Homebrew 빌드는 `--enable-gpl --enable-version3`이라 GPLv3). ffmpeg를 앱 안에 넣어 배포하려면 그 라이선스 의무를 따로 지켜야 한다.
