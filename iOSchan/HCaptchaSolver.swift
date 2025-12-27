import Foundation
import UIKit

//super fucked

#if canImport(HCaptcha)
import HCaptcha

enum HCaptchaSolverError: Error {
    case noWindow
}

private enum _HCaptchaRetainer { static var retained: HCaptcha? }

struct HCaptchaSolver {
    static func solve(siteKey: String, baseURL: URL) async throws -> String {
        let config = HCaptchaConfig(siteKey: siteKey, baseURL: baseURL)
        let hcaptcha = try HCaptcha(config: config)
        _HCaptchaRetainer.retained = hcaptcha
        let view = try await findPresentingView()
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                hcaptcha.validate(on: view, resetOnError: true) { result in
                    // Release after completion
                    _HCaptchaRetainer.retained = nil
                    switch result {
                    case .success(let token):
                        cont.resume(returning: token)
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    @MainActor private static func findPresentingView() async throws -> UIView {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }),
           let rootView = window.rootViewController?.view {
            return rootView
        }
        if let window = UIApplication.shared.windows.first, let rootView = window.rootViewController?.view {
            return rootView
        }
        throw HCaptchaSolverError.noWindow
    }
}
#else

struct HCaptchaSolver {
    static func solve(siteKey: String, baseURL: URL) async throws -> String {
        throw NSError(domain: "HCaptcha", code: -1, userInfo: [NSLocalizedDescriptionKey: "HCaptcha SDK not integrated. Add https://github.com/hCaptcha/HCaptcha-ios-sdk via Swift Package Manager."])
    }
}

#endif

