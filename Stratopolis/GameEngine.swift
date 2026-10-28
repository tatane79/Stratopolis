import Foundation
import Observation

enum BoardPresentation: String, CaseIterable, Equatable, Sendable {
    case topDown
    case isometric

    var displayName: String {
        switch self {
        case .topDown: "Vue du dessus"
        case .isometric: "Vue isométrique"
        }
    }
}

enum TileColor: String, Codable, Equatable, Sendable {
    case red
    case green
    case neutral
}

enum Player: String, CaseIterable, Codable, Equatable, Sendable {
    case red
    case green

    var color: TileColor {
        self == .red ? .red : .green
    }

    var opponent: Player {
        self == .red ? .green : .red
    }

    var displayName: String {
        self == .red ? "Rouge" : "Vert"
    }
}

enum GameMode: Equatable, Sendable {
    case computer
    case localMultiplayer
    case online
}

struct BoardCoordinate: Hashable, Codable, Sendable {
    let x: Int
    let y: Int

    static func + (lhs: BoardCoordinate, rhs: BoardCoordinate) -> BoardCoordinate {
        BoardCoordinate(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    var neighbors: [BoardCoordinate] {
        [
            BoardCoordinate(x: x + 1, y: y),
            BoardCoordinate(x: x - 1, y: y),
            BoardCoordinate(x: x, y: y + 1),
            BoardCoordinate(x: x, y: y - 1)
        ]
    }
}

struct CellLayer: Codable, Equatable, Sendable {
    let tileID: UUID
    let color: TileColor
}

struct Tile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let colors: [TileColor]

    init(id: UUID = UUID(), colors: [TileColor]) {
        self.id = id
        self.colors = colors
    }
}

struct Placement: Codable, Equatable, Sendable {
    let tile: Tile
    let center: BoardCoordinate
    let rotation: Int

    var coordinates: [BoardCoordinate] {
        Self.offsets(for: rotation).map { center + $0 }
    }

    private static func offsets(for rotation: Int) -> [BoardCoordinate] {
        let base = [
            BoardCoordinate(x: 0, y: -1),
            BoardCoordinate(x: 0, y: 0),
            BoardCoordinate(x: 1, y: 0)
        ]
        return base.map { coordinate in
            (0..<(rotation % 4 + 4) % 4).reduce(coordinate) { value, _ in
                BoardCoordinate(x: -value.y, y: value.x)
            }
        }
    }
}

struct ZoneScore: Codable, Equatable, Sendable {
    let surface: Int
    let height: Int

    var total: Int {
        surface * height
    }

    static let zero = ZoneScore(surface: 0, height: 0)
}

struct ScoreImpact: Codable, Equatable, Sendable {
    let red: Int
    let green: Int
}

struct PlayedTurn: Codable, Equatable, Sendable {
    let placement: Placement
    let player: Player
}

struct TimeControl: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Category: String, Codable, Sendable {
        case rapid
        case standard
        case correspondence
    }

    let id: String
    let name: String
    let initialSeconds: TimeInterval
    let incrementSeconds: TimeInterval
    let category: Category

    static let presets: [TimeControl] = [
        TimeControl(id: "blitz-5", name: "5 min", initialSeconds: 300, incrementSeconds: 0, category: .rapid),
        TimeControl(id: "rapid-10-5", name: "10 min + 5 s", initialSeconds: 600, incrementSeconds: 5, category: .rapid),
        TimeControl(id: "rapid-15-10", name: "15 min + 10 s", initialSeconds: 900, incrementSeconds: 10, category: .rapid),
        TimeControl(id: "standard-30-15", name: "30 min + 15 s", initialSeconds: 1_800, incrementSeconds: 15, category: .standard),
        TimeControl(id: "standard-60-30", name: "60 min + 30 s", initialSeconds: 3_600, incrementSeconds: 30, category: .standard),
        TimeControl(id: "day-1", name: "1 jour", initialSeconds: 86_400, incrementSeconds: 0, category: .correspondence),
        TimeControl(id: "day-3", name: "3 jours", initialSeconds: 259_200, incrementSeconds: 0, category: .correspondence),
        TimeControl(id: "day-7", name: "7 jours", initialSeconds: 604_800, incrementSeconds: 0, category: .correspondence)
    ]

