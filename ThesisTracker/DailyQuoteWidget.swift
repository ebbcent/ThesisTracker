import SwiftUI

// MARK: - Feature #14 : Citation motivante du jour

struct DailyQuoteWidget: View {
    @ObservedObject var store: DataStore
    @AppStorage("pinnedQuoteIndex") private var pinnedQuoteIndex: Int = -1

    private static let quotes: [(text: String, author: String)] = [
        ("Ce que l'on conçoit bien s'énonce clairement, et les mots pour le dire arrivent aisément.", "Nicolas Boileau"),
        ("Il n'y a pas de vent favorable pour celui qui ne sait pas où il va.", "Sénèque"),
        ("L'imagination est plus importante que le savoir.", "Albert Einstein"),
        ("Écrire, c'est une façon de parler sans être interrompu.", "Jules Renard"),
        ("La thèse est l'art de transformer l'incertitude en certitude provisoire.", "Umberto Eco"),
        ("Travaillez, prenez de la peine : c'est le fonds qui manque le moins.", "Jean de La Fontaine"),
        ("Le succès, c'est d'aller d'échec en échec sans perdre son enthousiasme.", "Winston Churchill"),
        ("Chaque page écrite est une victoire sur le silence.", "Anonyme"),
        ("La persévérance est la mère de la bonne fortune.", "Miguel de Cervantes"),
        ("On ne finit pas une thèse, on l'abandonne.", "Umberto Eco"),
        ("Un intellectuel est quelqu'un dont l'esprit se regarde lui-même.", "Paul Valéry"),
        ("La recherche est voir ce que tout le monde a vu et penser ce que personne n'a pensé.", "Albert von Szent-Györgyi"),
        ("Écrire, c'est aussi ne pas parler. C'est se taire. C'est hurler sans bruit.", "Marguerite Duras"),
        ("La lecture est à l'esprit ce que l'exercice est au corps.", "Joseph Addison"),
        ("Nul n'est prophète en son pays, mais tout chercheur peut l'être dans sa bibliographie.", "Anonyme"),
        ("La connaissance s'acquiert par l'expérience, tout le reste n'est qu'information.", "Albert Einstein"),
        ("Mieux vaut allumer une bougie que maudire l'obscurité.", "Confucius"),
        ("Le génie, c'est un pour cent d'inspiration et quatre-vingt-dix-neuf pour cent de transpiration.", "Thomas Edison"),
        ("Ce n'est pas parce que les choses sont difficiles que nous n'osons pas, c'est parce que nous n'osons pas qu'elles sont difficiles.", "Sénèque"),
        ("La thèse est un marathon, pas un sprint — mais chaque sprint compte.", "Anonyme"),
    ]

    private var todayQuoteIndex: Int {
        if pinnedQuoteIndex >= 0 && pinnedQuoteIndex < Self.quotes.count {
            return pinnedQuoteIndex
        }
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dayOfYear % Self.quotes.count
    }

    private var quote: (text: String, author: String) { Self.quotes[todayQuoteIndex] }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#0F766E").opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#0F766E"))
                    }
                    Text("Citation du jour")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        let next = (todayQuoteIndex + 1) % Self.quotes.count
                        pinnedQuoteIndex = next
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.pressable)
                    .help("Citer une autre")
                    .accessibilityLabel("Citer une autre")
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("❝")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Color(hex: "#0F766E").opacity(0.4))
                        .offset(y: -2)
                    Text(quote.text)
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Text("— \(quote.author)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .italic()
                }
            }
        }
    }
}
