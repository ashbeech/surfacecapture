//
//  AppDelegate.swift
//  Surface Capture App
//

import UIKit
import SwiftUI
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Prevent screen from sleeping during capture
        UIApplication.shared.isIdleTimerDisabled = true

        // Audio session setup
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
        
        // First launch setup for onboarding
        setupFirstLaunchDefaults()
        
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView()

        // Use a UIHostingController as window root view controller.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
    
    private func setupFirstLaunchDefaults() {
        // Reset previous onboarding key that might be incorrect
        if isFirstLaunch() {
            print("First launch detected - setting up defaults")
            // Reset any previous onboarding keys if they exist
            UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
        }
        
        let userDefaults = UserDefaults.standard
        
        // Safely set up each default value only if not already set
        if userDefaults.object(forKey: "onboardingShownCount") == nil {
            userDefaults.set(0, forKey: "onboardingShownCount")
            print("Set onboardingShownCount to 0")
        }
        
        if userDefaults.object(forKey: "hasCompletedOnboarding") == nil {
            userDefaults.set(false, forKey: "hasCompletedOnboarding")
            print("Set hasCompletedOnboarding to false")
        }
        
        if userDefaults.object(forKey: "maxOnboardingShows") == nil {
            userDefaults.set(10, forKey: "maxOnboardingShows")
            print("Set maxOnboardingShows to 10")
        }
        
        // Output current values for debugging
        print("Current UserDefaults:")
        print("- onboardingShownCount: \(userDefaults.integer(forKey: "onboardingShownCount"))")
        print("- hasCompletedOnboarding: \(userDefaults.bool(forKey: "hasCompletedOnboarding"))")
        print("- maxOnboardingShows: \(userDefaults.integer(forKey: "maxOnboardingShows"))")
    }
    
    private func isFirstLaunch() -> Bool {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            return true
        }
        return false
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Re-enable screen idle timer when app goes to background
        UIApplication.shared.isIdleTimerDisabled = false
        
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        
        // Reset idle timer disabling
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
}
