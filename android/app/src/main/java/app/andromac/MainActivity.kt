package app.andromac

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private var resumeTick by mutableIntStateOf(0)

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        enableEdgeToEdge()
        Link.init(this)
        handleLink(intent)
        if (Link.isPaired) LinkService.start(this)
        setContent { AndromacTheme { Root(resumeTick) } }
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); handleLink(intent) }
    override fun onResume() { super.onResume(); resumeTick++ }

    private fun handleLink(i: Intent?) {
        val uri = i?.data?.takeIf { it.scheme == "andromac" } ?: return
        Link.savePairing(uri.toString()); LinkService.start(this); Link.restart()
    }
}


// ---------- root / navigation ----------
private enum class Tab(val label: String, val icon: ImageVector) {
    Home("Home", Icons.Rounded.Home),
    Clipboard("Clipboard", Icons.Rounded.List),
    Screen("Screen", Icons.Rounded.Phone),
    Settings("Settings", Icons.Rounded.Settings),
}

@Composable
private fun Root(tick: Int) {
    var screen by remember { mutableStateOf("main") }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    val reduced = LocalReduced.current
    val snack = remember { SnackbarHostState() }
    var toast by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(toast) { toast?.let { snack.showSnackbar(it, duration = SnackbarDuration.Short); toast = null } }
    LaunchedEffect(Unit) { delay(900); introPlayed = true }
    BackHandler(screen != "main") { screen = "main" }
    BackHandler(screen == "main" && tab != 0) { tab = 0 }
    if (screen == "apps") { AppsScreen { screen = "main" }; return }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets.statusBars,
        snackbarHost = { SnackbarHost(snack) },
        bottomBar = {
            val d = androidx.compose.ui.platform.LocalDensity.current
            // labels stay readable at huge font sizes instead of wrapping inside the bar
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, minOf(d.fontScale, 1.2f))) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                    Tab.entries.forEachIndexed { i, t ->
                        NavigationBarItem(
                            selected = tab == i, onClick = { tab = i },
                            icon = { Icon(t.icon, contentDescription = null) },
                            label = { Text(t.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            alwaysShowLabel = true,
                            colors = NavigationBarItemDefaults.colors(
                                indicatorColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.onSurface,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant),
                            modifier = Modifier.semantics { contentDescription = "${t.label} tab" },
                        )
                    }
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad)) {
            AnimatedContent(
                targetState = tab, label = "tabs",
                transitionSpec = {
                    val d = if (reduced) 0 else Mo.Normal
                    fadeIn(tween(d, easing = Mo.Emph)) togetherWith fadeOut(tween(if (reduced) 0 else Mo.Fast, easing = Mo.Emph))
                },
            ) { t ->
                when (Tab.entries[t]) {
                    Tab.Home -> HomeTab(tick, goTab = { tab = it }, notify = { toast = it })
                    Tab.Clipboard -> ClipboardTab(notify = { toast = it })
                    Tab.Screen -> ScreenTab(tick)
                    Tab.Settings -> SettingsTab(tick, openApps = { screen = "apps" })
                }
            }
        }
    }
}

// ---------- permissions ----------
private class Perms(val listener: Boolean, val sms: Boolean, val posts: Boolean, val battery: Boolean, val overlay: Boolean) {
    val allGood get() = listener && sms && posts && battery && overlay
}

private fun readPerms(ctx: Context): Perms {
    fun has(p: String) = ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    return Perms(
        listener = NotificationManagerCompat.getEnabledListenerPackages(ctx).contains(ctx.packageName),
        sms = has(Manifest.permission.RECEIVE_SMS),
        posts = Build.VERSION.SDK_INT < 33 || has(Manifest.permission.POST_NOTIFICATIONS),
        battery = ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName),
        overlay = true,
    )
}

