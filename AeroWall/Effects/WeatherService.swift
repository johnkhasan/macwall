import Foundation
import Combine

/// Current weather from Open-Meteo (free, no API key), used by the "Live Weather" effect.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    enum Condition: String {
        case clear, cloudy, fog, rain, snow, storm

        init(wmoCode: Int) {
            switch wmoCode {
            case 0, 1: self = .clear
            case 2, 3: self = .cloudy
            case 45, 48: self = .fog
            case 51...67, 80...82: self = .rain
            case 71...77, 85, 86: self = .snow
            case 95...99: self = .storm
            default: self = .cloudy
            }
        }

        var effect: ParticleScene.Kind? {
            switch self {
            case .rain, .storm: return .rain
            case .snow: return .snow
            case .clear, .cloudy, .fog: return nil
            }
        }

        var title: String { rawValue.capitalized }

        var symbol: String {
            switch self {
            case .clear: return "sun.max"
            case .cloudy: return "cloud"
            case .fog: return "cloud.fog"
            case .rain: return "cloud.rain"
            case .snow: return "cloud.snow"
            case .storm: return "cloud.bolt.rain"
            }
        }
    }

    struct Place: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?

        var displayName: String {
            [name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    @Published private(set) var condition: Condition?
    @Published private(set) var temperature: Double?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let settings = AppSettings.shared
    private var timer: Timer?
    private var fetchedCoordinate: String?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        settings.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.updateSchedule() }
            .store(in: &cancellables)
        updateSchedule()
    }

    private func updateSchedule() {
        guard settings.effect == .weather,
              let latitude = settings.weatherLatitude,
              let longitude = settings.weatherLongitude else {
            timer?.invalidate()
            timer = nil
            return
        }
        let coordinate = "\(latitude),\(longitude)"
        if timer == nil {
            let timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        if coordinate != fetchedCoordinate {
            refreshNow()
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    func refresh() async {
        guard let latitude = settings.weatherLatitude, let longitude = settings.weatherLongitude else { return }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
        ]

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
            }
            let current: Current
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let response = try JSONDecoder().decode(Response.self, from: data)
            condition = Condition(wmoCode: response.current.weather_code)
            temperature = response.current.temperature_2m
            lastUpdated = Date()
            errorMessage = nil
            fetchedCoordinate = "\(latitude),\(longitude)"
        } catch {
            errorMessage = "Couldn't load the weather: \(error.localizedDescription)"
        }
    }

    func searchPlaces(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "format", value: "json"),
        ]

        struct Response: Decodable {
            let results: [Place]?
        }

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(Response.self, from: data).results ?? []
    }

    func select(_ place: Place) {
        settings.weatherPlace = place.displayName
        settings.weatherLatitude = place.latitude
        settings.weatherLongitude = place.longitude
        refreshNow()
    }
}
