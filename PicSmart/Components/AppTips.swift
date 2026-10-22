//
//  AppTips.swift
//  PicSmart
//

import SwiftUI
import TipKit

// MARK: - App Tips

struct PullToRefreshTip: Tip {
    var title: Text {
        Text("Pull to Refresh")
    }
    var message: Text? {
        Text("Pull down on any screen to re-scan and detect newly added photos or videos.")
    }
    var image: Image? {
        Image(systemName: "arrow.clockwise")
    }
}

struct BestShotTip: Tip {
    var title: Text {
        Text("Algorithmic Best Shot")
    }
    var message: Text? {
        Text("The yellow 'Best' badge marks the sharpest image in the burst. Tap any other photo to make it your keeper instead.")
    }
    var image: Image? {
        Image(systemName: "checkmark.seal")
    }
}

struct TapToPreviewTip: Tip {
    var title: Text {
        Text("High-Resolution Inspection")
    }
    var message: Text? {
        Text("Tap any photo to open a crisp, full-resolution zoomable preview.")
    }
    var image: Image? {
        Image(systemName: "magnifyingglass")
    }
}
