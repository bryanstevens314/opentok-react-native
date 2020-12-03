package com.opentokreactnative;

import android.content.Context;
import android.graphics.PixelFormat;
import android.graphics.SurfaceTexture;
import android.hardware.Camera;
import android.hardware.Camera.CameraInfo;
import android.hardware.Camera.Parameters;
import android.hardware.Camera.PreviewCallback;
import android.hardware.Camera.Size;
import android.os.Handler;

import android.view.Display;
import android.view.View;
import android.view.WindowManager;

import com.opentok.android.BaseVideoCapturer;
import com.opentok.android.Publisher;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.locks.ReentrantLock;

class TokboxVideoCapturer extends BaseVideoCapturer implements PreviewCallback {

    public final static int PREFERRED_CAPTURE_WIDTH = 640;
    public final static int PREFERRED_CAPTURE_HEIGHT = 480;

    public final static int DEFAULT_ZOOM_LEVEL         = 1;


    /* larger sizes result in poor quality video
    public final static int PREFERRED_CAPTURE_WIDTH = 1440;
    public final static int PREFERRED_CAPTURE_HEIGHT = 2460;
    */
    private View contentView;
    private int mCameraIndex = 0;
    private Camera mCamera;
    private CameraInfo mCurrentDeviceInfo = null;
    public ReentrantLock mPreviewBufferLock = new ReentrantLock();
    private int PIXEL_FORMAT = 17;
    PixelFormat mPixelFormat = new PixelFormat();
    private boolean isCaptureStarted = false;
    private boolean isCaptureRunning = false;
    private final int mNumCaptureBuffers = 3;
    private int mExpectedFrameSize = 0;
    private int mCaptureWidth = -1;
    private int mCaptureHeight = -1;
    private int mCaptureFPS = -1;
    private Display mCurrentDisplay;
    private SurfaceTexture mSurfaceTexture;
    private Publisher publisher;
    private boolean blackFrames = false;
    int fps = 1;
    int width = 0;
    int height = 0;
    int[] frame;


    private final static int CLIENT_ZOOM_SCALER = 5;
    private final static int SERVER_ZOOM_SCALER = 7;

    public boolean mbIsZooming = false;
    private int mMaxZoom = 0;
    private int mCurrentZoom = DEFAULT_ZOOM_LEVEL;
    private boolean mbIsSmoothZoomSupported = false;
    private boolean mbIsZoomSupported = false;
    private boolean mbZoomRequestFromServer = false;


    Handler mHandler = new Handler();
    Runnable newFrame = new Runnable() {
        public void run() {
            if (TokboxVideoCapturer.this.isCaptureRunning) {
                if (TokboxVideoCapturer.this.frame == null) {
//                    Log.i(Config.CALL_LOG_TAG, "TokboxVideoCapturer : newFrame callback.  Setting frame width = " + PREFERRED_CAPTURE_WIDTH + ", height = " + PREFERRED_CAPTURE_HEIGHT );
                    TokboxVideoCapturer.this.width = PREFERRED_CAPTURE_WIDTH;
                    TokboxVideoCapturer.this.height = PREFERRED_CAPTURE_HEIGHT;
                    TokboxVideoCapturer.this.frame = new int[TokboxVideoCapturer.this.width * TokboxVideoCapturer.this.height];
                }

                TokboxVideoCapturer.this.provideIntArrayFrame(TokboxVideoCapturer.this.frame, 2, TokboxVideoCapturer.this.width, TokboxVideoCapturer.this.height, 0, false);
                TokboxVideoCapturer.this.mHandler.postDelayed(TokboxVideoCapturer.this.newFrame, (long) (1000 / TokboxVideoCapturer.this.fps));
            }

        }
    };

    public TokboxVideoCapturer(Context context ) {
        this.mCameraIndex = getCameraIndex(false);
        WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        this.mCurrentDisplay = windowManager.getDefaultDisplay();

    }

