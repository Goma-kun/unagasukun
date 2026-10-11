package jp.nishira.unagasukun

import android.app.Application
import android.content.res.Configuration
import jp.nishira.unagasukun.core.L10n
import jp.nishira.unagasukun.notify.Notifier
import java.util.Locale

class UnagasukunApp : Application() {
    override fun onCreate() {
        super.onCreate()
        applyLocale()
        Notifier.ensureChannel(this)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyLocale()
    }

    /** core が組み立てる文（Describe・お祝い・既定ラベル）を端末の言語に合わせる */
    private fun applyLocale() {
        val locale: Locale = resources.configuration.locales[0] ?: Locale.getDefault()
        L10n.strings = L10n.forLocale(locale)
    }
}
