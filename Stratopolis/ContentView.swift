import SwiftUI

struct ContentView: View {
    @State private var game = GameModel()
    @State private var online = OnlineGameCoordinator()
    @State private var showsOnlineLobby = false
    @State private var showsHistory = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GamePalette.backgroundTop, GamePalette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                if geometry.size.width >= 760 && geometry.size.width > geometry.size.height {
                    LandscapeGameLayout(game: game)
                } else {
                    CompactGameLayout(
                        game: game,
                        showsFullScores: geometry.size.width >= 700
                    )
                }
            }
        }
        .sheet(isPresented: $game.showsRules) {
            RulesView()
        }
        .confirmationDialog(
            "Nouvelle partie",
            isPresented: $game.showsNewGameOptions,
            titleVisibility: .visible
        ) {
            Button("Jouer contre l’IA") {
                game.newGame(mode: .computer)
            }
            Button("Jouer avec un ami sur cet appareil") {
                game.newGame(mode: .localMultiplayer)
            }
            Button("Jouer en ligne") {
                showsOnlineLobby = true
            }
            Button("Parties enregistrées") {
                showsHistory = true
            }
            Button("Cadence : \(game.selectedTimeControl.name)") {
                game.showsTimeControlSettings = true
            }
            if game.hasSelectedGameMode {
                Button("Annuler", role: .cancel) {}
            }
        } message: {
            Text("Choisissez votre adversaire pour cette partie.")
        }
        .sheet(isPresented: $game.showsTimeControlSettings) {
            TimeControlSettingsView(game: game)
        }
        .sheet(isPresented: $showsOnlineLobby) {
            OnlineLobbyView(coordinator: online)
        }
        .sheet(isPresented: $showsHistory) {
            GameHistoryView(coordinator: online)
        }
        .task {
            online.connect(to: game)
            game.playComputerTurnIfNeeded()
        }
        .preferredColorScheme(.dark)
    }
}

private struct LandscapeGameLayout: View {
    let game: GameModel

    var body: some View {
        HStack(spacing: 24) {
            GameSidebar(game: game)
                .frame(width: 300)
            GamePlayArea(game: game)
        }
        .padding(24)
    }
}

private struct CompactGameLayout: View {
    let game: GameModel
    let showsFullScores: Bool

    var body: some View {
        VStack(spacing: 10) {
            CompactHeader(game: game)
            TurnIndicator(
                player: game.currentPlayer,
                isFinished: game.isFinished,
                isComputer: game.isComputerTurn
            )
            if game.usesClock {
                ChessClockView(game: game)
            }

            if showsFullScores {
                PortraitPlayerBar(game: game)
            }

            GamePlayArea(game: game)
            CompactGameFooter(game: game)
        }
        .padding(12)
    }
}

private struct PortraitPlayerBar: View {
    let game: GameModel

    var body: some View {
        HStack(spacing: 12) {
            PlayerScoreCard(
                player: .red,
                score: game.redScore,
                remaining: game.piles[.red]?.count ?? 0,
                isCurrent: game.currentPlayer == .red && !game.isFinished
            )
            PlayerScoreCard(
                player: .green,
                score: game.greenScore,
                remaining: game.piles[.green]?.count ?? 0,
                isCurrent: game.currentPlayer == .green && !game.isFinished
            )
        }
    }
}

private struct CompactGameFooter: View {
    let game: GameModel

