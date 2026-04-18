//
//  GPXStatsLogic.swift
//  SnowCountry
//
//  Created by Ryan Potter on 1/6/24.
//

import CoreLocation
let elevationLossThreshold: Double = 5.0

// Calculate total distance from GPX locations (in kilometers or miles)
func calculateTotalDistance(locations: [CLLocation], isMetric: Bool) -> Double {
    var totalDistance: Double = 0.0
    // Ensure there are at least two locations to calculate distance
    if locations.count >= 2 {
        for i in 0..<locations.count - 1 {
            let startLocation = locations[i]
            let endLocation = locations[i + 1]
            let distance = startLocation.distance(from: endLocation)
            totalDistance += isMetric ? distance / 1000.0 : distance / 1609.34
        }
    }
    return totalDistance
}

// Calculate total Up distance from GPX locations (in kilometers or miles)
func calculateTotalUpDistance(locations: [CLLocation], isMetric: Bool) -> Double {
    var totalUpDistance: Double = 0.0
    // Ensure there are at least two locations to calculate distance
    if locations.count >= 2 {
        for i in 0..<locations.count - 1 {
            let startLocation = locations[i]
            let endLocation = locations[i + 1]
            if startLocation.altitude < endLocation.altitude {
                let distance = startLocation.distance(from: endLocation)
                totalUpDistance += isMetric ? distance / 1000.0 : distance / 1609.34
            }
        }
    }
    return totalUpDistance
}

// Calculate total Down distance from GPX locations (in kilometers or miles)
func calculateTotalDownDistance(locations: [CLLocation], isMetric: Bool) -> Double {
    var totalDownDistance: Double = 0.0
    // Ensure there are at least two locations to calculate distance
    if locations.count >= 2 {
        for i in 0..<locations.count - 1 {
            let startLocation = locations[i]
            let endLocation = locations[i + 1]
            if startLocation.altitude > endLocation.altitude {
                let distance = startLocation.distance(from: endLocation)
                totalDownDistance += isMetric ? distance / 1000.0 : distance / 1609.34
            }
        }
    }
    return totalDownDistance
}

// Calculate maximum elevation from GPX locations (in meters or feet)
func calculateMaxElevation(locations: [CLLocation], isMetric: Bool) -> Double {
    var maxElevation: Double = 0.0
    for location in locations {
        let elevation = isMetric ? location.altitude : location.altitude * 3.28084
        if elevation > maxElevation {
            maxElevation = elevation
        }
    }
    return maxElevation
}

// Calculate minimum elevation from GPX locations (in meters or feet)
func calculateMinElevation(locations: [CLLocation], isMetric: Bool) -> Double {
    guard !locations.isEmpty else {
        return 0.0 // Return 0.0 if there are no locations
    }
    
    // Map all altitudes and find the minimum value
    let minElevation = locations.map { $0.altitude }.min() ?? 0.0
    
    // Convert to feet if needed
    return isMetric ? minElevation : minElevation * 3.28084
}

func calculateTotalElevationLoss(locations: [CLLocation], isMetric: Bool, windowSize: Int = 3) -> Double {
    let elevations = locations.map { $0.altitude }
    let smoothedElevations = movingAverage(for: elevations, windowSize: windowSize)

    var totalElevationLoss: Double = 0.0
    let elevationLossThreshold: Double = 0.9 // Set your threshold value

    // Ensure there are at least two elements in smoothedElevations
    if smoothedElevations.count >= 2 {
        for i in 0..<smoothedElevations.count - 1 {
            let startElevation = smoothedElevations[i]
            let endElevation = smoothedElevations[i + 1]

            // Check for a decrease in elevation
            let elevationChange = startElevation - endElevation
            if elevationChange > elevationLossThreshold {
                // Convert to feet if necessary
                let elevationLoss = isMetric ? elevationChange : elevationChange * 3.28084
                totalElevationLoss += elevationLoss
            }
        }
    }

    return totalElevationLoss
}