    static let recommended = presets[2]
}

struct GameClock: Codable, Equatable, Sendable {
    let control: TimeControl
    var redSeconds: TimeInterval
    var greenSeconds: TimeInterval
    var activeSince: Date?
    var timedOutPlayer: Player?

    init(control: TimeControl) {
        self.control = control
        redSeconds = control.initialSeconds
        greenSeconds = control.initialSeconds
    }

    func remaining(for player: Player) -> TimeInterval {
        player == .red ? redSeconds : greenSeconds
    }
}

struct AssistanceOptions: Codable, Equatable, Sendable {
    var scoreImpact = false
    var candidatePlacements = false
    var bestPlacement = false

    static let none = AssistanceOptions()

    var allowedOnline: AssistanceOptions {
        var options = self
        options.bestPlacement = false
        return options
    }
}

struct GameSnapshot: Codable, Equatable, Sendable {
    let board: [BoardCoordinate: [CellLayer]]
    let piles: [Player: [Tile]]
    let currentPlayer: Player
    let history: [PlayedTurn]
    let assistance: AssistanceOptions
    let clock: GameClock
}

private enum PlacementValidation: Equatable {
    case allowed
    case gameFinished
    case unevenSupport
    case disconnected
    case colorConflict
    case singleSupportingTile

    var message: String {
        switch self {
        case .allowed:
            "Position autorisée."
        case .gameFinished:
            "La partie est terminée."
        case .unevenSupport:
            "Pose interdite : les trois carrés doivent reposer au même niveau, sans vide."
        case .disconnected:
            "Pose interdite : au niveau 1, la tuile doit toucher une tuile existante par un côté."
        case .colorConflict:
            "Pose interdite : un carré rouge et un carré vert ne peuvent pas être superposés."
        case .singleSupportingTile:
            "Pose interdite : une tuile empilée doit reposer sur au moins deux tuiles différentes."
        }
    }
}

@MainActor
@Observable
final class GameModel {
    private(set) var board: [BoardCoordinate: [CellLayer]] = [:]
    private(set) var piles: [Player: [Tile]] = [:]
    private(set) var currentPlayer: Player = .red
    private(set) var history: [PlayedTurn] = []
    var previewCenter = BoardCoordinate(x: 0, y: 1)
    private(set) var hasPreviewPlacement = false
    var rotation = 0
    var showsRules = false
    var showsNewGameOptions = false
    var boardPresentation: BoardPresentation = .topDown
    var showsScoreImpact = false
    var showsCandidatePlacements = false
    var showsBestPlacement = false
    private(set) var message = "Touchez le plateau pour choisir une position."
    private(set) var isComputerThinking = false
    let computerPlayer: Player = .green
    private(set) var gameMode: GameMode = .computer
    private(set) var hasSelectedGameMode = false
    private(set) var onlineLocalPlayer: Player?
    private(set) var agreedAssistance = AssistanceOptions.none
    private(set) var clock = GameClock(control: .recommended)
    var selectedTimeControl = TimeControl.recommended
    var showsTimeControlSettings = false
    @ObservationIgnored var didCommitOnlineTurn: ((GameSnapshot) -> Void)?
    var aiLevel = 6 {
        didSet {
            aiLevel = min(10, max(1, aiLevel))
        }
    }
    @ObservationIgnored private var computerTurnTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    init() {
        newGame()
        showsNewGameOptions = true
    }

    var currentTile: Tile? {
        piles[currentPlayer]?.first
    }

    var isComputerTurn: Bool {
        hasSelectedGameMode && gameMode == .computer && currentPlayer == computerPlayer && !isFinished
    }

    var usesClock: Bool {
        gameMode != .computer
    }

