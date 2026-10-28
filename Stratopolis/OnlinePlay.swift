import CloudKit
import Foundation
import GameKit
import Observation

struct PlayerRating: Codable, Equatable, Sendable {
    var value: Int = 1_200
    var gamesPlayed: Int = 0

    mutating func apply(score: Double, opponentRating: Int) {
        let expected = 1 / (1 + pow(10, Double(opponentRating - value) / 400))
        let factor = gamesPlayed < 30 ? 32.0 : 20.0
        value = max(100, Int((Double(value) + factor * (score - expected)).rounded()))
        gamesPlayed += 1
    }
}

struct ArchivedGame: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let playedAt: Date
    let redName: String
    let greenName: String
    let redRating: Int
    let greenRating: Int
    let redScore: Int
    let greenScore: Int
    let assistance: AssistanceOptions
    let snapshot: GameSnapshot
}

private enum MatchMessage: Codable, Sendable {
    case proposal(AssistanceOptions, TimeControl)
    case start(GameSnapshot, hostPlayerID: String)
    case state(GameSnapshot)
}

@MainActor
@Observable
final class OnlineGameCoordinator: NSObject {
    enum Phase: Equatable {
        case signedOut
        case ready
        case searching
        case negotiating
        case playing
        case failed(String)
    }

    private(set) var phase: Phase = .signedOut
    private(set) var displayName = "Game Center"
    private(set) var opponentName = ""
    private(set) var rating = PlayerRating()
    private(set) var opponentRating = 1_200
    private(set) var remoteProposal: AssistanceOptions?
    private(set) var remoteTimeControl: TimeControl?
    private(set) var archives: [ArchivedGame] = []
    var ratingRange = 200
    var proposal = AssistanceOptions.none
    var timeControl = TimeControl.recommended

    @ObservationIgnored private var match: GKMatch?
    @ObservationIgnored private weak var game: GameModel?
    @ObservationIgnored private let archiveStore = GameArchiveStore()
    @ObservationIgnored private var didArchiveCurrentMatch = false

    override init() {
        if let data = UserDefaults.standard.data(forKey: "stratopolis.rating"),
           let saved = try? JSONDecoder().decode(PlayerRating.self, from: data) {
            rating = saved
        }
        super.init()
    }

