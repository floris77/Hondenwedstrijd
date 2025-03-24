import Foundation
import UserNotifications
import MessageUI
import SwiftUI

@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var isPushNotificationsEnabled = false
    @Published var isSMSNotificationsEnabled = false
    @Published var isEmailNotificationsEnabled = false
    
    @AppStorage("notifiedMatches") private var notifiedMatchesData: Data = Data()
    private var notifiedMatches: Set<UUID> = []
    
    private init() {
        loadNotifiedMatches()
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isPushNotificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestPushNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
            DispatchQueue.main.async {
                self.isPushNotificationsEnabled = success
            }
        }
    }
    
    func toggleNotification(for matchId: UUID) {
        if notifiedMatches.contains(matchId) {
            notifiedMatches.remove(matchId)
        } else {
            notifiedMatches.insert(matchId)
        }
        saveNotifiedMatches()
    }
    
    func hasNotificationEnabled(for matchId: UUID) -> Bool {
        notifiedMatches.contains(matchId)
    }
    
    private func loadNotifiedMatches() {
        if let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: notifiedMatchesData) {
            notifiedMatches = decoded
        }
    }
    
    private func saveNotifiedMatches() {
        if let encoded = try? JSONEncoder().encode(notifiedMatches) {
            notifiedMatchesData = encoded
        }
    }
    
    func scheduleNotification(for match: Match) {
        guard isPushNotificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Aanstaande Wedstrijd"
        content.body = "\(match.type) in \(match.location) begint binnenkort!"
        content.sound = .default
        
        // Schedule notification for 1 day before the match
        let calendar = Calendar.current
        guard let notificationDate = calendar.date(byAdding: .day, value: -1, to: match.date) else { return }
        
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: match.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func sendSMSNotification(for match: Match, to phoneNumber: String) {
        // Implementation would require SMS gateway integration
        // This is a placeholder for the actual implementation
    }
    
    func sendEmailNotification(for match: Match, to email: String) {
        // Implementation would require email service integration
        // This is a placeholder for the actual implementation
    }
} 