//
//  OTVideoCaptureIOSDefault.m
//  otkit-objc-libs
//
//  Created by Charley Robinson on 10/11/13.
//
//

#import <Availability.h>
#import <UIKit/UIKit.h>
#import "OTCameraCapture.h"
#import <CoreVideo/CoreVideo.h>

#define SYSTEM_VERSION_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)


#define kTimespanWithNoFramesBeforeRaisingAnError 20.0 // NSTimeInterval(secs)

typedef NS_ENUM(int32_t, OTCapturerErrorCode) {

    OTCapturerSuccess = 0,

    /** Publisher couldn't access to the camera */
    OTCapturerError = 1650,

    /** Publisher's capturer is not capturing frames */
    OTCapturerNoFramesCaptured = 1660,

    /** Publisher's capturer authorization failed */
    OTCapturerAuthorizationDenied = 1670,
};


@interface OTCameraCapture()
@property (nonatomic, strong) NSTimer *noFramesCapturedTimer;
@property (nonatomic) UIInterfaceOrientation currentStatusBarOrientation;
@end

@implementation OTCameraCapture {
    __weak id<OTVideoCaptureConsumer> _videoCaptureConsumer;
    OTVideoFrame* _videoFrame;
    
    uint32_t _captureWidth;
    uint32_t _captureHeight;
    NSString* _capturePreset;
    
    AVCaptureSession *_captureSession;
    AVCaptureDeviceInput *_videoInput;
    AVCaptureVideoDataOutput *_videoOutput;

    BOOL _capturing;
    
    dispatch_source_t _blackFrameTimer;
    uint8_t* _blackFrame;
    double _blackFrameTimeStarted;
    
    enum OTCapturerErrorCode _captureErrorCode;
    
    BOOL isFirstFrame;
    BOOL getBase64;
    RCTResponseSenderBlock base64Callback;
    AVCaptureDevicePosition _cameraPosition;
    int zoomIndex;
}

@synthesize captureSession = _captureSession;
@synthesize videoInput = _videoInput, videoOutput = _videoOutput;
@synthesize videoCaptureConsumer = _videoCaptureConsumer;

#define OTK_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE 20

-(id)init {
    self = [super init];
    if (self) {
        _cameraPosition = AVCaptureDevicePositionBack;
        _capturePreset = AVCaptureSessionPreset1280x720;

        [[self class] dimensionsForCapturePreset:_capturePreset
                                           width:&_captureWidth
                                          height:&_captureHeight];
        _capture_queue = dispatch_queue_create("com.tokbox.OTVideoCapture",
                                               DISPATCH_QUEUE_SERIAL);
        _videoFrame = [[OTVideoFrame alloc] initWithFormat:
                      [OTVideoFormat videoFormatNV12WithWidth:_captureWidth
                                                       height:_captureHeight]];
        isFirstFrame = false;
    }
    return self;
}

- (int32_t)captureSettings:(OTVideoFormat*)videoFormat {
    videoFormat.pixelFormat = OTPixelFormatNV12;
    videoFormat.imageWidth = _captureWidth;
    videoFormat.imageHeight = _captureHeight;
    return 0;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:UIApplicationWillChangeStatusBarOrientationNotification
     object:nil];
    [self stopCapture];
    [self releaseCapture];
    
    if (_capture_queue) {
        _capture_queue = nil;
    }
    _videoFrame = nil;
}

- (AVCaptureDevice *) cameraWithPosition:(AVCaptureDevicePosition) position {
    NSArray *devices = [[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:position] devices];
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

- (BOOL) hasMultipleCameras {
    return [[[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified] devices] count] > 1;
}

- (BOOL) hasTorch {
    return [[[self videoInput] device] hasTorch];
}

- (AVCaptureTorchMode) torchMode {
    return [[[self videoInput] device] torchMode];
}

- (void) setTorchMode:(AVCaptureTorchMode) torchMode {
    
    AVCaptureDevice *device = [[self videoInput] device];
    if ([device isTorchModeSupported:torchMode] &&
        [device torchMode] != torchMode)
    {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            [device setTorchMode:torchMode];
            [device unlockForConfiguration];
        } else {
            //Handle Error
        }
    }
}

