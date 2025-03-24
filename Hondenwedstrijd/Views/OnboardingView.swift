import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let image: String
    let title: String
    let description: String
}

struct OnboardingView: View {
    @Binding var isOnboardingCompleted: Bool
    @State private var currentPage = 0
    
    let pages = [
        OnboardingPage(
            image: "list.bullet",
            title: "Alle Wedstrijden",
            description: "Bekijk alle beschikbare hondenwedstrijden in Nederland op één plek"
        ),
        OnboardingPage(
            image: "bell",
            title: "Notificaties",
            description: "Ontvang direct een bericht wanneer nieuwe wedstrijden beschikbaar komen"
        ),
        OnboardingPage(
            image: "tag",
            title: "Categorieën",
            description: "Filter wedstrijden op type en inschrijfstatus"
        ),
        OnboardingPage(
            image: "location",
            title: "Locaties",
            description: "Vind wedstrijden bij jou in de buurt"
        )
    ]
    
    var body: some View {
        ZStack {
            ColorTheme.background
                .ignoresSafeArea()
            
            VStack {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 20) {
                            Image(systemName: page.image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .foregroundColor(ColorTheme.primary)
                            
                            Text(page.title)
                                .font(.title)
                                .bold()
                                .foregroundColor(ColorTheme.text)
                            
                            Text(page.description)
                                .multilineTextAlignment(.center)
                                .foregroundColor(ColorTheme.text)
                                .padding(.horizontal)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        isOnboardingCompleted = true
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Volgende" : "Start")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(ColorTheme.primary)
                        .cornerRadius(25)
                }
                .padding(.bottom, 50)
            }
        }
    }
} 