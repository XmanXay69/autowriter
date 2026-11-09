//
//  PermissionView.swift
//  The first-run screen: walks you through turning on Accessibility.
//  AutoWriter checks every second, so this screen goes away by itself as
//  soon as the switch is on.
//

import SwiftUI

struct PermissionView: View {
    let model: AppModel

    var body: some View {
        VStack {
            Spacer(minLength: 20)
            Card(padding: EdgeInsets(top: 18, leading: 22, bottom: 20, trailing: 22)) {
                Caption("One-time setup")
                Text("AutoWriter needs the Accessibility permission")
                    .font(.system(size: 19, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("It lets AutoWriter press keys in other apps and see which window is in front. AutoWriter doesn't record your screen or your keystrokes, and it only types when you press Start.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Click **Open System Settings**. It opens Privacy & Security → Accessibility.")
                    step(2, "Turn on **AutoWriter**. (Not in the list? Click **+**, pick AutoWriter in Applications.)")
                    step(3, "Come back here. AutoWriter notices by itself within a second.")
                }
                .padding(.vertical, 4)

                HStack(spacing: 8) {
                    Button("Open System Settings") {
                        Permissions.requestAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.awPrimary)
                    Button("Check Again") { model.hasPermission = Permissions.hasAccessibility }
                        .buttonStyle(.aw)
                    Spacer()
                }

                Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4)

                Text("Switch already on but you still see this? macOS may be remembering an older copy of AutoWriter. Click Reset Permission, turn AutoWriter on again, then click Quit & Reopen.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Button("Reset Permission") { Permissions.resetAccessibility(); Permissions.openAccessibilitySettings() }
                    Button("Quit & Reopen") { Permissions.quitAndReopen() }
                }
                .buttonStyle(.awLink)
            }
            .frame(maxWidth: 500)
            Spacer(minLength: 20)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)
                .background(Theme.accentSoft, in: Circle())
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
