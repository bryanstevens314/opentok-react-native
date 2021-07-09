//
//  OTPublisherManager.m
//  OpenTokReactNative
//
//  Created by Bryan Stevens on 12/12/20.
//  Copyright © 2020 TokBox Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTBridgeMethod.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(OTPublisherManager, RCTEventEmitter)

RCT_EXTERN_METHOD(isFlashSupported: (RCTResponseSenderBlock*)callback)

RCT_EXTERN_METHOD(setFlash: (NSString*)torchMode)

RCT_EXTERN_METHOD(swapCamera: (BOOL)position)

RCT_EXTERN_METHOD(zoomIn)

RCT_EXTERN_METHOD(zoomOut)

RCT_EXTERN_METHOD(resetZoom)

RCT_EXTERN_METHOD(getImgData: (RCTResponseSenderBlock*)callback)

RCT_EXTERN_METHOD(clearPreview: (RCTResponseSenderBlock*)callback)

@end
