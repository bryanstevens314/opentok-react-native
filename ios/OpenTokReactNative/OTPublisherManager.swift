//
//  OTPublisher.swift
//  OpenTokReactNative
//
//  Created by Manik Sachdeva on 1/17/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

import Foundation

@objc(OTPublisherManager)
class OTPublisherManager: RCTViewManager {
    
    static var publisherId: String = ""
    
    override func view() -> UIView {
        return OTPublisherView();
    }

    override static func requiresMainQueueSetup() -> Bool {
        return true;
    }
    
    @objc func setFlash(_ torchMode: String ) -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.setFlash(torchMode)
    }
    
    @objc func swapCamera(_ position: Bool ) -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.swapCamera(position)
    }
    
    @objc func zoomIn() -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.zoomIn()
    }
    
    @objc func zoomOut() -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.zoomOut()
    }
    
    @objc func resetZoom() -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.resetZoom()
    }
    
    @objc func getImgData(_ callback: @escaping RCTResponseSenderBlock) -> Void {
        guard let publisher = OTRN.sharedState.publishers[OTPublisherManager.publisherId] else { return }
        let capturer = publisher.videoCapture as! OTCameraCapture
        capturer.getImgData(callback)
    }
    
    @objc func clearPreview(_ callback: @escaping RCTResponseSenderBlock) -> Void {
        callback([]);
    }
}