    var body: some View {
        VStack(spacing: 8) {
            Text(game.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(game.canPlacePreview ? GamePalette.green : .white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            GameControls(game: game)
        }
    }
}

private struct GameSidebar: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            BrandHeader()
            TurnIndicator(
                player: game.currentPlayer,
                isFinished: game.isFinished,
                isComputer: game.isComputerTurn
            )
            if game.usesClock {
                ChessClockView(game: game)
            }
            PlayerScoreCard(
                player: .red,
                score: game.redScore,
                remaining: game.piles[.red]?.count ?? 0,
                isCurrent: game.currentPlayer == .red && !game.isFinished
            )
            PlayerScoreCard(
                player: .green,
                score: game.greenScore,
                remaining: game.piles[.green]?.count ?? 0,
                isCurrent: game.currentPlayer == .green && !game.isFinished
            )
            Spacer(minLength: 8)
            Text(game.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(game.canPlacePreview ? GamePalette.green : .white.opacity(0.72))
                .lineLimit(2, reservesSpace: true)
            GameControls(game: game)
        }
        .padding(24)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.08))
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("STRATOPOLIS")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .tracking(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
            Text("SURFACE × HAUTEUR")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct CompactHeader: View {
    let game: GameModel

    var body: some View {
        let impact = game.previewScoreImpact
        HStack {
            Text("STRATOPOLIS")
                .font(.title2.weight(.black))
            Spacer()
            ScorePill(player: .red, score: game.redScore.total, impact: impact?.red)
            ScorePill(player: .green, score: game.greenScore.total, impact: impact?.green)
        }
    }
}

private struct TurnIndicator: View {
    let player: Player
    let isFinished: Bool
    let isComputer: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                }
                .shadow(color: indicatorColor.opacity(0.8), radius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(isFinished ? "PARTIE TERMINÉE" : (isComputer ? "TOUR DE L’ORDINATEUR" : "TOUR DU JOUEUR"))
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.7))
                if !isFinished {
                    Text(isComputer ? "VERT · IA" : (player == .red ? "ROUGE" : "VERT"))
                        .font(.title2.weight(.black))
                        .foregroundStyle(indicatorColor)
                }
            }

            Spacer()

            if !isFinished {
                Image(systemName: "hand.point.right.fill")
                    .font(.title2)
                    .foregroundStyle(indicatorColor)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(indicatorColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(indicatorColor.opacity(0.85), lineWidth: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var indicatorColor: Color {
        isFinished ? GamePalette.gold : GamePalette.color(for: player.color)
    }

    private var accessibilityText: String {
        isFinished ? "Partie terminée" : (isComputer ? "Tour de l’ordinateur" : "Tour du joueur \(player.displayName)")
    }
}

private struct ScorePill: View {
    let player: Player
    let score: Int
    let impact: Int?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(GamePalette.color(for: player.color))
                .frame(width: 10, height: 10)
            Text(score, format: .number)
                .font(.headline.monospacedDigit())
            if let impact {
                HStack(spacing: 0) {
                    Text("(")
                    Text(impact, format: .number.sign(strategy: .always()))
                    Text(")")
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.25), in: Capsule())
        .accessibilityLabel("\(player.displayName), \(score) points")
        .accessibilityValue(impact.map { "Variation prévue : \($0)" } ?? "")
    }
}

private struct PlayerScoreCard: View {
    let player: Player
    let score: ZoneScore
    let remaining: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(GamePalette.color(for: player.color))
                .frame(width: 18, height: 18)
                .shadow(color: GamePalette.color(for: player.color).opacity(0.55), radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(player.displayName)
                        .font(.headline)
                    if isCurrent {
                        Text("À VOUS")
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                }
                Text("\(score.surface) cases × niveau \(score.height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(score.total, format: .number)
                    .font(.title2.weight(.black).monospacedDigit())
                Text("\(remaining) tuiles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .background(isCurrent ? .white.opacity(0.11) : .black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(isCurrent ? GamePalette.color(for: player.color).opacity(0.7) : .clear, lineWidth: 1.5)
        }
    }
}

private struct GamePlayArea: View {
    let game: GameModel

    var body: some View {
        GeometryReader { geometry in
            let trayHeight = min(112, max(86, geometry.size.height * 0.18))
            let spacing: CGFloat = 12
            let availableBoardHeight = max(0, geometry.size.height - trayHeight - spacing)
            let boardFrame = CGRect(
                x: 0,
                y: trayHeight + spacing,
                width: geometry.size.width,
                height: availableBoardHeight
            )
            ZStack(alignment: .topLeading) {
                TileTray(game: game)
                    .frame(width: geometry.size.width, height: trayHeight)
                    .zIndex(2)

                SceneBoardView(game: game)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .overlay {
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(.white.opacity(0.1))
                            .allowsHitTesting(false)
                    }
                    .frame(width: boardFrame.width, height: boardFrame.height)
                    .position(x: boardFrame.midX, y: boardFrame.midY)
            }
        }
        .coordinateSpace(.named("gamePlayArea"))
    }
}

private struct TileTray: View {
    let game: GameModel
    @GestureState private var liveRotation: Angle = .zero

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.isFinished ? "PARTIE TERMINÉE" : "TUILE À PLACER")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text(game.isFinished ? "Toutes les tuiles ont été jouées." : "Glissez pour déplacer · Touchez pour tourner · Pincez pour zoomer")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let tile = game.currentTile {
                TilePiece3DPreview(
                    colors: tile.colors,
                    rotation: game.rotation
                )
                    .frame(width: 88, height: 88)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .rotationEffect(liveRotation)
                    .animation(.snappy(duration: 0.18), value: game.rotation)
                    .contentShape(Rectangle())
                    .gesture(rotationGesture)
                    .accessibilityLabel("Tuile à placer")
                    .accessibilityHint("Touchez le plateau pour choisir sa position. Utilisez le bouton Tourner pour la faire pivoter.")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1))
        }
    }

    private var rotationGesture: some Gesture {
        RotateGesture()
            .updating($liveRotation) { value, state, _ in
                guard value.rotation.degrees.isFinite else { return }
                state = value.rotation
            }
            .onEnded { value in
                let quarterTurns = snappedQuarterTurns(for: value.rotation)
                guard quarterTurns != 0 else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    game.rotate(by: quarterTurns)
                }
            }
    }
}

private func snappedQuarterTurns(for angle: Angle) -> Int {
    guard angle.degrees.isFinite else { return 0 }
    let rawQuarterTurns = angle.degrees / 90
    let roundedQuarterTurns = Int(rawQuarterTurns.rounded())
    if roundedQuarterTurns == 0, abs(angle.degrees) >= 30 {
        return angle.degrees > 0 ? 1 : -1
    }
    return roundedQuarterTurns
}

