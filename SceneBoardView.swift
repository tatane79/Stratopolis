import SwiftUI
import SceneKit
import UIKit

private enum TileVisualFactory {
    static let cellSize: Float = 1
    static let cellGap: Float = -0.025
    static let tileThickness: Float = 0.18
    static let colorInset: Float = 0.105

    static func makeCell(color: TileColor, opacity: CGFloat, isValid: Bool) -> SCNNode {
        let root = SCNNode()
        let baseSide = CGFloat(cellSize - cellGap)
        let baseGeometry = SCNBox(
            width: baseSide,
            height: CGFloat(tileThickness),
            length: baseSide,
            chamferRadius: 0.055
        )
        let glossyBlack = material(
            color: UIColor(white: 0.012, alpha: opacity),
            roughness: 0.1
        )
        glossyBlack.metalness.contents = 0.18
        glossyBlack.specular.contents = UIColor(white: 1, alpha: 0.9)
        glossyBlack.transparency = opacity
        if opacity < 1 {
            glossyBlack.emission.contents = isValid
                ? UIColor(red: 0.04, green: 0.20, blue: 0.07, alpha: 0.16)
                : UIColor(red: 0.42, green: 0.025, blue: 0.01, alpha: 0.25)
        }
        baseGeometry.materials = [glossyBlack]

        let baseNode = SCNNode(geometry: baseGeometry)
        baseNode.name = "selectable-tile-part"
        baseNode.castsShadow = true
        root.addChildNode(baseNode)

        if color != .neutral {
            let inset = CGFloat(colorInset)
            let colorGeometry = SCNBox(
                width: baseSide - inset * 2,
                height: 0.026,
                length: baseSide - inset * 2,
                chamferRadius: 0.055
            )
            let colorMaterial = material(
                color: uiColor(for: color).withAlphaComponent(opacity),
                roughness: 0.2
            )
            colorMaterial.metalness.contents = 0.04
            colorMaterial.specular.contents = UIColor(white: 1, alpha: 0.72)
            colorMaterial.transparency = opacity
            if opacity < 1 {
                colorMaterial.emission.contents = isValid
                    ? UIColor(red: 0.04, green: 0.25, blue: 0.07, alpha: 0.16)
                    : UIColor(red: 0.65, green: 0.025, blue: 0.01, alpha: 0.28)
            }
            colorGeometry.materials = [colorMaterial]

            let colorNode = SCNNode(geometry: colorGeometry)
            colorNode.name = "selectable-tile-part"
            colorNode.position.y = tileThickness / 2 + 0.012
            colorNode.castsShadow = false
            root.addChildNode(colorNode)
        }
        return root
    }

    static func material(color: UIColor, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0
        material.isDoubleSided = true
        return material
    }

    static func uiColor(for color: TileColor) -> UIColor {
        switch color {
        case .red:
            UIColor(red: 0.84, green: 0.055, blue: 0.025, alpha: 1)
        case .green:
            UIColor(red: 0.17, green: 0.62, blue: 0.055, alpha: 1)
        case .neutral:
            UIColor(white: 0.012, alpha: 1)
        }
    }
}

struct TilePiece3DPreview: UIViewRepresentable {
    let colors: [TileColor]
    let rotation: Int

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 2.15
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 5, 0)
        cameraNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode

        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 650
        ambient.color = UIColor(white: 0.72, alpha: 1)
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let keyNode = SCNNode()
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        let root = SCNNode()
        root.name = "tile-preview-root"
        scene.rootNode.addChildNode(root)
        updatePiece(in: root)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let root = view.scene?.rootNode.childNode(
            withName: "tile-preview-root",
            recursively: false
        ) else { return }
        updatePiece(in: root)
    }

    private func updatePiece(in root: SCNNode) {
        root.childNodes.forEach { $0.removeFromParentNode() }
        let baseOffsets = [(0, -1), (0, 0), (1, 0)]
        let normalizedRotation = ((rotation % 4) + 4) % 4
        let offsets = baseOffsets.map { offset in
            (0..<normalizedRotation).reduce(offset) { value, _ in (-value.1, value.0) }
        }
        let centerX = Float(offsets.map(\.0).reduce(0, +)) / Float(offsets.count)
        let centerZ = Float(offsets.map(\.1).reduce(0, +)) / Float(offsets.count)

        for (index, offset) in offsets.enumerated() where colors.indices.contains(index) {
            let node = TileVisualFactory.makeCell(
                color: colors[index],
                opacity: 1,
                isValid: true
            )
            node.position = SCNVector3(
                Float(offset.0) - centerX,
                TileVisualFactory.tileThickness / 2,
                Float(offset.1) - centerZ
            )
            root.addChildNode(node)
        }
    }
}

