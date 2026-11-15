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
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
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
    val reduced = rememberReducedMotion()
    val snack = remember { SnackbarHostState() }
    var toast by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(toast) { toast?.let { snack.showSnackbar(it); toast = null } }
    BackHandler(screen != "main") { screen = "main" }
    BackHandler(screen == "main" && tab != 0) { tab = 0 }
    if (screen == "apps") { AppsScreen { screen = "main" }; return }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = WindowInsets.statusBars,
        snackbarHost = { SnackbarHost(snack) },
        bottomBar = {
            val d = androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, minOf(d.fontScale, 1.2f))) {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                Tab.entries.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i, onClick = { tab = i },
                        icon = { Icon(t.icon, contentDescription = null) },
                        label = { Text(t.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        alwaysShowLabel = true,
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
                    val d = if (reduced) 0 else 220
                    fadeIn(tween(d)) togetherWith fadeOut(tween(d))
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
        overlay = AndroidSettings.canDrawOverlays(ctx),
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
        add(PermSpec(perms.overlay, "Display over other apps",
            "Switch on Andromac in this list so what you copy on the phone reaches your Mac instantly, even when Andromac is in the background.", "Allow") {
            ctx.startActivity(Intent(AndroidSettings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")))
        })
        if (includeA11y) add(PermSpec(a11yOn, "Accessibility",
            "Settings, Accessibility, Installed apps, Andromac: switch it on so your Mac can tap and type on this phone.", "Open") {
            ctx.startActivity(Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS))
        })
    }
}

// ---------- building blocks ----------
@Composable
private fun Page(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(top = 16.dp, start = 4.dp).semantics { heading() })
        content()
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun Heading(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 8.dp, bottom = 8.dp).semantics { heading() })
}

@Composable
private fun AppCard(modifier: Modifier = Modifier, container: Color = MaterialTheme.colorScheme.surfaceContainer, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier.fillMaxWidth(), shape = MaterialTheme.shapes.large, color = container,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), tonalElevation = 1.dp,
    ) { Column(Modifier.fillMaxWidth(), content = content) }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Heading(title)
        AppCard(content = { Column(Modifier.padding(vertical = 4.dp), content = content) })
    }
}

@Composable
private fun Body(text: String, modifier: Modifier = Modifier) =
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)

@Composable
private fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null, onClick: () -> Unit) {
    Button(onClick, modifier.fillMaxWidth().heightIn(min = 52.dp), enabled = enabled, shape = RoundedCornerShape(16.dp)) {
        if (icon != null) { Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

@Composable
private fun TonalButton(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit) {
    FilledTonalButton(onClick, modifier.fillMaxWidth().heightIn(min = 48.dp), shape = RoundedCornerShape(16.dp)) {
        if (icon != null) { Icon(icon, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp)) }
        Text(text, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

@Composable
private fun SwitchRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit, icon: ImageVector? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .semantics { stateDescription = if (checked) "On" else "Off" }
            .toggleable(checked, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(icon, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(14.dp)) }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (subtitle != null) Body(subtitle)
        }
        Spacer(Modifier.width(12.dp))
        Switch(checked, null, thumbContent = if (checked) {
            { Icon(Icons.Rounded.Check, null, Modifier.size(SwitchDefaults.IconSize)) }
        } else null)
    }
}

@Composable
private fun NavRow(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Body(value)
        }
        Icon(Icons.Rounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun StatusPill(icon: ImageVector, text: String, color: Color, onDark: Boolean = false) {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = if (onDark) 0.16f else 0.14f))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(16.dp), tint = color)
        Spacer(Modifier.width(6.dp))
        Text(text, style = MaterialTheme.typography.labelLarge, color = color)
    }
}

