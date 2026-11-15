#if APP_STORE
import StoreKit
import SwiftUI

/// Optional developer tips for the Mac App Store edition: consumable in-app
/// purchases. Nothing in Glimpse is locked behind a tip.
@MainActor
final class TipJar: ObservableObject {
    static let shared = TipJar()
    static let productIDs = [
        "com.tastyjam.glimpse.tip.small",
        "com.tastyjam.glimpse.tip.medium",
        "com.tastyjam.glimpse.tip.large",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var message: String?
    @Published private(set) var purchasing = false
    private var updates: Task<Void, Never>?

    private init() {
        // Event-driven: finishes transactions that complete outside a purchase
        // call (Ask to Buy approvals, purchases interrupted by quitting).
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
    }

    func load() async {
        guard products.isEmpty else { return }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            if products.isEmpty { message = String(localized: "Tips are unavailable right now.") }
        } catch {
            message = String(localized: "Tips are unavailable right now.")
        }
    }

    func buy(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        message = nil
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                message = String(localized: "Thank you for supporting Glimpse! 💜")
            case .success(.unverified):
                message = String(localized: "The purchase could not be verified.")
            case .pending:
                message = String(localized: "The purchase is waiting for approval.")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = String(localized: "The purchase failed: \(error.localizedDescription)")
        }
    }
}

/// The tip buttons shown in About.
struct TipJarView: View {
    @ObservedObject private var tips = TipJar.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach(tips.products, id: \.id) { product in
                    Button("\(product.displayName) · \(product.displayPrice)") {
                        Task { await tips.buy(product) }
                    }
                    .disabled(tips.purchasing)
                }
                if tips.products.isEmpty && tips.message == nil { ProgressView().controlSize(.small) }
            }
            if let message = tips.message {
                Text(message).font(.callout).foregroundColor(.secondary)
            }
        }
        .task { await tips.load() }
    }
}

/// Asks for an App Store review at most once per version, only after two weeks
/// of use, and only when the person opens Settings. macOS decides whether the
/// prompt actually appears (at most three times a year).
enum ReviewPrompt {
    private static let firstUseKey = "GlimpseFirstUse"
    private static let requestedVersionKey = "GlimpseReviewRequestedVersion"

    @MainActor static func requestIfDue() {
        let defaults = UserDefaults.standard
        guard let firstUse = defaults.object(forKey: firstUseKey) as? Date else {
            defaults.set(Date(), forKey: firstUseKey)
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard Date().timeIntervalSince(firstUse) >= 14 * 24 * 60 * 60,
              defaults.string(forKey: requestedVersionKey) != version else { return }
        defaults.set(version, forKey: requestedVersionKey)
        // ponytail: the deprecated call works on macOS 12 through current; its
        // replacement needs an NSViewController the settings window doesn't have.
        SKStoreReviewController.requestReview()
    }
}
#endif
