package com.npetillo.fedsmokertv.ui

import android.view.KeyEvent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.npetillo.fedsmokertv.AppVm
import com.npetillo.fedsmokertv.BuildConfig
import com.npetillo.fedsmokertv.DEFAULT_SERVER
import com.npetillo.fedsmokertv.R
import com.npetillo.fedsmokertv.Screen
import kotlinx.coroutines.delay

/** Scales the 1920x1080 design canvas to the screen (letterboxed if the aspect differs). */
@Composable
fun AppUi(vm: AppVm) {
    BoxWithConstraints(Modifier.fillMaxSize().background(P.ink)) {
        val scale = minOf(constraints.maxWidth / 1920f, constraints.maxHeight / 1080f)
        CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
            Box(Modifier.align(Alignment.Center).box(1920, 1080).clipToBounds()) {
                when (val s = vm.screen) {
                    Screen.Login -> LoginScreen(vm)
                    is Screen.Error -> ErrorScreen(s, vm.errorIdx)
                    is Screen.Live -> LiveScreen(s.live)
                }
            }
        }
    }
}

@Composable
fun Footer(hints: List<Pair<String, String>>) {
    Box(Modifier.at(96, 1008).box(1728, 1).background(P.w10))
    KeyHints(hints, Modifier.at(96, 1008))
}

// ---------- login (centred sign-in form over the warm wash) ----------

@Composable
private fun FormField(label: String, value: String, placeholder: String, secure: Boolean, focused: Boolean, modifier: Modifier) {
    val empty = value.isEmpty()
    val shown = if (empty) placeholder else if (secure) "•".repeat(value.length) else value
    Box(modifier.box(600, 100).let { if (focused) it.rounded(P.w100, 8) else it }) {
        if (!focused) Box(Modifier.at(0, 99).box(600, 1).background(P.w15))
        Txt(label.uppercase(), 18, if (focused) P.ink60 else P.w35, Modifier.at(24, 18).width(552.dp))
        val color = when {
            focused && empty -> P.ink60
            focused -> P.ink
            empty -> P.w35
            else -> P.w85
        }
        Txt(shown, 28, color, Modifier.at(24, 50).width(552.dp))
    }
}

@Composable
private fun LoginScreen(vm: AppVm) {
    val l = vm.login
    Box(Modifier.box(1920, 1080)) {
        Image(painterResource(R.drawable.wash_bottom), null, Modifier.at(0, 660).box(1920, 420), contentScale = ContentScale.FillBounds)
        Txt("SIGN IN", 20, P.w35, Modifier.at(660, 150))
        Txt("FedSmokerTV", 64, P.w100, Modifier.at(660, 178))
        Txt("Use your Xtream Codes account.", 26, P.w60, Modifier.at(660, 266))
        FormField("Server URL", l.server, DEFAULT_SERVER, false, l.idx == 0, Modifier.at(660, 356))
        FormField("Username", l.username, "", false, l.idx == 1, Modifier.at(660, 468))
        FormField("Password", l.password, "", true, l.idx == 2, Modifier.at(660, 580))
        Row(Modifier.at(660, 720), verticalAlignment = Alignment.CenterVertically) {
            PillButton(if (l.busy) "Signing in…" else "Sign in", l.idx == 3)
            Spacer(Modifier.width(28.dp))
            Txt("Saved on this TV only", 20, P.w35)
        }
        Txt(l.status, 22, if (l.statusIsError) P.emberLight else P.w60, Modifier.at(660, 820).width(900.dp), maxLines = 2)
        Txt("v" + BuildConfig.VERSION_NAME, 18, P.w35, Modifier.at(96, 1022))
    }
    l.editing?.let { field -> EditDialog(field, l.value(field), vm::onEdited) }
}

private fun isOkKey(e: androidx.compose.ui.input.key.KeyEvent): Boolean {
    val c = e.nativeKeyEvent.keyCode
    return e.nativeKeyEvent.action == KeyEvent.ACTION_UP &&
        (c == KeyEvent.KEYCODE_DPAD_CENTER || c == KeyEvent.KEYCODE_ENTER || c == KeyEvent.KEYCODE_NUMPAD_ENTER)
}

