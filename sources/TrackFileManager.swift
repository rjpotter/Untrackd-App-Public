//
//  TrackFileManager.swift
//  SnowCountry
//
//  Created by Ryan Potter on 3/21/26.
//

import Foundation
import CoreLocation

class TrackFileManager {

    static func importFile(
        result: Result<[URL], Error>,
        onLocationsLoaded: ([CLLocation]) -> Void,
        onTrackDataLoaded: (TrackData) -> Void,
        onMessage: (String) -> Void
    ) {
        switch result {
        case .success(let urls):
            for selectedFile in urls {
                let startAccessing = selectedFile.startAccessingSecurityScopedResource()
                defer { selectedFile.stopAccessingSecurityScopedResource() }
                if startAccessing {
                    do {
                        let fileManager = FileManager.default
                        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let destinationURL = documentDirectory.appendingPathComponent(selectedFile.lastPathComponent)
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            try fileManager.removeItem(at: destinationURL)
                        }
                        try fileManager.copyItem(at: selectedFile, to: destinationURL)
                        let data = try Data(contentsOf: selectedFile)
                        if selectedFile.pathExtension == "json" {
                            let decodedData = try JSONDecoder().decode(TrackData.self, from: data)
                            let rawLocations = decodedData.locations.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
                            onTrackDataLoaded(decodedData)
                            onLocationsLoaded(cleanGPXLocations(rawLocations))
                        } else if selectedFile.pathExtension == "gpx" {
                            let gpxString = String(data: data, encoding: .utf8) ?? ""
                            let rawLocations = GPXParser.parseGPX(gpxString)
                            let cleanedLocations = cleanGPXLocations(rawLocations)
                            saveCleanedLocations(cleanedLocations, originalGPXString: gpxString, to: destinationURL)
                            onLocationsLoaded(cleanedLocations)
                            
                            // Update stats cache
                            StatsCache.shared.addTrack(fileURL: destinationURL) { _ in
                                print("✅ Cache updated after import")
                            }
                        }
                        onMessage("Imported \(selectedFile.lastPathComponent)")
                    } catch {
                        print("Error copying file: \(error)")
                        onMessage("Error copying file: \(error.localizedDescription)")
                    }
                } else {
                    onMessage("Access to the file was denied.")
                }
            }
        case .failure(let error):
            print("Error during file import: \(error.localizedDescription)")
            onMessage("Failed to import: \(error.localizedDescription)")
        }
    }

    static func exportFile(named fileName: String, locationManager: LocationManager) -> ShareableFile? {
        let fileURL = locationManager.getDocumentsDirectory().appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("File does not exist at path: \(fileURL.path)")
            return nil
        }
        return ShareableFile(url: fileURL)
    }

    static func saveCleanedLocations(_ locations: [CLLocation], originalGPXString: String, to url: URL) {
        print("💾 saveCleanedLocations called: \(locations.count) locations → \(url.lastPathComponent)")
        // Extract original track name
        var trackName = "Track"
        if let range = originalGPXString.range(of: "<name>", options: .caseInsensitive),
           let endRange = originalGPXString.range(of: "</name>", options: .caseInsensitive, range: range.upperBound..<originalGPXString.endIndex) {
            trackName = String(originalGPXString[range.upperBound..<endRange.lowerBound])
        }

        var gpxString = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <gpx version="1.1" creator="Untrackd"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xmlns="http://www.topografix.com/GPX/1/1"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <trk>
            <name>\(trackName)</name>
            <trkseg>
        """

        let formatter = ISO8601DateFormatter()
        for location in locations {
            gpxString += """
              <trkpt lat="\(location.coordinate.latitude)" lon="\(location.coordinate.longitude)">
                <ele>\(location.altitude)</ele>
                <time>\(formatter.string(from: location.timestamp))</time>
              </trkpt>
            """
        }

        gpxString += """
            </trkseg>
          </trk>
        </gpx>
        """

        do {
            try gpxString.write(to: url, atomically: true, encoding: .utf8)
            print("✅ Saved cleaned file with \(locations.count) locations, name: \(trackName)")
        } catch {
            print("❌ Failed to save cleaned file: \(error)")
        }
    }
    
    static func cleanGPXLocations(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count > 1 else { return locations }
        
        // Pass 1: Hard limits — remove any point that is physically impossible
        // regardless of context. These thresholds are absolute maximums.
        let maxHorizontalPerSec: Double = 40.0  // 40 m/s (~90 mph) hard cap
        let maxElevRatePerSec: Double = 15.0    // 15 m/s vertical — physically impossible on skis
        
        var pass1: [CLLocation] = [locations[0]]
        for i in 1..<locations.count {
            let prev = pass1.last!
            let curr = locations[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }
            
            let dist = curr.distance(from: prev)
            let elevChange = abs(curr.altitude - prev.altitude)
            
            if dist / dt > maxHorizontalPerSec { continue }
            if elevChange / dt > maxElevRatePerSec { continue }
            
            pass1.append(curr)
        }
        
        // TEMP DEBUG — add after pass1 is built, before pass2
        let debugSegs = (1..<pass1.count).compactMap { i -> (Int, Double, Date)? in
            let prev = pass1[i-1], curr = pass1[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { return nil }
            let mph = (curr.distance(from: prev) / dt) * 2.23694
            return (i, mph, curr.timestamp)
        }.sorted { $0.1 > $1.1 }.prefix(10)

        if pass1.first?.timestamp.description.contains("2026-01-11") == true {
            print("🔍 TOP 10 SPEEDS in 2026_01_11 track:")
            for (i, mph, t) in debugSegs {
                print("  [\(i)] \(t) → \(String(format: "%.1f", mph)) mph")
            }
        }
        // TEMP DEBUG — context around index 1629
        if pass1.first?.timestamp.description.contains("2026-01-11") == true {
            let glitchIdx = 1629
            let start = max(0, glitchIdx - 5)
            let end = min(pass1.count - 1, glitchIdx + 5)
            print("🔍 CONTEXT around index \(glitchIdx):")
            for i in start...end {
                let p = pass1[i]
                if i > 0 {
                    let prev = pass1[i-1]
                    let dt = p.timestamp.timeIntervalSince(prev.timestamp)
                    let dist = p.distance(from: prev)
                    let mph = dt > 0 ? (dist/dt)*2.23694 : 0
                    print("  [\(i)] \(p.timestamp) lat=\(String(format: "%.6f", p.coordinate.latitude)) lon=\(String(format: "%.6f", p.coordinate.longitude)) ele=\(String(format: "%.1f", p.altitude))m → \(String(format: "%.1f", mph))mph in \(String(format: "%.0f", dt))s (\(String(format: "%.1f", dist))m)")
                } else {
                    print("  [\(i)] \(p.timestamp) lat=\(String(format: "%.6f", p.coordinate.latitude)) lon=\(String(format: "%.6f", p.coordinate.longitude)) ele=\(String(format: "%.1f", p.altitude))m")
                }
            }
            // Also print what avgCtx and skipSpeed would be for index 1629
            var ctxSpeeds: [Double] = []
            for j in max(0, 1626)..<1629 {
                let a = pass1[j], b = pass1[j+1]
                let t = b.timestamp.timeIntervalSince(a.timestamp)
                let d = b.distance(from: a)
                if t > 0 { ctxSpeeds.append(d/t) }
            }
            for j in 1629..<min(1632, pass1.count-1) {
                let a = pass1[j], b = pass1[j+1]
                let t = b.timestamp.timeIntervalSince(a.timestamp)
                let d = b.distance(from: a)
                if t > 0 { ctxSpeeds.append(d/t) }
            }
            let avg = ctxSpeeds.reduce(0,+) / Double(max(ctxSpeeds.count,1))
            let prev = pass1[1628]
            let curr = pass1[1629]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            let speedToCurr = dt > 0 ? curr.distance(from: prev)/dt : 0
            print("  avgCtx=\(String(format: "%.1f", avg*2.23694))mph speedToCurr=\(String(format: "%.1f", speedToCurr*2.23694))mph threshold=\(String(format: "%.1f", avg*2.5*2.23694))mph")
            if pass1.count > 1630 {
                let next = pass1[1630]
                let skipDt = next.timestamp.timeIntervalSince(prev.timestamp)
                let skipSpeed = skipDt > 0 ? next.distance(from: prev)/skipDt : 0
                print("  skipSpeed=\(String(format: "%.1f", skipSpeed*2.23694))mph threshold=\(String(format: "%.1f", speedToCurr*0.6*2.23694))mph")
            }
        }
        
        // Pass 2: Contextual glitch filter.
        //
        // CHECK A — behind-only context, skip is smoother
        // CHECK B — massive ratio jump from rest (mid-run teleport, next point also fast)
        // CHECK C — distance implausible given behind context speed × time

        var pass2: [CLLocation] = []
        guard !pass1.isEmpty else { return [] }
        pass2.append(pass1[0])

        for i in 1..<pass1.count {
            let prev = pass2.last!
            let curr = pass1[i]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { continue }

            let speedToCurr = curr.distance(from: prev) / dt

            // Behind: last 3 segments in cleaned output
            var behindSpeeds: [Double] = []
            let p2count = pass2.count
            for j in max(0, p2count - 3)..<p2count - 1 {
                let a = pass2[j], b = pass2[j + 1]
                let t = b.timestamp.timeIntervalSince(a.timestamp)
                let d = b.distance(from: a)
                if t > 0 { behindSpeeds.append(d / t) }
            }

            if !behindSpeeds.isEmpty {
                let avgBehind = behindSpeeds.reduce(0, +) / Double(behindSpeeds.count)

                // CHECK A: speed way above behind context AND skipping produces smoother path
                if speedToCurr > avgBehind * 2.5 && speedToCurr > 8.0 {
                    if i + 1 < pass1.count {
                        let next = pass1[i + 1]
                        let skipDt = next.timestamp.timeIntervalSince(prev.timestamp)
                        let skipSpeed = skipDt > 0 ? next.distance(from: prev) / skipDt : Double.infinity
                        if skipSpeed < speedToCurr * 0.6 {
                            print("🗑 Pass2 CHECK-A dropped point at \(curr.timestamp): \(String(format: "%.1f", speedToCurr * 2.23694)) mph (avgBehind \(String(format: "%.1f", avgBehind * 2.23694)) mph, skip \(String(format: "%.1f", skipSpeed * 2.23694)) mph)")
                            continue
                        }
                    } else {
                        // Last point, no next — drop if massively above context
                        if speedToCurr > avgBehind * 3.5 {
                            print("🗑 Pass2 CHECK-A (last pt) dropped point at \(curr.timestamp): \(String(format: "%.1f", speedToCurr * 2.23694)) mph")
                            continue
                        }
                    }
                }

                // CHECK B: massive ratio jump — mid-run teleport where next point is also fast
                // (so CHECK A's skip test fails because skip speed is also high)
                if speedToCurr > 25.0 && speedToCurr > avgBehind * 6.0 {
                    print("🗑 Pass2 CHECK-B dropped point at \(curr.timestamp): \(String(format: "%.1f", speedToCurr * 2.23694)) mph (avgBehind \(String(format: "%.1f", avgBehind * 2.23694)) mph, ratio \(String(format: "%.1fx", speedToCurr / avgBehind)))")
                    continue
                }

                // CHECK C: distance jumped beyond what behind context speed could produce
                // Only fires on longer time gaps (≥5s) to avoid false positives on normal
                // 3s GPS intervals where legitimate acceleration can cover 70-90m
                if speedToCurr > avgBehind * 4.0 && speedToCurr > 15.0 && dt >= 5.0 {
                    let actualDist = curr.distance(from: prev)
                    let expectedMaxDist = max(70.0, avgBehind * dt * 4.0)
                    if actualDist > expectedMaxDist {
                        print("🗑 Pass2 CHECK-C dropped point at \(curr.timestamp): \(String(format: "%.1f", speedToCurr * 2.23694)) mph (dist \(String(format: "%.1f", actualDist))m > expected \(String(format: "%.1f", expectedMaxDist))m)")
                        continue
                    }
                }
            }

            pass2.append(curr)
        }
        
        // Pass 3: Tail-trim — only trim if there's no meaningful activity after the gap.
        let minTailGapSeconds: TimeInterval = 300.0   // 5 min gap to even consider trimming
        let maxDriftSpeedMps: Double = 0.5            // basically stationary
        let minPostGapDistanceM: Double = 100.0       // if they move >100m after gap, keep it

        var result = pass2
        var trimIndex: Int? = nil

        for i in stride(from: result.count - 1, through: 1, by: -1) {
            let curr = result[i]
            let prev = result[i - 1]
            let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
            let speed = dt > 0 ? curr.distance(from: prev) / dt : 0

            if dt > minTailGapSeconds && speed < maxDriftSpeedMps {
                // Check if there's meaningful movement after this gap
                let postGapPoints = Array(result[i...])
                var totalPostGapDistance: Double = 0
                for j in 1..<postGapPoints.count {
                    totalPostGapDistance += postGapPoints[j].distance(from: postGapPoints[j-1])
                }
                
                // Only trim if there's very little movement after the gap
                if totalPostGapDistance < minPostGapDistanceM {
                    trimIndex = i
                }
                break
            }
        }

        if let idx = trimIndex {
            result = Array(result.prefix(idx))
        }
        
        return result
    }
    
    static func cleanAllGPXFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        
        let gpxFiles = files.filter { $0.pathExtension.lowercased() == "gpx" }
        print("🧹 Cleaning \(gpxFiles.count) GPX files...")
        
        var cleaned = 0
        for fileURL in gpxFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let gpxString = String(data: data, encoding: .utf8) else { continue }
            
            let rawLocations = GPXParser.parseGPX(gpxString)
            let cleanedLocations = cleanGPXLocations(rawLocations)
            
            if cleanedLocations.count < rawLocations.count {
                saveCleanedLocations(cleanedLocations, originalGPXString: gpxString, to: fileURL)
                cleaned += 1
                print("✅ Cleaned \(fileURL.lastPathComponent): \(rawLocations.count) → \(cleanedLocations.count) points")
            }
        }
        print("🧹 Done. Cleaned \(cleaned) of \(gpxFiles.count) files.")
    }
}
