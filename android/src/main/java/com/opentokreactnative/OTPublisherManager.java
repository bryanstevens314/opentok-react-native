package com.opentokreactnative;

import android.os.AsyncTask;

import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.opentok.android.Publisher;

public class OTPublisherManager extends ReactContextBaseJavaModule {

    private static OTCameraCapture capturer;
    private static Publisher mPublisher;
    public OTRN sharedState;

    public OTPublisherManager(ReactApplicationContext reactContext) {

        super(reactContext);
        sharedState = OTRN.getSharedState();

    }

    public static Publisher initialize(ReactApplicationContext context, boolean audioTrack, boolean videoTrack, String name, int audioBitrate, String resolution, String frameRate) {
        capturer = new OTCameraCapture(context);

        mPublisher = new Publisher.Builder(context)
                .audioTrack(audioTrack)
                .videoTrack(videoTrack)
                .name(name)
                .audioBitrate(audioBitrate)
                .resolution(Publisher.CameraCaptureResolution.valueOf(resolution))
                .frameRate(Publisher.CameraCaptureFrameRate.valueOf(frameRate))
                .capturer(capturer)
                .build();
        return mPublisher;
    }
    @Override
    public String getName() {
        return this.getClass().getSimpleName();
    }

    private class AsyncSwapCamera extends AsyncTask<Void, Void, Void> {

        public AsyncSwapCamera(boolean cameraPosition) {
            super();
            capturer.swapCamera(cameraPosition);
        }

        @Override
        protected Void doInBackground(Void... voids) {
            return null;
        }
    }

    @ReactMethod
    public void swapCamera(boolean cameraPosition) {
        AsyncSwapCamera task = new AsyncSwapCamera(cameraPosition);
        task.execute();
    }

    @ReactMethod
    public void setFlash(String isFlashOn) {

        capturer.setFlashEnabled(isFlashOn);
    }

    @ReactMethod
    public void getImgData(Callback callback) {

        capturer.getImgData(callback);
    }

    @ReactMethod
    public void clearPreview(Callback callback) {

        capturer.clearPreview(callback);
    }
}
