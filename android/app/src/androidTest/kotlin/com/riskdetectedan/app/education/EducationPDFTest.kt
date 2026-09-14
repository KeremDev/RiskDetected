package com.riskdetectedan.app.education

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.riskdetectedan.feature.profile.EducationCertificatePDF
import com.riskdetectedan.core.data.education.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EducationPDFTest {
    @Test fun sharedServerSnapshotsProducePersonalDuplexDocuments() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        val snapshots=Json.parseToJsonElement(instrumentation.context.assets.open("education/server-snapshots.json").bufferedReader().use { it.readText() }).jsonArray
        snapshots.forEachIndexed { index, raw ->
            val snapshot=raw.jsonObject
            val result=buildJsonObject { put("owner_id","20000000-0000-0000-0000-000000000001");put("document_id","70000000-0000-0000-0000-00000000000${index+1}");put("revision",1);put("snapshot",snapshot) }
            val file=EducationCertificatePDF.file(context,result)
            PdfRenderer(ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)).use { pdf ->
                assertEquals("standard server snapshot $index",2,pdf.pageCount)
                pdf.openPage(0).use { page ->
                    assertEquals(595,page.width);assertEquals(842,page.height)
                    val bitmap=Bitmap.createBitmap(595,842,Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
                    page.render(bitmap,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    var darkPixels=0
                    for(y in 40..780 step 3)for(x in 34..560 step 3)if(Color.red(bitmap.getPixel(x,y))<150)darkPixels++
                    assertTrue("visible certificate content",darkPixels>300)
                    if(index==0)java.io.File(context.cacheDir,"education-android-front.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
                    bitmap.recycle()
                }
            }
            val modified=file.lastModified();assertEquals(file,EducationCertificatePDF.file(context,result));assertEquals(modified,file.lastModified())
        }
        val base=snapshots[0].jsonObject
        val scope=base.getValue("scope").jsonObject
        val topics=scope.objects("topics")+(0..29).map { EducationRules.topic("G4-LONG-$it","G4",("Çalışanın işyerine özgü güvenli çalışma açıklaması. ").repeat(15),5) }
        val longer=base.with("scope",scope.with("topics",objects(topics))).with("is_draft",JsonPrimitive(true))
        val result=buildJsonObject { put("owner_id","20000000-0000-0000-0000-000000000001");put("snapshot",longer) }
        val file=EducationCertificatePDF.file(context,result)
        PdfRenderer(ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)).use { pdf -> assertTrue(pdf.pageCount>2);assertEquals(0,pdf.pageCount%2) }
    }
}
