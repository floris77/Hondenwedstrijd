import Foundation
import SwiftSoup
import SwiftUI

@MainActor
class ScrapingService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let urls = [
        "https://my.orweja.nl/home/kalender/1",
        "https://my.orweja.nl/kalender",
        "https://orweja.nl/jachthondenproeven",
        "https://orweja.nl/maps",
        "https://orweja.nl/veldwedstrijden"
    ]
    
    var categories: Set<String> {
        Set(matches.map { $0.category })
    }
    
    func fetchMatches() async {
        isLoading = true
        error = nil
        matches = []
        
        do {
            var allMatches: [Match] = []
            
            // Try each URL in sequence
            for url in urls {
                do {
                    let urlMatches = try await fetchFromURL(URL(string: url)!)
                    if !urlMatches.isEmpty {
                        allMatches.append(contentsOf: urlMatches)
                        print("Successfully fetched \(urlMatches.count) matches from \(url)")
                    }
                } catch {
                    print("Failed to fetch from \(url): \(error)")
                    continue
                }
            }
            
            // Remove duplicates and sort
            matches = Array(Set(allMatches)).sorted { $0.date < $1.date }
            
            if matches.isEmpty {
                throw ScrapingError.noDataFound
            }
            
            print("Total matches found: \(matches.count)")
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
        
        // Try multiple selectors for content areas
        let contentSelectors = [
            "#main-content",
            ".main-content",
            ".content-area",
            ".page-content",
            "#content",
            ".kalender",
            ".calendar",
            ".events",
            ".wedstrijden"
        ]
        
        let searchArea = try doc.select(contentSelectors.joined(separator: ", ")).first() ?? doc
        
        // Print structure for debugging
        print("Document structure for \(url.absoluteString):")
        print(try searchArea.html())
        
        var matches: [Match] = []
        
        // 1. Try finding tables with specific classes
        let tableSelectors = [
            "table.calendar",
            "table.events",
            "table.wedstrijden",
            "table.matches",
            "table.kalender",
            ".table",
            "table"
        ]
        
        let tables = try searchArea.select(tableSelectors.joined(separator: ", "))
        print("Found \(tables.count) tables")
        
        for table in tables {
            if let tableMatches = try? parseTable(table), !tableMatches.isEmpty {
                matches.append(contentsOf: tableMatches)
            }
        }
        
        // 2. Try finding event containers
        let eventSelectors = [
            ".event",
            ".wedstrijd",
            ".match",
            ".calendar-item",
            "[class*='event']",
            "[class*='wedstrijd']",
            "[class*='match']",
            "[class*='calendar']"
        ]
        
        let events = try searchArea.select(eventSelectors.joined(separator: ", "))
        print("Found \(events.count) event elements")
        
        for event in events {
            if let match = try? parseEvent(event) {
                matches.append(match)
            }
        }
        
        // 3. Try finding date-containing elements
        if matches.isEmpty {
            let datePattern = "\\d{1,2}[-/.](\\d{1,2}|[A-Za-z]+)[-/.]\\d{2,4}"
            let elements = try searchArea.select("*")
            
            for element in elements {
                let text = try element.text()
                if text.matches(pattern: datePattern) {
                    if let match = try? parseElement(element) {
                        matches.append(match)
                    }
                }
            }
        }
        
        return matches
    }
    
    private func parseTable(_ table: Element) throws -> [Match] {
        var matches: [Match] = []
        
        let rows = try table.select("tr, .row")
        guard rows.count > 1 else { return [] }
        
        // Try to find headers in multiple ways
        var headers: [String] = []
        if let headerRow = rows.first {
            headers = try headerRow.select("th, td, .header, .cell").map { 
                try $0.text().lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        print("Table headers found: \(headers)")
        
        // Map common header variations
        let headerMappings = [
            "datum": ["datum", "date", "dag", "day"],
            "type": ["type", "soort", "proef", "wedstrijd", "event"],
            "category": ["categorie", "klasse", "category", "class"],
            "location": ["locatie", "plaats", "location", "venue"],
            "status": ["status", "inschrijving", "registration", "state"]
        ]
        
        // Find column indices
        let dateIndex = headers.firstIndex { str in headerMappings["datum"]?.contains(where: { str.contains($0) }) ?? false } ?? 0
        let typeIndex = headers.firstIndex { str in headerMappings["type"]?.contains(where: { str.contains($0) }) ?? false } ?? 1
        let categoryIndex = headers.firstIndex { str in headerMappings["category"]?.contains(where: { str.contains($0) }) ?? false } ?? 2
        let locationIndex = headers.firstIndex { str in headerMappings["location"]?.contains(where: { str.contains($0) }) ?? false } ?? 3
        let statusIndex = headers.firstIndex { str in headerMappings["status"]?.contains(where: { str.contains($0) }) ?? false } ?? 4
        
        for row in rows.dropFirst() {
            let cells = try row.select("td, .cell")
            if cells.count >= min(dateIndex, typeIndex) + 1 {
                let dateString = try cells[dateIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let type = try cells[typeIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let category = cells.count > categoryIndex ? try cells[categoryIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let location = cells.count > locationIndex ? try cells[locationIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let status = cells.count > statusIndex ? try cells[statusIndex].text().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                
                if let match = createMatch(dateString: dateString, type: type, category: category, organizer: "", location: location, status: status) {
                    matches.append(match)
                }
            }
        }
        
        return matches
    }
    
    private func parseEvent(_ event: Element) throws -> Match? {
        // Define selectors
        let dateSelector = "[class*='date'], [class*='datum'], time, .date, .datum"
        let typeSelector = "[class*='type'], [class*='title'], h3, h4, .type, .title"
        let categorySelector = "[class*='category'], [class*='categorie'], .category, .categorie"
        let locationSelector = "[class*='location'], [class*='locatie'], .location, .locatie"
        let statusSelector = "[class*='status'], [class*='state'], .status, .state"
        
        let dateText = try event.select(dateSelector).first()?.text() ?? ""
        let typeText = try event.select(typeSelector).first()?.text() ?? ""
        let categoryText = try event.select(categorySelector).first()?.text() ?? ""
        let locationText = try event.select(locationSelector).first()?.text() ?? ""
        let statusText = try event.select(statusSelector).first()?.text() ?? ""
        
        return createMatch(dateString: dateText, type: typeText, category: categoryText, organizer: "", location: locationText, status: statusText)
    }
    
    private func parseElement(_ element: Element) throws -> Match? {
        let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract date and other information
        let datePattern = "\\d{1,2}[-/.](\\d{1,2}|[A-Za-z]+)[-/.]\\d{2,4}"
        let regex = try? NSRegularExpression(pattern: datePattern)
        let range = NSRange(text.startIndex..., in: text)
        
        guard let match = regex?.firstMatch(in: text, range: range),
              let dateRange = Range(match.range, in: text) else {
            return nil
        }
        
        let dateString = String(text[dateRange])
        let remainingText = text.replacingCharacters(in: dateRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Split remaining text into components
        let components = remainingText.components(separatedBy: CharacterSet(charactersIn: ",-/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let type = components.first ?? ""
        let location = components.count > 1 ? components[1] : ""
        let category = components.count > 2 ? components[2] : ""
        
        return createMatch(dateString: dateString, type: type, category: category, organizer: "", location: location, status: "")
    }
    
    private func createMatch(dateString: String, type: String, category: String, organizer: String, location: String, status: String) -> Match? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "nl_NL")
        
        // Support various date formats including Dutch month names
        let dateFormats = [
            "dd-MM-yyyy",
            "d-M-yyyy",
            "dd/MM/yyyy",
            "d/M/yyyy",
            "yyyy-MM-dd",
            "dd-MMM-yyyy",
            "d MMM yyyy",
            "dd MMM yyyy"
        ]
        
        // Clean up the date string
        let cleanDateString = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        var date: Date?
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
        case let s where s.contains("gesloten") || s.contains("vol"):
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

extension Match: Hashable {
    static func == (lhs: Match, rhs: Match) -> Bool {
        lhs.date == rhs.date && lhs.type == rhs.type
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(type)
    }
} 