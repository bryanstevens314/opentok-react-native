//
//  OTCameraCapture.m
//  OpenTokReactNative
//
//  Created by Bryan Stevens on 12/12/20.
//  Copyright © 2020 TokBox Inc. All rights reserved.
//

#import "OTCameraCapture.h"

@implementation OTCameraCapture  {
    OTVideoFrame* _videoFrame;
    
    uint32_t _captureWidth;
    uint32_t _captureHeight;
    NSString* _capturePreset;

    BOOL _capturing;
    BOOL getBase64;
    RCTResponseSenderBlock base64Callback;
    
    CVImageBufferRef imageBuffer;
    dispatch_source_t _blackFrameTimer;
    uint8_t* _blackFrame;
    int zoomIndex;
}

@synthesize captureSession = _captureSession;
@synthesize videoInput = _videoInput;
@synthesize videoOutput = _videoOutput;
@synthesize videoCaptureConsumer = _videoCaptureConsumer;

-(id)init {
    self = [super init];
    if (self) {
        _capturePreset = AVCaptureSessionPreset1280x720;
        _captureWidth = 1920;
        _captureHeight = 1080;
        
        _capture_queue = dispatch_queue_create("com.tokbox.ORCameraCapture", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stopCapture];
    [self releaseCapture];
    
    if (_capture_queue) {
        _capture_queue = nil;
    }
}

- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureDevice *) frontFacingCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

- (AVCaptureDevice *) backFacingCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

- (AVCaptureTorchMode) torchMode {
    return [[[self videoInput] device] torchMode];
}

- (void)setTorchMode:(AVCaptureTorchMode) torchMode {
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isTorchModeSupported:torchMode] && [device torchMode] != torchMode) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setTorchMode:torchMode];
            [device unlockForConfiguration];
        } else {
            NSLog(@"VSPTBVideoCapture setTorchMode error: %@",error);
        }
    }
}

- (void)setFlash:(NSString *) mode {
    AVCaptureTorchMode torchMode = [mode isEqualToString:@"torch"] ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isTorchModeSupported:torchMode] && [device torchMode] != torchMode) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setTorchMode:torchMode];
            [device unlockForConfiguration];
        } else {
            NSLog(@"VSPTBVideoCapture setTorchMode error: %@",error);
        }
    }
}

- (void)zoomTo:(CGFloat)scale shouldRamp:(BOOL)shouldRamp {
    AVCaptureDevice *inputDevice = [[self videoInput] device];
    if (scale != inputDevice.videoZoomFactor) {
        NSError *lockError = nil;
        [inputDevice lockForConfiguration:&lockError];
        if (!lockError) {
            if (shouldRamp) {
                [inputDevice rampToVideoZoomFactor:scale withRate:1];
            } else {
                inputDevice.videoZoomFactor = scale;
            }
            [inputDevice unlockForConfiguration];
        }
    }
}

- (void)zoomIn{
    zoomIndex++;
    CGFloat maxZoom = [[self videoInput] device].activeFormat.videoMaxZoomFactor;
    CGFloat currentZoom = (CGFloat) (maxZoom / 75) * zoomIndex;
    if(currentZoom < maxZoom){
        [self zoomTo:currentZoom shouldRamp:NO];
    } else {
        zoomIndex--;
    }
}

- (void)zoomOut{
    if(zoomIndex == 1){
        [self zoomTo:1 shouldRamp:NO];
        return;
    }
    zoomIndex--;
    CGFloat maxZoom = [[self videoInput] device].activeFormat.videoMaxZoomFactor;
    CGFloat currentZoom = (CGFloat) (maxZoom / 75) * zoomIndex;
    if(currentZoom >= 1){
        [self zoomTo:currentZoom shouldRamp:NO];
    } else {
        zoomIndex++;
    }
}

- (void)resetZoom{
    zoomIndex = 0;
    [self zoomTo:1 shouldRamp:NO];
}

- (void)getImgData:(RCTResponseSenderBlock) callback{
    getBase64 = YES;
    base64Callback = callback;
}

- (void)updateCaptureFormatWithWidth:(uint32_t)width height:(uint32_t)height {
    _captureWidth = width;
    _captureHeight = height;
    
    OTVideoFormat *videoFormat = [OTVideoFormat videoFormatNV12WithWidth:_captureWidth height:_captureHeight];
    videoFormat.estimatedFramesPerSecond = 30;
    videoFormat.estimatedCaptureDelay = 0;
    
    _videoFrame = [[OTVideoFrame alloc] initWithFormat:videoFormat];
    _videoFrame.orientation = [self currentDeviceOrientation];
}

- (void)swapCamera:(BOOL) position {
    return [self setCameraPosition:position ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
}

- (void)setCameraPosition:(AVCaptureDevicePosition) position {
    [self setTorchMode:AVCaptureTorchModeOff];
    
    NSError *error;
    AVCaptureDeviceInput * newVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:[self cameraWithPosition:position] error:&error];

    if (error){
        NSLog(@"Error setting up Video Capture input: %@", error);
        return;
    }
    
    dispatch_sync(_capture_queue, ^() {
        [_captureSession beginConfiguration];
        [_captureSession removeInput:_videoInput];
        if ([_captureSession canAddInput:newVideoInput]) {
            [_captureSession addInput:newVideoInput];
            _videoInput = newVideoInput;
        } else {
            [_captureSession addInput:_videoInput];
        }
        [_captureSession commitConfiguration];
    });
    return;
}

- (void)releaseCapture {
    [self stopCapture];
    [_videoOutput setSampleBufferDelegate:nil queue:NULL];
    [_captureSession stopRunning];
    _captureSession = nil;
    _videoOutput = nil;
    
    _videoInput = nil;
    
    if (_blackFrameTimer) {
        _blackFrameTimer = nil;
    }
    
    free(_blackFrame);
}

