import ContactsUI
import SwiftUI

extension View {
  /// Wraps `.contactAccessPicker` so the symbol is never invoked when the
  /// iOS app runs on an Apple-silicon Mac ("Designed for iPad").
  ///
  /// The ContactsUI symbol does not exist in the macOS framework. This guard
  /// only stops the call; the app target also links ContactsUI with
  /// `-weak_framework` (OTHER_LDFLAGS) so the missing symbol binds to nil
  /// instead of failing at launch on a Mac (ITMS-90863). `AnyView` keeps the
  /// picker's opaque type out of callers' static view types, so a Mac never
  /// resolves its (missing) type descriptor.
  func limitedContactAccessPicker(
    isPresented: Binding<Bool>,
    onSelection: @escaping ([String]) -> Void
  ) -> AnyView {
    if #available(iOS 18, *), !ProcessInfo.processInfo.isiOSAppOnMac {
      AnyView(contactAccessPicker(isPresented: isPresented, completionHandler: onSelection))
    } else {
      AnyView(self)
    }
  }
}