    private int findCamera(int cameraPosition) {
        int cameraId = -1;
        // Search for the front facing camera
        int numberOfCameras = Camera.getNumberOfCameras();
        for (int i = 0; i < numberOfCameras; i++) {
            CameraInfo info = new CameraInfo();
            Camera.getCameraInfo(i, info);
            if (info.facing == cameraPosition) {
//                Log.d(TAG, "Camera found");
                cameraId = i;
                break;
            }
        }
        return cameraId;
    }

    public void swapCamera(String cameraPosition) {
        boolean wasStarted = this.isCaptureStarted;
        if (this.mCamera != null) {
            this.stopCapture();
            this.mCamera.release();
            this.mCamera = null;
        }
        if(cameraPosition.equals("back")){
            this.mCameraIndex = this.findCamera(CameraInfo.CAMERA_FACING_BACK);
        } else {
            this.mCameraIndex = this.findCamera(CameraInfo.CAMERA_FACING_FRONT);
        }
        if (wasStarted) {


            this.mCamera = Camera.open(this.mCameraIndex);
            this.initCamera();
            this.startCapture();
        }

    }

    private void initCamera() {
        mCamera.setZoomChangeListener(new Camera.OnZoomChangeListener() {
            @Override
            public void onZoomChange(int zoomValue, boolean stopped, Camera camera) {
//                Log.i( Config.CALL_LOG_TAG, "onZoomChange : stopped = " + stopped );
                if (stopped) {
                    mbIsZooming = false;
//                    BusProvider.getBus().post(new ZoomSuccessEvent(mbZoomRequestFromServer));
                }
            }
        });

        Camera.Parameters params = this.mCamera.getParameters();
        mMaxZoom = params.getMaxZoom();
        mCurrentZoom = DEFAULT_ZOOM_LEVEL;   // server starts zoom level at 1.

        mCamera.cancelAutoFocus();
        if( mbIsSmoothZoomSupported ) {
//            Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : Starting smooth zoom to level " + mCurrentZoom );
            mbIsZooming = true;
            mCamera.startSmoothZoom(DEFAULT_ZOOM_LEVEL);
        }
        else {
//            Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : Immediate zooming to " + mCurrentZoom );
//            doImmediateZoom();
        }


        // mbIsZooming = false;
        mbIsSmoothZoomSupported = params.isSmoothZoomSupported();
        mbIsZoomSupported = params.isZoomSupported();

        this.mCurrentDeviceInfo = new CameraInfo();
        Camera.getCameraInfo(this.mCameraIndex, this.mCurrentDeviceInfo);

    }

    @Override
    public void init() {
        try {

            this.mCamera = Camera.open(this.mCameraIndex);

            initCamera();

        } catch (RuntimeException ex) {
//            Log.e(Config.CALL_LOG_TAG, "TokboxVideoCapturer : init() : An exception occurred. " + ex.getMessage() );
//            this.publisher.onCameraFailed();
        }
    }

    protected Camera getCamera(){
        return mCamera;
    }
    protected boolean getIsZoomSupported(){ return mbIsZoomSupported; }