@Composable
private fun MacGlyph(tint: Color, modifier: Modifier = Modifier.size(24.dp)) {
    Canvas(modifier) {
        val w = size.width; val h = size.height; val sw = w * 0.09f
        drawRoundRect(tint, Offset(w * 0.14f, h * 0.18f), Size(w * 0.72f, h * 0.5f), CornerRadius(w * 0.07f),
            style = androidx.compose.ui.graphics.drawscope.Stroke(sw))
        drawRoundRect(tint, Offset(w * 0.04f, h * 0.76f), Size(w * 0.92f, h * 0.09f), CornerRadius(w * 0.05f))
    }
}

// ---------- Home ----------
private val HeroBrush = Brush.verticalGradient(listOf(Color(0xFF0D0D0D), Color(0xFF0D0D0D)))   // flat: no gradient
private val HeroText = Color(0xFFF5F5F5)
private val HeroSub = Color(0xFFA1A1A1)

@Composable
private fun HomeTab(tick: Int, goTab: (Int) -> Unit, notify: (String) -> Unit) {
    val ctx = LocalContext.current
    val perms = remember(tick, Link.state) { readPerms(ctx) }
    val st = Link.state
    val paired = Link.isPaired
    val sc = LocalStatusColors.current
    Page("Andromac") {
        // ----- hero -----
        val paused = paired && !Settings.keepConnected && st.phase != Link.Phase.CONNECTED
        val heroGreen = Brand.Green; val heroAmber = Color(0xFFFFC857); val heroRed = Color(0xFFFF9B93)
        val (icon, pill, pillColor) = when {
            paused -> Triple(Icons.Rounded.Close, "Paused", heroAmber)
            st.phase == Link.Phase.CONNECTED -> Triple(Icons.Rounded.CheckCircle, "Connected", heroGreen)
            st.phase == Link.Phase.CONNECTING -> Triple(Icons.Rounded.Refresh, "Connecting", heroAmber)
            st.phase == Link.Phase.OFFLINE -> Triple(Icons.Rounded.Warning, "Offline", heroRed)
            else -> Triple(Icons.Rounded.Info, "Not paired", heroAmber)
        }
        val title = when {
            paused -> "Paused"
            st.phase == Link.Phase.CONNECTED -> "Connected to ${st.macName ?: "your Mac"}"
            st.phase == Link.Phase.CONNECTING -> "Connecting…"
            st.phase == Link.Phase.OFFLINE -> "Mac not reachable"
            else -> "Pair your Mac"
        }
        val sub = when {
            paused -> "Background connection is off. Turn it on below to sync again."
            st.phase == Link.Phase.CONNECTED -> "Notifications, codes and clipboard are syncing."
            st.phase == Link.Phase.CONNECTING -> st.detail.ifEmpty { "Reaching your Mac over the private network." }
            st.phase == Link.Phase.OFFLINE -> "Check that your Mac is awake and signed in to the same account. ${st.detail}".trim()
            else -> "Scan the QR code shown by Andromac on your Mac, or paste the pairing link."
        }
        Surface(Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.extraLarge, color = Color.Transparent,
            border = BorderStroke(1.dp, Color(0xFF2A2A2A))) {
            Column(Modifier.background(HeroBrush).padding(20.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.semantics { contentDescription = "Andromac logo" }) {
                    OrbitLogo(112.dp, pulse = st.phase == Link.Phase.CONNECTED && !paused)
                }
                StatusPill(icon, pill, pillColor, onDark = true)
                Text(title, style = MaterialTheme.typography.headlineSmall, color = HeroText,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    modifier = Modifier.semantics { heading() })
                Text(sub, style = MaterialTheme.typography.bodyMedium, color = HeroSub,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                if (!paired) {
                    Spacer(Modifier.height(4.dp))
                    PrimaryButton("Scan QR from your Mac") {
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
                    TonalButton("Paste pairing link") {
                        val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val t = cm.primaryClip?.getItemAt(0)?.coerceToText(ctx)?.toString()?.trim()
                        if (t != null && t.startsWith("andromac://")) {
                            Link.savePairing(t); LinkService.start(ctx); Link.restart(); notify("Pairing…")
                        } else notify("Copy the pairing link on your Mac first")
                    }
                } else if (st.phase == Link.Phase.OFFLINE && !paused) {
                    Spacer(Modifier.height(4.dp))
                    PrimaryButton("Try again", icon = Icons.Rounded.Refresh) { Link.restart() }
                }
            }
        }

        // ----- network sign-in / error -----
        if (Net.state == "login") {
            AppCard(container = MaterialTheme.colorScheme.primaryContainer) {
                Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Lock, null, tint = MaterialTheme.colorScheme.onPrimaryContainer)
                        Spacer(Modifier.width(10.dp))
                        Text("Sign in once", style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onPrimaryContainer,
                            modifier = Modifier.semantics { heading() })
                    }
                    Text("Andromac has its own private network built in. Sign in with the same account you use on your Mac.",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                    PrimaryButton("Sign in") { Net.loginUrl?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } }
                }
            }
        } else if (Net.state == "error") {
            Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Rounded.Warning, null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(10.dp))
                Text("Secure connection problem: ${Net.detail}", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
        }

        // ----- master switch -----
        AppCard {
            val on = Settings.keepConnected
            SwitchRow(
                "Stay connected in the background",
                if (on) "On. Andromac keeps your Mac connected while the app is closed, so notifications, codes and clipboard sync all the time."
                else "Off. Nothing syncs until you turn this on.",
                on, { v ->
                    if (v) { Link.init(ctx); Settings.updateKeepConnected(true); LinkService.start(ctx) }
                    else { Settings.updateKeepConnected(false); Link.stop(); ctx.stopService(Intent(ctx, LinkService::class.java)) }
                },
                icon = Icons.Rounded.Refresh,
            )
        }

        // ----- setup checklist -----
        val netOk = Net.state == "running"
        val a = if (netOk) 1 else 0
        val b = if (paired) 1 else 0
        val c = if (perms.allGood) 1 else 0
        val done = a + b + c
        if (done < 3) {
            Column {
                Heading("Finish setup")
                AppCard {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("$done of 3 steps done", style = MaterialTheme.typography.titleMedium)
                        LinearProgressIndicator(
                            progress = { done / 3f }, modifier = Modifier.fillMaxWidth().height(8.dp).clip(CircleShape)
                                .semantics { contentDescription = "Setup progress, $done of 3 steps done" },
                            color = MaterialTheme.colorScheme.primary, trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                        )
                        StepRow(1, "Sign in to the private network", netOk,
                            when (Net.state) { "login" -> "Tap Sign in above."; "error" -> "There is a connection problem."; "running" -> "Done."; else -> "Starting up…" })
                        StepRow(2, "Pair your Mac", paired,
                            if (paired) "Done." else "Open Andromac on your Mac and tap Scan QR. Or copy the link on the Mac and tap Paste pairing link.")
                        StepRow(3, "Allow permissions for Andromac", perms.allGood,
                            if (perms.allGood) "Done." else "Andromac needs these to do its job:")
                    }
                    if (!perms.allGood) {
                        val specs = permSpecs(perms, false, false).filter { !it.ok }
                        Column(Modifier.padding(bottom = 8.dp)) { specs.forEach { PermRow(it) } }
                        if (!perms.listener) Text("If the switch is greyed out: Andromac app info, then the menu at the top right, then Allow restricted settings.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                    }
                }
            }
        }

        // ----- quick cards -----
        Column {
            Heading("Quick actions")
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                QuickCard(Icons.Rounded.List, "Clipboard",
                    if (Settings.syncClipboard) "Syncing both ways in real time. See what was copied." else "Sync is off. Tap to review history and turn it on.") { goTab(1) }
                QuickCard(null, "View and control your Mac",
                    if (paired) "See your Mac's screen on this phone." else "Pair your Mac first.", enabled = paired) {
                    ctx.startActivity(Intent(ctx, ViewerActivity::class.java))
                }
            }
        }
    }
}

