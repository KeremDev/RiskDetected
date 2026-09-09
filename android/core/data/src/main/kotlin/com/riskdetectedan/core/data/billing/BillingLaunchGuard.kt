package com.riskdetectedan.core.data.billing

import java.util.concurrent.atomic.AtomicBoolean

internal fun canLaunchBilling(finishing: Boolean, destroyed: Boolean, foreground: Boolean) =
    !finishing && !destroyed && foreground

/** Reject, rather than queue, a second checkout from another paywall instance. */
internal class BillingLaunchGuard {
    private val owned = AtomicBoolean(false)
    fun acquire(): Boolean = owned.compareAndSet(false, true)
    fun release() { owned.set(false) }
}
