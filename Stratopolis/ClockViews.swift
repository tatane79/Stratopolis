import SwiftUI

struct ChessClockView: View {
    let game: GameModel

    var body: some View {
        HStack(spacing: 10) {
            PlayerClockCell(
                player: .red,
                seconds: game.clock.redSeconds,
                isActive: game.currentPlayer == .red && !game.isFinished,
                hasTimedOut: game.clock.timedOutPlayer == .red
            )
            PlayerClockCell(
                player: .green,
                seconds: game.clock.greenSeconds,
                isActive: game.currentPlayer == .green && !game.isFinished,
                hasTimedOut: game.clock.timedOutPlayer == .green
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PlayerClockCell: View {
    let player: Player
    let seconds: TimeInterval
    let isActive: Bool
    let hasTimedOut: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(player == .red ? Color.red : Color.green)
                .frame(width: 10, height: 10)
            Text(Self.formatted(seconds))
                .font(.system(.headline, design: .monospaced, weight: .bold))
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if isActive {
                Image(systemName: "timer")
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            hasTimedOut ? Color.red.opacity(0.3) : (isActive ? Color.yellow.opacity(0.16) : .black.opacity(0.2)),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.yellow.opacity(0.8) : .white.opacity(0.08))
        }
        .accessibilityLabel("\(player.displayName), \(Self.spoken(seconds)) restantes")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        if total >= 86_400 {
            let days = total / 86_400
            let hours = (total % 86_400) / 3_600
            return "\(days)j \(hours)h"
        }
        if total >= 3_600 {
            return String(format: "%02d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        if total >= 86_400 {
            return "\(total / 86_400) jours et \((total % 86_400) / 3_600) heures"
        }
        return "\(total / 60) minutes et \(total % 60) secondes"
    }
}

struct TimeControlSettingsView: View {
    let game: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                TimeControlSection(
                    title: "Rapide",
                    explanation: "Pour une partie dynamique sur une seule session.",
                    controls: TimeControl.presets.filter { $0.category == .rapid },
                    selection: game.selectedTimeControl
                ) { game.selectedTimeControl = $0 }

                TimeControlSection(
                    title: "Classique",
                    explanation: "Pour prendre le temps d’analyser les empilements.",
                    controls: TimeControl.presets.filter { $0.category == .standard },
                    selection: game.selectedTimeControl
                ) { game.selectedTimeControl = $0 }

                TimeControlSection(
                    title: "Correspondance",
                    explanation: "Chaque joueur dispose de cette réserve totale pour une partie étalée sur plusieurs jours.",
                    controls: TimeControl.presets.filter { $0.category == .correspondence },
                    selection: game.selectedTimeControl
                ) { game.selectedTimeControl = $0 }
            }
            .navigationTitle("Cadence")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TimeControlSection: View {
    let title: LocalizedStringKey
    let explanation: LocalizedStringKey
    let controls: [TimeControl]
    let selection: TimeControl
    let select: (TimeControl) -> Void

    var body: some View {
        Section {
            ForEach(controls) { control in
                Button {
                    select(control)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(control.name)
                                .foregroundStyle(.primary)
                            if control.incrementSeconds > 0 {
                                Text("Incrément de \(Int(control.incrementSeconds)) secondes par coup")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selection == control {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(explanation)
        }
    }
}
