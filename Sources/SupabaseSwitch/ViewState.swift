import SwiftUI

/// With the macOS 27 SDK `@State` and `@FocusState` are macros, and their
/// compiler plugin ships with Xcode but not with the Command Line Tools.
/// Through these aliases the attributes resolve to the property wrappers
/// instead, which build the same with or without Xcode.
///
/// Con el SDK de macOS 27 `@State` y `@FocusState` son macros, y su plugin
/// del compilador viene con Xcode pero no con las Command Line Tools. Con
/// estos alias el atributo resuelve al envoltorio de propiedad, que compila
/// igual con o sin Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias ViewFocus<Value: Hashable> = SwiftUI.FocusState<Value>
