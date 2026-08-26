package dev.dartitect.media;

import android.Manifest;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;

import androidx.annotation.NonNull;

import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.net.URLConnection;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

public final class DartitectMediaPlugin implements FlutterPlugin,
        MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.RequestPermissionsResultListener {
    private static final int REQUEST_PERMISSION = 7019;
    private static final String PREFERENCES = "dartitect_media";
    private static final String PERMISSION_REQUESTED = "legacy_write_requested";
    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private MethodChannel.Result pendingPermission;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "dev.dartitect/media");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() { detachActivity(); }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() { detachActivity(); }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        if (pendingPermission != null) {
            pendingPermission.error("cancelled", null, null);
            pendingPermission = null;
        }
        activityBinding = null;
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "status": result.success(permissionStatus()); break;
            case "request": requestPermission(result); break;
            case "saveImage": saveImage(call, result); break;
            case "clearOwnedState": clearOwnedState(result); break;
            default: result.notImplemented();
        }
    }

    private void clearOwnedState(MethodChannel.Result result) {
        boolean cleared = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .remove(PERMISSION_REQUESTED)
                .commit();
        if (cleared) result.success(null);
        else result.error("cleanup_failed", null, null);
    }

    private String permissionStatus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return "authorized";
        if (context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                == PackageManager.PERMISSION_GRANTED) {
            return "authorized";
        }
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getBoolean(PERMISSION_REQUESTED, false)
                ? "denied" : "notDetermined";
    }

    private void requestPermission(MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            result.success("authorized");
            return;
        }
        if (activity == null || pendingPermission != null) {
            result.error("cancelled", null, null);
            return;
        }
        if ("authorized".equals(permissionStatus())) {
            result.success("authorized");
            return;
        }
        boolean recorded = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PERMISSION_REQUESTED, true)
                .commit();
        if (!recorded) {
            result.error("native_error", null, null);
            return;
        }
        pendingPermission = result;
        activity.requestPermissions(
                new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
                REQUEST_PERMISSION
        );
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                              @NonNull int[] grantResults) {
        if (requestCode != REQUEST_PERMISSION || pendingPermission == null) return false;
        MethodChannel.Result result = pendingPermission;
        pendingPermission = null;
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        mainHandler.post(() -> result.success(granted ? "authorized" : "denied"));
        return true;
    }

    private void saveImage(MethodCall call, MethodChannel.Result result) {
        String path = call.argument("path");
        String album = call.argument("album");
        if (path == null) {
            result.error("invalid_file", null, null);
            return;
        }
        File source = new File(path);
        if (!source.exists()) {
            result.error("file_not_found", null, null);
            return;
        }
        if (!source.isFile() || !source.canRead()) {
            result.error("invalid_file", null, null);
            return;
        }
        if (!"authorized".equals(permissionStatus())) {
            result.error("permission_denied", null, null);
            return;
        }
        new Thread(() -> performSave(source, album, result), "dartitect-media-save").start();
    }

    private void performSave(File source, String album, MethodChannel.Result result) {
        Uri inserted = null;
        try {
            ContentResolver resolver = context.getContentResolver();
            ContentValues values = new ContentValues();
            values.put(MediaStore.Images.Media.DISPLAY_NAME, source.getName());
            String mime = URLConnection.guessContentTypeFromName(source.getName());
            values.put(MediaStore.Images.Media.MIME_TYPE, mime == null ? "image/*" : mime);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                String folder = Environment.DIRECTORY_PICTURES
                        + (album == null ? "" : File.separator + album);
                values.put(MediaStore.Images.Media.RELATIVE_PATH, folder);
                values.put(MediaStore.Images.Media.IS_PENDING, 1);
            }
            inserted = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
            if (inserted == null) throw new IllegalStateException();
            try (FileInputStream input = new FileInputStream(source);
                 OutputStream output = resolver.openOutputStream(inserted, "w")) {
                if (output == null) throw new IllegalStateException();
                byte[] buffer = new byte[64 * 1024];
                int read;
                while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ContentValues complete = new ContentValues();
                complete.put(MediaStore.Images.Media.IS_PENDING, 0);
                resolver.update(inserted, complete, null, null);
            }
            Map<String, Object> receipt = new HashMap<>();
            receipt.put("identifier", inserted.toString());
            mainHandler.post(() -> result.success(receipt));
        } catch (Throwable failure) {
            if (inserted != null) context.getContentResolver().delete(inserted, null, null);
            mainHandler.post(() -> result.error("native_error", null, null));
        }
    }
}
