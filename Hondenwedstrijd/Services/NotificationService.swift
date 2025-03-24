import Foundation
import UserNotifications
import MessageUI

class NotificationService: ObservableObject {
    @Published var isPushNotificationsEnabled = false
    @Published var isSMSNotificationsEnabled = false
    @Published var isEmailNotificationsEnabled = false
    
    static let shared = NotificationService()
    
    private init() {
        checkNotificationStatus()
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isPushNotificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestPushNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.isPushNotificationsEnabled = granted
            }
        }
    }
    
    func scheduleMatchNotification(for match: Match) {
        let content = UNMutableNotificationContent()
        content.title = "Nieuwe Wedstrijd Beschikbaar"
        content.body = "\(match.type) in \(match.location) is nu open voor inschrijving"
        content.sound = .default
        
        // Schedule notification for when registration opens
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(identifier: match.id.uuidString, content: content, trigger: trigger)
        
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