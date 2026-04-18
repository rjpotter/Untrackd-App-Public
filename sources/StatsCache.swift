//
//  StatsCache.swift
//  SnowCountry
//
//  Created by Ryan Potter on 3/21/26.
//

import Foundation
import CoreLocation

// MARK: - Activity Store

/// Lightweight, separately persisted store for track activity types.
/// Stored as [fileName: activityName] so custom activities work seamlessly.
/// Lives in its own JSON file so cache rebuilds never wipe activity assignments.
class ActivityStore {
    static let shared = ActivityStore()

    private let fileName = "activities.json"
    private var store: [String: String] = [:]

    private var storeURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        store = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    func activity(for fileName: String) -> String? {
        store[fileName]
    }

    func setActivity(_ activity: String, for fileName: String) {
        store[fileName] = activity
        save()
        NotificationCenter.default.post(name: NSNotification.Name("ActivityStoreUpdated"), object: nil)
    }

    func removeActivity(for fileName: String) {
        store.removeValue(forKey: fileName)
        save()
    }

    /// All activity assignments, keyed by fileName
    var all: [String: String] { store }

    // MARK: - Custom Activity Management

    private let customActivitiesKey = "customActivities"

    var customActivities: [String] {
        get { UserDefaults.standard.stringArray(forKey: customActivitiesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: customActivitiesKey) }
    }

    func addCustomActivity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customActivities.contains(trimmed) else { return }
        var current = customActivities
        current.append(trimmed)
        customActivities = current
    }

    func removeCustomActivity(_ name: String) {
        customActivities = customActivities.filter { $0 != name }
    }
}

// MARK: - Built-in Activity Types

enum BuiltInActivity: String, CaseIterable {
    case skiing          = "Skiing"
    case snowboarding    = "Snowboarding"
    case hiking          = "Hiking"
    case skiTouring      = "Ski Touring / Skinning"
    case snowshoeing     = "Snowshoeing"
    case biking          = "Biking"
    case running         = "Running"
    case crossCountry    = "Cross Country Skiing"
    case other           = "Other"

    var icon: String {
        switch self {
        case .skiing:       return "⛷️"
        case .snowboarding: return "🏂"
        case .hiking:       return "🥾"
        case .skiTouring:   return "🎿"
        case .snowshoeing:  return "🏔️"
        case .biking:       return "🚴"
        case .running:      return "🏃"
        case .crossCountry: return "🎿"
        case .other:        return "🏅"
        }
    }
}

/// Returns all available activities: built-in + any user-defined custom ones
func allActivities() -> [String] {
    BuiltInActivity.allCases.map { $0.rawValue } + ActivityStore.shared.customActivities
}

func iconForActivity(_ name: String) -> String {
    BuiltInActivity(rawValue: name)?.icon ?? "🏅"
}

// MARK: - Season Helpers

/// Ski seasons run September → August. "2024-2025" covers Sep 2024 – Aug 2025.
func seasonKey(for date: Date) -> String {
    let cal = Calendar.current
    let year = cal.component(.year, from: date)
    let month = cal.component(.month, from: date)
    // Sep–Dec → season starts this year; Jan–Aug → season started last year
    let startYear = month >= 9 ? year : year - 1
    return "\(startYear)-\(startYear + 1)"
}

func seasonDisplayName(_ key: String) -> String {
    // "2024-2025" → "2024 – 2025 Season"
    let parts = key.split(separator: "-")
    guard parts.count == 2 else { return key }
    return "\(parts[0]) – \(parts[1]) Season"
}

/// "2024-2025" → "'24-'25 Season"
func shortSeasonName(_ key: String) -> String {
    let parts = key.split(separator: "-")
    guard parts.count == 2 else { return key }
    let start = String(parts[0].suffix(2))
    let end   = String(parts[1].suffix(2))
    return "'\(start)-'\(end) Season"
}

// MARK: - Data Models

struct TrackStatsEntry: Codable {
    let fileName: String
    let trackName: String
    let maxSpeedMps: Double
    let avgDownSpeedMps: Double
    let avgUpSpeedMps: Double
    let totalDistanceM: Double
    let upDistanceM: Double
    let downDistanceM: Double
    let maxElevationM: Double
    let minElevationM: Double
    let verticalLossM: Double
    let verticalGainM: Double
    let upDuration: TimeInterval
    let downDuration: TimeInterval
    let date: Date
    let calculatedAt: Date
    let simplifiedCoordinates: [[Double]]
    // activityType is NOT stored here — lives in ActivityStore to avoid cache rebuilds
}