    public int startCapture() {
        try {
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : startCapture() : ");

            if (this.isCaptureStarted) {
                return -1;
            }
            else {
                if (this.mCamera != null) {

                    this.configureCaptureSize(PREFERRED_CAPTURE_WIDTH, PREFERRED_CAPTURE_HEIGHT);
                    Parameters parameters = this.mCamera.getParameters();
                    parameters.setPreviewSize(this.mCaptureWidth, this.mCaptureHeight);
//                    Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : startCapture() : Configuring capture size.  mCaptureWidth =  " + mCaptureWidth + ", mCaptureHeight = " + mCaptureHeight );

                    parameters.setPreviewFormat(this.PIXEL_FORMAT);
                    parameters.setPreviewFrameRate(this.mCaptureFPS);
                    parameters.setRecordingHint(true);

                    if (!isFrontCamera()) { //front cameras generally don't support AutoFocus
                        parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);  // not supported by Samsung
                    }

                    try {
                        this.mCamera.setParameters(parameters);
                    } catch (RuntimeException var6) {

                        // Try to fix the focus mode.  If it can't be done, then run without it.   Don't fail out of here.
//                        Log.e(Config.CALL_LOG_TAG, "Camera.setParameters(parameters) - failed.   Trying FOCUS_MODE_AUDIO, if supported", var6);
                        //                    this.publisher.onCameraFailed();
                        try {
                            List<String> focusModes = parameters.getSupportedFocusModes();
                            if (focusModes.contains(Parameters.FOCUS_MODE_AUTO))
                                parameters.setFocusMode(Parameters.FOCUS_MODE_AUTO);
                            this.mCamera.setParameters(parameters);
                        }
                        catch( RuntimeException ex ){
//                            Log.e(Config.CALL_LOG_TAG, "Camera.setParameters(parameters) - failed.  Tried FOCUS_MODE_AUDIO", ex);
                        }
                    }

//                    Log.i(Config.CALL_LOG_TAG, "Continuing setup. ");
                    PixelFormat.getPixelFormatInfo( PixelFormat.RGBA_8888, this.mPixelFormat);
                    int bufSize = this.mCaptureWidth * this.mCaptureHeight * this.mPixelFormat.bitsPerPixel / 8;
                    Object buffer = null;

                    for (int e = 0; e < 3; ++e) {
                        byte[] var7 = new byte[bufSize];
                        this.mCamera.addCallbackBuffer(var7);
                    }

                    try {
                        this.mSurfaceTexture = new SurfaceTexture(42);
                        this.mCamera.setPreviewTexture(this.mSurfaceTexture);
                    } catch (Exception var5) {
                        //                    this.publisher.onCameraFailed();
                        var5.printStackTrace();
                        return -1;
                    }

                    this.mCamera.setPreviewCallbackWithBuffer(this);
                    this.mCamera.startPreview();
                    this.mPreviewBufferLock.lock();
                    this.mExpectedFrameSize = bufSize;
                    this.mPreviewBufferLock.unlock();
                } else {
                    this.blackFrames = true;
                    this.mHandler.postDelayed(this.newFrame, (long) (1000 / this.fps));
                }

                this.isCaptureRunning = true;
                this.isCaptureStarted = true;

//                Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : startCapture() : Finished capture size");

                return 0;
            }
        }
        catch( Exception ex ){
//            Log.e(Config.CALL_LOG_TAG, "TokboxVideoCapturer : startCapture() : An exception occurred. " + ex.getMessage() );
            return -1;
        }
    }

    public int stopCapture() {
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : stopCapture()" );
        if (this.mCamera != null) {
            this.mPreviewBufferLock.lock();

            try {
                if (this.isCaptureRunning) {
                    this.isCaptureRunning = false;
                    this.mCamera.stopPreview();
                    this.mCamera.setPreviewCallbackWithBuffer((PreviewCallback) null);
                }
            } catch (RuntimeException var2) {
//                Log.e(Config.CALL_LOG_TAG, "Camera.stopPreview() - failed ", var2);
//                this.publisher.onCameraFailed();
                return -1;
            }

            this.mPreviewBufferLock.unlock();
        }

        this.isCaptureStarted = false;
        if (this.blackFrames) {
            this.mHandler.removeCallbacks(this.newFrame);
        }

        return 0;
    }

    @Override
    public void destroy() {
        if (this.mCamera != null) {
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : destroy() : Stopping capture, releasing camera");
            this.stopCapture();
            this.mCamera.release();
            this.mCamera = null;

        }
        else{
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : destroy() :  camera = null");
        }
    }

    @Override
    public boolean isCaptureStarted() {
        return this.isCaptureStarted;
    }

    @Override
    public CaptureSettings getCaptureSettings() {
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : getCaptureSettings()");

        CaptureSettings settings = new CaptureSettings();
        if (this.mCamera != null) {
            settings = new CaptureSettings();
            this.configureCaptureSize(PREFERRED_CAPTURE_WIDTH, PREFERRED_CAPTURE_HEIGHT);
            settings.fps = this.mCaptureFPS;
            settings.width = this.mCaptureWidth;
            settings.height = this.mCaptureHeight;
            settings.format = 1;
            settings.expectedDelay = 0;
        } else {
            settings.fps = this.fps;
            settings.width = PREFERRED_CAPTURE_WIDTH;
            settings.height = PREFERRED_CAPTURE_HEIGHT;
            settings.format = 2;
        }

        return settings;
    }

    @Override
    public void onPause() {
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : onPause()" );
    }

    @Override
    public void onResume() {
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : onResume()" );
    }

    private int getNaturalCameraOrientation() {
        return this.mCurrentDeviceInfo != null ? this.mCurrentDeviceInfo.orientation : 0;
    }

    public boolean isFrontCamera() {
        return this.mCurrentDeviceInfo != null ? this.mCurrentDeviceInfo.facing == 1 : false;
    }

    public int getCameraIndex() {
        return this.mCameraIndex;
    }



    private int compensateCameraRotation(int uiRotation) {
        short currentDeviceOrientation = 0;
        switch (uiRotation) {
            case 0:
                currentDeviceOrientation = 0;
                break;
            case 1:
                currentDeviceOrientation = 270;
                break;
            case 2:
                currentDeviceOrientation = 180;
                break;
            case 3:
                currentDeviceOrientation = 90;
        }

        int cameraOrientation = this.getNaturalCameraOrientation();
        int cameraRotation = roundRotation(currentDeviceOrientation);
        boolean totalCameraRotation = false;
        boolean usingFrontCamera = this.isFrontCamera();
        int totalCameraRotation1;
        if (usingFrontCamera) {
            int inverseCameraRotation = (360 - cameraRotation) % 360;
            totalCameraRotation1 = (inverseCameraRotation + cameraOrientation) % 360;
        } else {
            totalCameraRotation1 = (cameraRotation + cameraOrientation) % 360;
        }

        return totalCameraRotation1;
    }

    private static int roundRotation(int rotation) {
        return (int) (Math.round((double) rotation / 90.0D) * 90L) % 360;
    }

    private static int getCameraIndex(boolean front) {
        for (int i = 0; i < Camera.getNumberOfCameras(); ++i) {
            CameraInfo info = new CameraInfo();
            Camera.getCameraInfo(i, info);
            if (front && info.facing == 1) {
                return i;
            }

            if (!front && info.facing == 0) {
                return i;
            }
        }

        return 0;
    }

    private void configureCaptureSize(int preferredWidth, int preferredHeight) {
        int maxFPS = 0;
        List sizes = null;

        try {

//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapture : configureCaptureSize() : requested width = " + preferredWidth + ", requestedHeight = " + preferredHeight );

            Parameters maxw = this.mCamera.getParameters();
            sizes = maxw.getSupportedPreviewSizes();

            // Get max frames per second from the list of supported frame rates.
            List maxh = maxw.getSupportedPreviewFrameRates();
            if (maxh != null) {
                Iterator s = maxh.iterator();

                while (s.hasNext()) {
                    Integer minw = (Integer) s.next();
                    if (minw.intValue() > maxFPS) {
                        maxFPS = minw.intValue();
                    }
                }
            }
        } catch (RuntimeException var11) {
//            Log.e(Config.CALL_LOG_TAG, "Error configuring capture size", var11);
//            this.publisher.onCameraFailed();
        }

//        this.mCaptureFPS = maxFPS;
        this.mCaptureFPS = 15;
        int var12 = 0;
        int var13 = 0;

        // get the largest width and height that is smaller than the preferredWidth and preferredHeight
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Start iterating supported camera sizes.  Preferred width = " + preferredWidth + ", preferred height = " + preferredHeight );
        if( preferredWidth < preferredHeight ){
            int temp = preferredHeight;
            preferredHeight = preferredWidth;
            preferredWidth = temp;
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Supported sizes are returned in landscape mode, so need to reverse preferredHeight and preferredWidth to get the best match." );
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : preferredWidth = " + preferredWidth + ", preferredHeight = " + preferredHeight );


        }
        for (int var14 = 0; var14 < sizes.size(); ++var14) {
            Size var17 = (Size) sizes.get(var14);
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : size " + var14 + " : width = " + var17.width + ", height = " + var17.height );

            if (var17.width >= var12 && var17.height >= var13 && var17.width <= preferredWidth && var17.height <= preferredHeight) {
                var12 = var17.width;
                var13 = var17.height;

//                Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : found size candidate : " + var17.toString() );

            }
        }

        if (var12 == 0 || var13 == 0) {
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Could not find a supported width and height that was smaller than the preferred width and height" );

            Size var15 = (Size) sizes.get(0);
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Look for minimum supported width and height that is smaller than the first supported size : " + var15.toString() );
            int var16 = var15.width;
            int minh = var15.height;

            for (int i = 1; i < sizes.size(); ++i) {
                var15 = (Size) sizes.get(i);
                if (var15.width <= var16 && var15.height <= minh) {
                    var16 = var15.width;
                    minh = var15.height;
//                    Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : found size candidate : " + var15.toString() );
                }
            }

            var12 = var16;
            var13 = minh;
        }

//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Setting mCaptureWidth : " + mCaptureWidth + ", mCaptureHeight = " + mCaptureHeight );
        float preferredAspectRatio = (float)preferredWidth / (float)preferredHeight;
        float supportedAspectRatio = (float)mCaptureWidth / (float)mCaptureHeight;
        float origAspectRatio = 640.0f/480.0f;
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : Requested aspect ratio = " + preferredAspectRatio + ", supported aspect ratio = " + supportedAspectRatio );
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : 640/ 480 = " + origAspectRatio );
        this.mCaptureWidth = var12;
        this.mCaptureHeight = var13;
    }

    public void onPreviewFrame(byte[] data, Camera camera) {
        this.mPreviewBufferLock.lock();
        if (this.isCaptureRunning && data.length == this.mExpectedFrameSize) {
            int currentRotation = this.compensateCameraRotation(this.mCurrentDisplay.getRotation());
            this.provideByteArrayFrame(data, 1, this.mCaptureWidth, this.mCaptureHeight, currentRotation, this.isFrontCamera());
            camera.addCallbackBuffer(data);
        }

        this.mPreviewBufferLock.unlock();
    }

    public void setPublisher(Publisher publisher) {
        this.publisher = publisher;
    }

    public void setFlashEnabled(boolean isFlashOn) {
//        Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : setFlashEnabled()");
        try {
            Camera.Parameters parameters = mCamera.getParameters();
            parameters.setFlashMode(isFlashOn ? Camera.Parameters.FLASH_MODE_TORCH : Camera.Parameters.FLASH_MODE_OFF);
            mCamera.setParameters(parameters);
        }
        catch( Exception ex ){
//            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : setFlashEnabled() : An error occurred : " + ex.getMessage() );
        }
    }

