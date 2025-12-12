import SwiftUI

struct GridLayoutSpec {
    /// 전체 캔버스 대비 그리드 높이 비율
    var gridHeightRatio: CGFloat = 0.32

    /// 좌우 여백 (캔버스 width 기준)
    var horizontalInsetRatio: CGFloat = 0.06

    /// 두 줄 사이 간격 (gridHeight 기준)
    var rowSpacingRatio: CGFloat = 0.10

    var firstRowCells: Int = 8
    var secondRowCells: Int = 6
}

