//
//  OTCameraCapture.h
//  OpenTok iOS SDK
//
//  Copyright (c) 2013 Tokbox, Inc. All rights reserved.
//
// gg

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <OpenTok/OpenTok.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTBridgeMethod.h>
#import <React/RCTEventEmitter.h>

@protocol OTVideoCapture;

@interface OTCameraCapture : NSObject
    <AVCaptureVideoDataOutputSampleBufferDelegate, OTVideoCapture>
{
    @protected
    dispatch_queue_t _capture_queue;
}

@property (nonatomic, retain) AVCaptureSession *captureSession;
@property (nonatomic, retain) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, retain) AVCaptureDeviceInput *videoInput;

@property (nonatomic, assign) NSString* captureSessionPreset;
@property (readonly) NSArray* availableCaptureSessionPresets;

@property (nonatomic, assign) double activeFrameRate;
- (BOOL)isAvailableActiveFrameRate:(double)frameRate;

@property (nonatomic, assign) AVCaptureDevicePosition cameraPosition;
@property (readonly) NSArray* availableCameraPositions;

- (BOOL)toggleCameraPosition;
- (void)setFlash:(NSString *) mode;
- (BOOL)isFlashSupported;
- (void)swapCamera:(BOOL) position;
- (void)getImgData:(RCTResponseSenderBlock) callback;
- (void)zoomIn;
- (void)zoomOut;
- (void)resetZoom;

@end