//
//    public int getCurrentZoom(){ return mCurrentZoom; }
//    public int getMaxZoom() { return mMaxZoom;}
//    public boolean canZoomIn() {
//        if (mCurrentZoom >= mMaxZoom )
//            return false;
//        else
//            return true;
//    }
//
//    public boolean canZoomOut() {
//        if( mCurrentZoom <= DEFAULT_ZOOM_LEVEL )
//            return false;
//        else
//            return true;
//    }
//
//
//    private void doImmediateZoom(){
//        Parameters params = this.mCamera.getParameters();
//        params.setZoom(mCurrentZoom);
//        mCamera.setParameters(params);
//        BusProvider.getBus().post(new ZoomSuccessEvent(mbZoomRequestFromServer));
//
//    }
//
//
//
//    private boolean updateZoomLevel( SignalTypeEnum type, int requestedCameraId,  int zoomToLevel, int zoomScaler ){
//        boolean bSuccess = true;
//
//
//        if( type == SignalTypeEnum.ZOOM_IN ){
//            if (mCurrentZoom >= mMaxZoom ) {
//                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : updateZoomLevel() : Zoom level is already at maximum." );
//                // /SignalTypeEnum requestType,int requestedCameraId, CameraInfo cameraInfo, String errMsg
//                BusProvider.getBus().post(new ZoomFailedEvent( type, requestedCameraId, ZOOM_LEVEL_ALREADY_MAXIMUM, mbZoomRequestFromServer ));
//                return false;
//            }
//
//            if (mCurrentZoom + zoomScaler >= mMaxZoom) {
//                mCurrentZoom = mMaxZoom;
//            } else {
//                mCurrentZoom += zoomScaler;
//            }
//
//        }
//        else if( type == SignalTypeEnum.ZOOM_OUT ){
//
//            if( mCurrentZoom <= DEFAULT_ZOOM_LEVEL ) {
//                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : updateZoomLevel() : Zoom level is already at minimum." );
//                BusProvider.getBus().post(new ZoomFailedEvent( SignalTypeEnum.ZOOM_OUT, requestedCameraId, ZOOM_LEVEL_ALREADY_MINIMUM, mbZoomRequestFromServer));
//                return false;
//            }
//
//            if (mCurrentZoom - zoomScaler <= DEFAULT_ZOOM_LEVEL) {
//                mCurrentZoom = DEFAULT_ZOOM_LEVEL;
//            } else {
//                // mCurrentZoom--;
//                mCurrentZoom -= zoomScaler;
//            }
//        }
//        else if( type == SignalTypeEnum.ZOOM_TO ){
//
//            if ((zoomToLevel < DEFAULT_ZOOM_LEVEL) || (zoomToLevel > mMaxZoom)) {
//                Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : zoomTo : requestZoom level is invalid. requested zoom level = " + zoomToLevel + ", maxZoomLevel = " + mMaxZoom );
//                BusProvider.getBus().post(new ZoomFailedEvent(  SignalTypeEnum.ZOOM_TO, requestedCameraId, REQUESTED_ZOOM_LEVEL_IS_INVALID, mbZoomRequestFromServer ));
//                return false;
//            }
//
//            mCurrentZoom = zoomToLevel;
//        }
//
//
//        return bSuccess;
//    }
//
//    public void doZoom( SignalTypeEnum type, int requestedCameraId, int zoomToLevel, boolean bZoomRequestFromServer ){
//        try {
//            if(zoomToLevel == mCurrentZoom )
//                return;
//
//
//            mbZoomRequestFromServer = bZoomRequestFromServer;
//            if (mCamera == null) {
////                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : mCamera is null." );
//                BusProvider.getBus().post(new ZoomFailedEvent( type, requestedCameraId, ZOOM_OPERATION_FAILED_NOT_INITIALIZED, mbZoomRequestFromServer ));
//                return;
//            }
//
//            if( mbIsZooming ){
////                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : Zoom is already in progress." );
//                BusProvider.getBus().post(new ZoomFailedEvent( type, requestedCameraId, ZOOM_OPERATION_ALREADY_IN_PROGRESS, mbZoomRequestFromServer ));
//                return;
//            }
//
//            // updating the current zoom level should be the last thing that happens so it's only updated on success.
//            int zoomScaler = CLIENT_ZOOM_SCALER;
//            if( bZoomRequestFromServer )
//                zoomScaler = SERVER_ZOOM_SCALER;
//
//            if( !updateZoomLevel( type, requestedCameraId, zoomToLevel, zoomScaler ) )
//                return;
//
//
//            mCamera.cancelAutoFocus();
//            if( mbIsSmoothZoomSupported ) {
////                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : Starting smooth zoom to level " + mCurrentZoom );
//                mbIsZooming = true;
//                mCamera.startSmoothZoom(mCurrentZoom);
//            }
//            else {
////                Log.i( Config.CALL_LOG_TAG, "TokboxCapturer : doZoom() : Immediate zooming to " + mCurrentZoom );
//                doImmediateZoom();
//            }
//        }
//        catch( Exception ex ){
////            Log.i( Config.CALL_LOG_TAG, "TokboxVideoCapturer : doZoom() : An error occurred : " + ex.getMessage() );
//        }
//
//    }
//




}
