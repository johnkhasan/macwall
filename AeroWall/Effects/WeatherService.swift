import Foundation

class WeatherService {
    static let shared = WeatherService()
    
    func fetchWeather(latitude: Double, longitude: Double, completion: @escaping (String?) -> Void) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current_weather=true"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                completion(nil)
                return
            }
            completion("Rain")
        }.resume()
    }
}