@Composable
private fun StepRow(n: Int, title: String, ok: Boolean, sub: String) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
        stateDescription = if (ok) "Done" else "Not done"
    }, verticalAlignment = Alignment.Top) {
        Box(
            Modifier.size(28.dp).clip(CircleShape)
                .background(if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest),
            contentAlignment = Alignment.Center,
        ) {
            if (ok) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onPrimary)
            else Text("$n", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurface)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text("Step $n: $title", style = MaterialTheme.typography.titleSmall)
            Body(sub)
        }
    }
}

@Composable
private fun QuickCard(icon: ImageVector?, title: String, sub: String, enabled: Boolean = true, onClick: () -> Unit) {
    Surface(
        onClick = onClick, enabled = enabled, shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainer, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
        modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp),
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            val tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                if (icon != null) Icon(icon, null, tint = tint) else MacGlyph(tint)
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Body(sub)
            }
            Icon(Icons.Rounded.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PermRow(p: PermSpec) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.Top) {
        Icon(if (p.ok) Icons.Rounded.CheckCircle else Icons.Rounded.Warning, null,
            tint = if (p.ok) LocalStatusColors.current.ok else LocalStatusColors.current.warn)
        Column(Modifier.weight(1f).padding(start = 14.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(p.title, style = MaterialTheme.typography.titleSmall)
            Body(if (p.ok) "Allowed for Andromac" else p.hint)
            if (!p.ok) FilledTonalButton(onClick = p.fix, modifier = Modifier.padding(top = 6.dp).heightIn(min = 48.dp).semantics { contentDescription = "${p.action}: ${p.title} for Andromac" },
                shape = RoundedCornerShape(14.dp)) { Text(p.action) }
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
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(15_000) } }
    val items = ClipHistory.items
    LazyColumn(
        Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(top = 16.dp, start = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Clipboard", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f).semantics { heading() })
                if (items.isNotEmpty()) TextButton(onClick = { ClipHistory.clear(); notify("History cleared") }, modifier = Modifier.heightIn(min = 48.dp)) {
                    Icon(Icons.Rounded.Delete, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Clear")
                }
            }
        }
        item {
            AppCard {
                SwitchRow("Sync clipboard",
                    if (Settings.syncClipboard) "Copy on your phone or Mac and it appears on the other one automatically, in real time."
                    else "Off. Copied text stays on the device where you copied it.",
                    Settings.syncClipboard, { Settings.updateSyncClipboard(it) }, icon = Icons.Rounded.Refresh)
            }
        }
        item {
            Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.Top) {
                Icon(Icons.Rounded.Info, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.width(8.dp))
                Body("Everything you copy on either device is saved here and swapped with your Mac each time you connect, even items copied while you were offline. Items from your Mac also appear in this phone's own clipboard history (Gboard or Samsung keyboard). Saved only on this phone; Clear removes it.")
            }
        }
        if (items.isEmpty()) {
            item {
                Column(Modifier.fillMaxWidth().padding(vertical = 40.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.size(72.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHigh), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.List, null, Modifier.size(34.dp), tint = MaterialTheme.colorScheme.primary)
                    }
                    Text("Nothing copied yet", style = MaterialTheme.typography.titleLarge,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    Text("Copy some text on your Mac or this phone. It will show up here and on the other device.",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }
        } else {
            item { Heading("Recent, tap to copy again") }
            items(items.toList(), key = { it.text }) { it ->
                val src = if (it.fromMac) "Mac" else "Phone"
                Surface(
                    onClick = { ClipHistory.recopy(ctx, it); notify("Copied again") },
                    shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp).semantics(mergeDescendants = true) {
                        contentDescription = "From $src, ${relTime(now, it.time)}. ${it.text.take(200)}. Double tap to copy again."
                    },
                ) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SourceBadge(it.fromMac)
                            Spacer(Modifier.weight(1f))
                            Text(relTime(now, it.time), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(it.text, style = MaterialTheme.typography.bodyLarge, maxLines = 4, overflow = TextOverflow.Ellipsis)
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
        Modifier.clip(RoundedCornerShape(50)).background(if (fromMac) c.secondaryContainer else c.primaryContainer).padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val tint = if (fromMac) c.onSecondaryContainer else c.onPrimaryContainer
        if (fromMac) MacGlyph(tint, Modifier.size(16.dp)) else Icon(Icons.Rounded.Phone, null, Modifier.size(16.dp), tint = tint)
        Spacer(Modifier.width(6.dp))
        Text(if (fromMac) "Mac" else "Phone", style = MaterialTheme.typography.labelMedium, color = tint)
    }
}

// ---------- Screen ----------
@Composable
private fun FeatureCard(icon: ImageVector?, title: String, body: String, action: String, enabled: Boolean = true, onClick: () -> Unit) {
    AppCard {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(48.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.primaryContainer), contentAlignment = Alignment.Center) {
                if (icon != null) Icon(icon, null, tint = MaterialTheme.colorScheme.onPrimaryContainer) else MacGlyph(MaterialTheme.colorScheme.onPrimaryContainer)
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
        FeatureCard(null, "View and control your Mac",
            "See your Mac's screen on this phone and use it like a touchpad. Touch to click, drag to move, two fingers to scroll, long-press to right-click. Your Mac asks you first.",
            "Open Mac screen", enabled = Link.isPaired) { ctx.startActivity(Intent(ctx, ViewerActivity::class.java)) }
        FeatureCard(Icons.Rounded.Share, if (sharing) "Sharing your screen" else "Control this phone from your Mac",
            "Your Mac shows this screen in a window and can tap, swipe and type. You approve every session and can stop at any time.",
            if (sharing) "Stop sharing" else "Start sharing", enabled = Link.isPaired) {
            if (sharing) { ScreenShareState.stop(ctx); sharing = false } else ScreenShareState.start(ctx)
        }
        Section("Let your Mac control this phone") {
            if (a11yOn) Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.CheckCircle, null, tint = LocalStatusColors.current.ok); Spacer(Modifier.width(12.dp))
                Text("Accessibility is on for Andromac", style = MaterialTheme.typography.bodyLarge)
            } else Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Body("Without this your Mac can see the screen but cannot tap or type. Android needs two quick steps:")
                Text("Step 1 (if needed)", style = MaterialTheme.typography.titleSmall)
                Body("Open Andromac's app info, tap the menu at the top right and choose Allow restricted settings. If you don't see it, go to step 2.")
                TonalButton("Open Andromac app info") { appInfo(ctx) }
                Text("Step 2", style = MaterialTheme.typography.titleSmall)
                Body("Open Accessibility, pick Andromac under Installed apps, and switch it on.")
                PrimaryButton("Open Accessibility") { ctx.startActivity(Intent(AndroidSettings.ACTION_ACCESSIBILITY_SETTINGS)) }
            }
        }
        if (!Link.isPaired) Body("Pair your Mac on the Home tab first.", Modifier.padding(horizontal = 8.dp))
    }
}

