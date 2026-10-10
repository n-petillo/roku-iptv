// Switches between the Login, Live and Error screens (port of MainScene + LoginScreen logic).
package com.npetillo.fedsmokertv

import android.app.Application
import androidx.annotation.OptIn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import kotlinx.coroutines.launch

/** Remote keys the app reacts to (mapped from Android key codes in MainActivity). */
enum class K { Up, Down, Left, Right, Ok, LongOk, Back, PlayPause, Menu, ChUp, ChDown }

sealed interface Screen {
    data object Login : Screen
    data class Live(val live: LiveState) : Screen
    data class Error(val heading: String, val message: String, val server: String) : Screen
}

const val ERROR_HINT = "Check the server URL includes the port (:8080 etc.) and the right http:// or https://."

class LoginState {
    var server by mutableStateOf(DEFAULT_SERVER)
    var username by mutableStateOf("")
    var password by mutableStateOf("")
    var idx by mutableIntStateOf(1) // server is prefilled, start on Username
    var busy by mutableStateOf(false)
    var status by mutableStateOf("")
    var statusIsError by mutableStateOf(false)
    /** Field being edited in the keyboard dialog: 0 server, 1 username, 2 password. */
    var editing by mutableStateOf<Int?>(null)

    fun value(i: Int) = when (i) { 0 -> server; 1 -> username; else -> password }

    fun setValue(i: Int, v: String) {
        when (i) {
            0 -> server = normalizeServer(v).ifEmpty { v.trim() }
            1 -> username = v.trim()
            else -> password = v
        }
    }

    fun fill(c: Creds?) {
        server = c?.server?.ifEmpty { null } ?: DEFAULT_SERVER
        username = c?.username.orEmpty()
        password = c?.password.orEmpty()
        // land on the first empty field, else on Sign in
        idx = listOf(server, username, password).indexOfFirst { it.isEmpty() }.let { if (it < 0) 3 else it }
        status = ""
        busy = false
    }
}

class AppVm(app: Application) : AndroidViewModel(app) {
    val store = Store(app)
    val api = Api()
    val login = LoginState()
    var screen by mutableStateOf<Screen>(Screen.Login)
        private set
    var exitRequested by mutableStateOf(false)
        private set
    var errorIdx by mutableIntStateOf(0)

    @OptIn(UnstableApi::class)
    val player: ExoPlayer = run {
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(USER_AGENT)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(20_000)
        ExoPlayer.Builder(app)
            .setMediaSourceFactory(DefaultMediaSourceFactory(app).setDataSourceFactory(http))
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
                true,
            )
            .build()
    }

    init {
        val creds = store.loadCreds()
        showLogin(creds, auto = creds != null && creds.password.isNotEmpty())
    }

    private fun leaveLive() {
        (screen as? Screen.Live)?.live?.dispose()
    }

    fun showLogin(creds: Creds?, auto: Boolean) {
        leaveLive()
        login.fill(creds)
        screen = Screen.Login
        if (auto) doLogin(auto = true)
    }

    private fun showError(heading: String, server: String, message: String = ERROR_HINT) {
        leaveLive()
        errorIdx = 0
        screen = Screen.Error(heading, message, server)
    }

    private fun showLive(creds: Creds) {
        leaveLive()
        val live = LiveState(
            scope = viewModelScope, api = api, store = store, creds = creds, player = player,
            onLogout = ::logout,
            onExit = { exitRequested = true },
            onFatal = { heading, message -> showError(heading, creds.server, message ?: ERROR_HINT) },
        )
        screen = Screen.Live(live)
        live.start()
    }

    fun doLogin(auto: Boolean = false) {
        val l = login
        val creds = Creds(normalizeServer(l.server), l.username.trim(), l.password)
        if (creds.server.isEmpty() || creds.username.isEmpty() || creds.password.isEmpty()) {
            l.status = "Enter server, username and password."
            l.statusIsError = true
            return
        }
        l.busy = true
        l.status = "Connecting to ${creds.server} …"
        l.statusIsError = false
        viewModelScope.launch {
            val r = api.login(creds)
            l.busy = false
            when (r) {
                is ApiResult.Ok -> {
                    l.status = ""
                    val full = creds.copy(ext = r.value)
                    store.saveCreds(full)
                    showLive(full)
                }
                is ApiResult.Err -> {
                    // a saved login that can't reach the server gets the error screen, not the form
                    if (auto && r.netError) {
                        showError("Cannot reach server", creds.server)
                        return@launch
                    }
                    l.status = r.error
                    l.statusIsError = true
                    l.idx = 3
                }
            }
        }
    }

    /** Forget the password so the next launch doesn't auto-login; keep server/username prefilled. */
    private fun logout() {
        val c = store.loadCreds()?.copy(password = "")
        viewModelScope.launch {
            if (c != null) store.saveCreds(c)
        }
        showLogin(c, auto = false)
    }

    fun onKey(k: K): Boolean {
        when (val s = screen) {
            is Screen.Live -> return s.live.onKey(k)
            is Screen.Error -> {
                when (k) {
                    K.Left, K.Right -> errorIdx = 1 - errorIdx
                    K.Ok -> {
                        val c = store.loadCreds()
                        if (errorIdx == 0 && c != null && c.password.isNotEmpty()) showLogin(c, true) else showLogin(c, false)
                    }
                    K.Back -> exitRequested = true
                    else -> return false
                }
                return true
            }
            Screen.Login -> {
                val l = login
                if (l.busy && k != K.Back) return true
                when (k) {
                    K.Up -> if (l.idx > 0) l.idx--
                    K.Down -> if (l.idx < 3) l.idx++
                    K.Ok -> if (l.idx < 3) l.editing = l.idx else doLogin()
                    K.Back -> exitRequested = true
                    else -> return false
                }
                return true
            }
        }
    }

    /** Keyboard dialog result. */
    fun onEdited(value: String?) {
        val i = login.editing ?: return
        login.editing = null
        if (value != null) {
            login.setValue(i, value)
            if (login.idx < 3) login.idx++ // advance to the next field
        }
    }

    fun onBackground() {
        (screen as? Screen.Live)?.live?.onBackground()
    }

    fun onForeground() {
        (screen as? Screen.Live)?.live?.onForeground()
    }

    override fun onCleared() {
        leaveLive()
        player.release()
    }
}
