import Foundation
@_exported import SwiftyStoreKit
import StoreKit

extension PurchaseDetails: @unchecked @retroactive Sendable {}
extension ReceiptInfo: @unchecked Sendable {}
extension Purchase: @unchecked @retroactive Sendable {}

public struct XCBuy {
    
    public static func buy(_ productId: String) async throws {
        do {
            let result = try await SwiftyStoreKit.async_purchaseProduct(productId)
            let verify_result = try await XCBuy.fetchVerifyInfo([productId])
            if result.needsFinishTransaction && verify_result.valids.contains(result.productId) {
                SwiftyStoreKit.finishTransaction(result.transaction)
            }
        } catch {
            throw error
        }
    }
    
    public static func restore() async throws {
        do {
            let result = await SwiftyStoreKit.async_restorePurchases().filter { $0.needsFinishTransaction }
            try await XCBuy.completeTransactions(result)
        } catch {
            throw error
        }
    }
    
    public static func completeTransactions(_ purchases: [Purchase]) async throws {
        let verify_result = try await XCBuy.fetchVerifyInfo(purchases.map { $0.productId })
        for purchase in purchases {
            if verify_result.valids.contains(purchase.productId) {
                SwiftyStoreKit.finishTransaction(purchase.transaction)
            } else if verify_result.expireds.contains(purchase.productId) {
                SwiftyStoreKit.finishTransaction(purchase.transaction)
            }
        }
    }
    
    public static func info(_ productIds: Set<String>) async -> Set<XCProduct> {
        let products = await SwiftyStoreKit.async_retrieveProductsInfo(productIds)
        var results: Set<XCProduct> = []
        for product in products {
            // priceLocale
            let p = XCProduct(id: product.productIdentifier, name: product.localizedTitle, price: product.localizedPrice ?? "-")
            results.insert(p)
        }
        return results
    }
    
    public static func fetchExpiryDate(_ productIds: Set<String>) async throws -> Date {
        if SwiftyStoreKit.canMakePayments {
            throw NSError(domain: "Currently unable to purchase", code: -2)
        }
        let result = try await XCBuy.verify(Array<String>(productIds))
        switch result {
        case .purchased(let expiryDate, let receiptItems):
            print("Product is valid until \(expiryDate)")
            return expiryDate
        case .expired(let expiryDate, let receiptItems):
            print("Product is expired since \(expiryDate)")
            return expiryDate
        case .notPurchased:
            throw NSError(domain: "This product has never been purchased", code: -1)
        }
    }
}

private extension XCBuy {
    @discardableResult
    static func verify(_ productIds: [String]) async throws -> VerifySubscriptionResult {
        let appleValidator = AppleReceiptValidator(service: .production, sharedSecret: "2692643d03684b37884f948b9718f938")
        let verify_receipt_result = try await SwiftyStoreKit.async_verifyReceipt(using: appleValidator)
        let result = if productIds.count == 1 {
            SwiftyStoreKit.verifySubscription(
                ofType: .autoRenewable,
                productId: productIds[0],
                inReceipt: verify_receipt_result.receipt
            )
        } else {
            SwiftyStoreKit.verifySubscriptions(
                ofType: .autoRenewable,
                productIds: Set(productIds),
                inReceipt: verify_receipt_result.receipt
            )
        }
        
        return result
    }
    
    @discardableResult
    static func fetchVerifyInfo(_ productIds: [String]) async throws -> (valids: Set<String>, expireds: Set<String>) {
        let result = try await XCBuy.verify(productIds)
        var valid: Set<String> = []
        var expired: Set<String> = []
        switch result {
        case .purchased(let expiryDate, let receiptItems):
            print("Product is valid until \(expiryDate)")
            for receiptItem in receiptItems {
                valid.insert(receiptItem.productId)
            }
        case .expired(let expiryDate, let receiptItems):
            print("Product is expired since \(expiryDate)")
            for receiptItem in receiptItems {
                expired.insert(receiptItem.productId)
            }
        case .notPurchased:
            print("This product has never been purchased")
        }
        return (valid, expired)
    }
}

extension SwiftyStoreKit {
    static func async_purchaseProduct(
        _ productId: String,
        quantity: Int = 1,
        atomically: Bool = false,
        applicationUsername: String = "",
        simulatesAskToBuyInSandbox: Bool = false
    ) async throws -> PurchaseDetails {
        try await withUnsafeThrowingContinuation { continuation in
            SwiftyStoreKit.purchaseProduct(
                productId,
                quantity: quantity,
                atomically: atomically,
                applicationUsername: applicationUsername,
                simulatesAskToBuyInSandbox: simulatesAskToBuyInSandbox
            ) { result in
                switch result {
                case .success(let purchase):
                    continuation.resume(returning: purchase)
                case .deferred(let purchase):
                    continuation.resume(returning: purchase)
                case .error(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    static func async_fetchReceipt(forceRefresh: Bool = true) async throws -> String {
        try await withUnsafeThrowingContinuation { c in
            SwiftyStoreKit.fetchReceipt(forceRefresh: forceRefresh) { fetchReceiptResult in
                switch fetchReceiptResult {
                case .success(let receiptData):
                    let receipt = receiptData.base64EncodedString()
                    c.resume(returning: receipt)
                case .error(let error):
                    c.resume(throwing: error)
                }
            }
        }
    }
    
    static func async_verifyReceipt(
        using validator: ReceiptValidator,
        forceRefresh: Bool = true
    ) async throws -> XCReceiptInfo {
        try await withUnsafeThrowingContinuation { continuation in
            SwiftyStoreKit.verifyReceipt(using: validator, forceRefresh: forceRefresh) { verifyReceiptResult in
                switch verifyReceiptResult {
                case .success(let receipt):
                    continuation.resume(returning: .init(receipt: receipt))
                case .error(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    static func async_restorePurchases(
        atomically: Bool = false,
        applicationUsername: String = ""
    ) async -> [Purchase] {
        await withUnsafeContinuation { continuation in
            SwiftyStoreKit.restorePurchases(atomically: atomically, applicationUsername: applicationUsername) { results in
                continuation.resume(returning: results.restoredPurchases)
            }
        }
    }
    
    static func async_retrieveProductsInfo(_ productIds: Set<String>) async -> Set<SKProduct> {
        await withUnsafeContinuation { c in
            SwiftyStoreKit.retrieveProductsInfo(productIds) { result in
                c.resume(returning: result.retrievedProducts)
            }
        }
    }
}

struct XCReceiptInfo: @unchecked Sendable {
    let receipt: ReceiptInfo
}

public struct XCProduct: Hashable {
    let id: String
    let name: String
    let price: String
}