struct SceneBoardView: UIViewRepresentable {
    let game: GameModel

    func makeCoordinator() -> Coordinator {
        Coordinator(game: game)
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.update(game: game)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private enum Metrics {
            static let cellSize = TileVisualFactory.cellSize
            static let cellGap = TileVisualFactory.cellGap
            static let tileThickness = TileVisualFactory.tileThickness
            static let colorInset = TileVisualFactory.colorInset
            static let boardPadding = 4
        }

        private struct PlacedTileKey: Hashable {
            let tileID: UUID
            let level: Int
        }

        private var game: GameModel
        private let scene = SCNScene()
        private let boardRoot = SCNNode()
        private let cameraOrbit = SCNNode()
        private let yawNode = SCNNode()
        private let pitchNode = SCNNode()
        private let cameraNode = SCNNode()
        private let previewRoot = SCNNode()
        private weak var sceneView: SCNView?
        private var previewVisualOffset = SCNVector3Zero
        private var dragStartBoardPoint = SCNVector3Zero
        private var dragStartCenter = SCNVector3Zero
        private var yaw: Float = -.pi / 4
        private var pitch: Float = .pi / 4.4
        private var cameraDistance: Float = 11
        private var initialPinchDistance: Float = 11
        private var isPreviewRotating = false

        init(game: GameModel) {
            self.game = game
            super.init()
            configureScene()
        }

        func makeView() -> SCNView {
            let view = SCNView(frame: .zero)
            sceneView = view
            view.scene = scene
            view.backgroundColor = UIColor(
                red: 0.035,
                green: 0.045,
                blue: 0.05,
                alpha: 1
            )
            view.antialiasingMode = .multisampling4X
            view.rendersContinuously = false
            view.preferredFramesPerSecond = 60
            view.autoenablesDefaultLighting = false
            view.pointOfView = cameraNode

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.numberOfTouchesRequired = 1
            tap.delegate = self

            let placementPan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePlacementPan(_:))
            )
            placementPan.minimumNumberOfTouches = 1
            placementPan.maximumNumberOfTouches = 1
            placementPan.delegate = self
            tap.require(toFail: placementPan)

            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.minimumNumberOfTouches = 2
            orbit.maximumNumberOfTouches = 2
            orbit.delegate = self

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self

            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(placementPan)
            view.addGestureRecognizer(orbit)
            view.addGestureRecognizer(pinch)

