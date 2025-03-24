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
        .tint(ColorTheme.primary)
    }
}

struct MatchListView: View {
    @EnvironmentObject var scrapingService: ScrapingService
    @State private var selectedCategory: String?
    @State private var selectedStatus: Match.RegistrationStatus?
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Section
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(title: "Alle", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        
                        ForEach(Array(scrapingService.categories), id: \.self) { category in
                            FilterChip(title: category, isSelected: selectedCategory == category) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                // Status Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterChip(title: "Alle Status", isSelected: selectedStatus == nil) {
                            selectedStatus = nil
                        }
                        
                        ForEach([Match.RegistrationStatus.available, .notAvailable, .closed], id: \.self) { status in
                            FilterChip(title: status.rawValue, isSelected: selectedStatus == status) {
                                selectedStatus = status
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
                
                // Matches List
                Group {
                    if scrapingService.isLoading {
                        ProgressView("Laden...")
                            .foregroundColor(ColorTheme.primary)
                    } else if let error = scrapingService.error {
                        VStack {
                            Text("Er is een fout opgetreden")
                                .font(.headline)
                                .foregroundColor(ColorTheme.error)
                            Text(error.localizedDescription)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.error)
                            Button("Opnieuw proberen") {
                                Task {
                                    await scrapingService.fetchMatches()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(ColorTheme.primary)
                        }
                    } else {
                        List(scrapingService.filteredMatches(category: selectedCategory, status: selectedStatus)) { match in
                            MatchRow(match: match)
                        }
                        .listStyle(PlainListStyle())
                    }
                }
            }
            .navigationTitle("Wedstrijden")
            .refreshable {
                await scrapingService.fetchMatches()
            }
            .background(ColorTheme.background)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? ColorTheme.primary : ColorTheme.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : ColorTheme.text)
                .cornerRadius(20)
        }
    }
}

struct MatchRow: View {
    let match: Match
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(match.type)
                .font(.headline)
                .foregroundColor(ColorTheme.text)
            
            Text(match.category)
                .font(.subheadline)
                .foregroundColor(ColorTheme.secondary)
            
            Text(match.location)
                .font(.subheadline)
                .foregroundColor(ColorTheme.text)
            
            Text(match.date, style: .date)
                .font(.subheadline)
                .foregroundColor(ColorTheme.text)
            
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
        .padding(.horizontal, 8)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 2)
    }
    
    private var registrationStatusColor: Color {
        switch match.registrationStatus {
        case .available:
            return ColorTheme.success
        case .notAvailable:
            return ColorTheme.warning
        case .closed:
            return ColorTheme.error
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
            .tint(ColorTheme.primary)
        }
    }
}

#Preview {
    ContentView()
} 