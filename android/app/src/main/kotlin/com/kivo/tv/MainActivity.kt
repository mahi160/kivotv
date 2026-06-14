package com.kivo.tv

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Prevent the soft keyboard from ever stealing D-pad key events.
        // On Android TV a hardware remote is the primary input; the IME
        // intercepting DPAD_UP/DOWN/LEFT/RIGHT before Flutter sees them
        // makes navigation completely broken.
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN or
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        )
    }
}
