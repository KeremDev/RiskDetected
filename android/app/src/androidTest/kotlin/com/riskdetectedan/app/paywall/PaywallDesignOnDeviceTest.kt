package com.riskdetectedan.app.paywall

import android.content.ContentValues
import android.graphics.Bitmap
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.riskdetectedan.core.designsystem.RdPaywallDesignBilling
import com.riskdetectedan.core.designsystem.RdPaywallDesignCta
import com.riskdetectedan.core.designsystem.RdPaywallDesignScreen
import com.riskdetectedan.core.designsystem.RdPaywallDesignTag
import com.riskdetectedan.core.designsystem.RdPaywallDesignTier
import com.riskdetectedan.core.designsystem.RiskDetectedLightOnlyTheme
import com.riskdetectedan.core.designsystem.rdPaywallDesignState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Gerçek cihaz/emülatör üzerinde paywall doğrulaması. Roborazzi goldenları JVM'de (Robolectric)
 * çalışır; bu test aynı ekranı gerçek Android grafik yığınında çalıştırır ve etkileşimi sürer:
 * yıllık ↔ aylık geçişi, PLUS ↔ PRO çapraz satışı ve alt bar bağlantıları.
 *
 * Mağaza/oturum bağımlılığı yoktur — satın alma akışı Google Play'in kendi ekranıdır ve burada
 * taklit edilmez; doğrulanan şey ekranın gerçek cihazda doğru çizilip doğru tepki verdiğidir.
 */
@RunWith(AndroidJUnit4::class)
class PaywallDesignOnDeviceTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun paywallRendersAndRespondsOnDevice() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                var tier by remember { mutableStateOf(RdPaywallDesignTier.Plus) }
                var billing by remember { mutableStateOf(RdPaywallDesignBilling.Yearly) }

                val state = rdPaywallDesignState(
                    tier = tier,
                    selectedBilling = billing,
                    yearlyPrice = "₺1.499,99",
                    yearlyMonthlyEquivalent = "₺124,99",
                    monthlyPrice = "₺149,99",
                    trialDays = if (tier == RdPaywallDesignTier.Plus) 7 else null,
                    discountPercent = 17,
                    priceUnavailableText = "fiyat yükleniyor",
                    cta = RdPaywallDesignCta(title = "Aboneliği Başlat"),
                )

                RdPaywallDesignScreen(
                    state = state,
                    onClose = {},
                    onSelectBilling = { billing = it },
                    onCta = {},
                    onRestore = {},
                    onTerms = {},
                    onPrivacy = {},
                    onManageSubscription = {},
                    onCrossSell = {
                        tier = if (tier == RdPaywallDesignTier.Plus) {
                            RdPaywallDesignTier.Pro
                        } else {
                            RdPaywallDesignTier.Plus
                        }
                        billing = RdPaywallDesignBilling.Yearly
                    },
                )
            }
        }

        // 1) PLUS + yıllık: gerçek Play teklifi varsayımıyla deneme anlatımı görünür.
        composeRule.onNodeWithTag(RdPaywallDesignTag.Plus).assertIsDisplayed()
        composeRule.onNodeWithTag(RdPaywallDesignTag.TrialTimeline).assertIsDisplayed()
        composeRule.onNodeWithText("Ücretsiz Deneme Nasıl Çalışır?").assertIsDisplayed()
        composeRule.onNodeWithText("7 gün ücretsiz").assertIsDisplayed()
        composeRule.onNodeWithText("%17 İndirim").assertIsDisplayed()
        capture("plus_yearly")

        // 2) Aylığa geçince deneme anlatımı yerini karşılaştırma tablosuna bırakır.
        composeRule.onNodeWithTag(RdPaywallDesignTag.PlanMonthly).performClick()
        composeRule.onNodeWithTag(RdPaywallDesignTag.ComparisonTable).assertIsDisplayed()
        composeRule.onNodeWithText("PLUS Abonelik Avantajları").assertIsDisplayed()
        capture("plus_monthly")

        // 3) Çapraz satış PRO ekranını açar.
        composeRule.onNodeWithTag(RdPaywallDesignTag.CrossSellPro).performClick()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Pro).assertIsDisplayed()
        composeRule.onNodeWithText("PRO Abonelik Avantajları").assertIsDisplayed()
        composeRule.onNodeWithText("Limitsiz").assertIsDisplayed()
        capture("pro_yearly")

        // 4) Yasal/abonelik bağlantıları her iki ekranda da erişilebilir olmalı.
        composeRule.onNodeWithTag(RdPaywallDesignTag.Restore).assertIsDisplayed()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Terms).assertIsDisplayed()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Privacy).assertIsDisplayed()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Manage).assertIsDisplayed()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Cta).assertIsDisplayed()

        // 5) PRO'dan PLUS'a dönüş.
        composeRule.onNodeWithTag(RdPaywallDesignTag.CrossSellPlus).performClick()
        composeRule.onNodeWithTag(RdPaywallDesignTag.Plus).assertIsDisplayed()
    }

    /**
     * Yakalanan kareyi MediaStore üzerinden `Pictures/RiskDetectedPaywallQA` altına yazar.
     * API 30+ kapsamlı depolamada uygulamanın kendi `Android/data` dizini adb kabuğundan
     * okunamıyor, uygulama debuggable olmadığı için `run-as` da yok; MediaStore yolu ise
     * host tarafından doğrudan çekilebiliyor.
     */
    private fun capture(name: String) {
        val bitmap = composeRule.onRoot().captureToImage().asAndroidBitmap()
        val resolver = InstrumentationRegistry.getInstrumentation().targetContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/RiskDetectedPaywallQA")
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        checkNotNull(uri) { "MediaStore kaydi olusturulamadi: $name" }
        resolver.openOutputStream(uri).use { output ->
            checkNotNull(output) { "MediaStore akisi acilamadi: $name" }
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        }
    }
}
