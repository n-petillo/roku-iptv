package com.npetillo.fedsmokertv

import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import com.npetillo.fedsmokertv.ui.AppUi

class MainActivity : ComponentActivity() {
    private val vm: AppVm by viewModels()
    private var okDown = false
    private var longFired = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            LaunchedEffect(vm.exitRequested) { if (vm.exitRequested) finish() }
            AppUi(vm)
        }
    }

    override fun onStart() {
        super.onStart()
        vm.onForeground()
    }

    override fun onStop() {
        vm.onBackground()
        super.onStop()
    }

    // All remote keys go through the state machines in AppVm/LiveState; the UI only draws state.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val code = event.keyCode
        val down = event.action == KeyEvent.ACTION_DOWN
        if (code == KeyEvent.KEYCODE_DPAD_CENTER || code == KeyEvent.KEYCODE_ENTER || code == KeyEvent.KEYCODE_NUMPAD_ENTER) {
            // OK fires on release; holding it ~0.6s is "long OK" (favorite), for remotes without a play/pause key
            if (down) {
                if (event.repeatCount == 0) {
                    okDown = true
                    longFired = false
                } else if (okDown && !longFired && (event.isLongPress || event.eventTime - event.downTime >= 600)) {
                    longFired = true
                    vm.onKey(K.LongOk)
                }
            } else if (event.action == KeyEvent.ACTION_UP) {
                if (okDown && !longFired) vm.onKey(K.Ok)
                okDown = false
            }
            return true
        }
        val k = when (code) {
            KeyEvent.KEYCODE_DPAD_UP -> K.Up
            KeyEvent.KEYCODE_DPAD_DOWN -> K.Down
            KeyEvent.KEYCODE_DPAD_LEFT -> K.Left
            KeyEvent.KEYCODE_DPAD_RIGHT -> K.Right
            KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_ESCAPE -> K.Back
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE -> K.PlayPause
            KeyEvent.KEYCODE_MENU, KeyEvent.KEYCODE_SETTINGS -> K.Menu
            KeyEvent.KEYCODE_CHANNEL_UP, KeyEvent.KEYCODE_PAGE_UP -> K.ChUp
            KeyEvent.KEYCODE_CHANNEL_DOWN, KeyEvent.KEYCODE_PAGE_DOWN -> K.ChDown
            else -> null
        } ?: return super.dispatchKeyEvent(event)
        if (down) {
            // arrows auto-repeat while held; everything else acts once per press
            val repeatable = k == K.Up || k == K.Down || k == K.Left || k == K.Right
            if (event.repeatCount == 0 || repeatable) return vm.onKey(k) || super.dispatchKeyEvent(event)
        }
        return true
    }
}