private fun isA11yOn(ctx: Context) =
    (AndroidSettings.Secure.getString(ctx.contentResolver, AndroidSettings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "").contains(ctx.packageName)

private fun appInfo(ctx: Context) = ctx.startActivity(
    Intent(AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")))

private class PermSpec(val ok: Boolean, val title: String, val hint: String, val action: String, val fix: () -> Unit)

@Composable
private fun permSpecs(perms: Perms, includeA11y: Boolean, a11yOn: Boolean): List<PermSpec> {
    val ctx = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    return buildList {
        add(PermSpec(perms.listener, "Notification access",
            "Open the list, find Andromac and switch it on, so your phone's notifications can reach your Mac.", "Allow") {
            ctx.startActivity(Intent(AndroidSettings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        })
        add(PermSpec(perms.sms, "SMS and one-time codes",
            "Tap Allow when Android asks, so Andromac can forward verification codes to your Mac.", "Allow") {
            launcher.launch(arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.POST_NOTIFICATIONS))
        })
        add(PermSpec(perms.posts, "Show notifications",
            "Tap Allow when Android asks, so Andromac can show your Mac's notifications on this phone.", "Allow") {
            launcher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
        })
        add(PermSpec(perms.battery, "Unrestricted battery",
            "Choose Allow so Android doesn't put Andromac to sleep and drop the connection in the background.", "Fix") {
            ctx.startActivity(Intent(AndroidSettings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}")))
        })
        if (includeA11y && !A11yToggle.canToggle(ctx)) add(PermSpec(a11yOn, "Control from Mac (optional)",
            "To keep payment apps working, Andromac can switch its control service on only during a session. That needs a one-time setup from your computer (see Screen tab). Without it, switch it on by hand: Settings, Accessibility, Installed apps, Andromac.", "Open") {
            ctx.startActivity(Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS))
        })
    }
}

// ---------- Home ----------
private fun pairFromClipboard(ctx: Context, notify: (String) -> Unit) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val t = cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim()
    if (t != null && t.startsWith("andromac://")) { Link.savePairing(t); LinkService.start(ctx); Link.restart(); notify("Pairing…") }
    else notify("Copy the pairing link on your Mac first")
}

private fun scanQr(ctx: Context, notify: (String) -> Unit) {
    val opts = com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions.Builder()
        .setBarcodeFormats(com.google.mlkit.vision.barcode.common.Barcode.FORMAT_QR_CODE).build()
    com.google.mlkit.vision.codescanner.GmsBarcodeScanning.getClient(ctx, opts).startScan()
        .addOnSuccessListener { b ->
            val t = b.rawValue?.trim()
            if (t != null && t.startsWith("andromac://")) { Link.savePairing(t); LinkService.start(ctx); Link.restart(); notify("Pairing…") }
            else notify("That QR code isn't from Andromac")
        }
        .addOnFailureListener { notify("Scanner unavailable. Use Paste pairing link instead.") }
}

@Composable
private fun HomeTab(tick: Int, goTab: (Int) -> Unit, notify: (String) -> Unit) {
    val ctx = LocalContext.current
    val perms = remember(tick, Link.state) { readPerms(ctx) }
    val st = Link.state
    val paired = Link.isPaired
    val mode = Quick.mode(ctx)
    val c = MaterialTheme.colorScheme
    val mac = st.macName?.takeIf { it.isNotBlank() }
    Page("Andromac") {
        // ----- hero: connection status first -----
        val chipColor = when (mode) {
            Quick.Mode.CONNECTED -> c.primary
            Quick.Mode.CONNECTING -> c.tertiary
            else -> c.onSurfaceVariant
        }
        val title = when (mode) {
            Quick.Mode.NOT_PAIRED -> "Pair your Mac"
            Quick.Mode.CONNECTED -> mac ?: "Your Mac"
            else -> mac ?: "Your Mac"
        }
        val sub = when (mode) {
            Quick.Mode.PAUSED -> "Syncing is paused. Turn it on to sync again."
            Quick.Mode.CONNECTED -> "Notifications, codes and clipboard are syncing."
            Quick.Mode.CONNECTING -> st.detail.ifEmpty { "Reaching your Mac over the private network." }
            Quick.Mode.OFFLINE -> "Make sure your Mac is awake and signed in to the same account."
            Quick.Mode.NOT_PAIRED -> "Scan the QR code shown by Andromac on your Mac, or paste the pairing link."
        }
        AppCard(Modifier.staggerIn(0)) {
            Column(Modifier.padding(Sp.x4).animateContentSize(moTween(Mo.Slow)), verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(48.dp).clip(CircleShape).background(c.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                        MacGlyph(if (mode == Quick.Mode.CONNECTED) c.primary else c.onSurfaceVariant, Modifier.size(24.dp))
                    }
                    Spacer(Modifier.width(Sp.x3))
                    Column(Modifier.weight(1f)) {
                        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
                        Body(if (paired) "Phone connection" else "Not connected yet")
                    }
                }
                StatusChip(Quick.stateText(mode), chipColor, pulse = mode == Quick.Mode.CONNECTING,
                    description = "Connection status: ${Quick.stateText(mode)}${if (mac != null && mode == Quick.Mode.CONNECTED) ", $mac" else ""}")
                Text(sub, style = MaterialTheme.typography.bodyMedium, color = c.onSurfaceVariant)
                when (mode) {
                    Quick.Mode.NOT_PAIRED -> {
                        PrimaryButton("Scan QR code") { scanQr(ctx, notify) }
                        TonalButton("Paste pairing link") { pairFromClipboard(ctx, notify) }
                    }
                    Quick.Mode.PAUSED -> PrimaryButton("Turn on") { Quick.setOn(ctx, true) }
                    Quick.Mode.OFFLINE -> PrimaryButton("Try again", icon = Icons.Rounded.Refresh) { Link.restart() }
                    Quick.Mode.CONNECTING -> LinearProgressIndicator(Modifier.fillMaxWidth().clip(CircleShape)
                        .semantics { contentDescription = "Connecting" }, color = c.tertiary, trackColor = c.surfaceContainerHigh)
                    Quick.Mode.CONNECTED -> PrimaryButton("Open Mac screen") { ctx.startActivity(Intent(ctx, ViewerActivity::class.java)) }
                }
                // Always available once paired: fully close the connection, or drop it and connect again.
                if (mode != Quick.Mode.NOT_PAIRED) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        TonalButton("Reconnect", Modifier.weight(1f), icon = Icons.Rounded.Refresh) {
                            Quick.setOn(ctx, true)                       // make sure the background service is on
                            Link.restart(); notify("Reconnecting…")
                        }
                        if (mode != Quick.Mode.PAUSED) TonalButton("Disconnect", Modifier.weight(1f)) {
                            Quick.setOn(ctx, false); notify("Disconnected. Tap Turn on to connect again.")
                        }
                    }
                }
            }
        }

        // ----- network sign-in / error -----
        if (Net.state == "login") {
            AppCard(Modifier.staggerIn(1)) {
                Column(Modifier.padding(Sp.x4), verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Lock, null, tint = c.tertiary)
                        Spacer(Modifier.width(Sp.x3))
                        Text("Sign in once", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                    }
                    Text("Andromac has its own private network built in. Sign in with the same account you use on your Mac.",
                        style = MaterialTheme.typography.bodyMedium, color = c.onSurfaceVariant)
                    PrimaryButton("Sign in") { Net.loginUrl?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } }
                }
            }
        } else if (Net.state == "error") {
            AppCard(Modifier.staggerIn(1)) {
                Row(Modifier.padding(Sp.x4), verticalAlignment = Alignment.Top) {
                    Icon(Icons.Rounded.Warning, null, tint = c.error)
                    Spacer(Modifier.width(Sp.x3))
                    Column(verticalArrangement = Arrangement.spacedBy(Sp.x1)) {
                        Text("Private network problem", style = MaterialTheme.typography.titleSmall)
                        Body("Andromac couldn't start its secure connection. Check your internet, then open Settings, Advanced for details.")
                    }
                }
            }
        }

        // ----- sync: toggles as rows -----
        Section("Sync") {
            Column(Modifier.staggerIn(2)) {
                SwitchRow("Stay connected", if (Settings.keepConnected) "Keeps your Mac connected while the app is closed." else "Nothing syncs until you turn this on.",
                    Settings.keepConnected, { v -> Quick.setOn(ctx, v) }, icon = Icons.Rounded.Refresh)
                SwitchRow("Clipboard", "Copy on one device, paste on the other.", Settings.syncClipboard,
                    { Settings.updateSyncClipboard(it) }, icon = Icons.Rounded.List)
                SwitchRow("Notifications", "Show your phone's notifications on your Mac.", Settings.mirrorNotifications,
                    { Settings.setMirror(it) }, icon = Icons.Rounded.Notifications)
            }
        }

        // ----- setup: progress, collapses to "All set" -----
        val netOk = Net.state == "running"
        val steps = listOf(netOk, paired, perms.allGood)
        val done = steps.count { it }
        val complete = paired && perms.allGood && Net.state != "login" && Net.state != "error"
        val rm = LocalReduced.current
        AnimatedContent(complete, label = "setup", modifier = Modifier.staggerIn(3),
            transitionSpec = { fadeIn(motion(rm, Mo.Slow)) togetherWith fadeOut(motion(rm, Mo.Fast)) using SizeTransform(clip = false) { _, _ -> motion(rm, Mo.Slow) } }) { ok ->
            if (ok) {
                Row(Modifier.fillMaxWidth().padding(horizontal = Sp.x1, vertical = Sp.x2).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.CheckCircle, null, tint = c.primary, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(Sp.x2))
                    Text("All set. Everything is ready.", style = MaterialTheme.typography.bodyMedium, color = c.onSurfaceVariant)
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Sp.x2)) {
                    Heading("Setup")
                    AppCard {
                        Column(Modifier.padding(Sp.x4), verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
                            Text("$done of 3 done", style = MaterialTheme.typography.titleMedium)
                            val prog by animateFloatAsState(done / 3f, moTween(Mo.Slow), label = "prog")
                            LinearProgressIndicator(
                                progress = { prog }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(CircleShape)
                                    .semantics { contentDescription = "Setup progress, $done of 3 done" },
                                color = c.primary, trackColor = c.surfaceContainerHigh, gapSize = 0.dp, drawStopIndicator = {},
                            )
                            StepRow(1, "Private network", netOk,
                                when (Net.state) { "login" -> "Tap Sign in above."; "error" -> "There is a connection problem."; "running" -> "Ready."; else -> "Starting up…" })
                            StepRow(2, "Pair your Mac", paired,
                                if (paired) "Paired." else "Scan the QR code on your Mac, or copy the pairing link there and paste it here.")
                            StepRow(3, "Permissions", perms.allGood, if (perms.allGood) "Granted." else "Andromac needs these to do its job:")
                        }
                        if (!perms.allGood) {
                            val specs = permSpecs(perms, false, false).filter { !it.ok }
                            Column(Modifier.padding(bottom = Sp.x2)) { specs.forEach { PermRow(it) } }
                            if (!perms.listener) Body("If the switch is greyed out: open app info, tap the menu at the top right, then Allow restricted settings.",
                                Modifier.padding(horizontal = Sp.x4, vertical = Sp.x2))
                        }
                    }
                }
            }
        }

        // ----- recent clipboard -----
        val last = ClipHistory.items.firstOrNull()
        Section("Recent") {
            if (last == null) {
                Row(Modifier.fillMaxWidth().padding(Sp.x4), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.List, null, tint = c.onSurfaceVariant)
                    Spacer(Modifier.width(Sp.x3))
                    Body("Nothing copied yet. Copy something on your Mac or phone and it shows up here.", Modifier.weight(1f))
                }
            } else {
                val src = if (last.fromMac) "Mac" else "Phone"
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).clickable(role = Role.Button, onClickLabel = "Open clipboard history") { goTab(1) }
                    .padding(horizontal = Sp.x4, vertical = Sp.x3)
                    .semantics(mergeDescendants = true) { contentDescription = "Last copied, from $src. ${if (last.image != null) "Image" else last.text.take(120)}" },
                    verticalAlignment = Alignment.CenterVertically) {
                    SourceBadge(last.fromMac)
                    Spacer(Modifier.width(Sp.x3))
                    Text(if (last.image != null) "Image" else last.text, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Icon(Icons.Rounded.KeyboardArrowRight, null, tint = c.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun StepRow(n: Int, title: String, ok: Boolean, sub: String) {
    val c = MaterialTheme.colorScheme
    val bg by animateColorAsState(if (ok) c.primary else c.surfaceContainerHigh, moTween(Mo.Normal), label = "step")
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { stateDescription = if (ok) "Done" else "Not done" }, verticalAlignment = Alignment.Top) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
            if (ok) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = c.onPrimary)
            else Text("$n", style = MaterialTheme.typography.labelLarge, color = c.onSurface)
        }
        Spacer(Modifier.width(Sp.x3))
        Column {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Body(sub)
        }
    }
}

