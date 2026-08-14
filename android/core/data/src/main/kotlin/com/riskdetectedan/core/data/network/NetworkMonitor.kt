package com.riskdetectedan.core.data.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors NetworkMonitor.swift — `isOnline` only. `isExpensive`/`isConstrained` (metered-
 * connection flags) exist on the Swift side but nothing actually reads them beyond publishing
 * them (checked: only `isOnline` drives real UI, the offline banner in RootView.swift) — not
 * ported here for the same reason, no consumer to justify them yet.
 *
 * Uses `registerDefaultNetworkCallback` (tracks whichever network the system considers "the"
 * active one) rather than `registerNetworkCallback` with a broad request — same "the network the
 * OS picked" semantics as iOS's `NWPathMonitor`, not "any network exists somewhere."
 */
@Singleton
class NetworkMonitor @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val _isOnline = MutableStateFlow(true)
    val isOnline: StateFlow<Boolean> = _isOnline

    init {
        val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                _isOnline.value = true
            }

            override fun onLost(network: Network) {
                _isOnline.value = false
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                // NET_CAPABILITY_VALIDATED (passed Android's captive-portal reachability check)
                // was tried first and reverted after live device testing showed it sticks
                // "offline" even once wifi is genuinely back — this emulator's networks report
                // INTERNET without ever flipping VALIDATED. iOS's NWPathMonitor `.satisfied`
                // means "usable network," not "passed a captive-portal probe" either — INTERNET
                // alone matches that semantic more accurately, not a workaround for one device.
                _isOnline.value = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }
        }
        connectivityManager?.registerDefaultNetworkCallback(callback)
        // No unregister: this is a process-lifetime Singleton, same as every other
        // Hilt-@Singleton repository in this module — there is no owning component whose
        // lifecycle would make unregistering meaningful before process death.
    }
}
