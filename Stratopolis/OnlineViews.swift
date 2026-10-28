import SwiftUI

struct OnlineLobbyView: View {
    @Bindable var coordinator: OnlineGameCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    LabeledContent("Joueur", value: coordinator.displayName)
                    LabeledContent("Classement ELO", value: coordinator.rating.value.formatted())
                }

                Section("Matchmaking") {
                    Stepper(
                        "Écart maximal : ±\(coordinator.ratingRange)",
                        value: $coordinator.ratingRange,
                        in: 50...800,
                        step: 50
                    )
                    Text("Recherche entre \(max(100, coordinator.rating.value - coordinator.ratingRange)) et \(coordinator.rating.value + coordinator.ratingRange) ELO.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Cadence proposée") {
                    Picker("Cadence", selection: $coordinator.timeControl) {
                        ForEach(TimeControl.presets) { control in
                            Text(control.name).tag(control)
                        }
                    }
                }

                Section("Assistances proposées") {
                    Toggle("Impact sur les scores", isOn: $coordinator.proposal.scoreImpact)
                    Toggle("Emplacements autorisés", isOn: $coordinator.proposal.candidatePlacements)
                }

                statusSection
            }
            .navigationTitle("Partie en ligne")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        if coordinator.phase == .searching {
                            coordinator.cancelSearch()
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Connexion") {
            switch coordinator.phase {
            case .signedOut:
                ContentUnavailableView(
                    "Game Center requis",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Connectez-vous à Game Center dans les Réglages.")
                )
                Button("Réessayer") {
                    coordinator.authenticate()
                }
            case .ready:
                Button("Chercher un adversaire") {
                    coordinator.findOpponent()
                }
            case .searching:
                ProgressView("Recherche d’un adversaire…")
                Button("Annuler", role: .cancel) {
                    coordinator.cancelSearch()
                }
            case .negotiating:
                if coordinator.opponentName.isEmpty {
                    ProgressView("Connexion…")
                } else {
                    LabeledContent("Adversaire", value: coordinator.opponentName)
                    LabeledContent("ELO adverse", value: coordinator.opponentRating.formatted())
                    if let remote = coordinator.remoteProposal,
                       remote != coordinator.proposal.allowedOnline || coordinator.remoteTimeControl != coordinator.timeControl {
                        Text("L’adversaire propose d’autres assistances. Ajustez vos choix jusqu’à obtenir une configuration identique.")
                            .foregroundStyle(.orange)
                    } else if coordinator.remoteProposal == coordinator.proposal.allowedOnline && coordinator.remoteTimeControl == coordinator.timeControl {
                        ProgressView("Accord obtenu, lancement…")
                    } else {
                        Text("En attente de la proposition adverse.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Proposer ces options") {
                        coordinator.submitProposal()
                    }
                }
            case .playing:
                Label("Partie connectée", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Revenir au plateau") {
                    dismiss()
                }
            case .failed(let message):
                ContentUnavailableView(
                    "Connexion impossible",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
                Button("Réessayer") {
                    coordinator.findOpponent()
                }
            }
        }
    }
}

struct GameHistoryView: View {
    let coordinator: OnlineGameCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.archives.isEmpty {
                    ContentUnavailableView(
                        "Aucune partie enregistrée",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Les parties en ligne terminées apparaîtront ici.")
                    )
                } else {
                    List(coordinator.archives) { archive in
                        Button {
                            coordinator.loadArchive(archive)
                            dismiss()
                        } label: {
                            ArchivedGameRow(archive: archive)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Parties enregistrées")
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

private struct ArchivedGameRow: View {
    let archive: ArchivedGame

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(archive.redName)
                Text(archive.redScore, format: .number)
                    .fontWeight(.bold)
                Text("–")
                    .foregroundStyle(.secondary)
                Text(archive.greenScore, format: .number)
                    .fontWeight(.bold)
                Text(archive.greenName)
            }
            .font(.headline)

            HStack {
                Text(archive.playedAt, format: .dateTime.day().month().year().hour().minute())
                Spacer()
                Text("\(archive.redRating) / \(archive.greenRating) ELO")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("\(archive.snapshot.history.count) coups · toucher pour analyser")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