func calculateTotalElevationGain(locations: [CLLocation], isMetric: Bool, windowSize: Int = 3) -> Double {
    let elevations = locations.map { $0.altitude }
    let smoothedElevations = movingAverage(for: elevations, windowSize: windowSize)

    var totalElevationGain: Double = 0.0
    let elevationGainThreshold: Double = 0.9 // Set your threshold value

    // Ensure there are at least two elements in smoothedElevations
    if smoothedElevations.count >= 2 {
        for i in 0..<smoothedElevations.count - 1 {
            let startElevation = smoothedElevations[i]
            let endElevation = smoothedElevations[i + 1]

            // Check for a decrease in elevation
            let elevationChange = endElevation - startElevation
            if elevationChange > elevationGainThreshold {
                // Convert to feet if necessary
                let deltaElevation = isMetric ? elevationChange : elevationChange * 3.28084
                totalElevationGain += deltaElevation
            }
        }
    }

    return totalElevationGain
}

func calculateTotalElevationChange(locations: [CLLocation], isMetric: Bool, windowSize: Int = 3) -> Double {
    let elevations = locations.map { $0.altitude }
    let smoothedElevations = movingAverage(for: elevations, windowSize: windowSize)

    var totalElevationChange: Double = 0.0
    let elevationChangeThreshold: Double = 0.9 // Set your threshold value

    // Ensure there are at least two elements in smoothedElevations
    if smoothedElevations.count >= 2 {
        for i in 0..<smoothedElevations.count - 1 {
            let startElevation = smoothedElevations[i]
            let endElevation = smoothedElevations[i + 1]

            var elevationChange = 0.0
            // Check for a decrease in elevation
            if endElevation > startElevation {
                elevationChange = endElevation - startElevation
            } else if endElevation < startElevation {
                elevationChange = startElevation - endElevation
            }
            if elevationChange > elevationChangeThreshold {
                // Convert to feet if necessary
                let elevationChange = isMetric ? elevationChange : elevationChange * 3.28084
                totalElevationChange += elevationChange
            }
        }
    }

    return totalElevationChange
}

// Normal Version
func calculateMaxSpeed(locations: [CLLocation]) -> Double {
    var maxSpeed: Double = 0.0
    let targetWindow: TimeInterval = 5.0
    let maxPlausibleSpeedMps: Double = 67.056
    let maxDistancePerSecond: Double = 40.0
    let minDistance: Double = 10.0
    let maxElevationChangePerSecond: Double = 15.0

    guard locations.count > 1 else { return 0.0 }

    var coordinateCount: [String: Int] = [:]
    for location in locations {
        let key = String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude)
        coordinateCount[key, default: 0] += 1
    }
    let badCoordinates = Set(coordinateCount.filter { $0.value > 3 }.keys)

    for i in 0..<locations.count {
        let start = locations[i]
        let startKey = String(format: "%.5f,%.5f", start.coordinate.latitude, start.coordinate.longitude)
        guard !badCoordinates.contains(startKey) else { continue }

        var bestJ = -1
        var bestTimeDiff = Double.infinity

        for j in (i + 1)..<locations.count {
            let gap = locations[j].timestamp.timeIntervalSince(start.timestamp)
            if gap > targetWindow * 2 { break }
            let diff = abs(gap - targetWindow)
            if diff < bestTimeDiff {
                bestTimeDiff = diff
                bestJ = j
            }
        }

        guard bestJ != -1 else { continue }

        let end = locations[bestJ]
        let endKey = String(format: "%.5f,%.5f", end.coordinate.latitude, end.coordinate.longitude)
        guard !badCoordinates.contains(endKey) else { continue }

        let timeGap = end.timestamp.timeIntervalSince(start.timestamp)
        guard timeGap >= 4.0 && timeGap <= 6.0 else { continue }

        let elevationChange = abs(end.altitude - start.altitude)
        guard elevationChange <= maxElevationChangePerSecond * timeGap else { continue }

        let distance = end.distance(from: start)
        guard distance >= minDistance else { continue }

        let speedMps = distance / timeGap
        guard distance <= maxDistancePerSecond * timeGap else { continue }
        guard speedMps <= maxPlausibleSpeedMps else { continue }

        maxSpeed = max(maxSpeed, speedMps)
    }

    return maxSpeed.rounded(toPlaces: 1)
}