    var canUndo: Bool {
        guard gameMode != .online else { return false }
        return gameMode == .localMultiplayer ? !history.isEmpty : history.contains { $0.player != computerPlayer }
    }

    var isLocalPlayersTurn: Bool {
        gameMode != .online || currentPlayer == onlineLocalPlayer
    }

    var snapshot: GameSnapshot {
        GameSnapshot(
            board: board,
            piles: piles,
            currentPlayer: currentPlayer,
            history: history,
            assistance: agreedAssistance,
            clock: clock
        )
    }

    var redScore: ZoneScore {
        bestZone(for: .red)
    }

    var greenScore: ZoneScore {
        bestZone(for: .green)
    }

    var isFinished: Bool {
        clock.timedOutPlayer != nil || piles.values.allSatisfy(\.isEmpty)
    }

    var previewPlacement: Placement? {
        guard hasPreviewPlacement, let currentTile else { return nil }
        return Placement(tile: currentTile, center: previewCenter, rotation: rotation)
    }

    var previewDisplayLevel: Int {
        guard let previewPlacement else { return 1 }
        return (previewPlacement.coordinates.map(height(at:)).max() ?? 0) + 1
    }

    var canPlacePreview: Bool {
        guard let previewPlacement else { return false }
        return validation(of: previewPlacement) == .allowed
    }

    var previewScoreImpact: ScoreImpact? {
        guard showsScoreImpact,
              let previewPlacement,
              validation(of: previewPlacement) == .allowed else {
            return nil
        }
        let resultingBoard = Self.board(after: previewPlacement, on: board)
        return ScoreImpact(
            red: Self.bestZone(for: .red, on: resultingBoard).total - redScore.total,
            green: Self.bestZone(for: .green, on: resultingBoard).total - greenScore.total
        )
    }

    var assistedCandidatePlacements: [Placement] {
        guard showsCandidatePlacements, !isComputerTurn, let currentTile else { return [] }
        return legalPlacements(for: currentTile, on: board).filter { placement in
            placement.coordinates.allSatisfy { height(at: $0) > 0 }
        }
    }