- (double) maxSupportedFrameRate {
    AVFrameRateRange* firstRange =
    [_videoInput.device.activeFormat.videoSupportedFrameRateRanges
                               objectAtIndex:0];
    
    CMTime bestDuration = firstRange.minFrameDuration;
    double bestFrameRate = bestDuration.timescale / bestDuration.value;
    CMTime currentDuration;
    double currentFrameRate;
    for (AVFrameRateRange* range in
         _videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        currentDuration = range.minFrameDuration;
        currentFrameRate = currentDuration.timescale / currentDuration.value;
        if (currentFrameRate > bestFrameRate) {
            bestFrameRate = currentFrameRate;
        }
    }
    
    return bestFrameRate;
}

- (BOOL)isAvailableActiveFrameRate:(double)frameRate
{
    return (nil != [self frameRateRangeForFrameRate:frameRate]);
}

- (double) activeFrameRate {
    CMTime minFrameDuration = _videoInput.device.activeVideoMinFrameDuration;
    double framesPerSecond =
    minFrameDuration.timescale / minFrameDuration.value;
    
    return framesPerSecond;
}

- (AVFrameRateRange*)frameRateRangeForFrameRate:(double)frameRate {
    for (AVFrameRateRange* range in
         _videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        if (range.minFrameRate <= frameRate && frameRate <= range.maxFrameRate)
        {
            return range;
        }
    }
    return nil;
}

- (void)setActiveFrameRateImpl:(double)frameRate : (BOOL) lockConfiguration {
    
    if (!_videoOutput || !_videoInput) {
        return;
    }
    
    AVFrameRateRange* frameRateRange =
    [self frameRateRangeForFrameRate:frameRate];
    if (nil == frameRateRange) {
        NSLog(@"unsupported frameRate %f", frameRate);
        return;
    }
    CMTime desiredMinFrameDuration = CMTimeMake(1, frameRate);
    CMTime desiredMaxFrameDuration = CMTimeMake(1, frameRate); // iOS 8 fix
    /*frameRateRange.maxFrameDuration*/;
    
    if(lockConfiguration) [_captureSession beginConfiguration];
    
    
    NSError* error;
    if ([_videoInput.device lockForConfiguration:&error]) {
        [_videoInput.device
         setActiveVideoMinFrameDuration:desiredMinFrameDuration];
        [_videoInput.device
         setActiveVideoMaxFrameDuration:desiredMaxFrameDuration];
        [_videoInput.device unlockForConfiguration];
    } else {
        NSLog(@"%@", error);
    }

    if(lockConfiguration) [_captureSession commitConfiguration];
}

- (void)setActiveFrameRate:(double)frameRate {
    dispatch_async(_capture_queue, ^{
        return [self setActiveFrameRateImpl : frameRate : TRUE];
    });
}

+ (void)dimensionsForCapturePreset:(NSString*)preset
                             width:(uint32_t*)width
                            height:(uint32_t*)height
{
    if ([preset isEqualToString:AVCaptureSessionPreset352x288]) {
        *width = 352;
        *height = 288;
    } else if ([preset isEqualToString:AVCaptureSessionPreset640x480]) {
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPreset1280x720]) {
        *width = 1280;
        *height = 720;
    } else if ([preset isEqualToString:AVCaptureSessionPreset1920x1080]) {
        *width = 1920;
        *height = 1080;
    } else if ([preset isEqualToString:AVCaptureSessionPresetPhoto]) {
        // see AVCaptureSessionPresetLow
        *width = 1920;
        *height = 1080;
    } else if ([preset isEqualToString:AVCaptureSessionPresetHigh]) {
        // see AVCaptureSessionPresetLow
        *width = 640;
        *height = 480;
    } else if ([preset isEqualToString:AVCaptureSessionPresetMedium]) {
        // see AVCaptureSessionPresetLow
        *width = 480;
        *height = 360;
    } else if ([preset isEqualToString:AVCaptureSessionPresetLow]) {
        // WARNING: This is a guess. might be wrong for certain devices.
        // We'll use updeateCaptureFormatWithWidth:height if actual output
        // differs from expected value
        *width = 192;
        *height = 144;
    }
}

