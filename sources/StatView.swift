//
//  StatView.swift
//  SnowCountry
//
//  Created by Ryan Potter on 12/1/23.
//

import SwiftUI
import CoreLocation
import MapKit
import Charts

struct StatView: View {
    var trackFilePath: URL
    @ObservedObject var locationManager = LocationManager()
    @State private var trackData: TrackData?
    @State private var locations: [CLLocation] = []
    @State private var trackHistoryViewMap = MKMapView()
    @EnvironmentObject var userSettings: UserSettings
    @State private var fileToShare: ShareableFile?
    @State private var isLoading = false
    @State private var loadingError: String?
    @State private var loadedTrackData: TrackData?
    @State private var showingEditTrackSheet = false
    @State private var newTrackName: String = ""
    @State private var showShareSheet = false
    @State private var shareURL: URL? = nil
    @State private var showingMapTypeSheet = false
    @State var trackName: String
    var trackDate: String
    @Environment(\.dismiss) private var dismiss
    @State private var isExpanded = false
    @State private var appleMapStyle: AppleMapStyle = .standard
    @State private var cachedStats: TrackStatsEntry?
    @State private var showingExportCard = false

    // MARK: - Activity State (display only — editing is in EditTrackDetailsView)
    @State private var currentActivity: String? = nil

    // MARK: - Visualization State
    @State private var trackColorMode: TrackColorMode = .normal
    @State private var showingColorModeSheet = false

    // MARK: - Playback State
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    @State private var playbackTimer: Timer? = nil
    @State private var isDraggingProgress = false

    private let playbackDuration: Double = 24.0

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    // MARK: - Playback coordinate

    private var playbackCoordinate: CLLocationCoordinate2D? {
        guard !locations.isEmpty, playbackProgress > 0 else { return nil }
        let idx = Int((playbackProgress * Double(locations.count - 1)).rounded())
        let clamped = max(0, min(locations.count - 1, idx))
        return locations[clamped].coordinate
    }

    // MARK: - Elevation computed properties

    private var hasAltitudeData: Bool {
        locations.count > 1 && (maxElevation - minElevation) > 1.0
    }

    private var elevationData: [ElevationPoint] {
        locations.enumerated().map { i, loc in
            ElevationPoint(index: i, elevation: loc.altitude)
        }
    }

    private var maxElevation: Double {
        locations.map { $0.altitude }.max() ?? 0
    }

    private var minElevation: Double {
        locations.map { $0.altitude }.min() ?? 0
    }

    private var elevationYMin: Double {
        let range = maxElevation - minElevation
        return minElevation - range * 0.10
    }

    private var elevationYMax: Double {
        let range = maxElevation - minElevation
        return maxElevation + range * 0.10
    }

    private var playbackCoordIndex: Int {
        let idx = Int((playbackProgress * Double(locations.count - 1)).rounded())
        return max(0, min(locations.count - 1, idx))
    }

    private var currentElevation: Double {
        guard !locations.isEmpty else { return 0 }
        return locations[playbackCoordIndex].altitude
    }

