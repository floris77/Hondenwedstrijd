import Foundation

struct Match: Identifiable, Codable {
    let id: UUID
    let date: Date
    let type: String
    let organizer: String
    let location: String
    let notes: String
    let registrationStatus: RegistrationStatus
    
    enum RegistrationStatus: String, Codable {
        case available = "Inschrijven"
        case notAvailable = "Nog niet beschikbaar"
        case closed = "Gesloten"
    }
    
    init(id: UUID = UUID(), date: Date, type: String, organizer: String, location: String, notes: String, registrationStatus: RegistrationStatus) {
        self.id = id
        self.date = date
        self.type = type
        self.organizer = organizer
        self.location = location
        self.notes = notes
        self.registrationStatus = registrationStatus
    }
} 