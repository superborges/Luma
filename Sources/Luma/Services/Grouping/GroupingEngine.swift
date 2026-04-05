import CoreLocation
import Foundation
import Vision

protocol GroupLocationNamingProvider: Sendable {
    func name(for coordinate: Coordinate) async -> String?
}

protocol VisualSubgroupingProvider: Sendable {
    func continuityDistance(between lhs: [MediaAsset], and rhs: [MediaAsset]) async -> Float?
    func subgroupAssets(in assets: [MediaAsset]) async -> [[MediaAsset]]
}

struct BurstGroupingPolicy: Sendable {
    var frameGapThreshold: TimeInterval = 12
    var burstSpanThreshold: TimeInterval = 20
    var focalLengthTolerance: Double = 0.15
    var anchorDistanceThreshold: Float = 0.28
    var completeDistanceThreshold: Float = 0.35

    func subgroupAssets(
        in assets: [MediaAsset],
        distanceProvider: (MediaAsset, MediaAsset) -> Float?
    ) -> [[MediaAsset]] {
        guard assets.count > 1 else { return assets.map { [$0] } }

        let sortedAssets = assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        var result: [[MediaAsset]] = []
        var currentGroup: [MediaAsset] = []

        for asset in sortedAssets {
            guard !currentGroup.isEmpty else {
                currentGroup = [asset]
                continue
            }

            let decision = decision(for: asset, currentGroup: currentGroup, distanceProvider: distanceProvider)
            if decision.appendToBurst {
                currentGroup.append(asset)
            } else {
                result.append(currentGroup)
                currentGroup = [asset]
            }
        }

        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }

        return result
    }

    func decision(
        for candidate: MediaAsset,
        currentGroup: [MediaAsset],
        distanceProvider: (MediaAsset, MediaAsset) -> Float?
    ) -> BurstDecision {
        guard let anchor = currentGroup.first,
              let previous = currentGroup.last else {
            return BurstDecision(appendToBurst: true)
        }

        let deltaTime = candidate.metadata.captureDate.timeIntervalSince(previous.metadata.captureDate)
        guard deltaTime <= frameGapThreshold else {
            return BurstDecision(appendToBurst: false, rejectionReason: .frameGap, deltaTime: deltaTime)
        }

        let totalSpan = candidate.metadata.captureDate.timeIntervalSince(anchor.metadata.captureDate)
        guard totalSpan <= burstSpanThreshold else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .burstSpan,
                deltaTime: deltaTime,
                totalSpan: totalSpan
            )
        }

        let orientationMatches = hasMatchingOrientation(lhs: anchor, rhs: candidate)
        guard orientationMatches else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .orientation,
                deltaTime: deltaTime,
                totalSpan: totalSpan,
                orientationMatches: false
            )
        }

        let focalLengthMatches = hasCompatibleFocalLength(lhs: anchor, rhs: candidate)
        guard focalLengthMatches else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .focalLength,
                deltaTime: deltaTime,
                totalSpan: totalSpan,
                orientationMatches: true,
                focalLengthMatches: false
            )
        }

        guard let anchorDistance = distanceProvider(anchor, candidate) else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .missingFeaturePrint,
                deltaTime: deltaTime,
                totalSpan: totalSpan,
                orientationMatches: true,
                focalLengthMatches: true
            )
        }
        let anchorDistanceLimit = currentGroup.count == 1
            ? max(anchorDistanceThreshold, completeDistanceThreshold)
            : anchorDistanceThreshold
        guard anchorDistance <= anchorDistanceLimit else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .anchorDistance,
                deltaTime: deltaTime,
                totalSpan: totalSpan,
                orientationMatches: true,
                focalLengthMatches: true,
                anchorDistance: anchorDistance
            )
        }

        var completeDistance: Float = 0
        for member in currentGroup {
            guard let memberDistance = distanceProvider(member, candidate) else {
                return BurstDecision(
                    appendToBurst: false,
                    rejectionReason: .missingFeaturePrint,
                    deltaTime: deltaTime,
                    totalSpan: totalSpan,
                    orientationMatches: true,
                    focalLengthMatches: true,
                    anchorDistance: anchorDistance
                )
            }
            completeDistance = max(completeDistance, memberDistance)
        }

        guard completeDistance <= completeDistanceThreshold else {
            return BurstDecision(
                appendToBurst: false,
                rejectionReason: .completeDistance,
                deltaTime: deltaTime,
                totalSpan: totalSpan,
                orientationMatches: true,
                focalLengthMatches: true,
                anchorDistance: anchorDistance,
                completeDistance: completeDistance
            )
        }

        return BurstDecision(
            appendToBurst: true,
            deltaTime: deltaTime,
            totalSpan: totalSpan,
            orientationMatches: true,
            focalLengthMatches: true,
            anchorDistance: anchorDistance,
            completeDistance: completeDistance
        )
    }

    private func hasMatchingOrientation(lhs: MediaAsset, rhs: MediaAsset) -> Bool {
        let lhsIsLandscape = lhs.metadata.imageWidth >= lhs.metadata.imageHeight
        let rhsIsLandscape = rhs.metadata.imageWidth >= rhs.metadata.imageHeight
        return lhsIsLandscape == rhsIsLandscape
    }

    private func hasCompatibleFocalLength(lhs: MediaAsset, rhs: MediaAsset) -> Bool {
        guard let lhsFocalLength = lhs.metadata.focalLength,
              let rhsFocalLength = rhs.metadata.focalLength,
              lhsFocalLength > 0,
              rhsFocalLength > 0 else {
            return true
        }

        let ratio = abs(lhsFocalLength - rhsFocalLength) / max(lhsFocalLength, rhsFocalLength)
        return ratio <= focalLengthTolerance
    }
}

