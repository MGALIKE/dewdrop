import Foundation

// MARK: - WeatherMonitor
// Current weather for the chip in the island header and for what Mochi wears (umbrella, shades,
// scarf). Data comes from Open-Meteo, which needs no key or account. The only thing sent is the
// name of the city (once, to find its coordinates) and then those coordinates. The city defaults
// to the one in the Mac's time zone and can be changed, or the whole thing switched off, in Settings.

@MainActor
final class WeatherMonitor {
    static let shared = WeatherMonitor()

    private var timer: Timer?
    private var place: (query: String, name: String, lat: Double, lon: Double)?
    private var generation = 0
    private var app: AppState { AppState.shared }

    private init() {}

    /// The big city of the Mac's time zone: "Europe/Istanbul" → "Istanbul".
    static var defaultCity: String {
        (TimeZone.current.identifier.split(separator: "/").last.map(String.init) ?? "")
            .replacingOccurrences(of: "_", with: " ")
    }

    func start() {
        if app.weatherCity.isEmpty { app.weatherCity = Self.defaultCity }
        let ud = UserDefaults.standard
        if let query = ud.string(forKey: "weatherPlaceQuery"), let name = ud.string(forKey: "weatherPlaceName") {
            place = (query, name, ud.double(forKey: "weatherPlaceLat"), ud.double(forKey: "weatherPlaceLon"))
        }
        let t = Timer(timeInterval: 30 * 60, repeats: true) { _ in
            Task { @MainActor in WeatherMonitor.shared.refresh() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    /// Call after the city or the on/off switch changed.
    func settingsChanged() {
        if !app.weatherEnabled {
            app.weather = nil
            app.showWeather = false
        }
        refresh()
    }

    func refresh() {
        guard app.weatherEnabled else { return }
        let city = app.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { app.weather = nil; return }
        generation += 1
        let run = generation
        let known = place?.query.caseInsensitiveCompare(city) == .orderedSame ? place : nil
        let fahrenheit = Locale.current.measurementSystem == .us

        Task {
            do {
                var spot = known
                if spot == nil {
                    guard let found = try await Self.geocode(city) else {
                        appendAppLog("nb.log", "Weather: no place called \(city.prefix(40))")
                        return
                    }
                    spot = (city, found.name, found.lat, found.lon)
                }
                guard let spot else { return }
                let info = try await Self.forecast(lat: spot.lat, lon: spot.lon, city: spot.name, fahrenheit: fahrenheit)
                guard run == self.generation, self.app.weatherEnabled else { return }
                self.place = spot
                let ud = UserDefaults.standard
                ud.set(spot.query, forKey: "weatherPlaceQuery"); ud.set(spot.name, forKey: "weatherPlaceName")
                ud.set(spot.lat, forKey: "weatherPlaceLat"); ud.set(spot.lon, forKey: "weatherPlaceLon")
                self.app.weather = info
            } catch {
                appendAppLog("nb.log", "Weather: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Open-Meteo

    private static func geocode(_ city: String) async throws -> (name: String, lat: Double, lon: Double)? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"),
                                 .init(name: "format", value: "json")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else { return nil }
        return (first["name"] as? String ?? city, lat, lon)
    }

    private static func forecast(lat: Double, lon: Double, city: String, fahrenheit: Bool) async throws -> WeatherInfo {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", lat)),
            .init(name: "longitude", value: String(format: "%.3f", lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "2"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        if fahrenheit { components.queryItems?.append(.init(name: "temperature_unit", value: "fahrenheit")) }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double,
              let code = current["weather_code"] as? Int else {
            throw URLError(.cannotParseResponse)
        }
        let isDay = (current["is_day"] as? Int ?? 1) == 1
        let daily = json["daily"] as? [String: Any]
        let high = (daily?["temperature_2m_max"] as? [Double])?.first ?? temp
        let low = (daily?["temperature_2m_min"] as? [Double])?.first ?? temp

        var hours: [WeatherInfo.Hour] = []
        if let hourly = json["hourly"] as? [String: Any],
           let times = hourly["time"] as? [Double],
           let temps = hourly["temperature_2m"] as? [Double],
           let codes = hourly["weather_code"] as? [Int] {
            let days = hourly["is_day"] as? [Int] ?? []
            let now = Date().timeIntervalSince1970
            for i in times.indices where times[i] > now && i < temps.count && i < codes.count {
                hours.append(.init(date: Date(timeIntervalSince1970: times[i]), temp: temps[i], code: codes[i],
                                   isDay: i < days.count ? days[i] == 1 : true))
                if hours.count == 4 { break }
            }
        }
        let celsius = fahrenheit ? (temp - 32) / 1.8 : temp
        return WeatherInfo(city: city, temp: temp, code: code, isDay: isDay, high: high, low: low,
                           hours: hours, fetched: Date(), isCold: celsius <= 2, unit: fahrenheit ? "F" : "C")
    }
}