private struct GameControls: View {
    let game: GameModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    game.rotate()
                } label: {
                    Label("Tourner", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameButtonStyle())
                .disabled(game.isComputerTurn || !game.isLocalPlayersTurn)

                Button {
                    game.place()
                } label: {
                    Label("Poser", systemImage: "square.stack.3d.up.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameButtonStyle(isPrimary: true))
                .disabled(!game.canPlacePreview || game.isComputerTurn || !game.isLocalPlayersTurn)
            }

            HStack {
                Button("Annuler", systemImage: "arrow.uturn.backward") {
                    game.undo()
                }
                .disabled(!game.canUndo)

                Spacer()

                Button("Règles", systemImage: "book.closed") {
                    game.showsRules = true
                }

                Button("Nouvelle partie", systemImage: "arrow.counterclockwise") {
                    game.showsNewGameOptions = true
                }
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))

            AssistanceControls(game: game)
        }
    }
}

private struct AssistanceControls: View {
    let game: GameModel
    @State private var showsAISettings = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                game.showsScoreImpact.toggle()
            } label: {
                Image(systemName: "plus.forwardslash.minus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AssistanceButtonStyle(isSelected: game.showsScoreImpact))
            .accessibilityLabel("Impact sur les scores")
            .accessibilityValue(game.showsScoreImpact ? "Activé" : "Désactivé")

            Button {
                game.showsCandidatePlacements.toggle()
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AssistanceButtonStyle(isSelected: game.showsCandidatePlacements))
            .accessibilityLabel("Emplacements candidats")
            .accessibilityValue(game.showsCandidatePlacements ? "Activés" : "Désactivés")

            Button {
                game.showsBestPlacement.toggle()
            } label: {
                Image(systemName: "star.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AssistanceButtonStyle(isSelected: game.showsBestPlacement))
            .accessibilityLabel("Meilleur coup")
            .accessibilityValue(game.showsBestPlacement ? "Activé" : "Désactivé")

            Button {
                showsAISettings = true
            } label: {
                Image(systemName: "brain.head.profile")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AssistanceButtonStyle(isSelected: false))
            .disabled(game.gameMode != .computer)
            .accessibilityLabel("Réglages de l’intelligence artificielle")
        }
        .disabled(game.gameMode == .online)
        .sheet(isPresented: $showsAISettings) {
            AILevelSettings(game: game)
                .presentationDetents([.height(230)])
        }
    }
}

private struct AILevelSettings: View {
    let game: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label("Intelligence artificielle", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                Button("Terminé") {
                    dismiss()
                }
            }

            VStack(spacing: 10) {
                HStack {
                    Text("Niveau")
                    Spacer()
                    Text(game.aiLevel, format: .number)
                        .font(.headline.monospacedDigit())
                }
                Slider(
                    value: Binding(
                        get: { Double(game.aiLevel) },
                        set: { game.aiLevel = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
            }
        }
        .padding(24)
    }
}

private struct AssistanceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(
                !isEnabled
                    ? .white.opacity(0.28)
                    : (isSelected ? GamePalette.gold : .white.opacity(0.78))
            )
            .frame(minHeight: 44)
            .background(
                !isEnabled
                    ? .black.opacity(0.1)
                    : (isSelected ? GamePalette.gold.opacity(0.18) : .black.opacity(0.2)),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        !isEnabled
                            ? .white.opacity(0.04)
                            : (isSelected ? GamePalette.gold.opacity(0.7) : .white.opacity(0.1))
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GameButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 13)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(isPrimary && isEnabled ? .black : .white.opacity(isEnabled ? 1 : 0.48))
            .opacity(isEnabled ? 1 : 0.62)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .gray.opacity(0.32) }
        if isPrimary {
            return GamePalette.gold.opacity(isPressed ? 0.72 : 1)
        }
        return .white.opacity(isPressed ? 0.16 : 0.1)
    }
}

private struct GameBoard: View {
    let game: GameModel
    @State private var previewDragOffset: BoardCoordinate?
    @GestureState private var liveRotation: Angle = .zero

    var body: some View {
        GeometryReader { geometry in
            let layout = BoardLayout(
                size: geometry.size,
                bounds: game.occupiedBounds,
                presentation: game.boardPresentation
            )
            let translationGesture = DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard let previewPlacement = game.previewPlacement else { return }
                    let startCoordinate = layout.coordinate(at: value.startLocation)
                    guard previewPlacement.coordinates.contains(startCoordinate) else { return }

                    let offset = previewDragOffset ?? BoardCoordinate(
                        x: startCoordinate.x - previewPlacement.center.x,
                        y: startCoordinate.y - previewPlacement.center.y
                    )
                    previewDragOffset = offset

                    let fingerCoordinate = layout.coordinate(at: value.location)
                    game.select(
                        BoardCoordinate(
                            x: fingerCoordinate.x - offset.x,
                            y: fingerCoordinate.y - offset.y
                        )
                    )
                }
                .onEnded { _ in
                    previewDragOffset = nil
                }
            let rotationGesture = RotateGesture()
                .updating($liveRotation) { value, state, _ in
                    guard game.previewPlacement != nil, value.rotation.degrees.isFinite else { return }
                    state = value.rotation
                }
                .onEnded { value in
                    guard game.previewPlacement != nil else { return }
                    let quarterTurns = snappedQuarterTurns(for: value.rotation)
                    guard quarterTurns != 0 else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        game.rotate(by: quarterTurns)
                    }
                }
            let placementTap = SpatialTapGesture()
                .onEnded { value in
                    game.select(layout.coordinate(at: value.location))
                }

            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(.black.opacity(0.42))
                BoardGrid(layout: layout)
                PlacedCells(game: game, layout: layout)
                PlacedTileOutlines(board: game.board, layout: layout)
                PreviewCells(game: game, layout: layout)
                    .rotationEffect(
                        liveRotation,
                        anchor: UnitPoint(
                            x: layout.center(of: game.previewCenter, level: game.previewDisplayLevel).x / geometry.size.width,
                            y: layout.center(of: game.previewCenter, level: game.previewDisplayLevel).y / geometry.size.height
                        )
                    )
                    .animation(.snappy(duration: 0.18), value: game.rotation)