struct BurstDecision: Sendable {
    var appendToBurst: Bool
    var rejectionReason: BurstRejectionReason?
    var deltaTime: TimeInterval?
    var totalSpan: TimeInterval?
    var orientationMatches: Bool?
    var focalLengthMatches: Bool?
    var anchorDistance: Float?
    var completeDistance: Float?
}

enum BurstRejectionReason: String, Sendable {
    case frameGap = "frame_gap"
    case burstSpan = "burst_span"
    case orientation = "orientation"
    case focalLength = "focal_length"
    case missingFeaturePrint = "missing_feature_print"
    case anchorDistance = "anchor_distance"
    case completeDistance = "complete_distance"
}

struct CLGeocoderLocationNamingProvider: GroupLocationNamingProvider {
    func name(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            if let pointOfInterest = placemark.areasOfInterest?.first, !pointOfInterest.isEmpty {
                return pointOfInterest
            }
            if let name = placemark.name, !name.isEmpty {
                return name
            }
            if let subLocality = placemark.subLocality, !subLocality.isEmpty {
                return subLocality
            }
            if let locality = placemark.locality, !locality.isEmpty {
                return locality
            }
            if let administrativeArea = placemark.administrativeArea, !administrativeArea.isEmpty {
                return administrativeArea
            }
            return nil
        } catch {
            return nil
        }
    }
}