/** Focusable pill for the keyboard dialog (the only place that uses real Compose focus). */
@Composable
private fun DialogButton(text: String, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    PillButton(
        text, focused,
        Modifier.onFocusChanged { focused = it.isFocused }.onKeyEvent { if (isOkKey(it)) { onClick(); true } else false }.focusable(),
    )
}

/** Keyboard dialog for one login field. Done on the keyboard (or Save) keeps the value; Back cancels. */
@Composable
private fun EditDialog(field: Int, initial: String, onDone: (String?) -> Unit) {
    val density = LocalDensity.current // the dialog window doesn't inherit the design-canvas scale
    Dialog(onDismissRequest = { onDone(null) }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        CompositionLocalProvider(LocalDensity provides density) { EditDialogBody(field, initial, onDone) }
    }
}

@Composable
private fun EditDialogBody(field: Int, initial: String, onDone: (String?) -> Unit) {
    val titles = listOf("Server URL", "Username", "Password")
    val start = if (field == 0 && initial.isEmpty()) DEFAULT_SERVER else initial
    var tf by remember { mutableStateOf(TextFieldValue(start, TextRange(start.length))) }
    val fr = remember { FocusRequester() }
    val kb = LocalSoftwareKeyboardController.current
    Column(Modifier.width(900.dp).rounded(P.ink, 12).outline(P.w15, 12).padding(48.dp)) {
        Txt(titles[field].uppercase(), 20, P.w35)
        Spacer(Modifier.height(16.dp))
        BasicTextField(
            value = tf,
            onValueChange = { tf = it },
            singleLine = true,
            textStyle = TextStyle(color = P.ink, fontSize = 32.sp, fontFamily = Abc),
            cursorBrush = SolidColor(P.ink),
            visualTransformation = if (field == 2) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = when (field) { 0 -> KeyboardType.Uri; 2 -> KeyboardType.Password; else -> KeyboardType.Ascii },
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { onDone(tf.text) }),
            modifier = Modifier.fillMaxWidth().focusRequester(fr)
                .onKeyEvent { if (isOkKey(it)) { kb?.show(); true } else false }
                .rounded(P.w100, 8).padding(horizontal = 24.dp, vertical = 20.dp),
        )
        Spacer(Modifier.height(20.dp))
        if (field == 0) Txt("Include the port and http:// or https://", 22, P.w60)
        Spacer(Modifier.height(32.dp))
        Row {
            DialogButton("Save") { onDone(tf.text) }
            Spacer(Modifier.width(20.dp))
            DialogButton("Cancel") { onDone(null) }
        }
    }
    LaunchedEffect(Unit) {
        delay(50)
        fr.requestFocus()
        kb?.show()
    }
}

// ---------- error ("Cannot reach server" with Retry / Edit account) ----------

@Composable
private fun ErrorScreen(s: Screen.Error, idx: Int) {
    Box(Modifier.box(1920, 1080)) {
        Txt("FedSmokerTV", 34, P.w100, Modifier.at(96, 50))
        Dot(modifier = Modifier.at(96, 307))
        Txt("CONNECTION", 20, P.w60, Modifier.at(120, 300))
        Txt(s.heading, 96, P.w100, Modifier.at(96, 340).width(1600.dp))
        Txt(s.message, 30, P.w60, Modifier.at(96, 480).width(900.dp), maxLines = 3, lineSpacing = 8)
        if (s.server.isNotEmpty()) {
            Box(Modifier.at(96, 600).height(64.dp).outline(P.w15, 8).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterStart) {
                Txt(s.server, 24, P.w85)
            }
        }
        Row(Modifier.at(96, 720)) {
            PillButton("Retry", idx == 0)
            Spacer(Modifier.width(20.dp))
            PillButton("Edit account", idx == 1)
        }
        Txt("Debug log: adb logcat -s FedSmokerTV while the app runs.", 18, P.w35, Modifier.at(1404, 880).width(420.dp), maxLines = 2)
        Footer(listOf("← →" to "Choose", "OK" to "Select", "Back" to "Exit"))
    }
}
