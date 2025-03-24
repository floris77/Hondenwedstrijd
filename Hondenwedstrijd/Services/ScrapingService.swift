import Foundation
import SwiftSoup

@MainActor
class ScrapingService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    var categories: Set<String> {
        Set(matches.map { $0.category })
    }
    
    func fetchMatches() async {
        isLoading = true
        error = nil
        
        do {
            let url = URL(string: "https://my.orweja.nl/home/kalender/1")!
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ScrapingError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw ScrapingError.httpError(statusCode: httpResponse.statusCode)
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                throw ScrapingError.invalidData
            }
            
            let doc = try SwiftSoup.parse(html)
            
            // First, try to find the table with the specific class or structure used by Orweja
            let tables = try doc.select("table")
            guard let matchesTable = tables.first(where: { table in
                // Look for table headers that match what we expect
                let headers = try? table.select("th").map { try $0.text() }
                return headers?.contains { $0.contains("Datum") || $0.contains("Type") } ?? false
            }) else {
                throw ScrapingError.tableNotFound
            }
            
            let rows = try matchesTable.select("tr")
            let rowsArray = Array(rows).dropFirst() // Skip header row
            
            matches = try rowsArray.compactMap { row in
                let columns = try row.select("td")
                guard columns.count >= 6 else { return nil }
                
                let dateString = try columns[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let type = try columns[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let category = try columns[2].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let organizer = try columns[3].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let location = try columns[4].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let registrationStatus = try columns[5].text().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Convert date string to Date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MM-yyyy"
                dateFormatter.locale = Locale(identifier: "nl_NL")
                
                guard let date = dateFormatter.date(from: dateString) else {
                    print("Failed to parse date: \(dateString)")
                    return nil
                }
                
                return Match(
                    date: date,
                    type: type,
                    category: category,
                    organizer: organizer,
                    location: location,
                    notes: "",
                    registrationStatus: Match.RegistrationStatus(rawValue: registrationStatus) ?? .notAvailable
                )
            }
            
            // Sort matches by date
            matches.sort { $0.date < $1.date }
            
        } catch {
            self.error = error
            print("Error fetching matches: \(error)")
        }
        
        isLoading = false
    }
    
    func filteredMatches(category: String? = nil, status: Match.RegistrationStatus? = nil) -> [Match] {
        matches.filter { match in
            let categoryMatch = category == nil || match.category == category
            let statusMatch = status == nil || match.registrationStatus == status
            return categoryMatch && statusMatch
        }
    }
}

enum ScrapingError: LocalizedError {
    case tableNotFound
    case invalidResponse
    case invalidData
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .tableNotFound:
            return "Kon de wedstrijdtabel niet vinden op de pagina."
        case .invalidResponse:
            return "Ongeldige response van de server."
        case .invalidData:
            return "De ontvangen data kon niet worden verwerkt."
        case .httpError(let statusCode):
            return "Server error (code \(statusCode)). Probeer het later opnieuw."
        }
    }
} 