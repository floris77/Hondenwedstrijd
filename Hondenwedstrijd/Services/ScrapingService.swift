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
            // Only try the main calendar URL since others return 404
            let url = URL(string: "https://my.orweja.nl/home/kalender/1")!
            let matches = try await fetchFromURL(url)
            if !matches.isEmpty {
                self.matches = matches.sorted { $0.date < $1.date }
                print("Successfully fetched \(matches.count) matches")
                return
            }
            
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
        
        print("Received HTML length: \(html.count)")
        
        let doc = try SwiftSoup.parse(html)
        
        // Try to find the main content area
        let mainContent = try doc.select("#main-content, .main-content, .content-area, .page-content").first()
        let searchArea = mainContent ?? doc
        
        // Print structure for debugging
        print("Document structure:")
        print(try searchArea.html())
        
        // Try multiple approaches to find the data
        var matches: [Match] = []
        
        // 1. Try finding tables directly
        let tables = try searchArea.select("table")
        print("Found \(tables.count) tables")
        
        for table in tables {
            if let tableMatches = try? parseTable(table), !tableMatches.isEmpty {
                matches.append(contentsOf: tableMatches)
            }
        }
        
        // 2. Try finding divs that look like table rows
        let rows = try searchArea.select(".row, .event-row, [class*='row'], [class*='event']")
        print("Found \(rows.count) potential row elements")
        
        for row in rows {
            if let match = try? parseRow(row) {
                matches.append(match)
            }
        }
        
        // 3. Try finding individual event elements
        let events = try searchArea.select(".event, .wedstrijd, .calendar-item, [class*='event'], [class*='wedstrijd']")
        print("Found \(events.count) potential event elements")
        
        for event in events {
            if let match = try? parseEvent(event) {
                matches.append(match)
            }
        }
        
        // 4. Try finding any div with date-like content
        let allDivs = try searchArea.select("div")
        print("Scanning \(allDivs.count) divs for date content")
        
        for div in allDivs {
            let text = try div.text()
            if text.matches(pattern: "\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4}") {
                if let match = try? parseDiv(div) {
                    matches.append(match)
                }
            }
        }
        
        // Remove duplicates based on date and type
        matches = Array(Set(matches))
        
        if matches.isEmpty {
            print("No matches found in any parsing attempt")
            throw ScrapingError.noDataFound
        }
        
        print("Found \(matches.count) total matches")
        return matches
    }
    
    private func parseTable(_ table: Element) throws -> [Match] {
        var matches: [Match] = []
        
        let rows = try table.select("tr")
        guard rows.count > 1 else { return [] }
        
        let headers = try rows[0].select("th, td").map { try $0.text().lowercased() }
        print("Table headers found: \(headers)")
        
        // Try to find relevant column indices
        let dateIndex = headers.firstIndex { $0.contains("datum") } ?? 0
        let typeIndex = headers.firstIndex { $0.contains("type") || $0.contains("soort") } ?? 1
        let categoryIndex = headers.firstIndex { $0.contains("categorie") || $0.contains("klasse") } ?? 2
        let organizerIndex = headers.firstIndex { $0.contains("organisator") || $0.contains("organisatie") } ?? 3
        let locationIndex = headers.firstIndex { $0.contains("locatie") || $0.contains("plaats") } ?? 4
        let statusIndex = headers.firstIndex { $0.contains("status") || $0.contains("inschrijving") } ?? 5
        
        for row in rows.dropFirst() {
            let cells = try row.select("td")
            if cells.count >= min(dateIndex, typeIndex) + 1 {
                let dateString = try cells[dateIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let type = try cells[typeIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let category = cells.count > categoryIndex ? try cells[categoryIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let organizer = cells.count > organizerIndex ? try cells[organizerIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let location = cells.count > locationIndex ? try cells[locationIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let status = cells.count > statusIndex ? try cells[statusIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                
                if let match = createMatch(dateString: dateString, type: type, category: category, organizer: organizer, location: location, status: status) {
                    matches.append(match)
                }
            }
        }
        
        return matches
    }
    
    private func parseRow(_ row: Element) throws -> Match? {
        let cells = try row.select("div, span, td")
        var dateString = ""
        var type = ""
        var category = ""
        var location = ""
        var status = ""
        
        for cell in cells {
            let text = try cell.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.matches(pattern: "\\d{1,2}[-/]\\d{1,2}[-/]\\d{2,4}") {
                dateString = text
            } else if text.lowercased().contains("open") || text.lowercased().contains("gesloten") {
                status = text
            } else if text.contains(",") {
                location = text
            } else if text.count > 20 {
                type = text
            } else if !text.isEmpty {
                category = text
            }
        }
        
        return createMatch(dateString: dateString, type: type, category: category, organizer: "", location: location, status: status)
    }
    
    private func parseEvent(_ event: Element) throws -> Match? {
        let dateText = try event.select("[class*='date'], [class*='datum'], time").first()?.text() ?? ""
        let typeText = try event.select("[class*='type'], [class*='title'], h3, h4").first()?.text() ?? ""
        let categoryText = try event.select("[class*='category'], [class*='categorie']").first()?.text() ?? ""
        let locationText = try event.select("[class*='location'], [class*='locatie']").first()?.text() ?? ""
        let statusText = try event.select("[class*='status'], [class*='state']").first()?.text() ?? ""
        
        return createMatch(dateString: dateText, type: typeText, category: categoryText, organizer: "", location: locationText, status: statusText)
    }
    
    private func parseDiv(_ div: Element) throws -> Match? {
        let text = try div.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let components = text.components(separatedBy: CharacterSet(charactersIn: ",-/"))
        
        guard components.count >= 2 else { return nil }
        
        let dateString = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let type = components.count > 1 ? components[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let location = components.count > 2 ? components[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        
        return createMatch(dateString: dateString, type: type, category: "", organizer: "", location: location, status: "")
    }
    
    private func createMatch(dateString: String, type: String, category: String, organizer: String, location: String, status: String) -> Match? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        
        let dateFormats = ["dd-MM-yyyy", "d-M-yyyy", "dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd"]
        var date: Date?
        
        // Clean up the date string
        let cleanDateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let parsedDate = dateFormatter.date(from: cleanDateString) {
                date = parsedDate
                break
            }
        }
        
        guard let date = date else {
            print("Failed to parse date: \(dateString)")
            return nil
        }
        
        // Only create match if we have at least a date and some other information
        guard !type.isEmpty || !category.isEmpty || !location.isEmpty else {
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

extension ScrapingError: LocalizedError {
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

extension Match: Hashable {
    static func == (lhs: Match, rhs: Match) -> Bool {
        lhs.date == rhs.date && lhs.type == rhs.type
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(type)
    }
} 