/* Debugging Version
func calculateMaxSpeed(locations: [CLLocation]) -> Double {
    var maxSpeed: Double = 0.0
    let targetWindow: TimeInterval = 5.0
    let maxPlausibleSpeedMps: Double = 67.056
    let maxDistancePerSecond: Double = 40.0
    let minDistance: Double = 10.0
    let maxElevationChangePerSecond: Double = 15.0

    guard locations.count > 1 else { return 0.0 }

    var coordinateCount: [String: Int] = [:]
    for location in locations {
        let key = String(format: "%.5f,%.5f", location.coordinate.latitude, location.coordinate.longitude)
        coordinateCount[key, default: 0] += 1
    }
    let badCoordinates = Set(coordinateCount.filter { $0.value > 3 }.keys)

    for i in 0..<locations.count {
        let start = locations[i]
        let startKey = String(format: "%.5f,%.5f", start.coordinate.latitude, start.coordinate.longitude)
        guard !badCoordinates.contains(startKey) else { continue }

        var bestJ = -1
        var bestTimeDiff = Double.infinity

        for j in (i + 1)..<locations.count {
            let gap = locations[j].timestamp.timeIntervalSince(start.timestamp)
            if gap > targetWindow * 2 { break }
            let diff = abs(gap - targetWindow)
            if diff < bestTimeDiff {
                bestTimeDiff = diff
                bestJ = j
            }
        }

        guard bestJ != -1 else { continue }

        let end = locations[bestJ]
        let endKey = String(format: "%.5f,%.5f", end.coordinate.latitude, end.coordinate.longitude)
        guard !badCoordinates.contains(endKey) else { continue }

        let timeGap = end.timestamp.timeIntervalSince(start.timestamp)
        guard timeGap >= 4.0 && timeGap <= 6.0 else { continue }

        let elevationChange = abs(end.altitude - start.altitude)
        if elevationChange > maxElevationChangePerSecond * timeGap {
            print("🏔️ Rejected elevation glitch at index \(i): \(elevationChange)m change in \(timeGap)s")
            print("  Start ele: \(start.altitude)m at \(start.timestamp)")
            print("  End ele:   \(end.altitude)m at \(end.timestamp)")
            continue
        }

        let distance = end.distance(from: start)
        guard distance >= minDistance else { continue }

        let speedMps = distance / timeGap

        if speedMps * 2.23694 > 38.0 {
            print("🚀 High speed at index \(i): \(speedMps * 2.23694) mph")
            print("  Start: \(start.coordinate.latitude), \(start.coordinate.longitude) ele: \(start.altitude)m at \(start.timestamp)")
            print("  End:   \(end.coordinate.latitude), \(end.coordinate.longitude) ele: \(end.altitude)m at \(end.timestamp)")
            print("  Distance: \(distance)m, ElevationChange: \(elevationChange)m in \(timeGap)s")
        }

        if distance > maxDistancePerSecond * timeGap {
            print("🚫 Rejected teleportation at index \(i): \(speedMps * 2.23694) mph, \(distance)m in \(timeGap)s")
            continue
        }

        guard speedMps <= maxPlausibleSpeedMps else {
            print("🚫 Rejected implausible speed at index \(i): \(speedMps * 2.23694) mph")
            continue
        }

        maxSpeed = max(maxSpeed, speedMps)
    }

    return maxSpeed.rounded(toPlaces: 1)
}
*/

func calculateUphillAvgSpeed(locations: [CLLocation], isMetric: Bool) -> Double {
    var totalUphillSpeeds: Double = 0.0
    var uphillSegments: Int = 0

    if locations.count >= 2 {
        var i = 0
        while i < locations.count - 1 {
            if locations[i].altitude < locations[i + 1].altitude {
                // Start of an uphill segment
                var segmentDistance: Double = 0.0
                var segmentTime: TimeInterval = 0.0

                var j = i
                while j < locations.count - 1 && locations[j].altitude < locations[j + 1].altitude {
                    let timeInterval = locations[j + 1].timestamp.timeIntervalSince(locations[j].timestamp)
                    if timeInterval > 0 {
                        segmentDistance += locations[j].distance(from: locations[j + 1])
                        segmentTime += timeInterval
                    }
                    j += 1
                }

                // Calculate average speed for this segment
                if segmentTime > 0 {
                    let segmentSpeed = segmentDistance / segmentTime * (isMetric ? 3.6 : 2.23694) // Convert to km/h or mph
                    totalUphillSpeeds += segmentSpeed
                    uphillSegments += 1
                }

                // Move to the next segment
                i = j
            } else {
                i += 1
            }
        }
    }

    // Calculate overall average uphill speed
    if uphillSegments > 0 {
        return totalUphillSpeeds / Double(uphillSegments)
    }

    return 0.0 // Return 0 if there's no data to calculate average uphill speed
}

