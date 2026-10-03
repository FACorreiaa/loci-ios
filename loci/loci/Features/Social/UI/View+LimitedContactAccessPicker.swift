import ContactsUI
import SwiftUI

extension View {
  /// Wraps `.contactAccessPicker` so the symbol is never invoked when the
  /// iOS app runs on an Apple-silicon Mac ("Designed for iPad").
  ///
  /// This avoids ITMS-90863 at upload time — the ContactsUI symbol does not
  /// exist in the macOS framework and would crash if called there.
  @ViewBuilder
  func limitedContactAccessPicker(
    isPresented: Binding<Bool>,
    onSelection: @escaping ([String]) -> Void
  ) -> some View {
    if #available(iOS 18, *), !ProcessInfo.processInfo.isiOSAppOnMac {
      self.contactAccessPicker(isPresented: isPresented, completionHandler: onSelection)
    } else {
      self
    }
  }
}