@Composable
private fun PermRow(p: PermSpec) {
    val c = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().padding(horizontal = Sp.x4, vertical = Sp.x2), verticalAlignment = Alignment.Top) {
        Icon(if (p.ok) Icons.Rounded.CheckCircle else Icons.Rounded.Warning, null,
            tint = if (p.ok) c.primary else LocalStatusColors.current.warn)
        Column(Modifier.weight(1f).padding(start = Sp.x3), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(p.title, style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.semantics { stateDescription = if (p.ok) "Granted" else "Needs attention" })
            Body(if (p.ok) "Granted" else p.hint)
            if (!p.ok) FilledTonalButton(onClick = p.fix, modifier = Modifier.padding(top = Sp.x2).heightIn(min = 48.dp)
                .semantics { contentDescription = "${p.action}: ${p.title} for Andromac" }, shape = RoundedCornerShape(50)) { Text(p.action) }
        }
    }
}

// ---------- Clipboard ----------
private fun relTime(now: Long, t: Long): String {
    val d = ((now - t) / 1000).coerceAtLeast(0)
    return when {
        d < 10 -> "Just now"
        d < 60 -> "$d sec ago"
        d < 3600 -> "${d / 60} min ago"
        d < 86400 -> "${d / 3600} h ago"
        else -> "${d / 86400} d ago"
    }
}

