//
//  WebRTCModels.swift
//  CameraStreamer
//
//  Created by Ashley Davison on 28/03/2025.
//

import WebRTC

struct WebRTCSessionDescription: Codable {
    let sdp: String
    let type: Int
    
    init(from rtcSessionDescription: RTCSessionDescription) {
        self.sdp = rtcSessionDescription.sdp
        
        switch rtcSessionDescription.type {
        case .offer:
            self.type = 0
        case .answer:
            self.type = 1
        case .prAnswer:
            self.type = 2
        default:
            self.type = -1
        }
    }
    
    var rtcSessionDescription: RTCSessionDescription {
        let type: RTCSdpType
        
        switch self.type {
        case 0:
            type = .offer
        case 1:
            type = .answer
        case 2:
            type = .prAnswer
        default:
            fatalError("Unknown SDP type")
        }
        
        return RTCSessionDescription(type: type, sdp: sdp)
    }
}

struct WebRTCIceCandidate: Codable {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
    
    init(from rtcIceCandidate: RTCIceCandidate) {
        self.sdp = rtcIceCandidate.sdp
        self.sdpMLineIndex = rtcIceCandidate.sdpMLineIndex
        self.sdpMid = rtcIceCandidate.sdpMid
    }
    
    var rtcIceCandidate: RTCIceCandidate {
        return RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}