actor VisionVisualSubgroupingProvider: VisualSubgroupingProvider {
    let burstPolicy: BurstGroupingPolicy

    private var featurePrints: [UUID: VNFeaturePrintObservation] = [:]

    init(
        burstPolicy: BurstGroupingPolicy = BurstGroupingPolicy()
    ) {
        self.burstPolicy = burstPolicy
    }

    func continuityDistance(between lhs: [MediaAsset], and rhs: [MediaAsset]) async -> Float? {
        let lhsObservations = observations(for: lhs)
        let rhsObservations = observations(for: rhs)
        guard !lhsObservations.isEmpty, !rhsObservations.isEmpty else { return nil }

        var bestDistance = Float.greatestFiniteMagnitude
        for lhsAsset in lhs {
            guard let lhsObservation = lhsObservations[lhsAsset.id] else { continue }
            for rhsAsset in rhs {
                guard let rhsObservation = rhsObservations[rhsAsset.id] else { continue }
                bestDistance = min(bestDistance, Self.featureDistance(from: lhsObservation, to: rhsObservation))
            }
        }

        return bestDistance.isFinite ? bestDistance : nil
    }

    func subgroupAssets(in assets: [MediaAsset]) async -> [[MediaAsset]] {
        await burstDebugGroups(in: assets)
    }

    private func observations(for assets: [MediaAsset]) -> [UUID: VNFeaturePrintObservation] {
        var observations: [UUID: VNFeaturePrintObservation] = [:]
        observations.reserveCapacity(assets.count)

        for asset in assets {
            if let cached = featurePrints[asset.id] {
                observations[asset.id] = cached
                continue
            }
            guard let observation = Self.makeFeaturePrint(for: asset) else { continue }
            featurePrints[asset.id] = observation
            observations[asset.id] = observation
        }

        return observations
    }

    func burstDebugGroups(in assets: [MediaAsset]) async -> [[MediaAsset]] {
        let sortedAssets = assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        let observations = observations(for: sortedAssets)
        var result: [[MediaAsset]] = []
        var currentGroup: [MediaAsset] = []

        for asset in sortedAssets {
            guard !currentGroup.isEmpty else {
                currentGroup = [asset]
                continue
            }

            let decision = burstPolicy.decision(for: asset, currentGroup: currentGroup) { lhs, rhs in
                guard let lhsObservation = observations[lhs.id],
                      let rhsObservation = observations[rhs.id] else {
                    return nil
                }
                return Self.featureDistance(from: lhsObservation, to: rhsObservation)
            }
            traceDecision(candidate: asset, currentGroup: currentGroup, decision: decision)

            if decision.appendToBurst {
                currentGroup.append(asset)
            } else {
                result.append(currentGroup)
                currentGroup = [asset]
            }
        }

        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }

        return result
    }

    private func traceDecision(candidate: MediaAsset, currentGroup: [MediaAsset], decision: BurstDecision) {
        var metadata: [String: String] = [
            "candidate": candidate.baseName,
            "anchor": currentGroup.first?.baseName ?? candidate.baseName,
            "group_size": String(currentGroup.count),
            "decision": decision.appendToBurst ? "append" : "split"
        ]
        if let rejectionReason = decision.rejectionReason {
            metadata["reason"] = rejectionReason.rawValue
        }
        if let deltaTime = decision.deltaTime {
            metadata["delta_time_ms"] = String(Int(deltaTime * 1000))
        }
        if let totalSpan = decision.totalSpan {
            metadata["burst_span_ms"] = String(Int(totalSpan * 1000))
        }
        if let orientationMatches = decision.orientationMatches {
            metadata["orientation_matches"] = orientationMatches ? "true" : "false"
        }
        if let focalLengthMatches = decision.focalLengthMatches {
            metadata["focal_matches"] = focalLengthMatches ? "true" : "false"
        }
        if let anchorDistance = decision.anchorDistance {
            metadata["anchor_distance"] = String(format: "%.3f", anchorDistance)
        }
        if let completeDistance = decision.completeDistance {
            metadata["complete_distance"] = String(format: "%.3f", completeDistance)
        }
        RuntimeTrace.event("burst_candidate", category: "grouping", metadata: metadata)
    }

    private static func makeFeaturePrint(for asset: MediaAsset) -> VNFeaturePrintObservation? {
        guard let sourceURL = sourceURL(for: asset),
              let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 512) else {
            return nil
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    private static func sourceURL(for asset: MediaAsset) -> URL? {
        let candidates = [asset.previewURL, asset.thumbnailURL, asset.rawURL]
        return candidates.compactMap { $0 }.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private static func featureDistance(from lhs: VNFeaturePrintObservation, to rhs: VNFeaturePrintObservation) -> Float {
        var distance: Float = .greatestFiniteMagnitude
        do {
            try lhs.computeDistance(&distance, to: rhs)
        } catch {
            return .greatestFiniteMagnitude
        }
        return distance
    }
}

struct GroupingEngine: Sendable {
    var timeThreshold: TimeInterval = 30 * 60
    var strongTimeThreshold: TimeInterval = 90 * 60
    var hardTimeThreshold: TimeInterval = 120 * 60
    var distanceThreshold: CLLocationDistance = 200
    var locationTransitionThreshold: CLLocationDistance = 350
    var minimumClusterSize: Int = 3
    var continuityWindowSize: Int = 3
    var visualChangeGapThreshold: TimeInterval = 5 * 60
    var sceneContinuityThreshold: Float = 0.8
    var namingTimeZone: TimeZone = .autoupdatingCurrent
    var namingLocale: Locale = Locale(identifier: "zh_Hans")
    var locationNamingProvider: any GroupLocationNamingProvider = CLGeocoderLocationNamingProvider()
    var visualSubgroupingProvider: any VisualSubgroupingProvider = VisionVisualSubgroupingProvider()

    func makeGroups(from assets: [MediaAsset], resolvesLocationNames: Bool = true) async -> [PhotoGroup] {
        guard !assets.isEmpty else { return [] }

        let startedAt = Date()
        let sorted = assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        let sceneSplitStartedAt = Date()
        let sceneGroups = await splitIntoSceneGroups(sorted)
        RuntimeTrace.metric(
            "grouping_scene_split_completed",
            category: "grouping",
            metadata: [
                "asset_count": String(sorted.count),
                "scene_group_count": String(sceneGroups.count),
                "duration_ms": durationString(since: sceneSplitStartedAt)
            ]
        )

        let representativeCoordinates = sceneGroups.map(representativeCoordinate(for:))
        let namingStartedAt = Date()
        let locationNamesByKey = resolvesLocationNames
            ? await resolveLocationNames(for: representativeCoordinates.compactMap { $0 })
            : [:]

        var groups: [PhotoGroup] = []
        groups.reserveCapacity(sceneGroups.count)
        var subgroupingDuration: TimeInterval = 0
        var namedGroupCount = 0

        for (chunk, representativeCoordinate) in zip(sceneGroups, representativeCoordinates) {
            let subgroupingStartedAt = Date()
            let subGroupAssets = await visualSubgroupingProvider.subgroupAssets(in: chunk)
            subgroupingDuration += subgroupingStartedAt.distance(to: .now)

            let locationName = representativeCoordinate.flatMap { locationNamesByKey[LocationNameKey($0)] }
            if locationName != nil {
                namedGroupCount += 1
            }

            groups.append(
                PhotoGroup(
                    id: UUID(),
                    name: makeBaseGroupName(for: chunk, resolvedLocationName: locationName),
                    assets: chunk.map(\.id),
                    subGroups: makeSubGroups(from: subGroupAssets),
                    timeRange: chunk.first!.metadata.captureDate ... chunk.last!.metadata.captureDate,
                    location: representativeCoordinate,
                    groupComment: nil,
                    recommendedAssets: chunk.filter { $0.aiScore?.recommended == true }.map(\.id)
                )
            )
        }

        RuntimeTrace.metric(
            "grouping_subgrouping_completed",
            category: "grouping",
            metadata: [
                "asset_count": String(sorted.count),
                "scene_group_count": String(sceneGroups.count),
                "duration_ms": durationString(for: subgroupingDuration)
            ]
        )
        RuntimeTrace.metric(
            "grouping_location_naming_completed",
            category: "grouping",
            metadata: [
                "group_count": String(sceneGroups.count),
                "named_group_count": String(namedGroupCount),
                "unique_coordinate_count": String(Set(representativeCoordinates.compactMap { $0.map(LocationNameKey.init) }).count),
                "duration_ms": durationString(since: namingStartedAt)
            ]
        )

        let names = makeUniqueGroupNames(for: groups.map(\.name))
        for index in groups.indices {
            groups[index].name = names[index]
        }

        RuntimeTrace.metric(
            "grouping_completed",
            category: "grouping",
            metadata: [
                "asset_count": String(sorted.count),
                "group_count": String(groups.count),
                "duration_ms": durationString(since: startedAt)
            ]
        )
        return groups
    }

    func refreshGroupNames(for groups: [PhotoGroup]) async -> [PhotoGroup] {
        guard !groups.isEmpty else { return groups }

        let coordinates = groups.compactMap(\.location)
        let namingStartedAt = Date()
        let locationNamesByKey = await resolveLocationNames(for: coordinates)

        var updatedGroups = groups.map { group in
            var updatedGroup = group
            let locationName = group.location.flatMap { locationNamesByKey[LocationNameKey($0)] }
            updatedGroup.name = makeBaseGroupName(for: group.timeRange.lowerBound, resolvedLocationName: locationName)
            return updatedGroup
        }

        let uniqueNames = makeUniqueGroupNames(for: updatedGroups.map(\.name))
        for index in updatedGroups.indices {
            updatedGroups[index].name = uniqueNames[index]
        }

        RuntimeTrace.metric(
            "grouping_background_location_naming_completed",
            category: "grouping",
            metadata: [
                "group_count": String(groups.count),
                "named_group_count": String(updatedGroups.filter { !$0.name.contains("月") }.count),
                "unique_coordinate_count": String(Set(coordinates.map(LocationNameKey.init)).count),
                "duration_ms": durationString(since: namingStartedAt)
            ]
        )

        return updatedGroups
    }

    private func splitIntoSceneGroups(_ assets: [MediaAsset]) async -> [[MediaAsset]] {
        await splitByHardTime(assets).flatMapAsync(refineSceneSession)
    }

    private func splitByHardTime(_ assets: [MediaAsset]) -> [[MediaAsset]] {
        var groups: [[MediaAsset]] = []
        var current: [MediaAsset] = []

        for asset in assets {
            if let previous = current.last,
               asset.metadata.captureDate.timeIntervalSince(previous.metadata.captureDate) >= hardTimeThreshold {
                groups.append(current)
                current = [asset]
            } else {
                current.append(asset)
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }

        return groups
    }

    private func refineSceneSession(_ assets: [MediaAsset]) async -> [[MediaAsset]] {
        guard assets.count > 1 else { return [assets] }

        let labels = locationLabels(for: assets)
        var result: [[MediaAsset]] = []
        var currentGroup = [assets[0]]

        for index in 1..<assets.count {
            let previous = assets[index - 1]
            let candidate = assets[index]
            let gap = candidate.metadata.captureDate.timeIntervalSince(previous.metadata.captureDate)

            let reasons = await transitionReasons(
                previous: previous,
                next: candidate,
                previousLabel: labels[previous.id] ?? 0,
                nextLabel: labels[candidate.id] ?? 0,
                gap: gap
            )

            guard !reasons.isEmpty else {
                currentGroup.append(candidate)
                continue
            }

            let leftWindow = Array(currentGroup.suffix(continuityWindowSize))
            let rightWindow = Array(assets[index..<min(index + continuityWindowSize, assets.count)])
            let assessment = await assessContinuity(
                leftWindow: leftWindow,
                rightWindow: rightWindow,
                previousLabel: labels[previous.id] ?? 0,
                nextLabel: labels[candidate.id] ?? 0
            )
            let shouldSplit = shouldSplit(gap: gap, reasons: reasons, assessment: assessment)

            traceSceneDecision(
                previous: previous,
                next: candidate,
                gap: gap,
                reasons: reasons,
                assessment: assessment,
                shouldSplit: shouldSplit,
                previousLabel: labels[previous.id] ?? 0,
                nextLabel: labels[candidate.id] ?? 0
            )

            if shouldSplit {
                result.append(currentGroup)
                currentGroup = [candidate]
            } else {
                currentGroup.append(candidate)
            }
        }

        if !currentGroup.isEmpty {
            result.append(currentGroup)
        }

        return result
    }

    private func transitionReasons(
        previous: MediaAsset,
        next: MediaAsset,
        previousLabel: Int,
        nextLabel: Int,
        gap: TimeInterval
    ) async -> Set<SceneTransitionReason> {
        var reasons: Set<SceneTransitionReason> = []

        if gap > timeThreshold {
            reasons.insert(.timeGap)
        }
        if isStrongLocationChange(previous: previous, next: next, previousLabel: previousLabel, nextLabel: nextLabel) {
            reasons.insert(.locationChange)
        }
        if gap >= visualChangeGapThreshold,
           let pairDistance = await visualSubgroupingProvider.continuityDistance(between: [previous], and: [next]),
           pairDistance > sceneContinuityThreshold * 1.5 {
            reasons.insert(.visualChange)
        }

        return reasons
    }

    private func isStrongLocationChange(
        previous: MediaAsset,
        next: MediaAsset,
        previousLabel: Int,
        nextLabel: Int
    ) -> Bool {
        if previousLabel > 0, nextLabel > 0, previousLabel != nextLabel {
            return true
        }
        if let distance = coordinateDistance(between: previous, and: next),
           distance >= locationTransitionThreshold {
            return true
        }
        return false
    }

    private func assessContinuity(
        leftWindow: [MediaAsset],
        rightWindow: [MediaAsset],
        previousLabel: Int,
        nextLabel: Int
    ) async -> SceneContinuityAssessment {
        let nearbyCoordinateDistance = minCoordinateDistance(between: leftWindow, and: rightWindow)
        let visualDistance = await visualSubgroupingProvider.continuityDistance(between: leftWindow, and: rightWindow)

        return SceneContinuityAssessment(
            sharesLocationCluster: previousLabel > 0 && previousLabel == nextLabel,
            nearbyCoordinateDistance: nearbyCoordinateDistance,
            visualDistance: visualDistance
        )
    }

    private func shouldSplit(
        gap: TimeInterval,
        reasons: Set<SceneTransitionReason>,
        assessment: SceneContinuityAssessment
    ) -> Bool {
        if assessment.sharesLocationCluster {
            return false
        }
        if let nearbyCoordinateDistance = assessment.nearbyCoordinateDistance,
           nearbyCoordinateDistance <= distanceThreshold {
            return false
        }
        if let visualDistance = assessment.visualDistance,
           visualDistance <= sceneContinuityThreshold {
            return false
        }
        if reasons.contains(.locationChange) {
            return true
        }
        if gap >= strongTimeThreshold {
            return true
        }
        if reasons.contains(.visualChange) {
            return true
        }
        return reasons.contains(.timeGap)
    }

    private func locationLabels(for assets: [MediaAsset]) -> [UUID: Int] {
        let locatedAssets = assets.filter { $0.metadata.gpsCoordinate != nil }
        guard locatedAssets.count >= minimumClusterSize else {
            return Dictionary(uniqueKeysWithValues: assets.map { ($0.id, 0) })
        }

        let coordinates = Dictionary(uniqueKeysWithValues: locatedAssets.compactMap { asset in
            asset.metadata.gpsCoordinate.map { (asset.id, $0) }
        })

        var labels: [UUID: Int] = [:]
        var clusterID = 0

        for asset in locatedAssets {
            guard labels[asset.id] == nil else { continue }

            let seedNeighbors = neighbors(of: asset.id, in: coordinates)
            if seedNeighbors.count + 1 < minimumClusterSize {
                labels[asset.id] = -1
                continue
            }

            clusterID += 1
            labels[asset.id] = clusterID

            var queue = seedNeighbors
            var visited = Set(queue)
            while !queue.isEmpty {
                let candidateID = queue.removeFirst()
                if labels[candidateID] == -1 {
                    labels[candidateID] = clusterID
                }
                guard labels[candidateID] == nil else { continue }

                labels[candidateID] = clusterID
                let expandedNeighbors = neighbors(of: candidateID, in: coordinates)
                if expandedNeighbors.count + 1 >= minimumClusterSize {
                    for neighbor in expandedNeighbors where !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        queue.append(neighbor)
                    }
                }
            }
        }

        var fallbackNoiseIndex = 1
        for asset in assets {
            if let label = labels[asset.id], label > 0 {
                continue
            }
            labels[asset.id] = -(fallbackNoiseIndex)
            fallbackNoiseIndex += 1
        }

        return labels
    }

    private func neighbors(of assetID: UUID, in coordinates: [UUID: Coordinate]) -> [UUID] {
        guard let source = coordinates[assetID] else { return [] }
        let sourceLocation = CLLocation(latitude: source.latitude, longitude: source.longitude)

        return coordinates.compactMap { candidateID, coordinate in
            guard candidateID != assetID else { return nil }
            let candidateLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return candidateLocation.distance(from: sourceLocation) <= distanceThreshold ? candidateID : nil
        }
    }

    private func representativeCoordinate(for assets: [MediaAsset]) -> Coordinate? {
        assets.compactMap(\.metadata.gpsCoordinate).first
    }

    private func resolveLocationNames(for coordinates: [Coordinate]) async -> [LocationNameKey: String] {
        var names: [LocationNameKey: String] = [:]
        var seenKeys = Set<LocationNameKey>()

        for coordinate in coordinates {
            let key = LocationNameKey(coordinate)
            guard seenKeys.insert(key).inserted else { continue }
            if let name = await locationNamingProvider.name(for: coordinate), !name.isEmpty {
                names[key] = name
            }
        }

        return names
    }

    private func coordinateDistance(between lhs: MediaAsset, and rhs: MediaAsset) -> CLLocationDistance? {
        guard let lhsCoordinate = lhs.metadata.gpsCoordinate,
              let rhsCoordinate = rhs.metadata.gpsCoordinate else {
            return nil
        }
        let lhsLocation = CLLocation(latitude: lhsCoordinate.latitude, longitude: lhsCoordinate.longitude)
        let rhsLocation = CLLocation(latitude: rhsCoordinate.latitude, longitude: rhsCoordinate.longitude)
        return lhsLocation.distance(from: rhsLocation)
    }

    private func minCoordinateDistance(between lhs: [MediaAsset], and rhs: [MediaAsset]) -> CLLocationDistance? {
        var bestDistance: CLLocationDistance?

        for lhsAsset in lhs {
            guard let lhsCoordinate = lhsAsset.metadata.gpsCoordinate else { continue }
            let lhsLocation = CLLocation(latitude: lhsCoordinate.latitude, longitude: lhsCoordinate.longitude)

            for rhsAsset in rhs {
                guard let rhsCoordinate = rhsAsset.metadata.gpsCoordinate else { continue }
                let rhsLocation = CLLocation(latitude: rhsCoordinate.latitude, longitude: rhsCoordinate.longitude)
                let distance = lhsLocation.distance(from: rhsLocation)
                bestDistance = min(bestDistance ?? distance, distance)
            }
        }

        return bestDistance
    }

    private func makeSubGroups(from groups: [[MediaAsset]]) -> [SubGroup] {
        groups.map { assets in
            let bestAsset = assets.max { subgroupScore(for: $0) < subgroupScore(for: $1) }?.id
            return SubGroup(
                id: UUID(),
                assets: assets.map(\.id),
                bestAsset: bestAsset
            )
        }
    }

    private func subgroupScore(for asset: MediaAsset) -> Int {
        let recommendedBoost = asset.aiScore?.recommended == true ? 1_000 : 0
        return recommendedBoost + (asset.aiScore?.overall ?? 0)
    }

    private func makeUniqueGroupNames(for baseNames: [String]) -> [String] {
        let totals = Dictionary(baseNames.map { ($0, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]

        return baseNames.map { baseName in
            guard let total = totals[baseName], total > 1 else {
                return baseName
            }

            let ordinal = seen[baseName, default: 0] + 1
            seen[baseName] = ordinal
            guard ordinal > 1 else {
                return baseName
            }
            return "\(baseName)·\(ordinal)"
        }
    }

    private func makeBaseGroupName(for assets: [MediaAsset], resolvedLocationName: String?) -> String {
        guard let start = assets.first?.metadata.captureDate else {
            return "未命名分组"
        }
        return makeBaseGroupName(for: start, resolvedLocationName: resolvedLocationName)
    }

    private func makeBaseGroupName(for start: Date, resolvedLocationName: String?) -> String {
        let period = periodLabel(for: start)
        if let resolvedLocationName, !resolvedLocationName.isEmpty {
            return "\(resolvedLocationName)·\(period)"
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = namingLocale
        dayFormatter.timeZone = namingTimeZone
        dayFormatter.dateFormat = "M月d日"
        return "\(dayFormatter.string(from: start))·\(period)"
    }

    private func periodLabel(for date: Date) -> String {
        let hour = namingCalendar().component(.hour, from: date)
        switch hour {
        case 5..<12:
            return "上午"
        case 12..<18:
            return "下午"
        default:
            return "夜晚"
        }
    }

    private func namingCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = namingTimeZone
        return calendar
    }

    private func traceSceneDecision(
        previous: MediaAsset,
        next: MediaAsset,
        gap: TimeInterval,
        reasons: Set<SceneTransitionReason>,
        assessment: SceneContinuityAssessment,
        shouldSplit: Bool,
        previousLabel: Int,
        nextLabel: Int
    ) {
        var metadata: [String: String] = [
            "previous_asset": previous.baseName,
            "next_asset": next.baseName,
            "gap_seconds": String(Int(gap)),
            "reasons": reasons.map(\.rawValue).sorted().joined(separator: ","),
            "decision": shouldSplit ? "split" : "keep",
            "previous_label": String(previousLabel),
            "next_label": String(nextLabel)
        ]
        if let nearbyCoordinateDistance = assessment.nearbyCoordinateDistance {
            metadata["nearby_coordinate_distance_m"] = String(format: "%.1f", nearbyCoordinateDistance)
        }
        if let visualDistance = assessment.visualDistance {
            metadata["visual_distance"] = String(format: "%.3f", visualDistance)
        }
        RuntimeTrace.event("scene_cut_candidate", category: "grouping", metadata: metadata)
    }

    private func durationString(since startedAt: Date) -> String {
        String(Int(startedAt.distance(to: .now) * 1000))
    }

    private func durationString(for duration: TimeInterval) -> String {
        String(format: "%.2f", duration * 1000)
    }
}

private struct SceneContinuityAssessment {
    let sharesLocationCluster: Bool
    let nearbyCoordinateDistance: CLLocationDistance?
    let visualDistance: Float?
}

private struct LocationNameKey: Hashable {
    let latitudeE3: Int
    let longitudeE3: Int

    init(_ coordinate: Coordinate) {
        latitudeE3 = Int((coordinate.latitude * 1000).rounded())
        longitudeE3 = Int((coordinate.longitude * 1000).rounded())
    }
}

private enum SceneTransitionReason: String {
    case timeGap = "time_gap"
    case locationChange = "location_change"
    case visualChange = "visual_change"
}

private extension Array {
    func flatMapAsync<T>(_ transform: (Element) async -> [T]) async -> [T] {
        var result: [T] = []
        for element in self {
            result.append(contentsOf: await transform(element))
        }
        return result
    }
}