+ (NSSet *)keyPathsForValuesAffectingAvailableCaptureSessionPresets
{
    return [NSSet setWithObjects:@"captureSession", @"videoInput", nil];
}

- (NSArray *)availableCaptureSessionPresets
{
    NSArray *allSessionPresets = [NSArray arrayWithObjects:
                                  AVCaptureSessionPreset352x288,
                                  AVCaptureSessionPreset640x480,
                                  AVCaptureSessionPreset1280x720,
                                  AVCaptureSessionPreset1920x1080,
                                  AVCaptureSessionPresetPhoto,
                                  AVCaptureSessionPresetHigh,
                                  AVCaptureSessionPresetMedium,
                                  AVCaptureSessionPresetLow,
                                  nil];
    
    NSMutableArray *availableSessionPresets =
    [NSMutableArray arrayWithCapacity:9];
    for (NSString *sessionPreset in allSessionPresets) {
        if ([[self captureSession] canSetSessionPreset:sessionPreset])
            [availableSessionPresets addObject:sessionPreset];
    }
    
    return availableSessionPresets;
}

- (void)updateCaptureFormatWithWidth:(uint32_t)width height:(uint32_t)height
{
    _captureWidth = width;
    _captureHeight = height;
    [_videoFrame setFormat:[OTVideoFormat
                           videoFormatNV12WithWidth:_captureWidth
                           height:_captureHeight]];
    
}

- (NSString*)captureSessionPreset {
    return _captureSession.sessionPreset;
}

- (void) setCaptureSessionPreset:(NSString*)preset {
    dispatch_async(_capture_queue, ^{
        AVCaptureSession *session = [self captureSession];
        
        if ([session canSetSessionPreset:preset] &&
            ![preset isEqualToString:session.sessionPreset]) {
            
            [self.captureSession beginConfiguration];
            self.captureSession.sessionPreset = preset;
            self->_capturePreset = preset;
            
            [self->_videoOutput setVideoSettings:
             [NSDictionary dictionaryWithObjectsAndKeys:
              [NSNumber numberWithInt:
               kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],
              kCVPixelBufferPixelFormatTypeKey,
              nil]];
            
            [self.captureSession commitConfiguration];
        }
    });
}

- (BOOL) toggleCameraPosition {
    AVCaptureDevicePosition currentPosition = _videoInput.device.position;
    if (AVCaptureDevicePositionBack == currentPosition) {
        [self setCameraPosition:AVCaptureDevicePositionFront];
    } else if (AVCaptureDevicePositionFront == currentPosition) {
        [self setCameraPosition:AVCaptureDevicePositionBack];
    }
    
    // TODO: check for success
    return YES;
}

- (NSArray*)availableCameraPositions {
    NSArray* devices = [[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified] devices];
    NSMutableSet* result = [NSMutableSet setWithCapacity:devices.count];
    for (AVCaptureDevice* device in devices) {
        [result addObject:[NSNumber numberWithInt:device.position]];
    }
    return [result allObjects];
}

- (void)swapCamera:(BOOL) position {
    return [self setCameraPosition:position ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack];
}

- (void)setCameraPosition:(AVCaptureDevicePosition) position {
    _cameraPosition = position;
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
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVCaptureSessionRuntimeErrorNotification
                                                  object:nil];
    [self stopCapture];
    [_videoOutput setSampleBufferDelegate:nil queue:NULL];
    AVCaptureSession *session = _captureSession;
    dispatch_async(_capture_queue, ^() {
        [session stopRunning];
    });
    
    _captureSession = nil;
    _videoOutput = nil;
    _videoInput = nil;
    
    if (_blackFrameTimer) {
        _blackFrameTimer = nil;
    }
    
    free(_blackFrame);

}

