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
            let url = URL(string: "https://my.orweja.nl/home/kalender/1")!
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
            
            print("Received HTML length: \(html.count)")
            
            let doc = try SwiftSoup.parse(html)
            
            // Try to find the main content area first
            let mainContent = try doc.select(".content-area, .main-content, #main-content, main").first()
            let searchArea = mainContent ?? doc
            
            // Look for tables in the content area
            let tables = try searchArea.select("table")
            print("Found \(tables.count) tables")
            
            // Try to find the table with event data
            guard let matchesTable = tables.first(where: { table in
                do {
                    let headers = try table.select("th, thead td").map { try $0.text().lowercased() }
                    print("Table headers: \(headers)")
                    return headers.contains { $0.contains("datum") || $0.contains("type") || $0.contains("categorie") }
                } catch {
                    return false
                }
            }) else {
                print("No matching table found")
                throw ScrapingError.tableNotFound
            }
            
            let rows = try matchesTable.select("tr")
            print("Found \(rows.count) rows")
            
            // Find header row to determine column indices
            let headerRow = try matchesTable.select("tr").first()
            let headerCells = try headerRow?.select("th, td").map { try $0.text().lowercased() } ?? []
            print("Header cells: \(headerCells)")
            
            let dateIndex = headerCells.firstIndex { $0.contains("datum") } ?? 0
            let typeIndex = headerCells.firstIndex { $0.contains("type") } ?? 1
            let categoryIndex = headerCells.firstIndex { $0.contains("categorie") } ?? 2
            let organizerIndex = headerCells.firstIndex { $0.contains("organisator") } ?? 3
            let locationIndex = headerCells.firstIndex { $0.contains("locatie") } ?? 4
            let statusIndex = headerCells.firstIndex { $0.contains("status") } ?? 5
            
            // Skip header row
            let dataRows = Array(rows).dropFirst()
            
            matches = try dataRows.compactMap { row in
                let columns = try row.select("td")
                guard columns.count >= max(dateIndex, typeIndex, categoryIndex, organizerIndex, locationIndex, statusIndex) + 1 else {
                    return nil
                }
                
                let dateString = try columns[dateIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let type = try columns[typeIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let category = try columns[categoryIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let organizer = try columns[organizerIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let location = try columns[locationIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let status = try columns[statusIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Convert date string to Date
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd-MM-yyyy"
                dateFormatter.locale = Locale(identifier: "nl_NL")
                
                guard let date = dateFormatter.date(from: dateString) else {
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
            
            // Sort matches by date
            matches.sort { $0.date < $1.date }
            print("Successfully parsed \(matches.count) matches")
            
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
            return "Kon de wedstrijdtabel niet vinden op de pagina. Probeer het later opnieuw."
        case .invalidResponse:
            return "Ongeldige response van de server. Controleer je internetverbinding."
        case .invalidData:
            return "De ontvangen data kon niet worden verwerkt. Probeer het later opnieuw."
        case .httpError(let statusCode):
            return "Server error (code \(statusCode)). Probeer het later opnieuw."
        }
    }
} 