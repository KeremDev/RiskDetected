package com.riskdetectedan.feature.profile

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.print.*
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.education.*
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.io.File

@Composable internal fun EducationCertificateDialog(result: JsonObject,busy: Boolean,canIssue: Boolean,close: ()->Unit,issue: ()->Unit,authorize: suspend ()->Unit,draft: JsonObject?,saveFields: (JsonObject)->Unit) {
    val context=LocalContext.current;val coroutine=rememberCoroutineScope();val snapshot=result.getValue("snapshot").jsonObject
    var edited by remember(result) { mutableStateOf(draft) }
    var file by remember(result) { mutableStateOf<File?>(null) };var page by remember(result){mutableIntStateOf(0)};var pages by remember {mutableIntStateOf(0)}
    var bitmap by remember(result,page){mutableStateOf<Bitmap?>(null)};var error by remember {mutableStateOf<String?>(null)}
    val save=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")){uri->if(uri!=null)coroutine.launch {
        runCatching { authorize();context.contentResolver.openOutputStream(uri)?.use { out->file!!.inputStream().use { it.copyTo(out) } } }.onFailure { error="Dosya kaydedilemedi." }
    } }
    LaunchedEffect(result,page) {
        runCatching {
            authorize();val current=EducationCertificatePDF.file(context,result);file=current
            PdfRenderer(ParcelFileDescriptor.open(current,ParcelFileDescriptor.MODE_READ_ONLY)).use { pdf->
                pages=pdf.pageCount;pdf.openPage(page.coerceIn(0,pages-1)).use { p->
                    val image=Bitmap.createBitmap(p.width*2,p.height*2,Bitmap.Config.ARGB_8888);image.eraseColor(android.graphics.Color.WHITE)
                    p.render(image,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);bitmap=image
                }
            }
        }.onFailure { error="Belge önizlemesi hazırlanamadı." }
    }
    Dialog(close,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Surface(Modifier.fillMaxWidth(.96f).fillMaxHeight(.95f),shape=MaterialTheme.shapes.large) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                Text("Kişisel eğitim belgesi",style=MaterialTheme.typography.titleLarge)
                TextButton(close){Text("Kapat")};error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
                result.strings("issues").forEach {Text(EducationRules.issue(it),color=MaterialTheme.colorScheme.error)}
                if(snapshot.flag("is_draft"))edited?.let { value ->
                    EducationSection("Eksik belge bilgilerini tamamla") {
                        EducationInput("Düzenleyici",value.text("provider_name"),{edited=value.with("provider_name",it)},!busy && canIssue)
                        value.objects("trainers").forEachIndexed { index,trainer ->
                            EducationInput("Eğitici unvanı",trainer.text("title"),{edited=replace(value,"trainers",index,trainer.with("title",it))},!busy && canIssue)
                        }
                        value.objects("scopes").forEachIndexed { index,scope ->if(scope["id"]==snapshot.getValue("scope").jsonObject["id"]) {
                            EducationInput("İşveren / vekili",scope.text("employer_name"),{edited=replace(value,"scopes",index,scope.with("employer_name",it))},!busy && canIssue)
                            scope.objects("participants").forEachIndexed { personIndex,person ->if(person["id"]==snapshot.getValue("person").jsonObject["id"]) {
                                EducationInput("Belgeye özel personel unvanı",person.text("job_title"),{edited=replace(value,"scopes",index,replace(scope,"participants",personIndex,person.with("job_title",it)))},!busy && canIssue)
                            } }
                        } }
                        Button({saveFields(value)},enabled=!busy && canIssue){Text("Bilgileri kaydet ve önizlemeyi yenile")}
                    }
                }
                bitmap?.let { Image(it.asImageBitmap(),"Belge sayfası ${page+1}",Modifier.fillMaxWidth().heightIn(min=360.dp)) }
                Row { TextButton({page--},enabled=page>0){Text("Önceki")};Text("${page+1} / $pages");TextButton({page++},enabled=page+1<pages){Text("Sonraki")} }
                if(snapshot.flag("is_draft"))Button(issue,enabled=canIssue && edited==draft && !busy && result.strings("issues").isEmpty()){Text("Belge numarasını al ve hazırla")}
                Row {
                    TextButton({save.launch((if(snapshot.flag("is_draft"))"TASLAK" else snapshot.text("number"))+".pdf")},enabled=file!=null && !busy){Text("Kaydet")}
                    TextButton({coroutine.launch { runCatching {
                        authorize();val uri=FileProvider.getUriForFile(context,context.packageName+".fileprovider",file!!)
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"Eğitim belgesini paylaş"))
                    }.onFailure {error="Paylaşım açılamadı."} }},enabled=file!=null && !busy){Text("Paylaş")}
                    TextButton({coroutine.launch {runCatching {
                        authorize();(context.getSystemService(android.content.Context.PRINT_SERVICE) as PrintManager).print("Eğitim belgesi",EducationPrint(file!!),PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).setDuplexMode(PrintAttributes.DUPLEX_MODE_LONG_EDGE).build())
                    }.onFailure {error="Yazdırma açılamadı."}}},enabled=file!=null && !busy){Text("Yazdır")}
                }
            }
        }
    }
}
private class EducationPrint(private val file: File): PrintDocumentAdapter() {
    override fun onLayout(oldAttributes: PrintAttributes?,newAttributes: PrintAttributes?,signal: android.os.CancellationSignal,callback: LayoutResultCallback,extras: android.os.Bundle?) {
        if(signal.isCanceled){callback.onLayoutCancelled();return}
        callback.onLayoutFinished(PrintDocumentInfo.Builder(file.name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).build(),oldAttributes!=newAttributes)
    }
    override fun onWrite(pages: Array<out PageRange>,destination: ParcelFileDescriptor,signal: android.os.CancellationSignal,callback: WriteResultCallback) {
        if(signal.isCanceled){callback.onWriteCancelled();return}
        try { java.io.FileOutputStream(destination.fileDescriptor).use { out->file.inputStream().use { it.copyTo(out) } };callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES)) }
        catch(error: Exception){callback.onWriteFailed("Belge yazdırılamadı.")}
    }
}