                if let placement = game.previewPlacement {
                    RotationCornerControls(
                        game: game,
                        placement: placement,
                        layout: layout,
                        boardSize: geometry.size
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(translationGesture)
            .simultaneousGesture(rotationGesture)
            .simultaneousGesture(placementTap, including: .gesture)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Plateau de Stratopolis")
            .accessibilityHint("Touchez un emplacement ou faites glisser la tuile pour la déplacer. Utilisez deux doigts pour la faire pivoter.")
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
    }

}

private struct RotationCornerControls: View {
    let game: GameModel
    let placement: Placement
    let layout: BoardLayout
    let boardSize: CGSize

    var body: some View {
        let frame = projectedFrame

        QuarterTurnButton(
            systemImage: "arrow.counterclockwise",
            accessibilityLabel: "Tourner d’un quart de tour à gauche"
        ) {
            game.rotate(by: -1)
        }
        .position(clampedPosition(x: frame.minX - 24, y: frame.minY - 24))

        QuarterTurnButton(
            systemImage: "arrow.clockwise",
            accessibilityLabel: "Tourner d’un quart de tour à droite"
        ) {
            game.rotate(by: 1)
        }
        .position(clampedPosition(x: frame.maxX + 24, y: frame.minY - 24))

        QuarterTurnButton(
            systemImage: "arrow.counterclockwise",
            accessibilityLabel: "Tourner d’un quart de tour à gauche"
        ) {
            game.rotate(by: -1)
        }
        .position(clampedPosition(x: frame.minX - 24, y: frame.maxY + 24))

        QuarterTurnButton(
            systemImage: "arrow.clockwise",
            accessibilityLabel: "Tourner d’un quart de tour à droite"
        ) {
            game.rotate(by: 1)
        }
        .position(clampedPosition(x: frame.maxX + 24, y: frame.maxY + 24))
    }

    private func clampedPosition(x: CGFloat, y: CGFloat) -> CGPoint {
        let margin: CGFloat = 26
        return CGPoint(
            x: min(max(x, margin), boardSize.width - margin),
            y: min(max(y, margin), boardSize.height - margin)
        )
    }

