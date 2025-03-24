import Foundation
import SwiftSoup
import SwiftUI

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
        matches = []
        
        do {
            // Try my.orweja.nl endpoints first
            let myOrwejaURLs = [
                "https://my.orweja.nl/home/kalender/1",
                "https://my.orweja.nl/kalender",
                "https://my.orweja.nl/m/kalender"
            ]
            
            for url in myOrwejaURLs {
                do {
                    let matches = try await fetchFromURL(URL(string: url)!)
                    if !matches.isEmpty {
                        self.matches = matches.sorted { $0.date < $1.date }
                        print("Successfully fetched \(matches.count) matches from \(url)")
                        return
                    }
                } catch {
                    print("Failed to fetch from \(url): \(error)")
                    continue
                }
            }
            
            // If all attempts fail, throw an error
            throw ScrapingError.noDataFound
        } catch {
            self.error = error
            print("Error fetching matches: \(error)")
        }
        
        isLoading = false
    }
    
    private func fetchFromURL(_ url: URL) async throws -> [Match] {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
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
        
        print("Received HTML length from \(url.absoluteString): \(html.count)")
        
        let doc = try SwiftSoup.parse(html)
        
        // Print the entire HTML structure for debugging
        print("HTML Structure:")
        print(try doc.html())
        
        // First try to find a table with specific headers
        let tables = try doc.select("table")
        print("Found \(tables.count) tables")
        
        for table in tables {
            let headers = try table.select("th, thead td").map { try $0.text().lowercased() }
            print("Table headers: \(headers)")
            
            if headers.contains(where: { $0.contains("datum") }) {
                return try parseTable(table)
            }
        }
        
        // If no table is found, try other containers
        let containers = try doc.select(".calendar-container, .events-list, .wedstrijden, #calendar")
        for container in containers {
            if let matches = try? parseContainer(container), !matches.isEmpty {
                return matches
            }
        }
        
        throw ScrapingError.tableNotFound
    }
    
    private func parseTable(_ table: Element) throws -> [Match] {
        var matches: [Match] = []
        
        let rows = try table.select("tr")
        guard rows.count > 1 else { return [] }
        
        let headers = try rows[0].select("th, td").map { try $0.text().lowercased() }
        print("Processing table with headers: \(headers)")
        
        let dateIndex = headers.firstIndex { $0.contains("datum") } ?? 0
        let typeIndex = headers.firstIndex { $0.contains("type") } ?? 1
        let categoryIndex = headers.firstIndex { $0.contains("categorie") } ?? 2
        let organizerIndex = headers.firstIndex { $0.contains("organisator") } ?? 3
        let locationIndex = headers.firstIndex { $0.contains("locatie") } ?? 4
        let statusIndex = headers.firstIndex { $0.contains("status") } ?? 5
        
        for row in rows.dropFirst() {
            let cells = try row.select("td")
            guard cells.count >= max(dateIndex, typeIndex, categoryIndex, locationIndex, statusIndex) + 1 else {
                continue
            }
            
            let dateString = try cells[dateIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let type = try cells[typeIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let category = try cells[categoryIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let organizer = organizerIndex < cells.count ? try cells[organizerIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let location = try cells[locationIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
            let status = try cells[statusIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let match = createMatch(dateString: dateString, type: type, category: category, organizer: organizer, location: location, status: status) {
                matches.append(match)
            }
        }
        
        return matches
    }
    
    private func parseContainer(_ container: Element) throws -> [Match] {
        var matches: [Match] = []
        
        let items = try container.select(".event-item, .calendar-item, .wedstrijd-item, div[class*='event'], div[class*='wedstrijd']")
        for item in items {
            if let match = try? parseContainerItem(item) {
                matches.append(match)
            }
        }
        
        return matches
    }
    
    private func parseContainerItem(_ item: Element) throws -> Match? {
        let dateText = try item.select("[class*='date'], [class*='datum']").first()?.text() ?? ""
        let typeText = try item.select("[class*='type'], [class*='title']").first()?.text() ?? ""
        let categoryText = try item.select("[class*='category'], [class*='categorie']").first()?.text() ?? ""
        let locationText = try item.select("[class*='location'], [class*='locatie']").first()?.text() ?? ""
        let statusText = try item.select("[class*='status']").first()?.text() ?? ""
        
        return createMatch(dateString: dateText, type: typeText, category: categoryText, organizer: "", location: locationText, status: statusText)
    }
    
    private func createMatch(dateString: String, type: String, category: String, organizer: String, location: String, status: String) -> Match? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        
        let dateFormats = ["dd-MM-yyyy", "d-M-yyyy", "dd/MM/yyyy", "d/M/yyyy"]
        var date: Date?
        
        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let parsedDate = dateFormatter.date(from: dateString) {
                date = parsedDate
                break
            }
        }
        
        guard let date = date else {
            print("Failed to parse date: \(dateString)")
            return nil
        }
        
        let registrationStatus: Match.RegistrationStatus
        switch status.lowercased() {
        case let s where s.contains("open") || s.contains("inschrijven"):
            registrationStatus = .available
        case let s where s.contains("gesloten"):
            registrationStatus = .closed
        default:
            registrationStatus = .notAvailable
        }
        
        return Match(
            date: date,
            type: type,
            category: category,
            organizer: organizer,
            location: location,
            notes: "",
            registrationStatus: registrationStatus
        )
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
    case noDataFound
    
    var errorDescription: String? {
        switch self {
        case .tableNotFound:
            return "Kon de wedstrijdtabel niet vinden op de pagina. Probeer het later opnieuw."
        case .invalidResponse:
            return "Ongeldige response van de server. Controleer je internetverbinding."
        case .invalidData:
            return "De ontvangen data kon niet worden verwerkt. Probeer het later opnieuw."
        case .httpError(let statusCode):
            return "Server error (code \(statusCode)). Probeer het later opnieuw."
        case .noDataFound:
            return "Geen wedstrijdgegevens gevonden. Probeer het later opnieuw."
        }
    }
}

extension String {
    func matches(pattern: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(self.startIndex..., in: self)
        return regex?.firstMatch(in: self, range: range) != nil
    }
} 