@Composable
private fun ClipboardTab(notify: (String) -> Unit) {
    val ctx = LocalContext.current
    val c = MaterialTheme.colorScheme
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(15_000) } }
    val items = ClipHistory.items
    val rm = LocalReduced.current
    LazyColumn(
        Modifier.fillMaxSize(), contentPadding = PaddingValues(start = Sp.x4, end = Sp.x4, bottom = Sp.x4),
        verticalArrangement = Arrangement.spacedBy(Sp.x3),
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = Sp.x4, start = Sp.x1), verticalAlignment = Alignment.CenterVertically) {
                Text("Clipboard", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f).semantics { heading() })
                if (items.isNotEmpty()) TextButton(onClick = { ClipHistory.clear(); notify("History cleared") }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Icon(Icons.Rounded.Delete, null, Modifier.size(18.dp)); Spacer(Modifier.width(Sp.x2)); Text("Clear")
                }
            }
        }
        item {
            AppCard(Modifier.staggerIn(0)) {
                SwitchRow("Sync clipboard",
                    if (Settings.syncClipboard) "Copy on one device and paste on the other, in real time."
                    else "Off. Copied items stay on the device where you copied them.",
                    Settings.syncClipboard, { Settings.updateSyncClipboard(it) }, icon = Icons.Rounded.Refresh)
            }
        }
        if (items.isEmpty()) {
            item {
                EmptyState(Icons.Rounded.List, "Nothing copied yet",
                    "Copy text, a link or an image on your Mac or this phone. It will show up here and on the other device.")
            }
        } else {
            item { Heading("Recent. Tap to copy again") }
            itemsIndexed(items.toList(), key = { _, it -> it.key }) { idx, it ->
                val src = if (it.fromMac) "Mac" else "Phone"
                PressCard(
                    onClick = { ClipHistory.recopy(ctx, it); notify("Copied again") },
                    modifier = Modifier.animateItem(fadeInSpec = moTween(Mo.Normal), fadeOutSpec = moTween(Mo.Fast), placementSpec = moTween(Mo.Normal)).staggerIn(idx + 1)
                        .heightIn(min = 64.dp).semantics(mergeDescendants = true) {
                            contentDescription = "From $src, ${relTime(now, it.time)}. ${if (it.image != null) "Image" else it.text.take(200)}. Double tap to copy again."
                        },
                ) {
                    Column(Modifier.padding(Sp.x4), verticalArrangement = Arrangement.spacedBy(Sp.x2)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SourceBadge(it.fromMac)
                            Spacer(Modifier.weight(1f))
                            AnimatedContent(relTime(now, it.time), label = "rel", transitionSpec = {
                                (slideInVertically(motion(rm, Mo.Normal)) { h -> h / 2 } + fadeIn(motion(rm, Mo.Normal))) togetherWith
                                    (slideOutVertically(motion(rm, Mo.Fast)) { h -> -h / 2 } + fadeOut(motion(rm, Mo.Fast)))
                            }) { t -> Text(t, style = MaterialTheme.typography.labelMedium, color = c.onSurfaceVariant) }
                        }
                        if (it.image != null) {
                            val bmp = remember(it.key) { ImageCodec.thumbnail(it.image)?.asImageBitmap() }
                            if (bmp != null) Image(bmp, "Copied image", Modifier.fillMaxWidth().heightIn(max = 220.dp).clip(RoundedCornerShape(Rad.m)),
                                contentScale = androidx.compose.ui.layout.ContentScale.Fit, alignment = Alignment.CenterStart)
                            else Text("Image", style = MaterialTheme.typography.bodyLarge)
                        } else Text(it.text, style = MaterialTheme.typography.bodyLarge, maxLines = 4, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

@Composable
private fun SourceBadge(fromMac: Boolean) {
    val c = MaterialTheme.colorScheme
    Row(
        Modifier.clip(CircleShape).background(c.surfaceContainerHigh).padding(horizontal = Sp.x3, vertical = Sp.x1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val tint = if (fromMac) c.tertiary else c.primary
        if (fromMac) MacGlyph(tint, Modifier.size(16.dp)) else Icon(Icons.Rounded.Phone, null, Modifier.size(16.dp), tint = tint)
        Spacer(Modifier.width(6.dp))
        Text(if (fromMac) "Mac" else "Phone", style = MaterialTheme.typography.labelMedium, color = c.onSurface)
    }
}

// ---------- Screen ----------
@Composable
private fun FeatureCard(icon: ImageVector?, title: String, body: String, action: String, enabled: Boolean = true, onClick: () -> Unit) {
    AppCard {
        Column(Modifier.padding(Sp.x4), verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                if (icon != null) Icon(icon, null, tint = MaterialTheme.colorScheme.primary) else MacGlyph(MaterialTheme.colorScheme.primary)
            }
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            Body(body)
            PrimaryButton(action, enabled = enabled, onClick = onClick)
        }
    }
}

@Composable
private fun ScreenTab(tick: Int) {
    val ctx = LocalContext.current
    val a11yOn = remember(tick) { isA11yOn(ctx) }
    var sharing by remember(tick) { mutableStateOf(ScreenShareState.active) }
    Page("Screen") {
        Column(Modifier.staggerIn(0)) {
            FeatureCard(null, "View and control your Mac",
                "See your Mac's screen on this phone and use it like a touchpad. Touch to click, drag to move, two fingers to scroll, long-press to right-click. Your Mac asks you first.",
                "Open Mac screen", enabled = Link.isPaired) { ctx.startActivity(Intent(ctx, ViewerActivity::class.java)) }
        }
        Column(Modifier.staggerIn(1)) {
            FeatureCard(Icons.Rounded.Share, if (sharing) "Sharing your screen" else "Control this phone from your Mac",
                "Your Mac shows this screen in a window and can tap, swipe and type. You approve every session and can stop at any time.",
                if (sharing) "Stop sharing" else "Start sharing", enabled = Link.isPaired) {
                if (sharing) { ScreenShareState.stop(ctx); sharing = false } else ScreenShareState.start(ctx)
            }
        }
        Section("Let your Mac control this phone") {
            Column(Modifier.padding(Sp.x4), verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
                if (A11yToggle.canToggle(ctx)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.CheckCircle, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(Sp.x3))
                        Text("Automatic and payment-safe", style = MaterialTheme.typography.bodyLarge)
                    }
                    Body("Control is switched on only while you are controlling this phone from the Mac, and switched off again afterwards. The rest of the time no accessibility service is running, so Paytm and banking apps work normally.")
                } else {
                    Body("Payment apps (Paytm, banks, UPI) refuse to work while an accessibility service that can tap for another device is on. To keep both working, Andromac can switch it on only during a session. One-time setup from your computer, with the phone connected over USB debugging:")
                    Text("adb shell pm grant app.andromac android.permission.WRITE_SECURE_SETTINGS",
                        style = MaterialTheme.typography.bodyMedium.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace))
                    Body("Or skip this: switch the service on by hand in Settings, Accessibility, Installed apps, Andromac, only when you want Mac control. It switches itself off again when the session ends, so payment apps keep working the rest of the time.")
                    TonalButton("Open Accessibility") { ctx.startActivity(Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS)) }
                }
            }
        }
        if (!Link.isPaired) Body("Pair your Mac on the Home tab first.", Modifier.padding(horizontal = Sp.x2))
    }
}

