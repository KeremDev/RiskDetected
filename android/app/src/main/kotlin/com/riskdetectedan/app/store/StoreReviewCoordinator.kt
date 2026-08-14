package com.riskdetectedan.app.store

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.google.android.play.core.review.ReviewManagerFactory
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.data.store.ReviewEligibilityRepository
import kotlinx.coroutines.tasks.await

@Composable
fun StoreReviewCoordinator(
    repository: ReviewEligibilityRepository,
    environmentConfig: RdEnvironmentConfig,
) {
    val context = LocalContext.current
    val pending by repository.requestPending.collectAsState()

    LaunchedEffect(pending) {
        if (!pending || repository.wasRequestedForVersion(environmentConfig.appVersionCode)) return@LaunchedEffect
        val activity = context.findActivity() ?: run {
            repository.postpone()
            return@LaunchedEffect
        }
        val manager = ReviewManagerFactory.create(context)
        runCatching {
            val reviewInfo = manager.requestReviewFlow().await()
            manager.launchReviewFlow(activity, reviewInfo).await()
        }.onSuccess {
            repository.markRequested(environmentConfig.appVersionCode)
        }.onFailure {
            repository.postpone()
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
