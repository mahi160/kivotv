package com.kivo.tv

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // SOFT_INPUT_STATE_HIDDEN: hides the keyboard when the activity
        // opens (so Home / Player don’t show a keyboard on launch) but
        // allows it to appear when a text field gains focus (needed for
        // the Search screen on Android TV).
        // SOFT_INPUT_ADJUST_NOTHING: don’t resize / pan the window —
        // the search field is already at the top so scrolling is fine.
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_HIDDEN or
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING
        )
    }
}
