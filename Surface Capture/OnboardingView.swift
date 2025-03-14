//
//  OnboardingView.swift
//  Surface Capture App
//

import SwiftUI
import Combine

struct OnboardingView: View {
    @Binding var isShowingOnboarding: Bool
    @ObservedObject var onboardingManager: OnboardingManager
    @State private var currentPage = 0
    
    // Animation states
    @State private var slideOffset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // Background color
            Color(UIColor.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Pages with horizontal paging effect
                ZStack {
                    ForEach(0..<3) { index in
                        if index == currentPage {
                            getPageView(for: index)
                                .offset(x: slideOffset)
                                .opacity(opacity)
                                .transition(.opacity)
                        }
                    }
                }
                
                // Pager indicator
                HStack(spacing: 10) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.5))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.bottom, 20)
                
                // Next button
                Button(action: {
                    if currentPage < 2 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            slideOffset = -UIScreen.main.bounds.width
                            opacity = 0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            currentPage += 1
                            slideOffset = UIScreen.main.bounds.width
                            
                            withAnimation(.easeInOut(duration: 0.3)) {
                                slideOffset = 0
                                opacity = 1
                            }
                        }
                    } else {
                        // Final page, dismiss onboarding
                        onboardingManager.completeOnboarding()
                        isShowingOnboarding = false
                    }
                }) {
                    Text(currentPage < 2 ? "Got it >" : "Let's go!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.bottom, 50)
            }
        }
        // Add debug button in debug builds
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            Button(action: {
                print("Debug - Skip onboarding")
                onboardingManager.completeOnboarding()
                isShowingOnboarding = false
            }) {
                Text("Skip")
                    .font(.caption)
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding()
            #endif
        }
    }
    
    @ViewBuilder
    func getPageView(for index: Int) -> some View {
        VStack(spacing: 30) {
            // Back button for pages 1 and 2
            if index > 0 {
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            slideOffset = UIScreen.main.bounds.width
                            opacity = 0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            currentPage -= 1
                            slideOffset = -UIScreen.main.bounds.width
                            
                            withAnimation(.easeInOut(duration: 0.3)) {
                                slideOffset = 0
                                opacity = 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .padding(.leading, 20)
                    
                    Spacer()
                }
                .padding(.top, 60)
            } else {
                // Empty space for alignment on first page
                Color.clear.frame(height: 100)
            }
            
            VStack(spacing: 30) {
                // Title
                Text(getTitle(for: index))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, index == 0 ? 20 : 0)
                
                // Diagram
                getDiagram(for: index)
                    .frame(width: 200, height: 200)
                    .padding()
                
                // Button example
                getButton(for: index)
                    .padding()
                
                // Explanatory text
                Text(getExplanation(for: index))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func getTitle(for index: Int) -> String {
        switch index {
        case 0:
            return "Welcome to Jigma"
        case 1:
            return "3-D Scanning"
        case 2:
            return "Work Mode"
        default:
            return ""
        }
    }
    
    @ViewBuilder
    func getDiagram(for index: Int) -> some View {
        switch index {
        case 0:
            // Person holding phone with projection
            ZStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 80))
                    .offset(x: -40)
                
                Image(systemName: "iphone")
                    .font(.system(size: 50))
                    .offset(x: 0, y: 10)
                
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 0))
                    path.addLine(to: CGPoint(x: 60, y: -30))
                    path.addLine(to: CGPoint(x: 60, y: 30))
                    path.addLine(to: CGPoint(x: 10, y: 0))
                }
                .fill(Color.blue.opacity(0.5))
                .offset(x: 30, y: 10)
                
                Rectangle()
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .offset(x: 80, y: 10)
            }
            
        case 1:
            // 3D surface relief with person
            ZStack {
                // 3D surface representation
                VStack(spacing: 0) {
                    ForEach(0..<10) { i in
                        HStack(spacing: 0) {
                            ForEach(0..<10) { j in
                                let height = sin(Double(i) * 0.7) * cos(Double(j) * 0.7) * 10
                                Rectangle()
                                    .fill(Color.blue.opacity(0.3 + height * 0.05))
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .offset(x: 40)
                
                Image(systemName: "person.fill")
                    .font(.system(size: 60))
                    .offset(x: -40)
                
                Image(systemName: "iphone")
                    .font(.system(size: 30))
                    .offset(x: -10, y: 10)
            }
            
        case 2:
            // Streaming between devices
            HStack(spacing: 40) {
                // First device
                VStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 50))
                    
                    Text("Device 1")
                        .font(.caption)
                }
                
                // Connection arrows
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20))
                        .offset(y: -10)
                    
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20))
                        .offset(y: 10)
                }
                
                // Second device
                VStack {
                    Image(systemName: "iphone")
                        .font(.system(size: 50))
                    
                    Text("Device 2")
                        .font(.caption)
                }
            }
            
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    func getButton(for index: Int) -> some View {
        switch index {
        case 0:
            // Add Image button
            HStack {
                Image(systemName: "photo.fill")
                Text("Add Image")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(Capsule().fill(Color.green))
            
        case 1:
            // Scan Surface button
            HStack {
                Image(systemName: "camera.fill")
                Text("Scan Surface")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(Capsule().fill(Color.blue))
            
        case 2:
            // Stream button
            HStack {
                Image(systemName: "wifi")
                Text("Stream")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding()
            .background(Capsule().fill(Color.purple))
            
        default:
            EmptyView()
        }
    }
    
    func getExplanation(for index: Int) -> String {
        switch index {
        case 0:
            return "Pick an image from your photos to use as reference for a mural. Project it onto a wall and trace."
        case 1:
            return "Capture any surface to use as reference on any surface."
        case 2:
            return "Once you've finished adjusting your reference, enter work mode to trace from one device or stream using two."
        default:
            return ""
        }
    }
}

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = OnboardingManager()
        OnboardingView(isShowingOnboarding: .constant(true), onboardingManager: manager)
    }
}
#endif