extension TrackStatsEntry: Identifiable {
    var id: String { fileName }
}

/// Runtime-only helper that pairs a TrackStatsEntry with its activity (from ActivityStore)
extension TrackStatsEntry {
    var activityType: String? {
        ActivityStore.shared.activity(for: fileName)
    }
}

struct LifetimeStatsCache: Codable {
    var topSpeedMps: Double
    var topSpeedFile: String
    var totalDownVerticalM: Double
    var totalDownDistanceM: Double
    var totalDuration: TimeInterval
    var totalDays: Int
    var lastUpdated: Date
}

/// Season-scoped stats — computed on demand, stored locally only (no Firebase)
struct SeasonStats {
    let season: String           // e.g. "2024-2025"
    let topSpeedMps: Double
    let topSpeedFile: String
    let totalDownVerticalM: Double
    let totalDownDistanceM: Double
    let totalDuration: TimeInterval
    let totalDays: Int
    let tracks: [TrackStatsEntry]

    static func build(season: String, from tracks: [TrackStatsEntry]) -> SeasonStats {
        let filtered = tracks.filter { seasonKey(for: $0.date) == season }
        let calendar = Calendar.current
        let uniqueDays = Set(filtered.map { calendar.startOfDay(for: $0.date) })

        var topSpeedMps = 0.0
        var topSpeedFile = ""
        var totalDownVerticalM = 0.0
        var totalDownDistanceM = 0.0
        var totalDuration = 0.0

        for entry in filtered {
            if entry.maxSpeedMps > topSpeedMps {
                topSpeedMps = entry.maxSpeedMps
                topSpeedFile = entry.fileName
            }
            totalDownVerticalM += entry.verticalLossM
            totalDownDistanceM += entry.downDistanceM
            totalDuration += entry.upDuration + entry.downDuration
        }

        return SeasonStats(
            season: season,
            topSpeedMps: topSpeedMps,
            topSpeedFile: topSpeedFile,
            totalDownVerticalM: totalDownVerticalM,
            totalDownDistanceM: totalDownDistanceM,
            totalDuration: totalDuration,
            totalDays: uniqueDays.count,
            tracks: filtered
        )
    }
}

struct StatsCacheFile: Codable {
    var lifetime: LifetimeStatsCache
    var tracks: [String: TrackStatsEntry]  // keyed by fileName
}

// MARK: - StatsCache Manager

class StatsCache {
    static let shared = StatsCache()
    