    var assistedBestPlacement: Placement? {
        guard showsBestPlacement, !isComputerTurn, let currentTile else { return nil }
        let candidates = legalPlacements(for: currentTile, on: board)
        let opponentTile = piles[currentPlayer.opponent]?.first
        return candidates
            .map { placement in
                (
                    placement,
                    maximumAIEvaluation(
                        of: placement,
                        for: currentPlayer,
                        opponentTile: opponentTile
                    )
                )
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    var occupiedBounds: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let coordinates = Array(board.keys)
        return (
            coordinates.map(\.x).min() ?? -2,
            coordinates.map(\.x).max() ?? 2,
            coordinates.map(\.y).min() ?? -2,
            coordinates.map(\.y).max() ?? 2
        )
    }

    func newGame(mode: GameMode? = nil) {
        computerTurnTask?.cancel()
        if let mode {
            gameMode = mode
            hasSelectedGameMode = true
        }
        let startingTileID = UUID()
        board = [
            BoardCoordinate(x: 0, y: 0): [CellLayer(tileID: startingTileID, color: .green)],
            BoardCoordinate(x: 1, y: 0): [CellLayer(tileID: startingTileID, color: .red)]
        ]
        piles = [
            .red: Self.makePile(for: .red).shuffled(),
            .green: Self.makePile(for: .green).shuffled()
        ]
        currentPlayer = Bool.random() ? .red : .green
        history = []
        clock = GameClock(control: selectedTimeControl)
        clock.activeSince = hasSelectedGameMode && usesClock ? .now : nil
        hasPreviewPlacement = false
        rotation = 0
        previewCenter = BoardCoordinate(x: 0, y: 1)
        if !hasSelectedGameMode {
            message = "Choisissez un mode de jeu."
        } else {
            message = gameMode == .computer && currentPlayer == computerPlayer
                ? "L’ordinateur commence."
                : "\(currentPlayer.displayName) commence."
        }
        scheduleComputerTurnIfNeeded()
        scheduleClock()
    }

    func configureOnlineGame(
        localPlayer: Player,
        assistance: AssistanceOptions,
        timeControl: TimeControl,
        initialSnapshot: GameSnapshot? = nil
    ) {
        let onlineAssistance = assistance.allowedOnline
        gameMode = .online
        hasSelectedGameMode = true
        onlineLocalPlayer = localPlayer
        agreedAssistance = onlineAssistance
        selectedTimeControl = timeControl
        showsScoreImpact = onlineAssistance.scoreImpact
        showsCandidatePlacements = onlineAssistance.candidatePlacements
        showsBestPlacement = false

        if let initialSnapshot {
            applyOnlineSnapshot(initialSnapshot)
        } else {
            newGame(mode: .online)
        }
        message = currentPlayer == localPlayer ? "À votre tour." : "Au tour de votre adversaire."
    }

    func applyOnlineSnapshot(_ snapshot: GameSnapshot) {
        guard gameMode == .online else { return }
        board = snapshot.board
        piles = snapshot.piles
        currentPlayer = snapshot.currentPlayer
        history = snapshot.history
        let onlineAssistance = snapshot.assistance.allowedOnline
        agreedAssistance = onlineAssistance
        clock = snapshot.clock
        selectedTimeControl = snapshot.clock.control
        showsScoreImpact = onlineAssistance.scoreImpact
        showsCandidatePlacements = onlineAssistance.candidatePlacements
        showsBestPlacement = false
        hasPreviewPlacement = false
        rotation = 0
        message = isFinished
            ? finalScoreMessage
            : (isLocalPlayersTurn ? "À votre tour." : "Au tour de votre adversaire.")
        scheduleClock()
    }

    func select(_ coordinate: BoardCoordinate) {
        guard hasSelectedGameMode, !isFinished, !isComputerTurn, isLocalPlayersTurn else { return }
        previewCenter = coordinate
        hasPreviewPlacement = true
        message = validationMessage
    }

    func rotate(by quarterTurns: Int = 1) {
        guard hasSelectedGameMode, !isFinished, !isComputerTurn, isLocalPlayersTurn else { return }
        rotation = (rotation + quarterTurns % 4 + 4) % 4
        message = validationMessage
    }

    func place() {
        guard hasSelectedGameMode, !isComputerTurn, isLocalPlayersTurn else { return }
        guard let placement = previewPlacement else {
            message = PlacementValidation.gameFinished.message
            return
        }
        let validation = validation(of: placement)
        guard validation == .allowed else {
            message = validation.message
            return
        }

        commit(placement)
        scheduleComputerTurnIfNeeded()
    }

    func undo() {
        guard canUndo else { return }
        computerTurnTask?.cancel()
        isComputerThinking = false
        let turnCount = gameMode == .computer && history.last?.player == computerPlayer ? 2 : 1
        var lastUndoneTurn: PlayedTurn?

        for _ in 0..<turnCount {
            guard let turn = history.popLast() else { break }
            lastUndoneTurn = turn
            for coordinate in turn.placement.coordinates {
                board[coordinate]?.removeLast()
                if board[coordinate]?.isEmpty == true {
                    board[coordinate] = nil
                }
            }
            piles[turn.player, default: []].insert(turn.placement.tile, at: 0)
        }

        guard let turn = lastUndoneTurn else { return }
        currentPlayer = turn.player
        previewCenter = turn.placement.center
        hasPreviewPlacement = true
        rotation = turn.placement.rotation
        message = "Dernier coup annulé."
    }

    func playComputerTurnIfNeeded() {
        scheduleComputerTurnIfNeeded()
    }

    func height(at coordinate: BoardCoordinate) -> Int {
        board[coordinate]?.count ?? 0
    }

    func topColor(at coordinate: BoardCoordinate) -> TileColor? {
        board[coordinate]?.last?.color
    }

    func isPreviewCell(_ coordinate: BoardCoordinate) -> Int? {
        previewPlacement?.coordinates.firstIndex(of: coordinate)
    }

    private var validationMessage: String {
        guard let previewPlacement else {
            return isFinished
                ? PlacementValidation.gameFinished.message
                : "Faites glisser la tuile sur la grille pour choisir sa position."
        }
        return validation(of: previewPlacement).message
    }

    private func validation(of placement: Placement) -> PlacementValidation {
        guard !isFinished else { return .gameFinished }

        let coordinates = placement.coordinates
        let heights = coordinates.map(height(at:))
        guard Set(heights).count == 1 else { return .unevenSupport }

        if heights[0] == 0 {
            let isConnected = coordinates.contains { coordinate in
                coordinate.neighbors.contains { height(at: $0) > 0 }
            }
            return isConnected ? .allowed : .disconnected
        }

        let hasColorConflict = coordinates.enumerated().contains { index, coordinate in
            guard let underneath = topColor(at: coordinate) else { return false }
            let above = placement.tile.colors[index]
            return (above == .red && underneath == .green) ||
                (above == .green && underneath == .red)
        }
        guard !hasColorConflict else { return .colorConflict }

        let supportingTiles = Set(coordinates.compactMap { board[$0]?.last?.tileID })
        guard supportingTiles.count >= 2 else { return .singleSupportingTile }

        return .allowed
    }

    private func bestZone(for player: Player) -> ZoneScore {
        Self.bestZone(for: player, on: board)
    }

    private func commit(_ placement: Placement) {
        settleClock()
        guard clock.timedOutPlayer == nil else { return }
        let movingPlayer = currentPlayer
        board = Self.board(after: placement, on: board)
        history.append(PlayedTurn(placement: placement, player: currentPlayer))
        piles[currentPlayer]?.removeFirst()
        addIncrement(to: movingPlayer)

        if isFinished {
            clock.activeSince = nil
            message = finalScoreMessage
        } else {
            currentPlayer = currentPlayer.opponent
            clock.activeSince = usesClock ? .now : nil
            hasPreviewPlacement = false
            rotation = 0
            message = isComputerTurn
                ? "L’ordinateur réfléchit…"
                : (gameMode == .computer ? "À votre tour." : "Au tour de \(currentPlayer.displayName).")
        }
        if gameMode == .online {
            didCommitOnlineTurn?(snapshot)
        }
    }

    private var finalScoreMessage: String {
        if let timedOutPlayer = clock.timedOutPlayer {
            return "\(timedOutPlayer.opponent.displayName) gagne au temps."
        }
        let red = redScore.total
        let green = greenScore.total
        return red == green
            ? "Égalité : \(red) points."
            : "\(red > green ? "Rouge" : "Vert") remporte la partie !"
    }

    private func scheduleClock() {
        clockTask?.cancel()
        guard usesClock, hasSelectedGameMode, !isFinished else { return }
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                settleClock()
            }
        }
    }

    private func settleClock(at now: Date = .now) {
        guard usesClock, !isFinished, let activeSince = clock.activeSince else { return }
        let elapsed = max(0, now.timeIntervalSince(activeSince))
        guard elapsed > 0 else { return }

        if currentPlayer == .red {
            clock.redSeconds = max(0, clock.redSeconds - elapsed)
            if clock.redSeconds == 0 {
                clock.timedOutPlayer = .red
            }
        } else {
            clock.greenSeconds = max(0, clock.greenSeconds - elapsed)
            if clock.greenSeconds == 0 {
                clock.timedOutPlayer = .green
            }
        }
        clock.activeSince = clock.timedOutPlayer == nil ? now : nil

        if clock.timedOutPlayer != nil {
            message = finalScoreMessage
            clockTask?.cancel()
            if gameMode == .online {
                didCommitOnlineTurn?(snapshot)
            }
        }
    }

    private func addIncrement(to player: Player) {
        guard usesClock, clock.control.incrementSeconds > 0 else { return }
        if player == .red {
            clock.redSeconds += clock.control.incrementSeconds
        } else {
            clock.greenSeconds += clock.control.incrementSeconds
        }
    }

    private func scheduleComputerTurnIfNeeded() {
        computerTurnTask?.cancel()
        guard isComputerTurn else { return }
        isComputerThinking = true
        message = "L’ordinateur réfléchit…"

        computerTurnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, isComputerTurn,
                  let tile = currentTile,
                  let placement = bestComputerPlacement(for: tile) else {
                self?.isComputerThinking = false
                return
            }
            previewCenter = placement.center
            rotation = placement.rotation
            hasPreviewPlacement = true
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, isComputerTurn else { return }
            commit(placement)
            isComputerThinking = false
        }
    }

    private func bestComputerPlacement(for tile: Tile) -> Placement? {
        let candidates = legalPlacements(for: tile, on: board)
        guard !candidates.isEmpty else { return nil }
        if aiLevel == 1 {
            return candidates.randomElement()
        }
        let opponentTile = piles[computerPlayer.opponent]?.first
        let ranked = candidates
            .map { placement in
                (placement, computerEvaluation(of: placement, opponentTile: opponentTile))
            }
            .sorted { $0.1 > $1.1 }
        let choicePool = aiLevel <= 2 ? 8 : aiLevel <= 4 ? 4 : aiLevel <= 6 ? 3 : aiLevel <= 8 ? 2 : 1
        return ranked.prefix(choicePool).randomElement()?.0
    }

    private func computerEvaluation(of placement: Placement, opponentTile: Tile?) -> Int {
        let resultingBoard = Self.board(after: placement, on: board)
        let immediate = Self.scoreDifference(for: computerPlayer, on: resultingBoard)
        let ownScore = Self.bestZone(for: computerPlayer, on: resultingBoard).total
        let level = placement.coordinates.map { resultingBoard[$0]?.count ?? 0 }.max() ?? 1
        let ownCells = placement.tile.colors.filter { $0 == computerPlayer.color }.count
        let positionalBonus = level * 3 + ownCells

        if aiLevel == 2 { return ownScore * 100 + positionalBonus }
        if aiLevel == 3 { return immediate * 100 + ownScore }
        if aiLevel == 4 { return immediate * 100 + ownScore * 3 + positionalBonus }
        guard let opponentTile else { return immediate * 100 + positionalBonus }
        let replies = legalPlacements(for: opponentTile, on: resultingBoard)
        let replyBudget = [0, 0, 0, 0, 2, 4, 8, 16, 32, Int.max][aiLevel - 1]
        let consideredReplies = replyBudget == Int.max
            ? replies
            : Array(replies.shuffled().prefix(replyBudget))
        let opponentBest = consideredReplies.map { reply in
            Self.scoreDifference(
                for: computerPlayer,
                on: Self.board(after: reply, on: resultingBoard)
            )
        }.min() ?? immediate
        return opponentBest * 100 + immediate * 10 + positionalBonus
    }

    private func maximumAIEvaluation(
        of placement: Placement,
        for player: Player,
        opponentTile: Tile?
    ) -> Int {
        let resultingBoard = Self.board(after: placement, on: board)
        let immediate = Self.scoreDifference(for: player, on: resultingBoard)
        let level = placement.coordinates.map { resultingBoard[$0]?.count ?? 0 }.max() ?? 1
        let ownCells = placement.tile.colors.filter { $0 == player.color }.count
        let positionalBonus = level * 3 + ownCells
        guard let opponentTile else { return immediate * 100 + positionalBonus }

        let replies = legalPlacements(for: opponentTile, on: resultingBoard)
        let opponentBest = replies.map { reply in
            Self.scoreDifference(
                for: player,
                on: Self.board(after: reply, on: resultingBoard)
            )
        }.min() ?? immediate
        return opponentBest * 100 + immediate * 10 + positionalBonus
    }

    private func legalPlacements(
        for tile: Tile,
        on candidateBoard: [BoardCoordinate: [CellLayer]]
    ) -> [Placement] {
        let coordinates = Array(candidateBoard.keys)
        let minX = (coordinates.map(\.x).min() ?? 0) - 2
        let maxX = (coordinates.map(\.x).max() ?? 0) + 2
        let minY = (coordinates.map(\.y).min() ?? 0) - 2
        let maxY = (coordinates.map(\.y).max() ?? 0) + 2

        return (minX...maxX).flatMap { x in
            (minY...maxY).flatMap { y in
                (0..<4).compactMap { rotation in
                    let placement = Placement(
                        tile: tile,
                        center: BoardCoordinate(x: x, y: y),
                        rotation: rotation
                    )
                    return Self.isAllowed(placement, on: candidateBoard) ? placement : nil
                }
            }
        }
    }

    private static func board(
        after placement: Placement,
        on source: [BoardCoordinate: [CellLayer]]
    ) -> [BoardCoordinate: [CellLayer]] {
        var result = source
        for (index, coordinate) in placement.coordinates.enumerated() {
            result[coordinate, default: []].append(
                CellLayer(tileID: placement.tile.id, color: placement.tile.colors[index])
            )
        }
        return result
    }

    private static func isAllowed(
        _ placement: Placement,
        on candidateBoard: [BoardCoordinate: [CellLayer]]
    ) -> Bool {
        let coordinates = placement.coordinates
        let heights = coordinates.map { candidateBoard[$0]?.count ?? 0 }
        guard Set(heights).count == 1 else { return false }
        if heights[0] == 0 {
            return coordinates.contains { coordinate in
                coordinate.neighbors.contains { candidateBoard[$0]?.isEmpty == false }
            }
        }
        let conflict = coordinates.enumerated().contains { index, coordinate in
            guard let underneath = candidateBoard[coordinate]?.last?.color else { return false }
            let above = placement.tile.colors[index]
            return (above == .red && underneath == .green) ||
                (above == .green && underneath == .red)
        }
        guard !conflict else { return false }
        return Set(coordinates.compactMap { candidateBoard[$0]?.last?.tileID }).count >= 2
    }

    private static func scoreDifference(
        for player: Player,
        on candidateBoard: [BoardCoordinate: [CellLayer]]
    ) -> Int {
        bestZone(for: player, on: candidateBoard).total -
            bestZone(for: player.opponent, on: candidateBoard).total
    }

    private static func bestZone(
        for player: Player,
        on candidateBoard: [BoardCoordinate: [CellLayer]]
    ) -> ZoneScore {
        var remaining = Set(candidateBoard.compactMap { coordinate, layers in
            layers.last?.color == player.color ? coordinate : nil
        })
        var best = ZoneScore.zero

        while let start = remaining.first {
            var frontier = [start]
            var zone: Set<BoardCoordinate> = []
            remaining.remove(start)

            while let coordinate = frontier.popLast() {
                zone.insert(coordinate)
                for neighbor in coordinate.neighbors where remaining.remove(neighbor) != nil {
                    frontier.append(neighbor)
                }
            }

            let height = zone.map { candidateBoard[$0]?.count ?? 0 }.max() ?? 0
            let candidate = ZoneScore(surface: zone.count, height: height)
            if candidate.total > best.total {
                best = candidate
            }
        }
        return best
    }

    private static func makePile(for player: Player) -> [Tile] {
        let own = player.color
        let opponent: TileColor = player == .red ? .green : .red
        let patterns: [[TileColor]] = [
            [own, own, own],
            [own, own, opponent],
            [own, opponent, own],
            [opponent, own, own],
            [own, own, .neutral],
            [own, .neutral, own],
            [.neutral, own, own],
            [.neutral, .neutral, own],
            [own, .neutral, .neutral],
            [.neutral, own, .neutral]
        ]
        return (patterns + patterns).map { Tile(colors: $0) }
    }
}
