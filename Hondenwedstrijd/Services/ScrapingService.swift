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
        
        do {
            // First try the calendar endpoint
            if let matches = try? await fetchFromCalendar() {
                self.matches = matches
                return
            }
            
            // If that fails, try the mobile endpoint
            if let matches = try? await fetchFromMobileEndpoint() {
                self.matches = matches
                return
            }
            
            // If both fail, try the main website
            if let matches = try? await fetchFromMainWebsite() {
                self.matches = matches
                return
            }
            
            // If all attempts fail, throw an error
            throw ScrapingError.noDataFound
        } catch {
            self.error = error
            print("Error fetching matches: \(error)")
        }
        
        isLoading = false
    }
    
    private func fetchFromCalendar() async throws -> [Match] {
        let url = URL(string: "https://my.orweja.nl/home/kalender/1")!
        return try await fetchFromURL(url)
    }
    
    private func fetchFromMobileEndpoint() async throws -> [Match] {
        let url = URL(string: "https://my.orweja.nl/m/kalender")!
        return try await fetchFromURL(url)
    }
    
    private func fetchFromMainWebsite() async throws -> [Match] {
        let url = URL(string: "https://www.orweja.nl/")!
        return try await fetchFromURL(url)
    }
    
    private func fetchFromURL(_ url: URL) async throws -> [Match] {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
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
        
        // Try multiple strategies to find the data
        let potentialDataContainers = try doc.select("table, .calendar-container, .events-list, .wedstrijden, #calendar, .competition-list")
        print("Found \(potentialDataContainers.count) potential data containers")
        
        for container in potentialDataContainers {
            // Try to parse as a table
            if let matches = try? parseTableData(container) {
                return matches
            }
            
            // Try to parse as a list
            if let matches = try? parseListData(container) {
                return matches
            }
        }
        
        throw ScrapingError.noDataFound
    }
    
    private func parseTableData(_ element: Element) throws -> [Match] {
        var matches: [Match] = []
        
        // Try to find rows (both in regular tables and div-based tables)
        let rows = try element.select("tr, .row, .event-row, .competition-row")
        print("Found \(rows.count) potential rows in table")
        
        // Try to determine the structure from the first row
        let headerRow = try rows.first()?.select("th, td, .cell, .header").map { try $0.text().lowercased() }
        print("Potential headers: \(String(describing: headerRow))")
        
        if headerRow == nil || headerRow?.isEmpty == true {
            return []
        }
        
        // Skip header row
        let dataRows = Array(rows.dropFirst())
        
        for row in dataRows {
            if let match = try? parseRow(row) {
                matches.append(match)
            }
        }
        
        return matches
    }
    
    private func parseListData(_ element: Element) throws -> [Match] {
        var matches: [Match] = []
        
        // Try to find event items
        let items = try element.select(".event-item, .competition-item, .calendar-item, .wedstrijd-item")
        print("Found \(items.count) potential list items")
        
        for item in items {
            if let match = try? parseListItem(item) {
                matches.append(match)
            }
        }
        
        return matches
    }
    
    private func parseRow(_ row: Element) throws -> Match? {
        let cells = try row.select("td, .cell")
        guard cells.count >= 4 else { return nil }
        
        // Try to extract data from cells with flexible position
        var dateString = ""
        var type = ""
        var category = ""
        var location = ""
        var status = ""
        
        for cell in cells {
            let text = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Try to determine the content type
            if text.matches(pattern: "\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4}") {
                dateString = text
            } else if text.lowercased().contains("open") || text.lowercased().contains("gesloten") {
                status = text
            } else if text.contains(",") {
                location = text
            } else if text.count > 20 {
                type = text
            } else {
                category = text
            }
        }
        
        // Convert date string to Date
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        
        // Try different date formats
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
            organizer: "",
            location: location,
            notes: "",
            registrationStatus: registrationStatus
        )
    }
    
    private func parseListItem(_ item: Element) throws -> Match? {
        let dateElement = try item.select(".date, .datum, [data-date]").first()
        let typeElement = try item.select(".type, .title, .naam").first()
        let categoryElement = try item.select(".category, .categorie").first()
        let locationElement = try item.select(".location, .locatie").first()
        let statusElement = try item.select(".status, .registration").first()
        
        guard let dateString = try dateElement?.text() else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        dateFormatter.dateFormat = "dd-MM-yyyy"
        
        guard let date = dateFormatter.date(from: dateString) else {
            print("Failed to parse date: \(dateString)")
            return nil
        }
        
        let type = try typeElement?.text() ?? ""
        let category = try categoryElement?.text() ?? ""
        let location = try locationElement?.text() ?? ""
        let status = try statusElement?.text() ?? ""
        
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
            organizer: "",
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