func calculateDownhillAvgSpeed(locations: [CLLocation], isMetric: Bool) -> Double {
    var totalDownhillSpeeds: Double = 0.0
    var downhillSegments: Int = 0

    if locations.count >= 2 {
        var i = 0
        while i < locations.count - 1 {
            if locations[i].altitude > locations[i + 1].altitude {
                // Start of a downhill segment
                var segmentDistance: Double = 0.0
                var segmentTime: TimeInterval = 0.0

                var j = i
                while j < locations.count - 1 && locations[j].altitude > locations[j + 1].altitude {
                    let timeInterval = locations[j + 1].timestamp.timeIntervalSince(locations[j].timestamp)
                    if timeInterval > 0 {
                        segmentDistance += locations[j].distance(from: locations[j + 1])
                        segmentTime += timeInterval
                    }
                    j += 1
                }

                // Calculate average speed for this segment
                if segmentTime > 0 {
                    let segmentSpeed = segmentDistance / segmentTime * (isMetric ? 3.6 : 2.23694) // Convert to km/h or mph
                    totalDownhillSpeeds += segmentSpeed
                    downhillSegments += 1
                }

                // Move to the next segment
                i = j
            } else {
                i += 1
            }
        }
    }

    // Calculate overall average downhill speed
    if downhillSegments > 0 {
        return totalDownhillSpeeds / Double(downhillSegments)
    }

    return 0.0 // Return 0 if there's no data to calculate average downhill speed
}

// Calculate max altitude from GPX locations (in meters or feet)
func calculateMaxAltitude(locations: [CLLocation], isMetric: Bool) -> Double {
    var maxAltitude: Double = -Double.infinity
    for location in locations {
        let altitude = isMetric ? location.altitude : location.altitude * 3.28084
        if altitude > maxAltitude {
            maxAltitude = altitude
        }
    }
    return maxAltitude
}

func calculateRawVerticalLoss(locations: [CLLocation]) -> Double {
    var totalLoss: Double = 0.0
    guard locations.count > 1 else { return 0.0 }
    for i in 1..<locations.count {
        let startAlt = locations[i - 1].altitude
        let endAlt = locations[i].altitude
        if endAlt < startAlt {
            totalLoss += startAlt - endAlt
        }
    }
    return totalLoss // always in meters, convert at display time
}

func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = .pad

    return formatter.string(from: duration) ?? "0s"
}

// Calculate total duration from GPX locations (in seconds)
func calculateDuration(locations: [CLLocation]) -> TimeInterval {
    guard let firstLocation = locations.first, let lastLocation = locations.last else {
        return 0
    }
    return lastLocation.timestamp.timeIntervalSince(firstLocation.timestamp)
}

func calculateTimeSpentUphill(locations: [CLLocation]) -> TimeInterval {
    var totalTimeUphill: TimeInterval = 0.0

    if locations.count >= 2 {
        for i in 0..<locations.count - 1 {
            if locations[i + 1].altitude > locations[i].altitude {
                let timeInterval = locations[i + 1].timestamp.timeIntervalSince(locations[i].timestamp)
                totalTimeUphill += timeInterval
            }
        }
    }

    return totalTimeUphill
}

func calculateTimeSpentDownhill(locations: [CLLocation]) -> TimeInterval {
    var totalTimeDownhill: TimeInterval = 0.0

    if locations.count >= 2 {
        for i in 0..<locations.count - 1 {
            if locations[i + 1].altitude < locations[i].altitude {
                let timeInterval = locations[i + 1].timestamp.timeIntervalSince(locations[i].timestamp)
                totalTimeDownhill += timeInterval
            }
        }
    }

    return totalTimeDownhill
}

// Function to apply a moving average filter to the elevation data
func movingAverage(for elevations: [Double], windowSize: Int) -> [Double] {
    guard elevations.count > windowSize else { return elevations }
    var smoothedElevations = [Double]()
    var window = [Double]()

    for elevation in elevations {
        window.append(elevation)
        if window.count > windowSize {
            window.removeFirst()
        }

        let average = window.reduce(0, +) / Double(window.count)
        smoothedElevations.append(average)
    }

    return smoothedElevations
}