- (void)setupAudioVideoSession {
    //-- Setup Capture Session.
    _captureErrorCode = OTCapturerSuccess;
    _captureSession = [[AVCaptureSession alloc] init];
    [_captureSession beginConfiguration];
    
    [_captureSession setSessionPreset:_capturePreset];
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        //Needs to be set in order to receive audio route/interruption events.
        _captureSession.usesApplicationAudioSession = NO;
    }
    
    //-- Create a video device and input from that Device.
    // Add the input to the capture session.
    AVCaptureDevice * videoDevice = [self backFacingCamera];
    if(videoDevice == nil) {
        NSLog(@"ERROR[OpenTok]: Failed to acquire camera device for video "
              "capture.");
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        OTError *err = [OTError errorWithDomain:OT_PUBLISHER_ERROR_DOMAIN
                                           code:OTCapturerError
                                       userInfo:nil];
        [self showCapturerError:err];
        [_captureSession commitConfiguration];
        _captureSession = nil;
        return;
    }
    
    //-- Add the device to the session.
    NSError *error;
    _videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice
                                                         error:&error];
    
    if (AVErrorApplicationIsNotAuthorizedToUseDevice == error.code) {
        [self initBlackFrameSender];
    }
    
    if(error || _videoInput == nil) {
        NSLog(@"ERROR[OpenTok]: Failed to initialize default video caputre "
              "session. (error=%@)", error);
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
        OTError *err = [OTError errorWithDomain:OT_PUBLISHER_ERROR_DOMAIN
                                           code:(AVErrorApplicationIsNotAuthorizedToUseDevice
                                                 == error.code) ? OTCapturerAuthorizationDenied :
                                                 OTCapturerError
                                       userInfo:nil];
        [self showCapturerError:err];
        _videoInput = nil;
        [_captureSession commitConfiguration];
        _captureSession = nil;
        return;
    }
    
    [_captureSession addInput:_videoInput];
    
    //-- Create the output for the capture session.
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [_videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    [_videoOutput setVideoSettings:
     [NSDictionary dictionaryWithObject:
      [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                 forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    // The initial queue will be the main queue and then after receiving first frame,
    // we switch to _capture_queue. The reason for this is to detect initial
    // device orientation
    [_videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_captureSession addOutput:_videoOutput];
    
    [self setActiveFrameRateImpl
     : OTK_VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE : FALSE];
    
    [_captureSession commitConfiguration];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionError:)
                                                 name:AVCaptureSessionRuntimeErrorNotification
                                               object:nil];

    [_captureSession startRunning];
}

- (void)captureSessionError:(NSNotification *)notification {
    [self invalidateNoFramesTimerSettingItUpAgain:NO];
    OTError *err = [OTError errorWithDomain:OT_PUBLISHER_ERROR_DOMAIN
                                       code:OTCapturerError
                                   userInfo:nil];
    NSError *captureSessionError = [notification.userInfo objectForKey:AVCaptureSessionErrorKey];
    NSLog(@"[OpenTok] AVCaptureSession error : %@", captureSessionError.localizedDescription);
    [self showCapturerError:err];
}

- (void)initCapture {
    [self setupAudioVideoSession];
}

- (void)initBlackFrameSender {
    _blackFrameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0, 0, _capture_queue);
    int blackFrameWidth = 320;
    int blackFrameHeight = 240;
    [self updateCaptureFormatWithWidth:blackFrameWidth height:blackFrameHeight];
    
    _blackFrame = malloc(blackFrameWidth * blackFrameHeight * 3 / 2);
    _blackFrameTimeStarted = CACurrentMediaTime();
    
    uint8_t* yPlane = _blackFrame;
    uint8_t* uvPlane =
    &(_blackFrame[(blackFrameHeight * blackFrameWidth)]);

    memset(yPlane, 0x00, blackFrameWidth * blackFrameHeight);
    memset(uvPlane, 0x7F, blackFrameWidth * blackFrameHeight / 2);
    
    __weak OTCameraCapture *weakSelf = self;
    if (_blackFrameTimer)
    {
        dispatch_source_set_timer(_blackFrameTimer, dispatch_walltime(NULL, 0),
                                  250ull * NSEC_PER_MSEC,
                                  1ull * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_blackFrameTimer, ^{
            
            OTCameraCapture *strongSelf = weakSelf;
            if (!strongSelf->_capturing) {
                return;
            }
            
            double now = CACurrentMediaTime();
            strongSelf->_videoFrame.timestamp =
            CMTimeMake((now - strongSelf->_blackFrameTimeStarted) * 90000, 90000);
            strongSelf->_videoFrame.format.imageWidth = blackFrameWidth;
            strongSelf->_videoFrame.format.imageHeight = blackFrameHeight;
            
            strongSelf->_videoFrame.format.estimatedFramesPerSecond = 4;
            strongSelf->_videoFrame.format.estimatedCaptureDelay = 0;
            strongSelf->_videoFrame.orientation = OTVideoOrientationUp;
            
            [strongSelf->_videoFrame clearPlanes];
            
            [strongSelf->_videoFrame.planes addPointer:yPlane];
            [strongSelf->_videoFrame.planes addPointer:uvPlane];
            
            [strongSelf->_videoCaptureConsumer consumeFrame:strongSelf->_videoFrame];
        });
        
        dispatch_resume(_blackFrameTimer);
    }
    
}

