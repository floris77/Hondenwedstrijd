import Foundation

struct CompletedMatch: Identifiable, Codable {
    let id: UUID
    let type: String
    let category: String
    let location: String
    let completionDate: Date
    let notes: String
    let ranking: Int?
    
    init(from match: Match, notes: String = "", ranking: Int? = nil) {
        self.id = match.id
        self.type = match.type
        self.category = match.category
        self.location = match.location
        self.completionDate = match.date
        self.notes = notes
        self.ranking = ranking
    }
} 