// ---------- Settings ----------
@Composable
private fun SettingsTab(tick: Int, openApps: () -> Unit) {
    val ctx = LocalContext.current
    val perms = remember(tick, Link.state) { readPerms(ctx) }
    val a11yOn = remember(tick) { isA11yOn(ctx) }
    val specs = permSpecs(perms, true, a11yOn)
    Page("Settings") {
        Section("Permissions for Andromac") {
            specs.forEach { PermRow(it) }
            if (!perms.listener || !a11yOn) Body(
                "If a switch is greyed out: open Andromac's app info, tap the menu at the top right and choose Allow restricted settings, then try again.",
                Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
            TextButton(onClick = { appInfo(ctx) }, modifier = Modifier.padding(horizontal = 8.dp).heightIn(min = 48.dp)) { Text("Open Andromac app info") }
        }
        Section("What to sync") {
            SwitchRow("Phone notifications on Mac", null, Settings.mirrorNotifications, { Settings.setMirror(it) })
            SwitchRow("Mac notifications on phone", null, Settings.showMacNotifications, { Settings.setMac(it) })
            SwitchRow("SMS and OTP codes", null, Settings.forwardSms, { Settings.setSms(it) })
            SwitchRow("Skip ongoing notifications", "Charging, music and similar", Settings.hideOngoing, { Settings.updateHideOngoing(it) })
            SwitchRow("Clipboard", "Real time, both ways", Settings.syncClipboard, { Settings.updateSyncClipboard(it) })
            NavRow("Choose apps", "${Settings.muted.size} muted", openApps)
        }
        Section("Terminal access (Termux, SSH)") {
            SwitchRow("SSH bridge to your Mac", "Reach your Mac from Termux even when the Tailscale app is off. Sessions survive Wi-Fi and mobile-data changes.",
                Settings.terminalBridge, { Settings.updateTerminalBridge(it) })
            if (Settings.terminalBridge) {
                Body("In Termux, add this to ~/.ssh/config, then run  ssh m5  (long-press the text to copy):", Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
                androidx.compose.foundation.text.selection.SelectionContainer {
                    Text("Host m5\n  HostName 127.0.0.1\n  Port 2222\n  User ${Link.macUser.ifEmpty { "<your Mac username>" }}\n  ServerAliveInterval 15\n  ServerAliveCountMax 4",
                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp))
                }
                Body("Needs Remote Login turned on in your Mac's Sharing settings.", Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            }
        }
        Section("Private network") {
            val signedIn = Net.state == "running"
            Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (signedIn) Icons.Rounded.CheckCircle else Icons.Rounded.Refresh, null,
                        tint = if (signedIn) LocalStatusColors.current.ok else LocalStatusColors.current.warn)
                    Spacer(Modifier.width(10.dp))
                    Text(if (signedIn) "Signed in" else if (Net.state == "login") "Waiting for sign-in" else if (Net.state == "error") "Problem" else "Starting…",
                        style = MaterialTheme.typography.titleMedium)
                }
                if (Net.account.isNotEmpty()) Body(Net.account)
                if (Net.deviceName.isNotEmpty() || Net.ip != null) Body("${Net.deviceName}  ${Net.ip ?: ""}".trim())
                Body("Built into Andromac, no separate Tailscale app needed.")
            }
            if (signedIn) TextButton(onClick = { Net.signOut() }, modifier = Modifier.padding(horizontal = 8.dp).heightIn(min = 48.dp)) { Text("Sign out or switch account") }
            else if (Net.state == "login") PrimaryButton("Sign in", Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Net.loginUrl?.let { ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) }
            }
        }
        if (Link.isPaired) TextButton(onClick = { Link.unpair() }, modifier = Modifier.align(Alignment.CenterHorizontally).heightIn(min = 48.dp)) {
            Text("Unpair this Mac", color = MaterialTheme.colorScheme.error)
        }
        Text("Andromac 0.3", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                navigationIcon = { IconButton(onClick = back) { Icon(Icons.Rounded.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad)) {
            Body("Choose which apps' notifications are sent to your Mac.", Modifier.padding(horizontal = 20.dp))
            OutlinedTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                label = { Text("Search apps") }, shape = RoundedCornerShape(16.dp),
                leadingIcon = { Icon(Icons.Rounded.Search, null) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )
            val list = apps
            if (list == null) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            } else {
                val shown = remember(list, query) { list.filter { it.label.contains(query, ignoreCase = true) } }
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                    items(shown, key = { it.pkg }) { a ->
                        val on = a.pkg !in Settings.muted
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 56.dp)
                                .semantics { stateDescription = if (on) "On" else "Off" }
                                .toggleable(on, role = Role.Switch, onValueChange = { Settings.setMuted(a.pkg, !it) })
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            AppIcon(a.pkg)
                            Text(a.label, Modifier.weight(1f).padding(horizontal = 14.dp), style = MaterialTheme.typography.bodyLarge)
                            Switch(on, null, thumbContent = if (on) {
                                { Icon(Icons.Rounded.Check, null, Modifier.size(SwitchDefaults.IconSize)) }
                            } else null)
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
    else Box(Modifier.size(40.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest))
}
