package com.riskdetectedan.app.home

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class PhotoTrayInsetsTest {
    @Test fun `three button navigation keeps CTA fully above system menu`() {
        assertEquals(60.dp, photoTrayBottomPadding(48.dp))
    }

    @Test fun `gesture navigation keeps a minimum breathing space`() {
        assertEquals(24.dp, photoTrayBottomPadding(0.dp))
    }
}
