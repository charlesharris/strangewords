import SwiftUI

/// The original look: a soft cherry-blossom day/night scene with falling petals.
/// Its palettes live on `TimeOfDay` (the app's first theme), and its scene and
/// dissolution are `PixelScene` / `PixelPetalDissolution`.
struct NatureTheme: SceneTheme {
    let id = "nature"
    let name = "nature"

    func palette(_ timeOfDay: TimeOfDay) -> Palette { timeOfDay.palette }

    func background(_ timeOfDay: TimeOfDay, _ palette: Palette) -> AnyView {
        AnyView(PixelScene(palette: palette, timeOfDay: timeOfDay))
    }

    var dissolution: any DissolutionEffect { PixelPetalDissolution() }
}
