//
//  TimedMessageList.swift
//  Surface Capture App
//

import SwiftUI
import Combine

class TimedMessageList: ObservableObject {
    struct Message: Identifiable {
        let id = UUID()
        let message: String
        let startTime = Date()
        fileprivate(set) var endTime: Date?
    }
    
    @Published var activeMessage: Message? = nil
    private var messages = [Message]()
    
    func add(_ msg: String) {
        DispatchQueue.main.async {
            self.messages.append(Message(message: msg))
            self.activeMessage = self.messages.first
        }
    }
    
    func remove(_ msg: String) {
        DispatchQueue.main.async {
            if let index = self.messages.firstIndex(where: { $0.message == msg }) {
                self.messages.remove(at: index)
                self.activeMessage = self.messages.first
            }
        }
    }
}
