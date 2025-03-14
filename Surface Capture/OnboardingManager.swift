//
//  OnboardingManager.swift
//  Surface Capture App
//

import Foundation
import Combine

class OnboardingManager: ObservableObject {
    @Published var shouldShowOnboarding: Bool = false
    
    // Key names for UserDefaults
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let onboardingShownCountKey = "onboardingShownCount"
    private let maxOnboardingShowsKey = "maxOnboardingShows"
    
    // Get max onboarding shows from UserDefaults (default to 10 if not set)
    private var maxOnboardingShows: Int {
        let storedValue = UserDefaults.standard.integer(forKey: maxOnboardingShowsKey)
        return storedValue > 0 ? storedValue : 10
    }
    
    init() {
        checkOnboardingStatus()
    }
    
    func checkOnboardingStatus() {
        // The key is now hasCompletedOnboarding instead of hasSeenOnboarding
        // This prevents conflict with existing UserDefaults
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        let onboardingShownCount = UserDefaults.standard.integer(forKey: onboardingShownCountKey)
        
        print("Debug - Show Count: \(onboardingShownCount), Max Shows: \(maxOnboardingShows), Has Completed: \(hasCompletedOnboarding)")
        
        // Always show onboarding if shown count is less than max shows
        if onboardingShownCount < maxOnboardingShows {
            shouldShowOnboarding = true
            
            // Increment shown count immediately
            UserDefaults.standard.set(onboardingShownCount + 1, forKey: onboardingShownCountKey)
            print("Debug - Incremented show count to: \(onboardingShownCount + 1)")
        } else {
            shouldShowOnboarding = false
        }
    }
    
    func completeOnboarding() {
        // Mark onboarding as completed
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        shouldShowOnboarding = false
    }
    
    func resetOnboarding() {
        // Reset all onboarding state
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.set(0, forKey: onboardingShownCountKey)
        shouldShowOnboarding = true
        print("Debug - Onboarding reset")
    }
    
    // Set a specific number of times to show onboarding
    func setMaxOnboardingShows(_ count: Int) {
        UserDefaults.standard.set(count, forKey: maxOnboardingShowsKey)
        print("Debug - Set max onboarding shows to: \(count)")
    }
}