// ---------- Settings ----------
@Composable
private fun SettingsTab(tick: Int, openApps: () -> Unit) {
    val ctx = LocalContext.current
    val c = MaterialTheme.colorScheme
    val perms = remember(tick, Link.state) { readPerms(ctx) }
    val a11yOn = remember(tick) { isA11yOn(ctx) }
    val specs = permSpecs(perms, true, a11yOn)
    var advanced by rememberSaveable { mutableStateOf(false) }
    Page("Settings") {
        Section("What to sync") {
            SwitchRow("Phone notifications on Mac", "Send what arrives here to your Mac.", Settings.mirrorNotifications, { Settings.setMirror(it) })
            SwitchRow("Mac notifications on phone", "Show your Mac's alerts here.", Settings.showMacNotifications, { Settings.setMac(it) })
            SwitchRow("SMS and codes", "Forward verification codes to your Mac.", Settings.forwardSms, { Settings.setSms(it) })
            SwitchRow("Skip ongoing notifications", "Charging, music and similar.", Settings.hideOngoing, { Settings.updateHideOngoing(it) })
            SwitchRow("Clipboard", "Real time, both ways.", Settings.syncClipboard, { Settings.updateSyncClipboard(it) })
            NavRow("Choose apps", if (Settings.muted.isEmpty()) "All apps are sent" else "${Settings.muted.size} muted", openApps)
        }
        Section("Permissions") {
            specs.forEach { PermRow(it) }
            if (!perms.listener || !a11yOn) Body(
                "If a switch is greyed out: open Andromac's app info, tap the menu at the top right and choose Allow restricted settings, then try again.",
                Modifier.padding(horizontal = Sp.x4, vertical = Sp.x2))
            TextButton(onClick = { appInfo(ctx) }, modifier = Modifier.padding(horizontal = Sp.x2).heightIn(min = 48.dp)) { Text("Open Andromac app info") }
        }
        Section("Private network") {
            val signedIn = Net.state == "running"
            Column(Modifier.padding(horizontal = Sp.x4, vertical = Sp.x3), verticalArrangement = Arrangement.spacedBy(Sp.x1)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (signedIn) Icons.Rounded.CheckCircle else Icons.Rounded.Refresh, null,
                        tint = if (signedIn) c.primary else c.onSurfaceVariant)
                    Spacer(Modifier.width(Sp.x3))
                    Text(if (signedIn) "Signed in" else if (Net.state == "login") "Waiting for sign-in" else if (Net.state == "error") "Problem" else "Starting…",
                        style = MaterialTheme.typography.titleMedium)
                }
                if (Net.account.isNotEmpty()) Body(Net.account)
                Body("Built into Andromac. No separate app needed.")
            }
            if (signedIn) TextButton(onClick = { Net.signOut() }, modifier = Modifier.padding(horizontal = Sp.x2).heightIn(min = 48.dp)) { Text("Sign out or switch account") }
            else if (Net.state == "login") PrimaryButton("Sign in", Modifier.padding(horizontal = Sp.x4, vertical = Sp.x2)) {
                Net.loginUrl?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) }
            }
        }
        Section("Files on your Mac") {
            val hasAll = remember(tick, Settings.fileShare) { FileServer.hasAllFilesAccess() }
            SwitchRow("Share this phone's files with your Mac", "Your Mac sees internal storage and the SD card as a drive named Phone in Finder.",
                Settings.fileShare, { Settings.updateFileShare(it); Link.applyFiles(ctx) })
            if (Settings.fileShare) {
                SwitchRow("Allow changes", "Off: your Mac can only read. On: it can also add, rename and delete files here.",
                    Settings.fileWrite, { Settings.updateFileWrite(it); Link.applyFiles(ctx) })
                if (!hasAll) {
                    Body("Android needs the \"All files access\" switch for Andromac before it can share files.", Modifier.padding(horizontal = Sp.x4))
                    PrimaryButton("Allow all files access", Modifier.padding(horizontal = Sp.x4, vertical = Sp.x2)) {
                        ctx.startActivity(Intent(AndroidSettings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${ctx.packageName}")))
                    }
                }
            }
        }
        // Advanced: terminal access and network details
        Column(verticalArrangement = Arrangement.spacedBy(Sp.x2)) {
            Heading("Advanced")
            AppCard {
                val rot by animateFloatAsState(if (advanced) 90f else 0f, moTween(Mo.Normal), label = "adv")
                Row(Modifier.fillMaxWidth().heightIn(min = 56.dp)
                    .semantics { stateDescription = if (advanced) "Expanded" else "Collapsed" }
                    .clickable(role = Role.Button) { advanced = !advanced }.padding(horizontal = Sp.x4, vertical = Sp.x3),
                    verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Terminal and network details", style = MaterialTheme.typography.bodyLarge)
                        Body("For Termux and SSH users")
                    }
                    Icon(Icons.Rounded.KeyboardArrowRight, null, Modifier.graphicsLayer { rotationZ = rot }, tint = c.onSurfaceVariant)
                }
                AnimatedVisibility(advanced, enter = expandVertically(moTween(Mo.Slow)) + fadeIn(moTween(Mo.Normal)),
                    exit = shrinkVertically(moTween(Mo.Normal)) + fadeOut(moTween(Mo.Fast))) {
                    Column {
                        SwitchRow("Terminal access", "Reach your Mac from Termux over SSH, even when other VPN apps are off. Sessions survive Wi-Fi and mobile-data changes.",
                            Settings.terminalBridge, { Settings.updateTerminalBridge(it) })
                        if (Settings.terminalBridge) {
                            Body("In Termux, add this to ~/.ssh/config, then run  ssh m5  (long-press the text to copy):", Modifier.padding(horizontal = Sp.x4, vertical = Sp.x1))
                            androidx.compose.foundation.text.selection.SelectionContainer {
                                Text("Host m5\n  HostName 127.0.0.1\n  Port 2222\n  User ${Link.macUser.ifEmpty { "<your Mac username>" }}\n  ServerAliveInterval 15\n  ServerAliveCountMax 4",
                                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.fillMaxWidth().padding(horizontal = Sp.x4, vertical = Sp.x2))
                            }
                            Body("Needs Remote Login turned on in your Mac's Sharing settings.", Modifier.padding(horizontal = Sp.x4, vertical = Sp.x1))
                        }
                        if (Net.deviceName.isNotEmpty() || Net.ip != null) Body("Network address: ${Net.deviceName}  ${Net.ip ?: ""}".trim(), Modifier.padding(Sp.x4))
                        if (Net.state == "error") Body("Network error: ${Net.detail}", Modifier.padding(horizontal = Sp.x4, vertical = Sp.x2))
                    }
                }
            }
        }
        if (Link.isPaired) TextButton(onClick = { Link.unpair() }, modifier = Modifier.align(Alignment.CenterHorizontally).heightIn(min = 48.dp)) {
            Text("Unpair this Mac", color = c.error)
        }
        Text("Andromac 0.3", style = MaterialTheme.typography.labelMedium, color = c.onSurfaceVariant,
            modifier = Modifier.align(Alignment.CenterHorizontally))
    }
}

