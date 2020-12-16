//
//  OTPublisherSwift.swift
//  OpenTokReactNative
//
//  Created by Bryan Stevens on 12/12/20.
//  Copyright © 2020 TokBox Inc. All rights reserved.
//

import Foundation

@objc(OTPublisherSwift)
class OTPublisherSwift: RCTViewManager {
  override func view() -> UIView {
    return OTPublisherView();
  }
    
  override static func requiresMainQueueSetup() -> Bool {
    return true;
  }
}