    private var projectedFrame: CGRect {
        let displayLevel = (placement.coordinates.map(game.height(at:)).max() ?? 0) + 1
        let centers = placement.coordinates.map {
            layout.center(of: $0, level: displayLevel)
        }
        let minX = centers.map(\.x).min() ?? 0
        let maxX = centers.map(\.x).max() ?? 0
        let minY = centers.map(\.y).min() ?? 0
        let maxY = centers.map(\.y).max() ?? 0
        return CGRect(
            x: minX - layout.cellSize / 2,
            y: minY - layout.tileHeight / 2,
            width: maxX - minX + layout.cellSize,
            height: maxY - minY + layout.tileHeight
        )
    }
}

private struct QuarterTurnButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.black))
                .frame(width: 44, height: 44)
                .foregroundStyle(.black)
                .background(GamePalette.gold, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.9), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct BoardGrid: View {
    let layout: BoardLayout

    var body: some View {
        Canvas { context, _ in
            var grid = Path()

            for x in layout.minX...layout.maxX {
                for y in layout.minY...layout.maxY {
                    let corners = layout.tileCorners(of: BoardCoordinate(x: x, y: y))
                    grid.move(to: corners.top)
                    grid.addLine(to: corners.right)
                    grid.addLine(to: corners.bottom)
                    grid.addLine(to: corners.left)
                    grid.closeSubpath()
                }
            }

            context.stroke(grid, with: .color(.white.opacity(0.09)), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }
}

private struct PlacedCells: View {
    let game: GameModel
    let layout: BoardLayout

    var body: some View {
        ForEach(sortedCoordinates, id: \.self) { coordinate in
            if let color = game.topColor(at: coordinate) {
                BoardCell(
                    color: color,
                    height: game.height(at: coordinate),
                    isPreview: false,
                    isValid: true,
                    size: layout.cellSize,
                    presentation: layout.presentation
                )
                .position(
                    layout.center(
                        of: coordinate,
                        level: game.height(at: coordinate)
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var sortedCoordinates: [BoardCoordinate] {
        game.board.keys.sorted {
            switch layout.presentation {
            case .topDown:
                ($0.y, $0.x) < ($1.y, $1.x)
            case .isometric:
                ($0.x + $0.y, $0.y) < ($1.x + $1.y, $1.y)
            }
        }
    }
}

private struct PlacedTileOutlines: View {
    let board: [BoardCoordinate: [CellLayer]]
    let layout: BoardLayout

    var body: some View {
        Canvas { context, _ in
            var visibleCoordinatesByTile: [UUID: Set<BoardCoordinate>] = [:]

            for (coordinate, layers) in board {
                guard let tileID = layers.last?.tileID else { continue }
                visibleCoordinatesByTile[tileID, default: []].insert(coordinate)
            }

            for (tileID, coordinates) in visibleCoordinatesByTile {
                let level = coordinates.compactMap { board[$0]?.count }.max() ?? 1
                let outline = perimeterPath(
                    for: coordinates,
                    level: level,
                    layout: layout
                )
                context.stroke(outline, with: .color(.black.opacity(0.8)), lineWidth: 4)
                context.stroke(outline, with: .color(outlineColor(for: tileID)), lineWidth: 1.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func outlineColor(for tileID: UUID) -> Color {
        let seed = tileID.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hues = [0.08, 0.14, 0.5, 0.58, 0.76, 0.9]
        return Color(hue: hues[seed % hues.count], saturation: 0.72, brightness: 1)
    }
}

private struct PreviewCells: View {
    let game: GameModel
    let layout: BoardLayout

    var body: some View {
        if let placement = game.previewPlacement {
            let displayLevel = (placement.coordinates.map(game.height(at:)).max() ?? 0) + 1

            ForEach(Array(placement.coordinates.enumerated()), id: \.offset) { index, coordinate in
                BoardCell(
                    color: placement.tile.colors[index],
                    height: displayLevel,
                    isPreview: true,
                    isValid: game.canPlacePreview,
                    size: layout.cellSize,
                    presentation: layout.presentation
                )
                .position(layout.center(of: coordinate, level: displayLevel))
            }

            PreviewPieceOutline(
                coordinates: placement.coordinates,
                level: displayLevel,
                layout: layout
            )
        }
    }
}

private func perimeterPath(
    for coordinates: Set<BoardCoordinate>,
    level: Int = 1,
    layout: BoardLayout
) -> Path {
    var outline = Path()

    for coordinate in coordinates {
        let corners = layout.tileCorners(of: coordinate, level: level)

        if !coordinates.contains(BoardCoordinate(x: coordinate.x - 1, y: coordinate.y)) {
            outline.move(to: corners.left)
            outline.addLine(to: corners.top)
        }
        if !coordinates.contains(BoardCoordinate(x: coordinate.x, y: coordinate.y - 1)) {
            outline.move(to: corners.top)
            outline.addLine(to: corners.right)
        }
        if !coordinates.contains(BoardCoordinate(x: coordinate.x + 1, y: coordinate.y)) {
            outline.move(to: corners.right)
            outline.addLine(to: corners.bottom)
        }
        if !coordinates.contains(BoardCoordinate(x: coordinate.x, y: coordinate.y + 1)) {
            outline.move(to: corners.bottom)
            outline.addLine(to: corners.left)
        }
    }

    return outline
}

private struct PreviewPieceOutline: View {
    let coordinates: [BoardCoordinate]
    let level: Int
    let layout: BoardLayout

    var body: some View {
        Canvas { context, _ in
            context.stroke(
                perimeterPath(for: Set(coordinates), level: level, layout: layout),
                with: .color(.orange),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6])
            )
        }
        .allowsHitTesting(false)
    }
}

private struct BoardCell: View {
    let color: TileColor
    let height: Int
    let isPreview: Bool
    let isValid: Bool
    let size: CGFloat
    let presentation: BoardPresentation

    var body: some View {
        switch presentation {
        case .topDown:
            TopDownTileCell(
                color: color,
                height: height,
                isPreview: isPreview,
                size: size
            )
        case .isometric:
            IsometricTileCell(
                color: color,
                height: height,
                isPreview: isPreview,
                isValid: isValid,
                size: size
            )
        }
    }
}

private struct TopDownTileCell: View {
    let color: TileColor
    let height: Int
    let isPreview: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let layerCount = min(max(height, 1), 8)
                let depth = min(
                    size * 0.42,
                    size * (0.04 + CGFloat(layerCount) * 0.1)
                )
                let horizontalInset = size * 0.08
                let verticalInset = size * 0.18
                let topRect = CGRect(
                    x: horizontalInset - depth * 0.16,
                    y: verticalInset - depth * 0.35,
                    width: canvasSize.width - horizontalInset * 2,
                    height: canvasSize.height - verticalInset * 2
                )
                let cornerRadius = max(4, size * 0.12)
                let baseColor = GamePalette.color(for: color)

                let bottomFace = Path { path in
                    path.move(to: CGPoint(x: topRect.minX, y: topRect.maxY))
                    path.addLine(to: CGPoint(x: topRect.maxX, y: topRect.maxY))
                    path.addLine(to: CGPoint(x: topRect.maxX + depth * 0.32, y: topRect.maxY + depth))
                    path.addLine(to: CGPoint(x: topRect.minX + depth * 0.32, y: topRect.maxY + depth))
                    path.closeSubpath()
                }
                let rightFace = Path { path in
                    path.move(to: CGPoint(x: topRect.maxX, y: topRect.minY))
                    path.addLine(to: CGPoint(x: topRect.maxX, y: topRect.maxY))
                    path.addLine(to: CGPoint(x: topRect.maxX + depth * 0.32, y: topRect.maxY + depth))
                    path.addLine(to: CGPoint(x: topRect.maxX + depth * 0.32, y: topRect.minY + depth))
                    path.closeSubpath()
                }

                context.fill(
                    bottomFace,
                    with: .color(baseColor.mix(with: .black, by: 0.48).opacity(isPreview ? 0.54 : 1))
                )
                context.fill(
                    rightFace,
                    with: .color(baseColor.mix(with: .black, by: 0.62).opacity(isPreview ? 0.5 : 1))
                )

                if layerCount > 1 {
                    for layer in 1..<layerCount {
                        let offset = CGFloat(layer) * depth / CGFloat(layerCount)
                        var seam = Path()
                        seam.move(to: CGPoint(x: topRect.minX + offset * 0.32, y: topRect.maxY + offset))
                        seam.addLine(to: CGPoint(x: topRect.maxX + offset * 0.32, y: topRect.maxY + offset))
                        context.stroke(seam, with: .color(.black.opacity(0.42)), lineWidth: 0.7)
                    }
                }

                let topFace = RoundedRectangle(cornerRadius: cornerRadius)
                    .path(in: topRect)
                context.fill(
                    topFace,
                    with: .linearGradient(
                        Gradient(colors: [
                            baseColor.mix(with: .white, by: 0.2).opacity(isPreview ? 0.72 : 1),
                            baseColor.opacity(isPreview ? 0.58 : 1)
                        ]),
                        startPoint: CGPoint(x: topRect.minX, y: topRect.minY),
                        endPoint: CGPoint(x: topRect.maxX, y: topRect.maxY)
                    )
                )
                context.stroke(
                    topFace,
                    with: .color(isPreview ? .clear : .white.opacity(0.3)),
                    lineWidth: 1
                )
            }

            if height > 1 {
                Text(height, format: .number)
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.72), in: Circle())
                    .scaleEffect(0.88)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.52), radius: 3, x: 2, y: 4)
    }
}

private struct IsometricTileCell: View {
    let color: TileColor
    let height: Int
    let isPreview: Bool
    let isValid: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let tileHeight = size * 0.52
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let top = CGPoint(x: center.x, y: center.y - tileHeight / 2)
                let right = CGPoint(x: center.x + size / 2, y: center.y)
                let bottom = CGPoint(x: center.x, y: center.y + tileHeight / 2)
                let left = CGPoint(x: center.x - size / 2, y: center.y)
                let depth = visibleDepth

                let rightFace = Path { path in
                    path.move(to: right)
                    path.addLine(to: bottom)
                    path.addLine(to: CGPoint(x: bottom.x, y: bottom.y + depth))
                    path.addLine(to: CGPoint(x: right.x, y: right.y + depth))
                    path.closeSubpath()
                }
                let leftFace = Path { path in
                    path.move(to: left)
                    path.addLine(to: bottom)
                    path.addLine(to: CGPoint(x: bottom.x, y: bottom.y + depth))
                    path.addLine(to: CGPoint(x: left.x, y: left.y + depth))
                    path.closeSubpath()
                }
                let topFace = Path { path in
                    path.move(to: top)
                    path.addLine(to: right)
                    path.addLine(to: bottom)
                    path.addLine(to: left)
                    path.closeSubpath()
                }

                let baseColor = GamePalette.color(for: color)
                context.fill(
                    leftFace,
                    with: .color(baseColor.mix(with: .black, by: 0.5).opacity(isPreview ? 0.55 : 1))
                )
                context.fill(
                    rightFace,
                    with: .color(baseColor.mix(with: .black, by: 0.68).opacity(isPreview ? 0.5 : 1))
                )

                if visibleLayerCount > 1 {
                    for layer in 1..<visibleLayerCount {
                        let yOffset = CGFloat(layer) * depth / CGFloat(visibleLayerCount)
                        var seam = Path()
                        seam.move(to: CGPoint(x: left.x, y: left.y + yOffset))
                        seam.addLine(to: CGPoint(x: bottom.x, y: bottom.y + yOffset))
                        seam.addLine(to: CGPoint(x: right.x, y: right.y + yOffset))
                        context.stroke(seam, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
                    }
                }

                context.fill(
                    topFace,
                    with: .linearGradient(
                        Gradient(colors: [
                            baseColor.opacity(isPreview ? 0.76 : 1),
                            baseColor.mix(with: .white, by: 0.16).opacity(isPreview ? 0.62 : 1)
                        ]),
                        startPoint: top,
                        endPoint: bottom
                    )
                )
                context.stroke(
                    topFace,
                    with: .color(isPreview ? .clear : .white.opacity(0.24)),
                    lineWidth: 1
                )
            }

            if height > 1 {
                Text(height, format: .number)
                    .font(.caption2.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.72), in: Circle())
                    .scaleEffect(0.88)
                    .offset(y: -size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 3, y: visibleDepth + 2)
    }

    private var visibleLayerCount: Int {
        min(max(height, 1), 8)
    }

    private var visibleDepth: CGFloat {
        min(
            size * 0.42,
            size * (0.02 + CGFloat(visibleLayerCount) * 0.09)
        )
    }
}

private struct TilePreview: View {
    let colors: [TileColor]
    let rotation: Int
    let presentation: BoardPresentation

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / 3.1, geometry.size.height / 2.2)
            ZStack {
                ForEach(Array(previewOffsets.enumerated()), id: \.offset) { index, offset in
                    BoardCell(
                        color: colors[index],
                        height: 1,
                        isPreview: false,
                        isValid: true,
                        size: unit,
                        presentation: presentation
                    )
                    .position(position(for: offset, unit: unit, in: geometry.size))
                }
            }
        }
    }

    private func position(
        for offset: BoardCoordinate,
        unit: CGFloat,
        in size: CGSize
    ) -> CGPoint {
        switch presentation {
        case .topDown:
            CGPoint(
                x: size.width / 2 + CGFloat(offset.x) * unit,
                y: size.height / 2 + CGFloat(offset.y) * unit
            )
        case .isometric:
            CGPoint(
                x: size.width / 2 + CGFloat(offset.x - offset.y) * unit / 2,
                y: size.height / 2 + CGFloat(offset.x + offset.y) * unit * 0.52 / 2
            )
        }
    }

    private var previewOffsets: [BoardCoordinate] {
        let base = [
            BoardCoordinate(x: 0, y: -1),
            BoardCoordinate(x: 0, y: 0),
            BoardCoordinate(x: 1, y: 0)
        ]
        return base.map { coordinate in
            (0..<rotation).reduce(coordinate) { value, _ in
                BoardCoordinate(x: -value.y, y: value.x)
            }
        }
    }
}

private struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    RulesIntroduction()
                    RuleSection(
                        number: "1",
                        title: "Mise en place",
                        text: "Chaque joueur reçoit un lot de 20 tuiles en L, le mélange et le place en pile, faces visibles. La tuile rectangulaire rouge et verte est placée entre les joueurs. Le premier joueur est tiré au sort."
                    )
                    RuleSection(
                        number: "2",
                        title: "Jouer une tuile",
                        text: "À tour de rôle, jouez obligatoirement la première tuile de votre pile. Vous pouvez l’orienter dans les quatre directions, puis choisir d’élargir la surface ou de l’empiler."
                    )
                    RuleSection(
                        number: "3",
                        title: "Élargir au niveau 1",
                        text: "La tuile doit être posée sur trois cases libres et être connectée à une tuile déjà placée par au moins un côté de carré. Les couleurs des côtés qui se touchent n’ont pas d’importance."
                    )
                    RuleSection(
                        number: "4",
                        title: "Empiler",
                        text: "Les trois carrés doivent reposer sans aucun vide sur des carrés situés au même niveau. La tuile doit couvrir au moins deux tuiles déjà jouées différentes. Un carré rouge et un carré vert ne peuvent jamais être superposés ; toutes les autres combinaisons sont autorisées. La hauteur n’est pas limitée."
                    )
                    RuleSection(
                        number: "5",
                        title: "Calculer une zone",
                        text: "Une zone regroupe les carrés visibles d’une même couleur connectés par leurs côtés, quels que soient leurs niveaux. Sa surface est son nombre de carrés visibles et sa hauteur est celle de son carré le plus haut."
                    )
                    RuleSection(
                        number: "6",
                        title: "Fin de partie et score",
                        text: "La partie se termine lorsque les 40 tuiles ont été posées. Le score d’une zone est sa surface multipliée par sa hauteur. Pour chaque joueur, seule sa zone ayant le meilleur score est retenue ; le score le plus élevé gagne."
                    )
                    OfficialVariantsSection()
                }
                .padding(24)
            }
            .navigationTitle("Règles du jeu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct RulesIntroduction: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("2 joueurs · dès 8 ans · 10 à 20 minutes", systemImage: "person.2.fill")
                .font(.headline)
                .foregroundStyle(GamePalette.gold)
            Text("Créez la meilleure surface à votre couleur en élargissant le territoire, en prenant de la hauteur et en recouvrant les zones adverses.")
                .font(.title3.weight(.semibold))
            Text("Contenu : 40 tuiles en L de trois carrés et une tuile de départ rectangulaire rouge et verte.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RuleSection: View {
    let number: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline.weight(.black))
                .frame(width: 34, height: 34)
                .background(GamePalette.gold, in: Circle())
                .foregroundStyle(.black)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OfficialVariantsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Variantes officielles", systemImage: "slider.horizontal.3")
                .font(.title3.weight(.bold))
            Text("Ordre préparé : chaque joueur organise librement sa pile avant la partie.")
            Text("Choix libre : toutes les tuiles sont visibles et le joueur choisit celle qu’il pose.")
            Text("Main de trois : chaque joueur choisit une tuile parmi trois, puis complète sa main avec la première tuile de sa pile.")
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

private struct BoardLayout {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
    let cellSize: CGFloat
    let origin: CGPoint
    let presentation: BoardPresentation

    var tileHeight: CGFloat {
        presentation == .isometric ? cellSize * 0.52 : cellSize
    }

    var layerRise: CGFloat {
        switch presentation {
        case .topDown:
            cellSize * 0.09
        case .isometric:
            cellSize * 0.09
        }
    }

    init(
        size: CGSize,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int),
        presentation: BoardPresentation
    ) {
        let padding = 2
        minX = bounds.minX - padding
        maxX = bounds.maxX + padding
        minY = bounds.minY - padding
        maxY = bounds.maxY + padding
        self.presentation = presentation

        let columns = CGFloat(maxX - minX + 1)
        let rows = CGFloat(maxY - minY + 1)

        switch presentation {
        case .topDown:
            cellSize = max(
                12,
                min((size.width - 32) / columns, (size.height - 40) / rows)
            )
            let boardWidth = columns * cellSize
            let boardHeight = rows * cellSize
            origin = CGPoint(
                x: (size.width - boardWidth) / 2 + cellSize / 2,
                y: (size.height - boardHeight) / 2 + cellSize / 2 - cellSize * 0.04
            )

        case .isometric:
            let diagonalCount = columns + rows
            let horizontalFit = (size.width - 36) * 2 / diagonalCount
            let verticalFit = (size.height - 52) * 2 / (diagonalCount * 0.52)
            cellSize = max(12, min(horizontalFit, verticalFit))

            let projectedWidth = diagonalCount * cellSize / 2
            let projectedHeight = diagonalCount * cellSize * 0.52 / 2
            let leftEdge = (size.width - projectedWidth) / 2
            let topEdge = (size.height - projectedHeight) / 2 - cellSize * 0.08
            origin = CGPoint(
                x: leftEdge + rows * cellSize / 2,
                y: topEdge + cellSize * 0.52 / 2
            )
        }
    }

    func center(of coordinate: BoardCoordinate, level: Int = 1) -> CGPoint {
        let column = CGFloat(coordinate.x - minX)
        let row = CGFloat(coordinate.y - minY)
        let elevation = CGFloat(max(level - 1, 0)) * layerRise

        switch presentation {
        case .topDown:
            return CGPoint(
                x: origin.x + column * cellSize - elevation * 0.28,
                y: origin.y + row * cellSize - elevation
            )
        case .isometric:
            return CGPoint(
                x: origin.x + (column - row) * cellSize / 2,
                y: origin.y + (column + row) * tileHeight / 2 - elevation
            )
        }
    }

    func coordinate(at point: CGPoint) -> BoardCoordinate {
        switch presentation {
        case .topDown:
            BoardCoordinate(
                x: Int(((point.x - origin.x) / cellSize).rounded()) + minX,
                y: Int(((point.y - origin.y) / cellSize).rounded()) + minY
            )

        case .isometric:
            BoardCoordinate(
                x: Int((
                    (2 * (point.x - origin.x) / cellSize +
                     2 * (point.y - origin.y) / tileHeight) / 2
                ).rounded()) + minX,
                y: Int((
                    (2 * (point.y - origin.y) / tileHeight -
                     2 * (point.x - origin.x) / cellSize) / 2
                ).rounded()) + minY
            )
        }
    }

    func tileCorners(of coordinate: BoardCoordinate, level: Int = 1) -> (
        top: CGPoint,
        right: CGPoint,
        bottom: CGPoint,
        left: CGPoint
    ) {
        let center = center(of: coordinate, level: level)

        switch presentation {
        case .topDown:
            return (
                CGPoint(x: center.x - cellSize / 2, y: center.y - cellSize / 2),
                CGPoint(x: center.x + cellSize / 2, y: center.y - cellSize / 2),
                CGPoint(x: center.x + cellSize / 2, y: center.y + cellSize / 2),
                CGPoint(x: center.x - cellSize / 2, y: center.y + cellSize / 2)
            )
        case .isometric:
            return (
                CGPoint(x: center.x, y: center.y - tileHeight / 2),
                CGPoint(x: center.x + cellSize / 2, y: center.y),
                CGPoint(x: center.x, y: center.y + tileHeight / 2),
                CGPoint(x: center.x - cellSize / 2, y: center.y)
            )
        }
    }
}

private enum GamePalette {
    static let backgroundTop = Color(red: 0.13, green: 0.15, blue: 0.16)
    static let backgroundBottom = Color(red: 0.035, green: 0.045, blue: 0.05)
    static let red = Color(red: 0.84, green: 0.055, blue: 0.025)
    static let green = Color(red: 0.17, green: 0.62, blue: 0.055)
    static let neutral = Color(red: 0.64, green: 0.64, blue: 0.59)
    static let gold = Color(red: 0.93, green: 0.7, blue: 0.23)

    static func color(for tileColor: TileColor) -> Color {
        switch tileColor {
        case .red: red
        case .green: green
        case .neutral: neutral
        }
    }
}

#Preview("iPad") {
    ContentView()
        .frame(width: 1180, height: 820)
}

#Preview("iPhone") {
    ContentView()
        .frame(width: 390, height: 844)
}