    private let cacheFileName = "stats_cache.json"
    private var cache: StatsCacheFile?
    
    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }
    
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Load / Save Cache
    
    func loadCache() -> StatsCacheFile? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(StatsCacheFile.self, from: data) else {
            return nil
        }
        self.cache = cache
        return cache
    }
    
    private func saveCache(_ cache: StatsCacheFile) {
        self.cache = cache
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: - Season Helpers

    /// Returns all seasons present in the cache, sorted newest first
    func availableSeasons() -> [String] {
        guard let cache = cache ?? loadCache() else { return [] }
        let seasons = Set(cache.tracks.values.map { seasonKey(for: $0.date) })
        return seasons.sorted().reversed()
    }

    /// Returns SeasonStats for a given season key
    func seasonStats(for season: String) -> SeasonStats {
        let loaded = cache ?? loadCache()
        let all: [TrackStatsEntry] = loaded.map { Array($0.tracks.values) } ?? []
        return SeasonStats.build(season: season, from: all)
    }

    // MARK: - Activity Helpers

    /// Most popular activity by number of tracks, returns (activityName, count) or nil
    func mostPopularActivity(from tracks: [TrackStatsEntry]? = nil) -> (String, Int)? {
        let loaded = cache ?? loadCache()
        let source: [TrackStatsEntry] = tracks ?? loaded.map { Array($0.tracks.values) } ?? []
        var counts: [String: Int] = [:]
        for entry in source {
            if let activity = ActivityStore.shared.activity(for: entry.fileName) {
                counts[activity, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return nil }
        return counts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    /// Activity breakdown: [(activityName, count)] sorted by count descending
    func activityBreakdown(from tracks: [TrackStatsEntry]? = nil) -> [(String, Int)] {
        let loaded = cache ?? loadCache()
        let source: [TrackStatsEntry] = tracks ?? loaded.map { Array($0.tracks.values) } ?? []
        var counts: [String: Int] = [:]
        for entry in source {
            if let activity = ActivityStore.shared.activity(for: entry.fileName) {
                counts[activity, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
    }

    // MARK: - Build Cache (one-time / full rebuild)
    
    func buildCache(completion: @escaping (StatsCacheFile) -> Void) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: self.documentsURL,
                includingPropertiesForKeys: nil
            ) else { return }
            
            let trackFiles = files.filter {
                $0.pathExtension.lowercased() == "gpx" ||
                $0.pathExtension.lowercased() == "json"
            }
            
            print("📊 Building stats cache for \(trackFiles.count) files...")
            
            var tracks: [String: TrackStatsEntry] = [:]
            var uniqueDays: Set<Date> = []
            let calendar = Calendar.current
            
            for fileURL in trackFiles {
                guard let entry = self.calculateStatsEntry(for: fileURL) else { continue }
                tracks[entry.fileName] = entry
                let day = calendar.startOfDay(for: entry.date)
                uniqueDays.insert(day)
                print("✅ Cached: \(entry.fileName) — \(String(format: "%.1f", entry.maxSpeedMps * 2.23694)) mph")
            }
            
            let lifetime = self.buildLifetimeFromTracks(tracks: tracks, uniqueDays: uniqueDays)
            let cacheFile = StatsCacheFile(lifetime: lifetime, tracks: tracks)
            self.saveCache(cacheFile)
            
            print("────────────────────────────")
            print("✅ Cache built: \(tracks.count) tracks, \(lifetime.totalDays) days")
            print("   Top Speed: \(String(format: "%.1f", lifetime.topSpeedMps * 2.23694)) mph — \(lifetime.topSpeedFile)")
            print("   Vertical:  \(String(format: "%.0f", lifetime.totalDownVerticalM * 3.28084)) ft")
            print("   Distance:  \(String(format: "%.1f", lifetime.totalDownDistanceM * 0.000621371)) mi")
            print("────────────────────────────")
            
            DispatchQueue.main.async {
                completion(cacheFile)
            }
        }
    }
    
    // MARK: - Add Track (after save or import)
    
    func addTrack(fileURL: URL, completion: @escaping (StatsCacheFile) -> Void) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            guard let entry = self.calculateStatsEntry(for: fileURL) else { return }
            
            var current = self.cache ?? StatsCacheFile(
                lifetime: LifetimeStatsCache(
                    topSpeedMps: 0, topSpeedFile: "",
                    totalDownVerticalM: 0, totalDownDistanceM: 0,
                    totalDuration: 0, totalDays: 0,
                    lastUpdated: Date()
                ),
                tracks: [:]
            )
            
            current.tracks[entry.fileName] = entry
            
            let calendar = Calendar.current
            let uniqueDays = Set(current.tracks.values.map {
                calendar.startOfDay(for: $0.date)
            })
            current.lifetime = self.buildLifetimeFromTracks(
                tracks: current.tracks,
                uniqueDays: uniqueDays
            )
            
            self.saveCache(current)
            print("✅ Added to cache: \(entry.fileName)")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("StatsCacheUpdated"),
                    object: current
                )
                completion(current)
            }
        }
    }

    func removeTrack(fileName: String, completion: @escaping (StatsCacheFile) -> Void) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            guard var current = self.cache ?? self.loadCache() else { return }
            
            current.tracks.removeValue(forKey: fileName)
            ActivityStore.shared.removeActivity(for: fileName) // clean up activity too
            
            let calendar = Calendar.current
            let uniqueDays = Set(current.tracks.values.map {
                calendar.startOfDay(for: $0.date)
            })
            current.lifetime = self.buildLifetimeFromTracks(
                tracks: current.tracks,
                uniqueDays: uniqueDays
            )
            
            self.saveCache(current)
            print("🗑️ Removed from cache: \(fileName)")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("StatsCacheUpdated"),
                    object: current
                )
                completion(current)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateStatsEntry(for fileURL: URL) -> TrackStatsEntry? {
        let fileName = fileURL.lastPathComponent
        
        var locations: [CLLocation] = []
        
        if fileURL.pathExtension.lowercased() == "gpx" {
            guard let gpxString = try? String(contentsOf: fileURL) else { return nil }
            let raw = GPXParser.parseGPX(gpxString)
            locations = TrackFileManager.cleanGPXLocations(raw)
        } else if fileURL.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let trackData = try? JSONDecoder().decode(TrackData.self, from: data) else { return nil }
            locations = trackData.locations.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
        
        // Extract track name
        var trackName = fileName
        if fileURL.pathExtension.lowercased() == "gpx",
           let gpxString = try? String(contentsOf: fileURL) {
            if let range = gpxString.range(of: "<name>", options: .caseInsensitive),
               let endRange = gpxString.range(of: "</name>", options: .caseInsensitive, range: range.upperBound..<gpxString.endIndex) {
                let extracted = String(gpxString[range.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty { trackName = extracted }
            }
        } else if fileURL.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: fileURL),
                  let trackData = try? JSONDecoder().decode(TrackData.self, from: data) {
            trackName = trackData.trackName ?? fileName
        }
        
        guard !locations.isEmpty, let firstLocation = locations.first else { return nil }
        
        let maxSpeedMps = calculateMaxSpeed(locations: locations)
        let avgDownSpeedMps = calculateDownhillAvgSpeed(locations: locations, isMetric: true) / 3.6
        let avgUpSpeedMps = calculateUphillAvgSpeed(locations: locations, isMetric: true) / 3.6
        
        var totalDistanceM = 0.0
        for i in 1..<locations.count {
            totalDistanceM += locations[i].distance(from: locations[i-1])
        }
        
        let upDistanceM = calculateTotalUpDistance(locations: locations, isMetric: true) * 1000
        let downDistanceM = calculateTotalDownDistance(locations: locations, isMetric: true) * 1000
        let maxElevationM = calculateMaxAltitude(locations: locations, isMetric: true)
        let minElevationM = calculateMinElevation(locations: locations, isMetric: true)
        let verticalLossM = calculateRawVerticalLoss(locations: locations)
        
        var verticalGainM = 0.0
        for i in 1..<locations.count {
            let gain = locations[i].altitude - locations[i-1].altitude
            if gain > 0 { verticalGainM += gain }
        }
        
        let upDuration = calculateTimeSpentUphill(locations: locations)
        let downDuration = calculateTimeSpentDownhill(locations: locations)
        
        let simplifiedCoordinates = StatsCache.simplifyCoordinates(locations, epsilon: 0.0001)
        print("📍 Simplified \(locations.count) → \(simplifiedCoordinates.count) points")
        
        return TrackStatsEntry(
            fileName: fileName,
            trackName: trackName,
            maxSpeedMps: maxSpeedMps,
            avgDownSpeedMps: avgDownSpeedMps,
            avgUpSpeedMps: avgUpSpeedMps,
            totalDistanceM: totalDistanceM,
            upDistanceM: upDistanceM,
            downDistanceM: downDistanceM,
            maxElevationM: maxElevationM,
            minElevationM: minElevationM,
            verticalLossM: verticalLossM,
            verticalGainM: verticalGainM,
            upDuration: upDuration,
            downDuration: downDuration,
            date: firstLocation.timestamp,
            calculatedAt: Date(),
            simplifiedCoordinates: simplifiedCoordinates
        )
    }
    
    private func buildLifetimeFromTracks(
        tracks: [String: TrackStatsEntry],
        uniqueDays: Set<Date>
    ) -> LifetimeStatsCache {
        var topSpeedMps = 0.0
        var topSpeedFile = ""
        var totalDownVerticalM = 0.0
        var totalDownDistanceM = 0.0
        var totalDuration = 0.0
        
        for (_, entry) in tracks {
            if entry.maxSpeedMps > topSpeedMps {
                topSpeedMps = entry.maxSpeedMps
                topSpeedFile = entry.fileName
            }
            totalDownVerticalM += entry.verticalLossM
            totalDownDistanceM += entry.downDistanceM
            totalDuration += entry.upDuration + entry.downDuration
        }
        
        return LifetimeStatsCache(
            topSpeedMps: topSpeedMps,
            topSpeedFile: topSpeedFile,
            totalDownVerticalM: totalDownVerticalM,
            totalDownDistanceM: totalDownDistanceM,
            totalDuration: totalDuration,
            totalDays: uniqueDays.count,
            lastUpdated: Date()
        )
    }
    
    func verifyCacheIntegrity(completion: @escaping (StatsCacheFile) -> Void) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: self.documentsURL,
                includingPropertiesForKeys: nil
            ) else { return }
            
            let trackFileNames = Set(files
                .filter { $0.pathExtension.lowercased() == "gpx" || $0.pathExtension.lowercased() == "json" }
                .map { $0.lastPathComponent }
            )
            
            guard var cache = self.loadCache() else {
                self.buildCache(completion: completion)
                return
            }
            
            let cachedFileNames = Set(cache.tracks.keys)
            let missing = trackFileNames.subtracting(cachedFileNames)
            let orphaned = cachedFileNames.subtracting(trackFileNames)
            
            if missing.isEmpty && orphaned.isEmpty {
                print("✅ Cache verified — no changes needed")
                DispatchQueue.main.async { completion(cache) }
                return
            }
            
            print("🔧 Cache out of sync — fixing \(missing.count) missing, \(orphaned.count) orphaned")
            
            for fileName in orphaned {
                cache.tracks.removeValue(forKey: fileName)
            }
            
            for fileName in missing {
                let fileURL = self.documentsURL.appendingPathComponent(fileName)
                if let entry = self.calculateStatsEntry(for: fileURL) {
                    cache.tracks[entry.fileName] = entry
                }
            }
            
            let calendar = Calendar.current
            let uniqueDays = Set(cache.tracks.values.map { calendar.startOfDay(for: $0.date) })
            cache.lifetime = self.buildLifetimeFromTracks(tracks: cache.tracks, uniqueDays: uniqueDays)
            self.saveCache(cache)
            
            print("✅ Cache repaired: \(cache.tracks.count) tracks")
            DispatchQueue.main.async { completion(cache) }
        }
    }
    
    // MARK: - Douglas-Peucker Simplification

    static func simplifyCoordinates(_ locations: [CLLocation], epsilon: Double = 0.0001) -> [[Double]] {
        guard locations.count > 2 else {
            return locations.map { [$0.coordinate.latitude, $0.coordinate.longitude] }
        }
        
        var maxDistance = 0.0
        var maxIndex = 0
        
        let first = locations.first!
        let last = locations.last!
        
        for i in 1..<locations.count - 1 {
            let distance = perpendicularDistance(locations[i], from: first, to: last)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }
        
        if maxDistance > epsilon {
            let left = simplifyCoordinates(Array(locations[0...maxIndex]), epsilon: epsilon)
            let right = simplifyCoordinates(Array(locations[maxIndex...locations.count-1]), epsilon: epsilon)
            return left.dropLast() + right
        } else {
            return [
                [first.coordinate.latitude, first.coordinate.longitude],
                [last.coordinate.latitude, last.coordinate.longitude]
            ]
        }
    }

    private static func perpendicularDistance(_ point: CLLocation, from lineStart: CLLocation, to lineEnd: CLLocation) -> Double {
        let x0 = point.coordinate.latitude
        let y0 = point.coordinate.longitude
        let x1 = lineStart.coordinate.latitude
        let y1 = lineStart.coordinate.longitude
        let x2 = lineEnd.coordinate.latitude
        let y2 = lineEnd.coordinate.longitude
        
        let dx = x2 - x1
        let dy = y2 - y1
        
        guard dx != 0 || dy != 0 else {
            return sqrt(pow(x0 - x1, 2) + pow(y0 - y1, 2))
        }
        
        let numerator = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1)
        let denominator = sqrt(dx * dx + dy * dy)
        return numerator / denominator
    }
    
    func invalidateCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        cache = nil
        print("🗑️ Cache invalidated — will rebuild on next launch")
    }
    
    func rebuildCacheInBackground(completion: @escaping (StatsCacheFile) -> Void) {
        invalidateCache()
        buildCache(completion: completion)
    }
}