    private func elevationString(_ meters: Double) -> String {
        userSettings.isMetric
            ? String(format: "%.0f m", meters)
            : String(format: "%.0f ft", meters * 3.28084)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            if !locations.isEmpty {
                if appleMapStyle.isMapbox {
                    MapboxTrackView(
                        locations: locations,
                        colorMode: trackColorMode,
                        playbackLocation: playbackCoordinate,
                        style: appleMapStyle
                    )
                    .ignoresSafeArea()
                } else {
                    TrackHistoryViewMap(
                        trackHistoryViewMap: $trackHistoryViewMap,
                        locations: locations,
                        style: appleMapStyle,
                        colorMode: trackColorMode,
                        playbackLocation: playbackCoordinate
                    )
                    .ignoresSafeArea()
                }
            }

            trackHeader
        }
        .safeAreaInset(edge: .bottom) {
            statsPanel
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .onAppear {
            _ = loadTrackData()
            currentActivity = ActivityStore.shared.activity(for: trackFilePath.lastPathComponent)
        }
        .onDisappear {
            stopPlayback()
        }
        .sheet(isPresented: $showingMapTypeSheet) {
            AppleMapStyleSheet(selectedStyle: $appleMapStyle)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingColorModeSheet) {
            TrackColorModeSheet(selectedMode: $trackColorMode)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareURL = nil
        }) {
            if let shareURL = shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    // MARK: - Track Header

    private var trackHeader: some View {
        VStack(spacing: 8) {

            // ── Title card ──────────────────────────────────────────────
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Button(action: { showingEditTrackSheet = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    Text(trackName)
                        .font(.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)

                    Menu {
                        Button(action: {
                            exportTrackFile(named: trackFilePath.lastPathComponent)
                        }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        Button(action: { /* TODO */ }) {
                            Label("Add to Map", systemImage: "map")
                        }
                        Button(action: { showingExportCard = true }) {
                            Label("Edit & Share", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                    }
                }

                // Date + activity badge on the same row
                HStack(spacing: 6) {
                    Text(trackDate)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let activity = currentActivity {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(iconForActivity(activity)) \(activity)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(radius: 6)
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // ── Controls row ────────────────────────────────────────────
            HStack(spacing: 8) {
                controlButton(icon: "paintpalette.fill") {
                    showingColorModeSheet = true
                }
                .padding(.leading, 12)

                playbackBar
                    .padding(.horizontal, 4)

                controlButton(icon: "map.fill") {
                    showingMapTypeSheet = true
                }
                .padding(.trailing, 12)
            }
        }
        .fullScreenCover(isPresented: $showingExportCard) {
            TrackExportView(
                locations: locations,
                trackName: trackName,
                trackDate: trackDate,
                cachedStats: cachedStats
            )
            .environmentObject(userSettings)
        }
    }

    // MARK: - Playback Bar

    private var playbackBar: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: max(0, geo.size.width * playbackProgress), height: 4)
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 2)
                        .offset(x: max(0, geo.size.width * playbackProgress - 7))
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            playbackProgress = max(0, min(1, value.location.x / geo.size.width))
                            isDraggingProgress = true
                            if isPlaying { pausePlayback() }
                        }
                        .onEnded { _ in
                            isDraggingProgress = false
                            if isPlaying { startPlaybackTimer() }
                        }
                )
            }
            .frame(height: 20)

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(radius: 4)
    }

    // MARK: - Reusable control button

    @ViewBuilder
    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(radius: 4)
    }

    // MARK: - Elevation Profile Card