            rebuildBoard()
            return view
        }

        func update(game: GameModel) {
            self.game = game
            rebuildBoard()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let sceneView else { return }
            let point = gesture.location(in: sceneView)
            let results = sceneView.hitTest(
                point,
                options: [
                    .searchMode: SCNHitTestSearchMode.all.rawValue,
                    .ignoreHiddenNodes: true
                ]
            )
            guard let hit = results.first(where: { result in
                result.node.name?.hasPrefix("selectable") == true
            }) else {
                return
            }

            if isPreviewNode(hit.node) {
                animatePreviewQuarterTurn()
                return
            }

            let position = hit.worldCoordinates
            game.select(
                BoardCoordinate(
                    x: Int(round(position.x / Metrics.cellSize)),
                    y: Int(round(position.z / Metrics.cellSize))
                )
            )
        }

        private func animatePreviewQuarterTurn() {
            guard !isPreviewRotating,
                  let placement = game.previewPlacement else {
                return
            }
            isPreviewRotating = true

            let target = Placement(
                tile: placement.tile,
                center: placement.center,
                rotation: placement.rotation + 1
            )
            let level = game.previewDisplayLevel

            for node in previewRoot.childNodes {
                guard let name = node.name,
                      let indexText = name.split(separator: "-").last,
                      let index = Int(indexText),
                      target.coordinates.indices.contains(index) else {
                    continue
                }

                let move = SCNAction.move(
                    to: worldPosition(
                        for: target.coordinates[index],
                        level: level
                    ),
                    duration: 0.16
                )
                move.timingMode = .easeInEaseOut
                node.runAction(move)
            }

            previewRoot.runAction(
                .sequence([
                    .wait(duration: 0.16),
                    .run { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            game.rotate()
                            isPreviewRotating = false
                        }
                    }
                ])
            )
        }

        @objc private func handlePlacementPan(_ gesture: UIPanGestureRecognizer) {
            guard let sceneView,
                  let worldPoint = boardPoint(
                      at: gesture.location(in: sceneView),
                      in: sceneView
                  ) else {
                if gesture.state == .ended || gesture.state == .cancelled {
                    finishPlacementDrag()
                }
                return
            }

            switch gesture.state {
            case .began:
                if game.previewPlacement == nil {
                    game.select(coordinate(at: worldPoint))
                }
                dragStartBoardPoint = worldPoint
                dragStartCenter = worldCenter(of: game.previewCenter)
                previewVisualOffset = SCNVector3Zero
                previewRoot.position = SCNVector3Zero

            case .changed:
                updatePlacementDrag(at: worldPoint)

            case .ended, .cancelled:
                updatePlacementDrag(at: worldPoint)
                finishPlacementDrag()

            default:
                break
            }
        }

        @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)

            if gesture.state == .changed {
                yaw -= Float(translation.x) * 0.008
                pitch = min(
                    .pi * 0.46,
                    max(.pi * 0.12, pitch - Float(translation.y) * 0.006)
                )
                applyCamera()
                gesture.setTranslation(.zero, in: view)
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialPinchDistance = cameraDistance
            case .changed:
                cameraDistance = min(24, max(5, initialPinchDistance / Float(gesture.scale)))
                applyCamera()
            default:
                break
            }
        }

        private func updatePlacementDrag(at worldPoint: SCNVector3) {
            let desiredCenter = SCNVector3(
                dragStartCenter.x + worldPoint.x - dragStartBoardPoint.x,
                0,
                dragStartCenter.z + worldPoint.z - dragStartBoardPoint.z
            )
            let coordinate = coordinate(at: desiredCenter)

            if coordinate != game.previewCenter || game.previewPlacement == nil {
                game.select(coordinate)
            }

            let snappedCenter = worldCenter(of: coordinate)
            previewVisualOffset = SCNVector3(
                desiredCenter.x - snappedCenter.x,
                0,
                desiredCenter.z - snappedCenter.z
            )
            previewRoot.position = previewVisualOffset
        }

        private func finishPlacementDrag() {
            dragStartBoardPoint = SCNVector3Zero
            dragStartCenter = SCNVector3Zero
            previewVisualOffset = SCNVector3Zero
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.14
            previewRoot.position = SCNVector3Zero
            SCNTransaction.commit()
        }

        private func coordinate(at worldPoint: SCNVector3) -> BoardCoordinate {
            BoardCoordinate(
                x: Int(round(worldPoint.x / Metrics.cellSize)),
                y: Int(round(worldPoint.z / Metrics.cellSize))
            )
        }

        private func worldCenter(of coordinate: BoardCoordinate) -> SCNVector3 {
            SCNVector3(
                Float(coordinate.x) * Metrics.cellSize,
                0,
                Float(coordinate.y) * Metrics.cellSize
            )
        }

        private func boardPoint(
            at point: CGPoint,
            in sceneView: SCNView
        ) -> SCNVector3? {
            sceneView.hitTest(
                point,
                options: [
                    .searchMode: SCNHitTestSearchMode.all.rawValue,
                    .ignoreHiddenNodes: true
                ]
            )
            .first { $0.node.name == "selectable-board" }?
            .worldCoordinates
        }

        private func isPreviewNode(_ candidate: SCNNode) -> Bool {
            var node: SCNNode? = candidate
            while let current = node {
                if current.name?.hasPrefix("selectable-preview") == true {
                    return true
                }
                node = current.parent
            }
            return false
        }

        private func configureScene() {
            previewRoot.name = "selectable-preview-root"
            scene.rootNode.addChildNode(boardRoot)
            scene.rootNode.addChildNode(cameraOrbit)
            cameraOrbit.addChildNode(yawNode)
            yawNode.addChildNode(pitchNode)
            pitchNode.addChildNode(cameraNode)

            let camera = SCNCamera()
            camera.fieldOfView = 42
            camera.zNear = 0.1
            camera.zFar = 100
            camera.wantsHDR = true
            cameraNode.camera = camera

            let ambient = SCNNode()
            let ambientLight = SCNLight()
            ambientLight.type = .ambient
            ambientLight.intensity = 480
            ambientLight.color = UIColor(white: 0.68, alpha: 1)
            ambient.light = ambientLight
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            let keyLight = SCNLight()
            keyLight.type = .directional
            keyLight.intensity = 1_150
            keyLight.castsShadow = true
            keyLight.shadowMode = .deferred
            keyLight.shadowRadius = 5
            keyLight.shadowColor = UIColor.black.withAlphaComponent(0.55)
            key.light = keyLight
            key.eulerAngles = SCNVector3(-1.05, -0.7, 0)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            let fillLight = SCNLight()
            fillLight.type = .omni
            fillLight.intensity = 520
            fillLight.color = UIColor(red: 0.72, green: 0.82, blue: 1, alpha: 1)
            fill.light = fillLight
            fill.position = SCNVector3(-5, 8, 5)
            scene.rootNode.addChildNode(fill)

            applyCamera()
        }

        private func applyCamera() {
            yawNode.eulerAngles.y = yaw
            pitchNode.eulerAngles.x = -pitch
            cameraNode.position = SCNVector3(0, 0, cameraDistance)
        }

        private func rebuildBoard() {
            boardRoot.childNodes.forEach { $0.removeFromParentNode() }
            previewRoot.childNodes.forEach { $0.removeFromParentNode() }
            previewRoot.position = previewVisualOffset

            let bounds = expandedBounds
            let centerX = Float(bounds.minX + bounds.maxX) / 2
            let centerZ = Float(bounds.minY + bounds.maxY) / 2
            cameraOrbit.position = SCNVector3(centerX, 0, centerZ)

            addBoardSurface(bounds: bounds)
            addGrid(bounds: bounds)
            addPlacedLayers()
            addAssistanceMarkers()
            boardRoot.addChildNode(previewRoot)
            addPreview()
        }

        private var expandedBounds: (minX: Int, maxX: Int, minY: Int, maxY: Int) {
            let occupied = game.occupiedBounds
            return (
                occupied.minX - Metrics.boardPadding,
                occupied.maxX + Metrics.boardPadding,
                occupied.minY - Metrics.boardPadding,
                occupied.maxY + Metrics.boardPadding
            )
        }

        private func addBoardSurface(
            bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
        ) {
            let columns = Float(bounds.maxX - bounds.minX + 1)
            let rows = Float(bounds.maxY - bounds.minY + 1)
            let geometry = SCNBox(
                width: CGFloat(columns),
                height: 0.08,
                length: CGFloat(rows),
                chamferRadius: 0.12
            )
            geometry.firstMaterial = material(
                color: UIColor(red: 0.055, green: 0.075, blue: 0.075, alpha: 1),
                roughness: 0.92
            )

            let node = SCNNode(geometry: geometry)
            node.name = "selectable-board"
            node.position = SCNVector3(
                Float(bounds.minX + bounds.maxX) / 2,
                -0.08,
                Float(bounds.minY + bounds.maxY) / 2
            )
            node.castsShadow = false
            boardRoot.addChildNode(node)
        }

        private func addGrid(
            bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
        ) {
            let lineMaterial = material(
                color: UIColor.white.withAlphaComponent(0.08),
                roughness: 1
            )
            let minX = Float(bounds.minX) - 0.5
            let maxX = Float(bounds.maxX) + 0.5
            let minZ = Float(bounds.minY) - 0.5
            let maxZ = Float(bounds.maxY) + 0.5

            for x in bounds.minX...(bounds.maxX + 1) {
                let line = SCNBox(
                    width: 0.012,
                    height: 0.006,
                    length: CGFloat(maxZ - minZ),
                    chamferRadius: 0
                )
                line.firstMaterial = lineMaterial
                let node = SCNNode(geometry: line)
                node.position = SCNVector3(Float(x) - 0.5, -0.035, (minZ + maxZ) / 2)
                boardRoot.addChildNode(node)
            }

            for y in bounds.minY...(bounds.maxY + 1) {
                let line = SCNBox(
                    width: CGFloat(maxX - minX),
                    height: 0.006,
                    length: 0.012,
                    chamferRadius: 0
                )
                line.firstMaterial = lineMaterial
                let node = SCNNode(geometry: line)
                node.position = SCNVector3((minX + maxX) / 2, -0.035, Float(y) - 0.5)
                boardRoot.addChildNode(node)
            }
        }

        private func addPlacedLayers() {
            var tileCoordinates: [PlacedTileKey: Set<BoardCoordinate>] = [:]
            for (coordinate, layers) in game.board {
                for (layerIndex, layer) in layers.enumerated() {
                    let level = layerIndex + 1
                    let node = makeTileNode(
                        color: layer.color,
                        opacity: 1,
                        isValid: true
                    )
                    node.name = "selectable-tile"
                    node.position = worldPosition(
                        for: coordinate,
                        level: level
                    )
                    boardRoot.addChildNode(node)
                    tileCoordinates[PlacedTileKey(tileID: layer.tileID, level: level), default: []]
                        .insert(coordinate)
                }
            }

            for (key, coordinates) in tileCoordinates {
                addPlacedTilePerimeter(coordinates: coordinates, level: key.level)
            }
        }

        private func addPlacedTilePerimeter(
            coordinates: Set<BoardCoordinate>,
            level: Int
        ) {
            let lineThickness: CGFloat = 0.022
            let lineLength: CGFloat = 1.005
            let topY = Float(level) * Metrics.tileThickness + 0.016
            let perimeterMaterial = material(
                color: UIColor(white: 0.72, alpha: 0.42),
                roughness: 0.24
            )
            perimeterMaterial.metalness.contents = 0.45
            perimeterMaterial.specular.contents = UIColor(white: 1, alpha: 0.65)

            func addLine(at position: SCNVector3, width: CGFloat, length: CGFloat) {
                let geometry = SCNBox(
                    width: width,
                    height: 0.012,
                    length: length,
                    chamferRadius: lineThickness / 2
                )
                geometry.materials = [perimeterMaterial]
                let node = SCNNode(geometry: geometry)
                node.name = "placed-tile-perimeter"
                node.position = position
                node.castsShadow = false
                boardRoot.addChildNode(node)
            }

            for coordinate in coordinates {
                let x = Float(coordinate.x)
                let z = Float(coordinate.y)
                if !coordinates.contains(BoardCoordinate(x: coordinate.x - 1, y: coordinate.y)) {
                    addLine(at: SCNVector3(x - 0.5, topY, z), width: lineThickness, length: lineLength)
                }
                if !coordinates.contains(BoardCoordinate(x: coordinate.x + 1, y: coordinate.y)) {
                    addLine(at: SCNVector3(x + 0.5, topY, z), width: lineThickness, length: lineLength)
                }
                if !coordinates.contains(BoardCoordinate(x: coordinate.x, y: coordinate.y - 1)) {
                    addLine(at: SCNVector3(x, topY, z - 0.5), width: lineLength, length: lineThickness)
                }
                if !coordinates.contains(BoardCoordinate(x: coordinate.x, y: coordinate.y + 1)) {
                    addLine(at: SCNVector3(x, topY, z + 0.5), width: lineLength, length: lineThickness)
                }
            }
        }

        private func addPreview() {
            guard let placement = game.previewPlacement else { return }
            let level = game.previewDisplayLevel

            for (index, coordinate) in placement.coordinates.enumerated() {
                let node = makeTileNode(
                    color: placement.tile.colors[index],
                    opacity: 0.74,
                    isValid: game.canPlacePreview
                )
                node.name = "selectable-preview-cell-\(index)"
                node.position = worldPosition(for: coordinate, level: level)
                node.renderingOrder = 100 + level
                previewRoot.addChildNode(node)

                let outline = makeOutlineNode(isValid: game.canPlacePreview)
                outline.name = "selectable-preview-outline-\(index)"
                outline.position = node.position
                outline.renderingOrder = 200 + level
                outline.childNodes.forEach { $0.renderingOrder = 200 + level }
                previewRoot.addChildNode(outline)
            }
        }

        private func addAssistanceMarkers() {
            let bestPlacement = game.assistedBestPlacement

            for placement in game.assistedCandidatePlacements where placement != bestPlacement {
                addPlacementPath(for: placement, color: .systemBlue, isHighlighted: false)
            }

            if let bestPlacement {
                addPlacementPath(for: bestPlacement, color: .systemYellow, isHighlighted: true)
            }
        }

        private func addPlacementPath(
            for placement: Placement,
            color: UIColor,
            isHighlighted: Bool
        ) {
            guard placement.coordinates.count == 3 else { return }
            let level = (placement.coordinates.map(game.height(at:)).max() ?? 0) + 1
            let pathHeight = Float(level) * Metrics.tileThickness + 0.065 + (isHighlighted ? 0.025 : 0)
            let renderingOrder = (isHighlighted ? 190 : 90) + level
            let points = placement.coordinates.map { coordinate in
                SCNVector3(
                    Float(coordinate.x) * Metrics.cellSize,
                    pathHeight,
                    Float(coordinate.y) * Metrics.cellSize
                )
            }
            let pathMaterial = material(color: color, roughness: 0.22)
            pathMaterial.emission.contents = color.withAlphaComponent(0.85)

            addCandidateSegment(
                from: points[0],
                to: points[1],
                material: pathMaterial,
                renderingOrder: renderingOrder
            )
            addCandidateSegment(
                from: points[1],
                to: points[2],
                material: pathMaterial,
                renderingOrder: renderingOrder
            )

            for point in points {
                let joint = SCNSphere(radius: 0.075)
                joint.materials = [pathMaterial]
                let node = SCNNode(geometry: joint)
                node.name = "candidate-placement-path"
                node.position = point
                node.renderingOrder = renderingOrder
                node.castsShadow = false
                boardRoot.addChildNode(node)
            }
        }

        private func addCandidateSegment(
            from start: SCNVector3,
            to end: SCNVector3,
            material: SCNMaterial,
            renderingOrder: Int
        ) {
            let direction = SIMD3<Float>(end.x - start.x, end.y - start.y, end.z - start.z)
            let length = simd_length(direction)
            guard length > 0 else { return }

            let capsule = SCNCapsule(capRadius: 0.075, height: CGFloat(length))
            capsule.materials = [material]
            let node = SCNNode(geometry: capsule)
            node.name = "candidate-placement-path"
            node.position = SCNVector3(
                (start.x + end.x) / 2,
                (start.y + end.y) / 2,
                (start.z + end.z) / 2
            )
            node.simdOrientation = simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: direction / length
            )
            node.renderingOrder = renderingOrder
            node.castsShadow = false
            boardRoot.addChildNode(node)
        }

        private func worldPosition(
            for coordinate: BoardCoordinate,
            level: Int
        ) -> SCNVector3 {
            SCNVector3(
                Float(coordinate.x) * Metrics.cellSize,
                Float(level - 1) * Metrics.tileThickness + Metrics.tileThickness / 2,
                Float(coordinate.y) * Metrics.cellSize
            )
        }

        private func makeTileNode(
            color: TileColor,
            opacity: CGFloat,
            isValid: Bool
        ) -> SCNNode {
            TileVisualFactory.makeCell(color: color, opacity: opacity, isValid: isValid)
        }

        private func makeOutlineNode(isValid: Bool) -> SCNNode {
            let side = CGFloat(Metrics.cellSize - Metrics.cellGap + 0.035)
            let height = CGFloat(Metrics.tileThickness + 0.025)
            let thickness: CGFloat = 0.025
            let outlineMaterial = SCNMaterial()
            outlineMaterial.diffuse.contents = (
                isValid
                ? UIColor(red: 1, green: 0.58, blue: 0.08, alpha: 0.95)
                : UIColor(red: 1, green: 0.18, blue: 0.05, alpha: 0.95)
            )
            outlineMaterial.emission.contents = outlineMaterial.diffuse.contents
            outlineMaterial.isDoubleSided = true

            let root = SCNNode()

            func addEdge(
                width: CGFloat,
                edgeHeight: CGFloat,
                length: CGFloat,
                position: SCNVector3
            ) {
                let geometry = SCNBox(
                    width: width,
                    height: edgeHeight,
                    length: length,
                    chamferRadius: thickness / 2
                )
                geometry.materials = [outlineMaterial]
                let edge = SCNNode(geometry: geometry)
                edge.position = position
                edge.castsShadow = false
                root.addChildNode(edge)
            }

            let halfSide = Float(side / 2)
            let halfHeight = Float(height / 2)

            for y in [-halfHeight, halfHeight] {
                for z in [-halfSide, halfSide] {
                    addEdge(
                        width: side,
                        edgeHeight: thickness,
                        length: thickness,
                        position: SCNVector3(0, y, z)
                    )
                }
                for x in [-halfSide, halfSide] {
                    addEdge(
                        width: thickness,
                        edgeHeight: thickness,
                        length: side,
                        position: SCNVector3(x, y, 0)
                    )
                }
            }

            for x in [-halfSide, halfSide] {
                for z in [-halfSide, halfSide] {
                    addEdge(
                        width: thickness,
                        edgeHeight: height,
                        length: thickness,
                        position: SCNVector3(x, 0, z)
                    )
                }
            }

            return root
        }

        private func material(color: UIColor, roughness: CGFloat) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.roughness.contents = roughness
            material.metalness.contents = 0
            material.isDoubleSided = true
            return material
        }

        private func uiColor(for color: TileColor) -> UIColor {
            TileVisualFactory.uiColor(for: color)
        }
    }
}
