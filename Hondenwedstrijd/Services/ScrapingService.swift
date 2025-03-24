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
            let url = URL(string: "https://www.hondenwedstrijd.nl/")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let html = String(data: data, encoding: .utf8)!
            let doc = try SwiftSoup.parse(html)
            
            guard let table = try doc.select("table").first() else {
                throw ScrapingError.tableNotFound
            }
            
            let rows = try table.select("tr")
            let rowsArray = Array(rows).dropFirst() // Skip header row
            
            matches = try rowsArray.compactMap { row in
                let columns = try row.select("td")
                if columns.count >= 7 {
                    let dateString = try columns[0].text()
                    let type = try columns[1].text()
                    let category = try columns[2].text()
                    let organizer = try columns[3].text()
                    let location = try columns[4].text()
                    let notes = try columns[5].text()
                    let registrationStatus = try columns[6].text()
                    
                    // Convert date string to Date
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "dd-MM-yyyy"
                    guard let date = dateFormatter.date(from: dateString) else {
                        return nil
                    }
                    
                    return Match(
                        date: date,
                        type: type,
                        category: category,
                        organizer: organizer,
                        location: location,
                        notes: notes,
                        registrationStatus: Match.RegistrationStatus(rawValue: registrationStatus) ?? .notAvailable
                    )
                }
                return nil
            }
        } catch {
            self.error = error
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

enum ScrapingError: Error {
    case tableNotFound
} 