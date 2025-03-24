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
            
            UpcomingMatchesView()
                .tabItem {
                    Label("Aanstaande", systemImage: "calendar")
                }
                .tag(1)
            
            CompletedMatchesView()
                .tabItem {
                    Label("Geschiedenis", systemImage: "checkmark.circle")
                }
                .tag(2)
            
            NotificationSettingsView()
                .tabItem {
                    Label("Instellingen", systemImage: "gear")
                }
                .tag(3)
        }
        .environmentObject(scrapingService)
        .environmentObject(notificationService)
        .task {
            await scrapingService.fetchMatches()
        }
        .tint(ColorTheme.primary)
        .background(ColorTheme.background)
    }
}

struct MatchListView: View {
    @EnvironmentObject var scrapingService: ScrapingService
    @State private var selectedCategory: String?
    @State private var selectedStatus: Match.RegistrationStatus?
    
    var body: some View {
        NavigationView {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter Section
                    VStack(spacing: 8) {
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
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    
                    // Matches List
                    if scrapingService.isLoading {
                        Spacer()
                        ProgressView("Laden...")
                            .foregroundColor(ColorTheme.primary)
                        Spacer()
                    } else if let error = scrapingService.error {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("Er is een fout opgetreden")
                                .font(.headline)
                                .foregroundColor(ColorTheme.error)
                            Text(error.localizedDescription)
                                .font(.subheadline)
                                .foregroundColor(ColorTheme.error)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Opnieuw proberen") {
                                Task {
                                    await scrapingService.fetchMatches()
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(ColorTheme.primary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(scrapingService.filteredMatches(category: selectedCategory, status: selectedStatus)) { match in
                                    MatchRow(match: match)
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                        }
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

struct UpcomingMatchesView: View {
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var scrapingService: ScrapingService
    
    var upcomingMatches: [Match] {
        scrapingService.matches.filter { match in
            notificationService.hasNotificationEnabled(for: match.id)
        }.sorted { $0.date < $1.date }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                if upcomingMatches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 50))
                            .foregroundColor(ColorTheme.secondary)
                        Text("Geen aanstaande wedstrijden")
                            .font(.headline)
                            .foregroundColor(ColorTheme.text)
                        Text("Zet notificaties aan voor wedstrijden die je niet wilt missen")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.text.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(upcomingMatches) { match in
                                MatchRow(match: match)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Aanstaande")
        }
    }
}

struct CompletedMatchesView: View {
    @AppStorage("completedMatches") private var completedMatchesData: Data = Data()
    @State private var completedMatches: [CompletedMatch] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                ColorTheme.background.ignoresSafeArea()
                
                if completedMatches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 50))
                            .foregroundColor(ColorTheme.secondary)
                        Text("Geen voltooide wedstrijden")
                            .font(.headline)
                            .foregroundColor(ColorTheme.text)
                        Text("Hier zie je een overzicht van wedstrijden waaraan je hebt deelgenomen")
                            .font(.subheadline)
                            .foregroundColor(ColorTheme.text.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(completedMatches) { match in
                                CompletedMatchRow(match: match)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Geschiedenis")
        }
        .onAppear {
            loadCompletedMatches()
        }
    }
    
    private func loadCompletedMatches() {
        if let decoded = try? JSONDecoder().decode([CompletedMatch].self, from: completedMatchesData) {
            completedMatches = decoded.sorted { $0.completionDate > $1.completionDate }
        }
    }
}

struct CompletedMatchRow: View {
    let match: CompletedMatch
    
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
                .foregroundColor(ColorTheme.text.opacity(0.8))
            
            Text(match.completionDate, style: .date)
                .font(.subheadline)
                .foregroundColor(ColorTheme.text.opacity(0.8))
            
            if !match.notes.isEmpty {
                Text(match.notes)
                    .font(.subheadline)
                    .foregroundColor(ColorTheme.text.opacity(0.8))
                    .padding(.top, 4)
            }
            
            if let ranking = match.ranking {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(ColorTheme.primary)
                    Text("Plaats \(ranking)")
                        .font(.subheadline)
                        .foregroundColor(ColorTheme.primary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: ColorTheme.primary.opacity(0.1), radius: 4, x: 0, y: 2)
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
                .background(isSelected ? ColorTheme.primary : ColorTheme.secondary.opacity(0.1))
                .foregroundColor(isSelected ? .white : ColorTheme.text)
                .cornerRadius(20)
                .shadow(color: isSelected ? ColorTheme.primary.opacity(0.3) : Color.clear, radius: 3, x: 0, y: 2)
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
                .foregroundColor(ColorTheme.text.opacity(0.8))
            
            Text(match.date, style: .date)
                .font(.subheadline)
                .foregroundColor(ColorTheme.text.opacity(0.8))
            
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: ColorTheme.primary.opacity(0.1), radius: 4, x: 0, y: 2)
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
                Section(header: Text("Notificaties").foregroundColor(ColorTheme.text)) {
                    Toggle("Push Notificaties", isOn: $notificationService.isPushNotificationsEnabled)
                        .onChange(of: notificationService.isPushNotificationsEnabled) { oldValue, newValue in
                            if newValue {
                                notificationService.requestPushNotificationPermission()
                            }
                        }
                    
                    Toggle("SMS Notificaties", isOn: $notificationService.isSMSNotificationsEnabled)
                    Toggle("E-mail Notificaties", isOn: $notificationService.isEmailNotificationsEnabled)
                }
                
                Section(header: Text("Over").foregroundColor(ColorTheme.text), footer: Text("Versie 1.0.0").foregroundColor(ColorTheme.text.opacity(0.6))) {
                    Text("Hondenwedstrijd App")
                        .foregroundColor(ColorTheme.text)
                }
            }
            .navigationTitle("Instellingen")
            .tint(ColorTheme.primary)
            .scrollContentBackground(.hidden)
            .background(ColorTheme.background)
        }
    }
}

#Preview {
    ContentView()
} 