- (BOOL) isCaptureStarted {
    return (_captureSession || _blackFrameTimer) && _capturing;
}

- (int32_t) startCapture {
    _capturing = YES;
    if (!_blackFrameTimer) {
        // Do no set timer if blackframe is being sent
        [self invalidateNoFramesTimerSettingItUpAgain:YES];
    }
    return 0;
}

- (int32_t) stopCapture {
    _capturing = NO;
    [self invalidateNoFramesTimerSettingItUpAgain:NO];
    return 0;
}

- (void)invalidateNoFramesTimerSettingItUpAgain:(BOOL)value {
    [self.noFramesCapturedTimer invalidate];
    self.noFramesCapturedTimer = nil;
    if (value) {
        self.noFramesCapturedTimer = [NSTimer scheduledTimerWithTimeInterval:kTimespanWithNoFramesBeforeRaisingAnError
                                                                      target:self
                                                                    selector:@selector(noFramesTimerFired:)
                                                                    userInfo:nil
                                                                     repeats:NO];
    }
}

- (void)noFramesTimerFired:(NSTimer *)timer {
    if (self.isCaptureStarted) {
        OTError *err = [OTError errorWithDomain:OT_PUBLISHER_ERROR_DOMAIN
                                           code:OTCapturerNoFramesCaptured
                                       userInfo:nil];
        [self showCapturerError:err];
    }
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
            return _cameraPosition == AVCaptureDevicePositionBack ? OTVideoOrientationRight : OTVideoOrientationLeft;
        case UIDeviceOrientationLandscapeRight:
            return _cameraPosition == AVCaptureDevicePositionBack ? OTVideoOrientationLeft : OTVideoOrientationRight;
        case UIDeviceOrientationFaceUp:
            return OTVideoOrientationUp;
        case UIDeviceOrientationFaceDown:
            return OTVideoOrientationUp;
    }
    
    return OTVideoOrientationUp;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{

}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    
    if (!(_capturing && _videoCaptureConsumer)) {
        return;
    }
    
    if (isFirstFrame == false)
    {
        isFirstFrame = true;
        [_videoOutput setSampleBufferDelegate:self queue:_capture_queue];
    }

    if (self.noFramesCapturedTimer){
        [self invalidateNoFramesTimerSettingItUpAgain:NO];
    }
        

    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [_videoCaptureConsumer consumeImageBuffer:imageBuffer
                                  orientation:[self currentDeviceOrientation]
                                    timestamp:time
                                     metadata:nil];
    
}

-(void)showCapturerError:(OTError*)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Custom-Video-Driver"
                                                                                 message:[NSString stringWithFormat:
                                                                                          @"Capturer failed with error : %@", error.description]
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        //We add buttons to the alert controller by creating UIAlertActions:
        UIAlertAction *actionOk = [UIAlertAction actionWithTitle:@"Ok"
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil]; //You can use a block here to handle a press on this button
        [alertController addAction:actionOk];
        [[[UIApplication sharedApplication] delegate].window.rootViewController
                                            presentViewController:alertController
                                            animated:YES completion:nil];
    });
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
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIDeviceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight ;
        case UIDeviceOrientationFaceUp:
            return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationFaceDown:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (BOOL)isFlashSupported {
    return [[[self videoInput] device] isTorchModeSupported:AVCaptureTorchModeOn];
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
    CGFloat currentZoom = ((CGFloat) (maxZoom / 75) * zoomIndex) + 1;
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
    CGFloat currentZoom = ((CGFloat) (maxZoom / 75) * zoomIndex) + 1;
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
@end