// ---------- apps ----------
private data class AppItem(val pkg: String, val label: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppsScreen(back: () -> Unit) {
    val ctx = LocalContext.current
    var apps by remember { mutableStateOf<List<AppItem>?>(null) }
    var query by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        apps = withContext(Dispatchers.Default) {
            val pm = ctx.packageManager
            val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            pm.queryIntentActivities(i, 0).map { AppItem(it.activityInfo.packageName, it.loadLabel(pm).toString()) }
                .distinctBy { it.pkg }.filter { it.pkg != ctx.packageName }.sortedBy { it.label.lowercase() }
        }
    }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Choose apps", modifier = Modifier.semantics { heading() }) },
                navigationIcon = { IconButton(onClick = back, modifier = Modifier.size(48.dp)) { Icon(Icons.Rounded.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad)) {
            Body("Choose which of this phone's apps send notifications to your Mac. Turned-off apps stay on the phone only.", Modifier.padding(horizontal = Sp.x4))
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                label = { Text("Search apps") }, shape = RoundedCornerShape(Rad.s),
                leadingIcon = { Icon(Icons.Rounded.Search, null) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = Sp.x4, vertical = Sp.x2),
            )
            val list = apps
            if (list == null) {
                // skeleton rows instead of a spinner
                Column(Modifier.fillMaxSize().padding(horizontal = Sp.x4).semantics { contentDescription = "Loading apps" }, verticalArrangement = Arrangement.spacedBy(Sp.x3)) {
                    repeat(8) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp), verticalAlignment = Alignment.CenterVertically) {
                            Skeleton(Modifier.size(40.dp), CircleShape)
                            Spacer(Modifier.width(Sp.x3))
                            Skeleton(Modifier.height(16.dp).fillMaxWidth(0.5f))
                        }
                    }
                }
            } else {
                val shown = remember(list, query) { list.filter { it.label.contains(query, ignoreCase = true) } }
                if (shown.isEmpty()) EmptyState(Icons.Rounded.Search, "No apps found", "Try a different name.")
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = Sp.x6)) {
                    itemsIndexed(shown, key = { _, a -> a.pkg }) { idx, a ->
                        val on = a.pkg !in Settings.muted
                        val src = remember { MutableInteractionSource() }
                        val pressed by src.collectIsPressedAsState()
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 56.dp).animateItem().staggerIn(idx)
                                .semantics { stateDescription = if (on) "On" else "Off" }
                                .toggleable(on, role = Role.Switch, interactionSource = src, indication = ripple(), onValueChange = { Settings.setMuted(a.pkg, !it) })
                                .padding(horizontal = Sp.x4, vertical = Sp.x2),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            AppIcon(a.pkg)
                            Text(a.label, Modifier.weight(1f).padding(horizontal = Sp.x4), style = MaterialTheme.typography.bodyLarge)
                            AppSwitch(on, pressed)
                        }
                    }
                }
            }
        }
    }
}

private val iconCache = android.util.LruCache<String, Bitmap>(120)

@Composable
private fun AppIcon(pkg: String) {
    val ctx = LocalContext.current
    var bmp by remember(pkg) { mutableStateOf(iconCache.get(pkg)) }
    LaunchedEffect(pkg) {
        if (bmp == null) bmp = withContext(Dispatchers.Default) {
            runCatching { ctx.packageManager.getApplicationIcon(pkg).toBitmap(96, 96) }.getOrNull()?.also { iconCache.put(pkg, it) }
        }
    }
    val b = bmp
    if (b != null) Image(b.asImageBitmap(), null, Modifier.size(40.dp))
    else Skeleton(Modifier.size(40.dp), CircleShape)
}
