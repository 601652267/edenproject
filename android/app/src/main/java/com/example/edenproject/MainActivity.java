package com.example.edenproject;

import androidx.annotation.NonNull;

import java.io.File;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String STORAGE_CHANNEL = "edenproject/app_storage";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                STORAGE_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if ("getEdenGalleryStorageDirectory".equals(call.method)) {
                File directory = new File(getFilesDir(), "eden_gallery");
                if (!directory.exists() && !directory.mkdirs()) {
                    result.error(
                            "storage_unavailable",
                            "Unable to create eden gallery storage directory.",
                            null
                    );
                    return;
                }
                result.success(directory.getAbsolutePath());
                return;
            }
            result.notImplemented();
        });
    }
}
