//
//  ProfileViewModel.swift
//  SnowCountry
//
//  Created by Ryan Potter on 2/23/24.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

class ProfileViewModel: ObservableObject {
    @Published var lifetimeStats: LifetimeStats = LifetimeStats()
    @Published var totalTracks: Int = 0

    // MARK: - Season / Filter State

    /// "Lifetime" or a season key like "2024-2025"
    @Published var selectedSeason: String = "Lifetime" {
        didSet { refreshSeasonStats() }
    }

    /// Sorted newest-first list of seasons found in cache. "Lifetime" is always first.
    @Published var availableSeasons: [String] = ["Lifetime"]

    /// Stats for the currently selected season (or lifetime if "Lifetime" selected)
    @Published var currentSeasonStats: DisplayStats = DisplayStats()

    /// Most popular activity name + count for the current scope
    @Published var mostPopularActivity: (name: String, count: Int)? = nil

    /// Activity breakdown for current scope [(name, count)] sorted by count
    @Published var activityBreakdown: [(name: String, count: Int)] = []
    
    @Published var selectedActivityFilter: String? = nil {
        didSet { refreshSeasonStats() }
    }

    // MARK: - Private

    private var locationManager: LocationManager
    private var userSettings: UserSettings
    private var trackFiles: [String] = []
    let user: User

    // Cached tracks array — refreshed whenever StatsCacheUpdated fires
    private var allTracks: [TrackStatsEntry] = []

    init(user: User, locationManager: LocationManager, userSettings: UserSettings) {
        self.user = user
        self.locationManager = locationManager
        self.userSettings = userSettings

        // Only load local cache for the current user — never for friends
        if user.id == Auth.auth().currentUser?.uid {
            if let cache = StatsCache.shared.loadCache() {
                allTracks = Array(cache.tracks.values)
                DispatchQueue.main.async {
                    self.lifetimeStats.topSpeed = cache.lifetime.topSpeedMps * 3.6
                    self.lifetimeStats.totalDownVertical = cache.lifetime.totalDownVerticalM
                    self.lifetimeStats.totalDownDistance = cache.lifetime.totalDownDistanceM
                    self.lifetimeStats.totalDuration = cache.lifetime.totalDuration
                    self.lifetimeStats.totalDays = cache.lifetime.totalDays
                    self.refreshAvailableSeasons()
                    self.refreshSeasonStats()
                }
            }
        }
        self.totalTracks = allTracks.count

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StatsCacheUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let cache = notification.object as? StatsCacheFile else { return }
            guard self.user.id == Auth.auth().currentUser?.uid else { return }
            let newDays = cache.lifetime.totalDays
            let newSpeed = cache.lifetime.topSpeedMps * 3.6
            guard newDays != self.lifetimeStats.totalDays ||
                  newSpeed != self.lifetimeStats.topSpeed else { return }
            self.allTracks = Array(cache.tracks.values)
            self.totalTracks = Array(cache.tracks.values).count
            self.applyLifetimeCache(cache.lifetime)
            self.refreshAvailableSeasons()
            self.refreshSeasonStats()
            self.syncToFirebase { }
        }