    func connect(to game: GameModel) {
        self.game = game
        game.didCommitOnlineTurn = { [weak self] snapshot in
            self?.send(.state(snapshot))
            self?.archiveAndRateIfNeeded(snapshot)
        }
        authenticate()
        Task { await loadArchives() }
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.phase = .failed(error.localizedDescription)
                } else if GKLocalPlayer.local.isAuthenticated {
                    self.displayName = GKLocalPlayer.local.displayName
                    self.phase = .ready
                } else {
                    self.phase = .signedOut
                }
            }
        }
    }

    func findOpponent() {
        guard GKLocalPlayer.local.isAuthenticated else {
            authenticate()
            return
        }

        phase = .searching
        remoteProposal = nil
        didArchiveCurrentMatch = false

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.queueName = "stratopolis.elo"
        request.properties = [
            "rating": rating.value,
            "minimumRating": max(100, rating.value - ratingRange),
            "maximumRating": rating.value + ratingRange
        ]

        Task {
            do {
                let foundMatch = try await GKMatchmaker.shared().findMatch(for: request)
                foundMatch.delegate = self
                match = foundMatch
                phase = .negotiating
                updateOpponent(from: foundMatch)
                send(.proposal(proposal.allowedOnline, timeControl))
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancelSearch() {
        GKMatchmaker.shared().cancel()
        match?.disconnect()
        match = nil
        phase = .ready
    }

    func submitProposal() {
        guard phase == .negotiating else { return }
        send(.proposal(proposal.allowedOnline, timeControl))
        beginIfAgreed()
    }

    func loadArchive(_ archive: ArchivedGame) {
        game?.configureOnlineGame(
            localPlayer: .red,
            assistance: archive.assistance,
            timeControl: archive.snapshot.clock.control,
            initialSnapshot: archive.snapshot
        )
    }

    private func updateOpponent(from match: GKMatch) {
        guard let opponent = match.players.first else { return }
        opponentName = opponent.displayName
        if let value = match.playerProperties?[opponent]?["rating"] as? Int {
            opponentRating = value
        }
    }

    private func beginIfAgreed() {
        let onlineProposal = proposal.allowedOnline
        guard remoteProposal == onlineProposal,
              remoteTimeControl == timeControl,
              let match,
              let game,
              let opponent = match.players.first else { return }

        let localID = GKLocalPlayer.local.gamePlayerID
        let hostID = min(localID, opponent.gamePlayerID)
        let localColor: Player = localID == hostID ? .red : .green

        if localID == hostID {
            game.configureOnlineGame(
                localPlayer: localColor,
                assistance: onlineProposal,
                timeControl: timeControl
            )
            send(.start(game.snapshot, hostPlayerID: hostID))
            phase = .playing
        }
    }

    private func receive(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(MatchMessage.self, from: data)
            switch message {
            case .proposal(let options, let control):
                remoteProposal = options.allowedOnline
                remoteTimeControl = control
                beginIfAgreed()
            case .start(let snapshot, let hostPlayerID):
                let localColor: Player = GKLocalPlayer.local.gamePlayerID == hostPlayerID ? .red : .green
                game?.configureOnlineGame(
                    localPlayer: localColor,
                    assistance: snapshot.assistance,
                    timeControl: snapshot.clock.control,
                    initialSnapshot: snapshot
                )
                phase = .playing
            case .state(let snapshot):
                game?.applyOnlineSnapshot(snapshot)
                archiveAndRateIfNeeded(snapshot)
            }
        } catch {
            phase = .failed("Données de partie invalides.")
        }
    }

    private func send(_ message: MatchMessage) {
        guard let match, let data = try? JSONEncoder().encode(message) else { return }
        do {
            try match.sendData(toAllPlayers: data, with: .reliable)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func archiveAndRateIfNeeded(_ snapshot: GameSnapshot) {
        guard !didArchiveCurrentMatch,
              snapshot.clock.timedOutPlayer != nil || snapshot.piles.values.allSatisfy(\.isEmpty) else { return }
        didArchiveCurrentMatch = true

        let redScore = score(for: .red, board: snapshot.board)
        let greenScore = score(for: .green, board: snapshot.board)
        let localIsRed = game?.onlineLocalPlayer == .red
        let result: Double
        if let timedOut = snapshot.clock.timedOutPlayer {
            result = (timedOut == .red) == localIsRed ? 0 : 1
        } else {
            result = redScore == greenScore ? 0.5 : ((redScore > greenScore) == localIsRed ? 1 : 0)
        }
        let oldRating = rating.value
        rating.apply(score: result, opponentRating: opponentRating)
        if let data = try? JSONEncoder().encode(rating) {
            UserDefaults.standard.set(data, forKey: "stratopolis.rating")
        }

        let archive = ArchivedGame(
            id: UUID(),
            playedAt: .now,
            redName: localIsRed ? displayName : opponentName,
            greenName: localIsRed ? opponentName : displayName,
            redRating: localIsRed ? oldRating : opponentRating,
            greenRating: localIsRed ? opponentRating : oldRating,
            redScore: redScore,
            greenScore: greenScore,
            assistance: snapshot.assistance,
            snapshot: snapshot
        )
        archives.insert(archive, at: 0)
        Task { try? await archiveStore.save(archive) }
    }

    private func loadArchives() async {
        archives = (try? await archiveStore.fetch()) ?? []
    }

    private func score(
        for player: Player,
        board: [BoardCoordinate: [CellLayer]]
    ) -> Int {
        var remaining = Set(board.compactMap { coordinate, layers in
            layers.last?.color == player.color ? coordinate : nil
        })
        var best = 0
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
            let height = zone.map { board[$0]?.count ?? 0 }.max() ?? 0
            best = max(best, zone.count * height)
        }
        return best
    }
}

extension OnlineGameCoordinator: GKMatchDelegate {
    nonisolated func match(
        _ match: GKMatch,
        didReceive data: Data,
        fromRemotePlayer player: GKPlayer
    ) {
        Task { @MainActor [weak self] in
            self?.receive(data)
        }
    }

    nonisolated func match(
        _ match: GKMatch,
        player: GKPlayer,
        didChange state: GKPlayerConnectionState
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if state == .connected {
                updateOpponent(from: match)
                phase = .negotiating
                send(.proposal(proposal, timeControl))
            } else if state == .disconnected {
                phase = .failed("L’adversaire s’est déconnecté.")
            }
        }
    }

    nonisolated func match(
        _ match: GKMatch,
        didFailWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.phase = .failed(error?.localizedDescription ?? "La connexion a été interrompue.")
        }
    }
}

@MainActor
private final class GameArchiveStore {
    private let database = CKContainer.default().privateCloudDatabase

    func save(_ archive: ArchivedGame) async throws {
        let record = CKRecord(recordType: "StratopolisGame", recordID: CKRecord.ID(recordName: archive.id.uuidString))
        record["playedAt"] = archive.playedAt
        record["payload"] = try JSONEncoder().encode(archive)
        _ = try await database.save(record)
    }

    func fetch() async throws -> [ArchivedGame] {
        let query = CKQuery(recordType: "StratopolisGame", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "playedAt", ascending: false)]
        let result = try await database.records(matching: query, resultsLimit: 100)
        return result.matchResults.compactMap { _, value in
            guard case .success(let record) = value,
                  let data = record["payload"] as? Data else { return nil }
            return try? JSONDecoder().decode(ArchivedGame.self, from: data)
        }
    }
}
