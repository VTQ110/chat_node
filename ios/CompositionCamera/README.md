# Bố Cục Cam – iOS camera với hướng dẫn bố cục

Ứng dụng camera iOS (SwiftUI + AVFoundation). Khi mở camera, màn hình hiển thị lưới bố cục
và gợi ý trực tiếp để chủ thể nằm đúng "điểm vàng", giúp chụp ảnh đẹp hơn.

## Tính năng

- **7 kiểu lưới bố cục**: Quy tắc 1/3, Tỉ lệ vàng (phi grid), Xoắn ốc vàng (xoay được 4 hướng),
  Tam giác vàng, Đường chéo, Đối xứng, Tắt. Mỗi kiểu có mẹo chụp hiện khi chọn.
- **Gợi ý thông minh** (nút ✨): nhận diện khuôn mặt (AVCaptureMetadataOutput) hoặc chủ thể nổi bật
  (Vision saliency), khoanh vùng chủ thể, nối tới điểm vàng gần nhất và nói cách di chuyển máy
  ("Hướng máy sang trái và lên trên"). Khi đúng vị trí khung chuyển xanh: "Bố cục đẹp!".
  Nếu chủ thể quá lớn sẽ nhắc lùi ra xa.
- **Thước cân bằng** (CoreMotion): đường chân trời luôn nằm ngang với thực tế, chuyển xanh khi máy thẳng.
- Chạm để lấy nét/đo sáng, đổi camera trước/sau, chụp ảnh và lưu vào thư viện Ảnh.
- Khung ngắm 3:4 khớp đúng với ảnh chụp, nên lưới trên màn hình trùng với ảnh thật.

## Cài lên iPhone không cần Mac (file .ipa)

Mỗi lần push thay đổi trong `ios/`, GitHub Actions (workflow `iOS build`) tự build app trên macOS và
tạo file **`CompositionCamera-unsigned.ipa`**. Tải file đó ở tab *Actions* → lần chạy mới nhất →
mục *Artifacts* (giải nén file .zip tải về để lấy .ipa).

File .ipa chưa được ký, nên cần ký bằng Apple ID của bạn khi cài:

1. Cài **Sideloadly** (Windows/Mac, https://sideloadly.io) hoặc **AltStore** (https://altstore.io).
2. Cắm iPhone vào máy tính, kéo file .ipa vào Sideloadly, nhập Apple ID rồi bấm *Start*.
3. Trên iPhone: *Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị* → tin cậy Apple ID của bạn.
4. iOS 16+: bật *Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển* rồi khởi động lại máy.

Với Apple ID miễn phí, app hết hạn sau 7 ngày (chỉ cần cài lại). Có tài khoản Apple Developer
(99 USD/năm) thì dùng Xcode/TestFlight như bên dưới.

## Chạy dự án bằng Xcode

Yêu cầu: Xcode 15+, iOS 16+, iPhone thật (Simulator không có camera).

```bash
brew install xcodegen
cd ios/CompositionCamera
xcodegen generate
open CompositionCamera.xcodeproj
```

Chọn Team ở mục *Signing & Capabilities*, đổi Bundle ID nếu cần, rồi Run trên iPhone.

## Cấu trúc

| File | Vai trò |
| --- | --- |
| `Camera/CameraService.swift` | AVCaptureSession, chụp ảnh, lưu ảnh, nhận diện chủ thể |
| `Camera/CameraPreviewView.swift` | Hiển thị preview camera |
| `Composition/CompositionGuide.swift` | Hình học các lưới bố cục và điểm vàng |
| `Composition/CompositionAdvisor.swift` | Tính gợi ý di chuyển máy |
| `Motion/LevelMonitor.swift` | Đo độ nghiêng máy |
| `Views/*` | Giao diện SwiftUI |