    private var elevationProfileCard: some View {
        VStack(spacing: 6) {
            HStack {
                Text("ELEVATION")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(elevationString(currentElevation))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                VStack {
                    Text(elevationString(maxElevation))
                    Spacer()
                    Text(elevationString((maxElevation + minElevation) / 2))
                    Spacer()
                    Text(elevationString(minElevation))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)

                GeometryReader { geo in
                    let chartWidth  = geo.size.width
                    let chartHeight = geo.size.height
                    let elevMin     = elevationYMin
                    let elevMax     = elevationYMax
                    let elevRange   = max(elevMax - elevMin, 1)
                    let xPos        = CGFloat(playbackProgress) * chartWidth
                    let yFraction   = (currentElevation - elevMin) / elevRange
                    let yPos        = chartHeight * (1.0 - CGFloat(yFraction))

                    ZStack(alignment: .topLeading) {
                        Chart(elevationData) { point in
                            AreaMark(
                                x: .value("Index", point.index),
                                y: .value("Elevation", point.elevation)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("Index", point.index),
                                y: .value("Elevation", point.elevation)
                            )
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: elevationYMin...elevationYMax)
                        .frame(width: chartWidth, height: chartHeight)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    playbackProgress = max(0, min(1, value.location.x / chartWidth))
                                    if isPlaying { pausePlayback() }
                                }
                                .onEnded { _ in
                                    if isPlaying { startPlaybackTimer() }
                                }
                        )

                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: chartHeight)
                            .offset(x: xPos)
                            .allowsHitTesting(false)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                            .offset(x: xPos - 5, y: yPos - 5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 100)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.3))
        .cornerRadius(10)
    }

    // MARK: - Playback Logic

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            if playbackProgress >= 1.0 { playbackProgress = 0.0 }
            isPlaying = true
            startPlaybackTimer()
        }
    }

    private func startPlaybackTimer() {
        let fps: Double = 30
        let tickInterval = 1.0 / fps
        let totalTicks = playbackDuration * fps
        let increment = 1.0 / totalTicks

        playbackTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                playbackProgress += increment
                if playbackProgress >= 1.0 {
                    playbackProgress = 1.0
                    stopPlayback()
                }
            }
        }
    }

    private func pausePlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
    }

    // MARK: - Stats Panel

    private let minH: CGFloat = 180
    private let maxH: CGFloat = 440

    private var statsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {

                    if hasAltitudeData && !elevationData.isEmpty {
                        elevationProfileCard
                            .padding(.horizontal)
                            .padding(.top, 20)
                    }

                    if let cached = cachedStats {
                        StatisticsGridView(
                            statistics: createCachedStatistics(
                                entry: cached,
                                isMetric: userSettings.isMetric
                            )
                        )
                    } else if let trackData = trackData {
                        StatisticsGridView(
                            statistics: createStatistics(
                                isMetric: userSettings.isMetric,
                                trackData: trackData
                            )
                        )
                    } else if !locations.isEmpty {
                        StatisticsGridView(
                            statistics: createGPXStatistics(
                                locations: locations,
                                isMetric: userSettings.isMetric
                            )
                        )
                    } else {
                        Text("No stats available")
                            .foregroundColor(.secondary)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: isExpanded ? maxH : minH, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .overlay(alignment: .top) {
            expandCollapseButton
                .offset(y: -10)
        }
        .sheet(isPresented: $showingEditTrackSheet) {
            EditTrackDetailsView(
                trackName: $trackName,
                filePath: trackFilePath,
                onSave: {
                    _ = self.loadTrackData()
                    // Refresh activity display in case it was changed in EditTrackDetailsView
                    currentActivity = ActivityStore.shared.activity(for: trackFilePath.lastPathComponent)
                }
            )
        }
        .shadow(radius: 8)
    }

    private var expandCollapseButton: some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.9)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 25))
                .foregroundStyle(.primary)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 35, height: 35)
                )
        }
    }

    // MARK: - Map Style Sheet

    private struct AppleMapStyleSheet: View {
        @Binding var selectedStyle: AppleMapStyle
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Map Style")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top)

                    appleStyleButton(name: "Default", description: "Standard Apple map.", systemImage: "map", style: .standard)
                    appleStyleButton(name: "Satellite", description: "High-resolution imagery.", systemImage: "globe.americas.fill", style: .satellite)
                    appleStyleButton(name: "Terrain", description: "Topographic map with contour lines.", systemImage: "mountain.2.fill", style: .mapboxTerrain)
                    appleStyleButton(name: "Satellite 3D", description: "Satellite imagery with 3D terrain.", systemImage: "globe.europe.africa.fill", style: .mapboxSatellite)
                }
                .padding()
            }
        }

        @ViewBuilder
        private func appleStyleButton(name: String, description: String, systemImage: String, style: AppleMapStyle) -> some View {
            Button {
                selectedStyle = style
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(name).font(.headline)
                            if selectedStyle == style {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        Text(description).font(.subheadline).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(radius: 3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Map helpers

    private func updateMapViewWithLocations() {
        guard !locations.isEmpty else { return }
        trackHistoryViewMap.removeOverlays(trackHistoryViewMap.overlays)
        let coordinates = locations.map { $0.coordinate }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        trackHistoryViewMap.addOverlay(polyline)
        let region = MKCoordinateRegion(polyline.boundingMapRect)
        trackHistoryViewMap.setRegion(region, animated: false)
    }

    func loadTrackData() -> TrackData? {
        isLoading = true
        let fileName = trackFilePath.lastPathComponent

        if let cache = StatsCache.shared.loadCache(),
           let entry = cache.tracks[fileName] {
            let fileModDate = (try? FileManager.default
                .attributesOfItem(atPath: trackFilePath.path))?[.modificationDate] as? Date
            if let modDate = fileModDate, modDate <= entry.calculatedAt {
                cachedStats = entry
                loadLocationsForMap()
                isLoading = false
                return nil
            }
        }

        do {
            if fileName.hasSuffix(".json") {
                let jsonData = try Data(contentsOf: trackFilePath)
                trackData = try JSONDecoder().decode(TrackData.self, from: jsonData)
                locations = trackData?.locations.map {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                } ?? []
            } else if fileName.hasSuffix(".gpx") {
                let gpxData = try Data(contentsOf: trackFilePath)
                let gpxString = String(data: gpxData, encoding: .utf8) ?? ""
                locations = TrackFileManager.cleanGPXLocations(GPXParser.parseGPX(gpxString))
            }
            StatsCache.shared.addTrack(fileURL: trackFilePath) { _ in
                if let cache = StatsCache.shared.loadCache() {
                    cachedStats = cache.tracks[fileName]
                }
            }
        } catch {
            loadingError = error.localizedDescription
        }

        isLoading = false
        updateMapViewWithLocations()
        return trackData
    }

    private func loadLocationsForMap() {
        if let cached = cachedStats, !cached.simplifiedCoordinates.isEmpty {
            let simplified = cached.simplifiedCoordinates.map {
                CLLocation(latitude: $0[0], longitude: $0[1])
            }
            locations = simplified
            updateMapViewWithLocations()
        }

        let filePath = trackFilePath
        DispatchQueue.global(qos: .background).async {
            var fullLocations: [CLLocation] = []
            let fileName = filePath.lastPathComponent

            if fileName.hasSuffix(".json"),
               let jsonData = try? Data(contentsOf: filePath),
               let td = try? JSONDecoder().decode(TrackData.self, from: jsonData) {
                fullLocations = td.locations.map {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                }
            } else if fileName.hasSuffix(".gpx"),
                      let gpxData = try? Data(contentsOf: filePath),
                      let gpxString = String(data: gpxData, encoding: .utf8) {
                fullLocations = GPXParser.parseGPX(gpxString)
            }

            guard !fullLocations.isEmpty else { return }
            DispatchQueue.main.async {
                locations = fullLocations
                updateMapViewWithLocations()
            }
        }
    }

    private func exportTrackFile(named fileName: String) {
        let fileURL = locationManager.getDocumentsDirectory().appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        shareURL = fileURL
        showShareSheet = true
    }

    // MARK: - Formatters / Statistics

    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0s"
    }

    private func createStatistics(isMetric: Bool, trackData: TrackData) -> [Statistic] {
        let tempLocationManager = LocationManager()
        tempLocationManager.locations = locations
        let maxSpeedMps = tempLocationManager.calculateMaxSpeed(locations: locations)
        let maxSpeed = (isMetric ? maxSpeedMps * 3.6 : maxSpeedMps * 2.23694).rounded(toPlaces: 1)
        let distance = (isMetric ? (trackData.totalDistance ?? 0) / 1000 : (trackData.totalDistance ?? 0) * 0.000621371).rounded(toPlaces: 1)
        let vertical = (isMetric ? (trackData.totalVertical ?? 0) : (trackData.totalVertical ?? 0) * 3.28084).rounded(toPlaces: 1)
        return [
            Statistic(title: "Max Speed", value: "\(maxSpeed) \(isMetric ? "km/h" : "mph")", image1: "speedometer", value1: "", image2: nil, value2: ""),
            Statistic(title: "Distance",  value: "\(distance) \(isMetric ? "km" : "mi")",      image1: "arrow.up.and.down", value1: "", image2: nil, value2: ""),
            Statistic(title: "Vertical",  value: "\(vertical) \(isMetric ? "m" : "ft")",        image1: "arrow.up.and.down", value1: "", image2: nil, value2: ""),
            Statistic(title: "Duration",  value: formatDuration(trackData.recordingDuration ?? 0), image1: "timer", value1: "", image2: nil, value2: "")
        ]
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()

    func formatNumber(_ value: Double, isMetric: Bool, unit: String) -> String {
        StatView.numberFormatter.groupingSeparator = isMetric ? "." : ","
        StatView.numberFormatter.decimalSeparator  = isMetric ? "," : "."
        let formatted = StatView.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted) \(unit)"
    }

    func createGPXStatistics(locations: [CLLocation], isMetric: Bool) -> [Statistic] {
        let locationManager = LocationManager()
        locationManager.locations = locations
        var totalDistanceMeters: Double = 0
        for i in 1..<locations.count { totalDistanceMeters += locations[i].distance(from: locations[i-1]) }
        let maxSpeedMps       = locationManager.calculateMaxSpeed(locations: locations)
        let maxSpeed          = isMetric ? maxSpeedMps * 3.6 : maxSpeedMps * 2.23694
        let avgDownSpeed      = locationManager.calculateAverageDownhillSpeed(isMetric: isMetric)
        let avgUpSpeed        = locationManager.calculateAverageUphillSpeed(isMetric: isMetric)
        let totalDistance     = totalDistanceMeters * (isMetric ? 0.001 : 0.000621371)
        let totalUpDistance   = locationManager.calculateUphillDistance(isMetric: isMetric)
        let totalDownDistance = locationManager.calculateDownhillDistance(isMetric: isMetric)
        let maxElevation      = locationManager.calculateMaxAltitude(isMetric: isMetric)
        let minElevation      = locationManager.calculateMinAltitude(isMetric: isMetric)
        let totalVerticalLoss   = locationManager.calculateVerticalLoss(isMetric: isMetric)
        let totalVerticalGain   = locationManager.calculateVerticalGain(isMetric: isMetric)
        let totalVerticalChange = locationManager.calculateVerticalChange(isMetric: isMetric)
        let upDuration        = locationManager.calculateTimeSpentUphill()
        let downDuration      = locationManager.calculateTimeSpentDownhill()
        return [
            Statistic(title: "Max Speed", value: formatNumber(maxSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph"),
                      image1: "arrow.up.right", value1: formatNumber(avgUpSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph"),
                      image2: "arrow.down.right", value2: formatNumber(avgDownSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph")),
            Statistic(title: "Vertical", value: formatNumber(totalVerticalLoss, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image1: "arrow.up", value1: formatNumber(totalVerticalGain, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image2: "arrow.up.and.down", value2: formatNumber(totalVerticalChange, isMetric: isMetric, unit: isMetric ? "m" : "ft")),
            Statistic(title: "Elevation", value: formatNumber(maxElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image1: "arrow.down.to.line", value1: formatNumber(minElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image2: "arrow.up.and.down", value2: formatNumber(maxElevation - minElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft")),
            Statistic(title: "Distance", value: formatNumber(totalDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi"),
                      image1: "arrow.up.right", value1: formatNumber(totalUpDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi"),
                      image2: "arrow.down.right", value2: formatNumber(totalDownDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi")),
            Statistic(title: "Duration", value: formatDuration(upDuration + downDuration),
                      image1: "arrow.up.right", value1: formatDuration(upDuration),
                      image2: "arrow.down.right", value2: formatDuration(downDuration))
        ]
    }

    func createCachedStatistics(entry: TrackStatsEntry, isMetric: Bool) -> [Statistic] {
        let maxSpeed      = isMetric ? entry.maxSpeedMps * 3.6     : entry.maxSpeedMps * 2.23694
        let avgDownSpeed  = isMetric ? entry.avgDownSpeedMps * 3.6  : entry.avgDownSpeedMps * 2.23694
        let avgUpSpeed    = isMetric ? entry.avgUpSpeedMps * 3.6    : entry.avgUpSpeedMps * 2.23694
        let totalDistance = isMetric ? entry.totalDistanceM / 1000  : entry.totalDistanceM * 0.000621371
        let upDistance    = isMetric ? entry.upDistanceM / 1000     : entry.upDistanceM * 0.000621371
        let downDistance  = isMetric ? entry.downDistanceM / 1000   : entry.downDistanceM * 0.000621371
        let maxElevation  = isMetric ? entry.maxElevationM          : entry.maxElevationM * 3.28084
        let minElevation  = isMetric ? entry.minElevationM          : entry.minElevationM * 3.28084
        let verticalLoss  = isMetric ? entry.verticalLossM          : entry.verticalLossM * 3.28084
        let verticalGain  = isMetric ? entry.verticalGainM          : entry.verticalGainM * 3.28084
        return [
            Statistic(title: "Max Speed", value: formatNumber(maxSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph"),
                      image1: "arrow.up.right", value1: formatNumber(avgUpSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph"),
                      image2: "arrow.down.right", value2: formatNumber(avgDownSpeed, isMetric: isMetric, unit: isMetric ? "km/h" : "mph")),
            Statistic(title: "Vertical", value: formatNumber(verticalLoss, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image1: "arrow.up", value1: formatNumber(verticalGain, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image2: "arrow.up.and.down", value2: formatNumber(verticalLoss + verticalGain, isMetric: isMetric, unit: isMetric ? "m" : "ft")),
            Statistic(title: "Elevation", value: formatNumber(maxElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image1: "arrow.down.to.line", value1: formatNumber(minElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft"),
                      image2: "arrow.up.and.down", value2: formatNumber(maxElevation - minElevation, isMetric: isMetric, unit: isMetric ? "m" : "ft")),
            Statistic(title: "Distance", value: formatNumber(totalDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi"),
                      image1: "arrow.up.right", value1: formatNumber(upDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi"),
                      image2: "arrow.down.right", value2: formatNumber(downDistance, isMetric: isMetric, unit: isMetric ? "km" : "mi")),
            Statistic(title: "Duration", value: formatDuration(entry.upDuration + entry.downDuration),
                      image1: "arrow.up.right", value1: formatDuration(entry.upDuration),
                      image2: "arrow.down.right", value2: formatDuration(entry.downDuration))
        ]
    }

    func extractTrackNameFromGPX(_ gpxString: String) -> String? {
        if let range = gpxString.range(of: "<n>", options: .caseInsensitive),
           let endRange = gpxString.range(of: "</n>", options: .caseInsensitive, range: range.upperBound..<gpxString.endIndex) {
            return String(gpxString[range.upperBound..<endRange.lowerBound])
        }
        return nil
    }
}

// MARK: - Activity Picker Sheet

struct ActivityPickerSheet: View {
    let currentActivity: String?
    let onSelect: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomAlert = false
    @State private var customInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Activities") {
                    ForEach(allActivities(), id: \.self) { activity in
                        Button(action: {
                            onSelect(activity)
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Text(iconForActivity(activity))
                                    .font(.system(size: 22))
                                Text(activity)
                                    .foregroundColor(.primary)
                                Spacer()
                                if currentActivity == activity {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(action: { showingCustomAlert = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 22))
                            Text("Add Custom Activity")
                                .foregroundColor(.orange)
                        }
                    }
                }

                if currentActivity != nil {
                    Section {
                        Button(role: .destructive, action: {
                            onClear()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Remove Activity Tag")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Set Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Activity", isPresented: $showingCustomAlert) {
                TextField("e.g. Paragliding", text: $customInput)
                Button("Add") {
                    let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        ActivityStore.shared.addCustomActivity(trimmed)
                        onSelect(trimmed)
                        dismiss()
                    }
                    customInput = ""
                }
                Button("Cancel", role: .cancel) { customInput = "" }
            } message: {
                Text("Enter a name for your custom activity. It will appear in all future track tagging.")
            }
        }
    }
}

// MARK: - TrackColorModeSheet

struct TrackColorModeSheet: View {
    @Binding var selectedMode: TrackColorMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Track Color")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)

                ForEach(TrackColorMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(mode.rawValue).font(.headline)
                                    if selectedMode == mode {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                                Text(mode.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: mode.icon)
                                .font(.system(size: 26))
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                        .shadow(radius: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

// MARK: - StatisticsGridView / StatisticCard

struct StatisticsGridView: View {
    var statistics: [Statistic]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible())], spacing: 5) {
            ForEach(statistics, id: \.self) { stat in
                if stat.title == "Vertical" {
                    StatisticCard(icon: "arrow.down", statistic: stat, iconColor: .red)
                } else if stat.title == "Elevation" {
                    StatisticCard(icon: "arrow.up.to.line", statistic: stat, iconColor: .green)
                } else {
                    StatisticCard(statistic: stat)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct StatisticCard: View {
    var icon: String? = nil
    let statistic: Statistic
    var image1: String? = nil
    var image2: String? = nil
    var iconColor: Color = .secondary

    var body: some View {
        VStack {
            HStack {
                Text(statistic.title).font(.headline).foregroundColor(.secondary)
                Spacer()
                if let img1 = statistic.image1 { Image(systemName: img1).foregroundColor(colorForIcon(img1)) }
                Text(statistic.value1 ?? "").font(.subheadline).foregroundColor(.secondary)
            }
            HStack {
                if let iconName = icon { Image(systemName: iconName).foregroundColor(iconColor) }
                let iconName = iconForStatistic(statistic.title)
                if !iconName.isEmpty { Image(systemName: iconName).foregroundColor(colorForStatistic(statistic.title)) }
                Text(statistic.value).font(.title3).fontWeight(.bold).foregroundColor(.primary)
                Spacer()
                if let img2 = statistic.image2 { Image(systemName: img2).foregroundColor(colorForIcon(img2)) }
                Text(statistic.value2 ?? "").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(5)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(Color.secondary.opacity(0.3))
        .cornerRadius(10)
    }

    func iconForStatistic(_ title: String) -> String {
        switch title {
        case "Max Speed": return "gauge.with.dots.needle.100percent"
        case "Distance":  return "arrow.up.and.down"
        case "Duration", "Record Time": return "clock"
        case "Altitude":  return "mountain.2.circle"
        case "Days":      return "calendar.circle"
        default:          return ""
        }
    }

    func colorForStatistic(_ title: String) -> Color {
        switch title {
        case "Max Speed":                          return .blue
        case "Distance":                           return .blue
        case "Elevation", "Vertical", "Altitude": return .orange
        case "Duration":                           return .purple
        case "Days", "Record Time":                return .red
        default:                                   return .gray
        }
    }

    func colorForIcon(_ imageName: String?) -> Color {
        guard let imageName = imageName else { return .gray }
        switch imageName {
        case "arrow.up", "arrow.up.to.line", "arrow.up.right":       return .green
        case "arrow.down", "arrow.down.to.line", "arrow.down.right": return .red
        case "arrow.up.and.down", "gauge.with.dots.needle.50percent": return .blue
        default: return .gray
        }
    }
}
