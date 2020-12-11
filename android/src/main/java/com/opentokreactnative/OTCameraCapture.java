package com.opentokreactnative;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.PixelFormat;
import android.graphics.SurfaceTexture;
import android.hardware.Camera;
import android.hardware.Camera.CameraInfo;
import android.hardware.Camera.Parameters;
import android.hardware.Camera.PreviewCallback;
import android.hardware.Camera.Size;
import android.os.AsyncTask;
import android.os.Bundle;
import android.os.Handler;

import android.os.Message;
import android.util.Base64;
import android.view.Display;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.WritableMap;
import com.opentok.android.BaseVideoCapturer;
import com.opentok.android.Publisher;
import com.opentok.android.Session;
import com.opentokreactnative.utils.EventUtils;

import java.io.IOException;
import java.io.OutputStreamWriter;
import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Timer;
import java.util.concurrent.locks.ReentrantLock;

class OTCameraCapture extends BaseVideoCapturer implements PreviewCallback {

    public final static int PREFERRED_CAPTURE_WIDTH = 640;
    public final static int PREFERRED_CAPTURE_HEIGHT = 480;

    private WritableMap response;
    private Context context;
    private Callback getImgDataCallback;
    private int mCameraIndex = 0;
    private Camera mCamera;
    private CameraInfo mCurrentDeviceInfo = null;
    public ReentrantLock mPreviewBufferLock = new ReentrantLock();
    private int PIXEL_FORMAT = 17;
    PixelFormat mPixelFormat = new PixelFormat();
    private boolean isCaptureStarted = false;
    private boolean isCaptureRunning = false;
    private int mExpectedFrameSize = 0;
    private int mCaptureWidth = -1;
    private int mCaptureHeight = -1;
    private int mCaptureFPS = -1;
    private Display mCurrentDisplay;
    private SurfaceTexture mSurfaceTexture;
    private boolean blackFrames = false;
    int fps = 1;
    int width = 0;
    int height = 0;
    int[] frame;


    Handler mHandler = new Handler();
    Runnable newFrame = new Runnable() {
        public void run() {
            if (OTCameraCapture.this.isCaptureRunning) {
                if (OTCameraCapture.this.frame == null) {
//                    Log.i(Config.CALL_LOG_TAG, "TokboxVideoCapturer : newFrame callback.  Setting frame width = " + PREFERRED_CAPTURE_WIDTH + ", height = " + PREFERRED_CAPTURE_HEIGHT );
                    OTCameraCapture.this.width = PREFERRED_CAPTURE_WIDTH;
                    OTCameraCapture.this.height = PREFERRED_CAPTURE_HEIGHT;
                    OTCameraCapture.this.frame = new int[OTCameraCapture.this.width * OTCameraCapture.this.height];
                }

                OTCameraCapture.this.provideIntArrayFrame(OTCameraCapture.this.frame, 2, OTCameraCapture.this.width, OTCameraCapture.this.height, 0, false);
                OTCameraCapture.this.mHandler.postDelayed(OTCameraCapture.this.newFrame, (long) (1000 / OTCameraCapture.this.fps));
            }

        }
    };

    public OTCameraCapture(Context reactContext ) {
        context = reactContext;
        this.mCameraIndex = getCameraIndex(false);
        WindowManager windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        this.mCurrentDisplay = windowManager.getDefaultDisplay();
    }

    public void swapCamera(boolean cameraPosition) {
        if (this.mCamera != null) {
            this.stopCapture();
        }
        this.mCameraIndex = this.getCameraIndex(cameraPosition);
        this.initCamera();
        if (!this.isCaptureStarted) {
            this.startCapture();
        }
    }

    private void initCamera() {

        this.mCamera = Camera.open(this.mCameraIndex);
        if(this.mCurrentDeviceInfo == null){
            this.mCurrentDeviceInfo = new CameraInfo();
        }
        Camera.getCameraInfo(this.mCameraIndex, this.mCurrentDeviceInfo);
    }

    @Override
    public void init() {
        initCamera();
    }

