import SwiftUI

/// C3: DragGesture(.global)는 **윈도우-로컬 좌상단 원점** 좌표를 반환한다.
/// 오버레이가 전체 화면이므로 윈도우 원점 == 스크린 원점(좌상단)이 된다.
/// 하지만 AppKit/ScreenCaptureKit은 좌하단 원점을 사용하므로,
/// onComplete로 전달된 rect를 사용할 때 반드시 좌표 변환이 필요하다.
/// 변환 공식: appKitY = screen.frame.maxY - swiftUIY
struct SelectionOverlayView: View {
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false

    private var selectionRect: CGRect {
        guard isDragging else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    var body: some View {
        ZStack {
            // 반투명 어두운 배경
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            // 선택 영역 (밝게 표시)
            if isDragging && selectionRect.width > 2 && selectionRect.height > 2 {
                Rectangle()
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .blendMode(.destinationOut)

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
            }
        }
        .compositingGroup()
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { _ in
                    let rect = selectionRect
                    isDragging = false
                    if rect.width > 10 && rect.height > 10 {
                        onComplete(rect)
                    } else {
                        onCancel()
                    }
                }
        )
    }
}
