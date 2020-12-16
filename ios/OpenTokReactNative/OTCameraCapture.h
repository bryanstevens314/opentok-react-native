//
//  OTCameraCapture.h
//  OpenTokReactNative
//
//  Created by Bryan Stevens on 12/12/20.
//  Copyright © 2020 TokBox Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenTok/OpenTok.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTBridgeMethod.h>
#import <React/RCTEventEmitter.h>

@protocol OTVideoCapture;


@interface OTCameraCapture : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, OTVideoCapture>
{
    @protected
    dispatch_queue_t _capture_queue;
}

@property (nonatomic, retain) AVCaptureSession *captureSession;
@property (nonatomic, retain) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, retain) AVCaptureDeviceInput *videoInput;

- (BOOL)toggleCameraPosition;
- (void)setFlash:(NSString *) mode;
- (void)swapCamera:(BOOL) position;
- (void)getImgData:(RCTResponseSenderBlock) callback;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;

@end