- (void)initCapture {
    NSError *error;
    _videoInput = [AVCaptureDeviceInput deviceInputWithDevice:[self backFacingCamera] error:&error];
    if (AVErrorApplicationIsNotAuthorizedToUseDevice == error.code) {
        [self initBlackFrameSender];
        _captureSession = nil;
        NSLog(@"ERROR[OpenTok]: Failed to initialize default video capture due to authorization failure. (error=%@)", error);
        return;
    }
    
    if(error || _videoInput == nil) {
        NSLog(@"ERROR[OpenTok]: Failed to initialize default video capture "
              "session. (error=%@)", error);
        return;
    }
    dispatch_sync(_capture_queue, ^() {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        [_videoOutput setAlwaysDiscardsLateVideoFrames:NO];
        [_videoOutput setVideoSettings: [NSDictionary dictionaryWithObject: [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        
        [_videoOutput setSampleBufferDelegate:self queue:_capture_queue];

        _captureSession = [[AVCaptureSession alloc] init];
        _captureSession.usesApplicationAudioSession = NO;
        [_captureSession setSessionPreset:_capturePreset];
        [_captureSession addInput:_videoInput];
        [_captureSession addOutput:_videoOutput];
        
        [_captureSession startRunning];
    });
}

- (void)initBlackFrameSender {
    
    int blackFrameWidth = 320;
    int blackFrameHeight = 240;
    [self updateCaptureFormatWithWidth:blackFrameWidth height:blackFrameHeight];
    
    _blackFrame = malloc(blackFrameWidth * blackFrameHeight * 3 / 2);
    
    uint8_t* yPlane = _blackFrame;
    uint8_t* uvPlane = &(_blackFrame[(blackFrameHeight * blackFrameWidth)]);
    
    memset(yPlane, 0x00, blackFrameWidth * blackFrameHeight);
    memset(uvPlane, 0x7F, blackFrameWidth * blackFrameHeight / 2);
    
    _blackFrameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _capture_queue);
    if (_blackFrameTimer)
    {
        dispatch_source_set_timer(_blackFrameTimer, dispatch_walltime(NULL, 0), 250ull * NSEC_PER_MSEC, 1ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_blackFrameTimer, ^{
            if (!self->_capturing) { return; }
            
            self->_videoFrame.timestamp = CMTimeMake((CACurrentMediaTime() - CACurrentMediaTime()) * 90000, 90000);
            self->_videoFrame.format.imageWidth = blackFrameWidth;
            self->_videoFrame.format.imageHeight = blackFrameHeight;
            
            self->_videoFrame.format.estimatedFramesPerSecond = 4;
            self->_videoFrame.format.estimatedCaptureDelay = 0;
            
            [self->_videoFrame clearPlanes];
            
            [self->_videoFrame.planes addPointer:yPlane];
            [self->_videoFrame.planes addPointer:uvPlane];
            
            [self->_videoCaptureConsumer consumeFrame:self->_videoFrame];
        });
        
        dispatch_resume(_blackFrameTimer);
    }
}

- (BOOL) isCaptureStarted {
    return (_captureSession || _blackFrameTimer) && _capturing;
}

- (int32_t) startCapture {
    _capturing = YES;
    return 0;
}

- (int32_t) stopCapture {
    _capturing = NO;
    return 0;
}

- (OTVideoOrientation)currentDeviceOrientation {
    switch([[UIDevice currentDevice] orientation]){
        case UIDeviceOrientationUnknown:
            return OTVideoOrientationUp;
        case UIDeviceOrientationPortrait:
            return OTVideoOrientationUp;
        case UIDeviceOrientationPortraitUpsideDown:
            return OTVideoOrientationDown;
        case UIDeviceOrientationLandscapeLeft:
            return OTVideoOrientationRight ;
        case UIDeviceOrientationLandscapeRight:
            return OTVideoOrientationLeft;
        case UIDeviceOrientationFaceUp:
            return OTVideoOrientationUp;
        case UIDeviceOrientationFaceDown:
            return OTVideoOrientationUp;
    }
    
    return OTVideoOrientationUp;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    if(!getBase64){
        connection.videoMirrored = YES;
        connection.videoOrientation = [self orientation];

        [_videoCaptureConsumer consumeImageBuffer:imageBuffer
                                          orientation:[self currentDeviceOrientation]
                                            timestamp:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                             metadata:nil];
    } else {
        [self base64WithImageBuffer: imageBuffer];
    }
    
CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
}

-(void)base64WithImageBuffer:(CVImageBufferRef) imageBuffer{
    getBase64 = NO;
    
    CGImageRef videoImage = [[CIContext contextWithOptions:nil]
                                         createCGImage:[CIImage imageWithCVPixelBuffer:imageBuffer]
                                         fromRect:CGRectMake(0, 0,
                                         CVPixelBufferGetWidth(imageBuffer),
                                         CVPixelBufferGetHeight(imageBuffer))];

    UIImage *image = [[UIImage alloc] initWithCGImage:videoImage];
    NSString *base64 = [UIImageJPEGRepresentation(image, 1) base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    CGImageRelease(videoImage);
    base64Callback([[NSArray alloc] initWithObjects:base64 , nil]);
    
}

-(AVCaptureVideoOrientation)orientation
{
    switch([[UIDevice currentDevice] orientation]){
        case UIDeviceOrientationUnknown:
            return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIDeviceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIDeviceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIDeviceOrientationFaceUp:
            return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationFaceDown:
            return AVCaptureVideoOrientationPortrait;
    }
}
@end
