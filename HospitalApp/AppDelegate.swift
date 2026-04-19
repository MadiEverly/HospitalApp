//
//  AppDelegate.swift
//  HospitalApp
//
//  Created by Duane Homick on 2026-01-28.
//

import UIKit
import FirebaseCore
import FirebaseAuth

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        // Ensure we have an authenticated user (anonymous is fine for crowd submissions)
        Task {
            await ensureAnonymousAuth()
            // Kick off a throttled purge of stale, unverified facility issues (>24h)
            await DataManager.shared.purgeStaleUnverifiedFacilityIssuesIfNeeded()
        }
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    // MARK: - Auth
    private func ensureAnonymousAuth() async {
        if Auth.auth().currentUser != nil {
            return
        }
        do {
            _ = try await Auth.auth().signInAnonymously()
        } catch {
            // We’ll still fall back to an Installations ID in DataManager if this fails,
            // but writes will likely be blocked by Firestore rules until Auth succeeds.
            print("Anonymous Auth failed: \(error.localizedDescription)")
        }
    }
}
