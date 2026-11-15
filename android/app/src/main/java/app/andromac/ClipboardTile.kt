package app.andromac

import android.content.Intent
import android.service.quicksettings.TileService

/** Tap the tile: opens a transparent activity that reads the clipboard and sends it. */
class ClipboardTile : TileService() {
    override fun onClick() {
        val i = Intent(this, ClipboardPushActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivityAndCollapse(i)
    }
}