        // Refresh activity display when ActivityStore changes (e.g. user sets an activity in StatView)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ActivityStoreUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  self.user.id == Auth.auth().currentUser?.uid else { return }
            self.refreshSeasonStats()
        }
    }

    // MARK: - Season Refresh

    private func refreshAvailableSeasons() {
        let seasons = Set(allTracks.map { seasonKey(for: $0.date) })
        let sorted = seasons.sorted().reversed()
        availableSeasons = ["Lifetime"] + sorted
    }

    private func refreshSeasonStats() {
        // Step 1: Filter by season only
        var scopedTracks: [TrackStatsEntry]
        if selectedSeason == "Lifetime" {
            scopedTracks = allTracks
        } else {
            scopedTracks = allTracks.filter { seasonKey(for: $0.date) == selectedSeason }
        }

        // Step 2: Compute activity breakdown from season-only tracks (before activity filter)
        // so the activity menu always shows all activities available in this season
        let breakdown = StatsCache.shared.activityBreakdown(from: scopedTracks)
        activityBreakdown = breakdown.map { (name: $0.0, count: $0.1) }
        if let top = breakdown.first {
            mostPopularActivity = (name: top.0, count: top.1)
        } else {
            mostPopularActivity = nil
        }

        // Step 3: Apply activity filter on top of season filter
        if let activityFilter = selectedActivityFilter {
            scopedTracks = scopedTracks.filter {
                ActivityStore.shared.activity(for: $0.fileName) == activityFilter
            }
        }

        // Step 4: Aggregate stats from fully filtered tracks
        let calendar = Calendar.current
        let uniqueDays = Set(scopedTracks.map { calendar.startOfDay(for: $0.date) })
        var topSpeedMps = 0.0
        var topSpeedFile = ""
        var totalVerticalM = 0.0
        var totalDistanceM = 0.0
        var totalDuration = 0.0

        for entry in scopedTracks {
            if entry.maxSpeedMps > topSpeedMps {
                topSpeedMps = entry.maxSpeedMps
                topSpeedFile = entry.fileName
            }
            totalVerticalM += entry.verticalLossM
            totalDistanceM += entry.downDistanceM
            totalDuration += entry.upDuration + entry.downDuration
        }

        currentSeasonStats = DisplayStats(
            topSpeedMps: topSpeedMps,
            topSpeedFile: topSpeedFile,
            totalDownVerticalM: totalVerticalM,
            totalDownDistanceM: totalDistanceM,
            totalDuration: totalDuration,
            totalDays: uniqueDays.count,
            tracks: scopedTracks
        )
    }
    
    // MARK: - Public Helpers

    /// All tracks filtered to the current selected season (or all if Lifetime)
    var scopedTracks: [TrackStatsEntry] {
        currentSeasonStats.tracks
    }

    // MARK: - Existing Methods

    func updateAndFetchLifetimeStats(completion: @escaping () -> Void) {
        if let cache = StatsCache.shared.loadCache() {
            allTracks = Array(cache.tracks.values)
            applyLifetimeCache(cache.lifetime)
            refreshAvailableSeasons()
            refreshSeasonStats()
            syncToFirebase(completion: completion)
        } else {
            StatsCache.shared.buildCache { [weak self] cache in
                guard let self = self else { return }
                self.allTracks = Array(cache.tracks.values)
                self.applyLifetimeCache(cache.lifetime)
                self.refreshAvailableSeasons()
                self.refreshSeasonStats()
                self.syncToFirebase(completion: completion)
            }
        }
    }

    func fetchLifetimeStatsFromFirebase(completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(user.id)

        userRef.getDocument { [weak self] (document, error) in
            guard let self = self else { return }

            if let error = error {
                completion()
                return
            }

            guard let document = document, document.exists else {
                completion()
                return
            }

            DispatchQueue.main.async {
                if let data = document.data()?["lifetimeStats"] as? [String: Any] {
                    self.lifetimeStats.totalDays = data["totalDays"] as? Int ?? 0
                    self.lifetimeStats.totalDownVertical = data["totalDownVertical"] as? Double ?? 0.0
                    self.lifetimeStats.totalDownDistance = data["totalDownDistance"] as? Double ?? 0.0
                    self.lifetimeStats.topSpeed = data["topSpeed"] as? Double ?? 0.0
                    self.lifetimeStats.totalDuration = data["totalDuration"] as? TimeInterval ?? 0.0
                    self.lifetimeStats.totalTracks = data["totalTracks"] as? Int ?? 0
                    self.totalTracks = data["totalTracks"] as? Int ?? 0
                } else if let data = document.data() {
                    self.lifetimeStats.totalDays = data["totalDays"] as? Int ?? 0
                    self.lifetimeStats.totalDownVertical = data["totalDownVertical"] as? Double ?? 0.0
                    self.lifetimeStats.totalDownDistance = data["totalDownDistance"] as? Double ?? 0.0
                    self.lifetimeStats.topSpeed = data["topSpeed"] as? Double ?? 0.0
                    self.lifetimeStats.totalDuration = data["totalDuration"] as? TimeInterval ?? 0.0
                    self.lifetimeStats.totalTracks = data["totalTracks"] as? Int ?? 0
                    self.totalTracks = data["totalTracks"] as? Int ?? 0
                }
                completion()
            }
        }
    }

    func loadTrackFiles() {
        let trackFilenames = locationManager.getTrackFiles().sorted(by: { $1 > $0 })
        self.trackFiles = trackFilenames
    }
    
    func updateLifetimeStats() {
        if let cache = StatsCache.shared.loadCache() {
            allTracks = Array(cache.tracks.values)
            applyLifetimeCache(cache.lifetime)
            refreshAvailableSeasons()
            refreshSeasonStats()
        } else {
            StatsCache.shared.buildCache { [weak self] cache in
                guard let self = self else { return }
                self.allTracks = Array(cache.tracks.values)
                self.applyLifetimeCache(cache.lifetime)
                self.refreshAvailableSeasons()
                self.refreshSeasonStats()
            }
        }
    }

    func applyLifetimeCache(_ lifetime: LifetimeStatsCache) {
        DispatchQueue.main.async {
            guard lifetime.totalDays > 0 else { return }
            self.lifetimeStats.topSpeed = lifetime.topSpeedMps * 3.6
            self.lifetimeStats.totalDownVertical = lifetime.totalDownVerticalM
            self.lifetimeStats.totalDownDistance = lifetime.totalDownDistanceM
            self.lifetimeStats.totalDuration = lifetime.totalDuration
            self.lifetimeStats.totalDays = lifetime.totalDays
        }
    }
    
    private func syncToFirebase(completion: @escaping () -> Void) {
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(self.user.id)
        let statsData: [String: Any] = [
            "totalDays": self.lifetimeStats.totalDays,
            "totalDownVertical": self.lifetimeStats.totalDownVertical,
            "totalDownDistance": self.lifetimeStats.totalDownDistance,
            "topSpeed": self.lifetimeStats.topSpeed,
            "totalDuration": self.lifetimeStats.totalDuration,
            "totalTracks": self.totalTracks   // ← new
        ]
        let batch = db.batch()
        batch.setData(["lifetimeStats": statsData], forDocument: userRef, merge: true)
        batch.commit { error in
            if let error = error {
                print("Error updating Firebase: \(error)")
            } else {
                print("✅ Firebase synced")
            }
            completion()
        }
    }

    // MARK: - Formatting

    func convertSpeed(_ speed: Double, toMetric: Bool) -> Double {
        if !toMetric {
            return speed
        } else {
            return speed * 0.621371
        }
    }
    
    func formattedTime(time: TimeInterval) -> String {
        let seconds = Int(time)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        var timeString = ""
        if days > 0 { timeString += "\(days) day\(days == 1 ? "" : "s")" }
        if hours > 0 {
            if !timeString.isEmpty { timeString += " " }
            timeString += "\(hours) hr"
        }
        return timeString.isEmpty ? "0 hr" : timeString
    }
    
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter
    }()

    func formatNumber(_ value: Double, isMetric: Bool, unit: String) -> String {
        ProfileViewModel.numberFormatter.groupingSeparator = isMetric ? "." : ","
        ProfileViewModel.numberFormatter.decimalSeparator = isMetric ? "," : "."
        let number = NSNumber(value: value)
        let formattedValue = ProfileViewModel.numberFormatter.string(from: number) ?? "\(value)"
        return "\(formattedValue) \(unit)"
    }
    
    func formatDistance(_ distance: Double) -> String {
        let unit = userSettings.isMetric ? "km" : "mi"
        let convertedDistance = userSettings.isMetric ? distance / 1000 : distance * 0.000621371
        return formatNumber(convertedDistance, isMetric: userSettings.isMetric, unit: unit)
    }

    func formatSpeed(_ speed: Double) -> String {
        let unit = userSettings.isMetric ? "km/h" : "mph"
        let convertedSpeed = userSettings.isMetric ? speed : speed * 0.621371
        return formatNumber(convertedSpeed, isMetric: userSettings.isMetric, unit: unit)
    }

    func formatElevation(_ elevation: Double) -> String {
        let unit = userSettings.isMetric ? "m" : "ft"
        let convertedElevation = userSettings.isMetric ? elevation : elevation * 3.28084
        return formatNumber(convertedElevation, isMetric: userSettings.isMetric, unit: unit)
    }
}

// MARK: - DisplayStats

/// Aggregated stats for either lifetime or a specific season scope.
/// Mirrors LifetimeStatsCache but also carries the filtered track array
/// so detail views can drill in without re-filtering.
struct DisplayStats {
    var topSpeedMps: Double = 0
    var topSpeedFile: String = ""
    var totalDownVerticalM: Double = 0
    var totalDownDistanceM: Double = 0
    var totalDuration: TimeInterval = 0
    var totalDays: Int = 0
    var tracks: [TrackStatsEntry] = []

    var isEmpty: Bool { tracks.isEmpty }
}
