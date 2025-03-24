import SwiftUI

struct ContentView: View {
    @StateObject private var scrapingService = ScrapingService()
    @StateObject private var notificationService = NotificationService.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MatchListView()
                .tabItem {
                    Label("Wedstrijden", systemImage: "list.bullet")
                }
                .tag(0)
            
            NotificationSettingsView()
                .tabItem {
                    Label("Instellingen", systemImage: "bell")
                }
                .tag(1)
        }
        .environmentObject(scrapingService)
        .environmentObject(notificationService)
        .task {
            await scrapingService.fetchMatches()
        }
    }
}

struct MatchListView: View {
    @EnvironmentObject var scrapingService: ScrapingService
    
    var body: some View {
        NavigationView {
            Group {
                if scrapingService.isLoading {
                    ProgressView("Laden...")
                } else if let error = scrapingService.error {
                    VStack {
                        Text("Er is een fout opgetreden")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Button("Opnieuw proberen") {
                            Task {
                                await scrapingService.fetchMatches()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List(scrapingService.matches) { match in
                        MatchRow(match: match)
                    }
                }
            }
            .navigationTitle("Wedstrijden")
            .refreshable {
                await scrapingService.fetchMatches()
            }
        }
    }
}

struct MatchRow: View {
    let match: Match
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(match.type)
                .font(.headline)
            
            Text(match.location)
                .font(.subheadline)
            
            Text(match.date, style: .date)
                .font(.subheadline)
            
            HStack {
                Text(match.registrationStatus.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(registrationStatusColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var registrationStatusColor: Color {
        switch match.registrationStatus {
        case .available:
            return .green
        case .notAvailable:
            return .orange
        case .closed:
            return .red
        }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject var notificationService: NotificationService
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notificaties")) {
                    Toggle("Push Notificaties", isOn: $notificationService.isPushNotificationsEnabled)
                        .onChange(of: notificationService.isPushNotificationsEnabled) { newValue in
                            if newValue {
                                notificationService.requestPushNotificationPermission()
                            }
                        }
                    
                    Toggle("SMS Notificaties", isOn: $notificationService.isSMSNotificationsEnabled)
                    Toggle("E-mail Notificaties", isOn: $notificationService.isEmailNotificationsEnabled)
                }
                
                Section(header: Text("Over"), footer: Text("Versie 1.0.0")) {
                    Text("Hondenwedstrijd App")
                }
            }
            .navigationTitle("Instellingen")
        }
    }
}

#Preview {
    ContentView()
} 