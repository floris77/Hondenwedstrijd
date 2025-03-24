import Foundation
import SwiftSoup

class ScrapingService: ObservableObject {
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var categories: Set<String> = []
    
    private let baseURL = "https://my.orweja.nl/home/kalender/1"
    
    func fetchMatches() async {
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        do {
            guard let url = URL(string: baseURL) else {
                throw URLError(.badURL)
            }
            
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "ScrapingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode HTML data"])
            }
            
            let doc = try SwiftSoup.parse(htmlString)
            let table = try doc.select("table").first()
            let rows = try table?.select("tr")
            
            var parsedMatches: [Match] = []
            var uniqueCategories = Set<String>()
            
            // Skip header row and process remaining rows
            if let rows = rows {
                let dataRows = Array(rows.dropFirst())
                for row in dataRows {
                    let columns = try row.select("td")
                    guard columns.count >= 7 else { continue }
                    
                    let dateString = try columns[0].text()
                    let type = try columns[1].text()
                    let category = try columns[2].text()
                    let organizer = try columns[3].text()
                    let location = try columns[4].text()
                    let notes = try columns[5].text()
                    let registrationText = try columns[6].text()
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd-MM-yyyy"
                    guard let date = dateFormatter.date(from: dateString) else { continue }
                    
                    let registrationStatus: Match.RegistrationStatus
                    switch registrationText.lowercased() {
                    case "inschrijven":
                        registrationStatus = .available
                    case "nog niet beschikbaar":
                        registrationStatus = .notAvailable
                    case "gesloten":
                        registrationStatus = .closed
                    default:
                        registrationStatus = .notAvailable
                    }
                    
                    let match = Match(
                        date: date,
                        type: type,
                        category: category,
                        organizer: organizer,
                        location: location,
                        notes: notes,
                        registrationStatus: registrationStatus
                    )
                    
                    parsedMatches.append(match)
                    uniqueCategories.insert(category)
                }
            }
            
            DispatchQueue.main.async {
                self.matches = parsedMatches.sorted { $0.date < $1.date }
                self.categories = uniqueCategories
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.error = error
            }
        }
    }
    
    func filteredMatches(category: String? = nil, status: Match.RegistrationStatus? = nil) -> [Match] {
        matches.filter { match in
            let categoryMatch = category == nil || match.category == category
            let statusMatch = status == nil || match.registrationStatus == status
            return categoryMatch && statusMatch
        }
    }
} 