    public int startCapture() {
        if (this.mCamera != null) {

            this.configureCaptureSize(PREFERRED_CAPTURE_WIDTH, PREFERRED_CAPTURE_HEIGHT);
            Parameters parameters = this.mCamera.getParameters();
            parameters.setPreviewSize(this.mCaptureWidth, this.mCaptureHeight);

            parameters.setPreviewFormat(this.PIXEL_FORMAT);

            if (!isFrontCamera()) { //front cameras generally don't support AutoFocus
                parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);  // not supported by Samsung
            }

            this.mCamera.setParameters(parameters);

            PixelFormat.getPixelFormatInfo( PixelFormat.RGBA_8888, this.mPixelFormat);
            int bufSize = this.mCaptureWidth * this.mCaptureHeight * this.mPixelFormat.bitsPerPixel / 8;

            for (int e = 0; e < 3; ++e) {
                byte[] var7 = new byte[bufSize];
                this.mCamera.addCallbackBuffer(var7);
            }

            try {
                this.mSurfaceTexture = new SurfaceTexture(42);
                this.mCamera.setPreviewTexture(this.mSurfaceTexture);
            } catch (Exception var5) {
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

        return 0;
    }

    public int stopCapture() {
        if (this.mCamera != null) {
            this.mPreviewBufferLock.lock();

            try {
                if (this.isCaptureRunning) {
                    this.mCamera.stopPreview();
                    this.mCamera.setPreviewCallbackWithBuffer((PreviewCallback) null);
                }
            } catch (RuntimeException var2) {
                return -1;
            }

            this.mPreviewBufferLock.unlock();
        }

        this.isCaptureStarted = false;
        if (this.blackFrames) {
            this.mHandler.removeCallbacks(this.newFrame);
        }

        this.mCamera.release();
        this.mCamera = null;
        return 0;
    }

    @Override
    public void destroy() {
        if (this.mCamera != null) {
//            Log.i( Config.CALL_LOG_TAG, "OTCameraCapture : destroy() : Stopping capture, releasing camera");
            this.stopCapture();
            this.mCamera.release();
            this.mCamera = null;

        }
        else{
//            Log.i( Config.CALL_LOG_TAG, "OTCameraCapture : destroy() :  camera = null");
        }
    }

    @Override
    public boolean isCaptureStarted() {
        return this.isCaptureStarted;
    }

    @Override
    public CaptureSettings getCaptureSettings() {
//        Log.i( Config.CALL_LOG_TAG, "OTCameraCapture : getCaptureSettings()");

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
//        Log.i( Config.CALL_LOG_TAG, "OTCameraCapture : onPause()" );
    }

    @Override
    public void onResume() {
//        Log.i( Config.CALL_LOG_TAG, "OTCameraCapture : onResume()" );
    }

    public boolean isFrontCamera() {
        return this.mCurrentDeviceInfo != null ? this.mCurrentDeviceInfo.facing == 1 : false;
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
        int tmp = currentDeviceOrientation;

        if (this.mCurrentDeviceInfo.facing == 1) {
            tmp = (360 - tmp) % 360;
        }
        return (tmp + this.mCurrentDeviceInfo.orientation) % 360;
    }

    private static int getCameraIndex(boolean front) {
        CameraInfo info = new CameraInfo();
        for (int i = 0; i < Camera.getNumberOfCameras(); ++i) {
            Camera.getCameraInfo(i, info);

            if ((front && info.facing == 1) || !front && info.facing == 0) {
                return i;
            }
        }

        return 0;
    }

    private void configureCaptureSize(int preferredWidth, int preferredHeight) {
        Parameters maxw = this.mCamera.getParameters();
        List sizes = maxw.getSupportedPreviewSizes();

        this.mCaptureFPS = 30;

        // get the largest width and height that is smaller than the preferredWidth and preferredHeight
        if( preferredWidth < preferredHeight ){
            int temp = preferredHeight;
            preferredHeight = preferredWidth;
            preferredWidth = temp;

        }
        for (Object size : sizes) {
            Size var17 = (Size) size;
            if (var17.width >= this.mCaptureWidth && var17.height >= this.mCaptureHeight && var17.width <= preferredWidth && var17.height <= preferredHeight) {
                this.mCaptureWidth = var17.width;
                this.mCaptureHeight = var17.height;
            }
        }

        if (this.mCaptureWidth == 0 || this.mCaptureHeight == 0) {

            Size var15 = (Size) sizes.get(0);
            int var16 = var15.width;
            int minh = var15.height;

            for (Object size : sizes) {
                var15 = (Size) size;
                if (var15.width <= var16 && var15.height <= minh) {
                    var16 = var15.width;
                    minh = var15.height;
                }
            }

            this.mCaptureWidth = var16;
            this.mCaptureHeight = minh;
        }
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

    public void setFlashEnabled(String isFlashOn) {
        Camera.Parameters parameters = mCamera.getParameters();
        parameters.setFlashMode(isFlashOn);
        mCamera.setParameters(parameters);
    }

    public void getImgData(Callback callback) {
        getImgDataCallback = callback;

        response = Arguments.createMap();

        int currentRotation = this.compensateCameraRotation(this.mCurrentDisplay.getRotation());

        Camera.Parameters params = mCamera.getParameters();
        params.setRotation(currentRotation);
        params.setJpegQuality(100);

        mCamera.setParameters(params);
        mCamera.takePicture(null, null, pictureCallback);
    }

    public void clearPreview(Callback callback){
        mCamera.startPreview();
        callback.invoke();
    }

    private final Camera.PictureCallback pictureCallback = new Camera.PictureCallback() {
        @Override
        public void onPictureTaken(byte[] data, Camera camera) {
            String encoded = Base64.encodeToString(data, Base64.DEFAULT);
            response.putString("base64", encoded);
            getImgDataCallback.invoke(null, response);
        }
    };
}
