package com.riskdetectedan.app.bootstrap

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.riskdetectedan.app.BuildConfig
import com.riskdetectedan.app.R
import com.riskdetectedan.core.designsystem.RdTheme

@Composable
fun AppSplashScreen() {
    // The pilot opens on the white Nova splash (İSGADA); the RiskDetected mark must not flash first.
    if (BuildConfig.NOVA_PILOT) {
        Box(Modifier.fillMaxSize().background(Color.White))
        return
    }
    Box(
        modifier = Modifier.fillMaxSize().background(RdTheme.colors.paper),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.rd_logo),
            contentDescription = null,
            modifier = Modifier.size(132.dp),
        )
    }
}
