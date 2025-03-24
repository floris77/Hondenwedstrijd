# Hondenwedstrijd App

Een iOS-applicatie voor het bijhouden van Nederlandse hondenwedstrijden. Deze app helpt gebruikers op de hoogte te blijven van beschikbare wedstrijden en hun inschrijfstatus.

## Functies

- Bekijk alle beschikbare hondenwedstrijden
- Ontvang notificaties wanneer:
  - Nieuwe wedstrijden beschikbaar komen
  - Wedstrijden open zijn voor inschrijving
  - Wedstrijden gesloten worden
- Kies tussen verschillende notificatiemethoden:
  - Push notificaties
  - SMS notificaties
  - E-mail notificaties
- Volledig in het Nederlands
- Automatische updates van wedstrijdgegevens

## Vereisten

- iOS 15.0 of hoger
- Xcode 13.0 of hoger
- Swift 5.5 of hoger

## Installatie

1. Clone de repository
2. Open het project in Xcode
3. Voeg de SwiftSoup dependency toe via Swift Package Manager
4. Build en run het project

## Configuratie

Voor het gebruik van push notificaties:
1. Configureer een Apple Push Notification service (APNs) certificaat
2. Voeg de benodigde capabilities toe in Xcode
3. Update de app's provisioning profile

Voor SMS notificaties:
1. Configureer een SMS gateway service
2. Voeg de benodigde API keys toe in de app's configuratie

Voor e-mail notificaties:
1. Configureer een e-mail service
2. Voeg de benodigde SMTP instellingen toe

## Privacy

De app verzamelt alleen de benodigde gegevens voor het functioneren van de notificaties. Alle persoonlijke gegevens worden veilig opgeslagen en worden niet gedeeld met derden.

## Support

Voor vragen of problemen, neem contact op via:
[Contactgegevens]

## Licentie

Dit project is eigendom van [Eigenaar] en is niet open source.

## Laatste Update
- GitHub integratie getest en bevestigd
- Basis app structuur geïmplementeerd
- Scraping functionaliteit toegevoegd 