package com.riskdetectedan.feature.profile

import android.content.Context
import android.graphics.*
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.res.ResourcesCompat
import com.riskdetectedan.core.data.education.*
import kotlinx.serialization.json.*
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter

object EducationCertificatePDF {
    const val rendererVersion=1
    private data class Block(val text: String,val size: Float=10f,val bold: Boolean=false,val space: Int=6,val reserved: Int=0)
    private data class Placed(val layout: StaticLayout,val y: Int)
    fun file(context: Context, certificate: JsonObject): File {
        val s=certificate.getValue("snapshot").jsonObject
        val owner=java.util.UUID.fromString(certificate.text("owner_id")).toString()
        val folder=File(context.cacheDir,"reports/education/$owner").apply { check(isDirectory || mkdirs()) }
        val name=if(s.flag("is_draft"))"draft-${s.text("source_session_id")}-${s.getValue("person").jsonObject.text("id")}" else "${java.util.UUID.fromString(certificate.text("document_id"))}-r${certificate.number("revision")}-renderer$rendererVersion"
        val file=File(folder,"$name.pdf")
        if(!s.flag("is_draft") && file.exists())return file
        val logo=runCatching { android.util.Base64.decode(s.text("logo_png_base64"),android.util.Base64.DEFAULT).let { BitmapFactory.decodeByteArray(it,0,it.size) } }.getOrNull()
        val scope=s.getValue("scope").jsonObject;val person=s.getValue("person").jsonObject
        val regular=ResourcesCompat.getFont(context,com.riskdetectedan.core.designsystem.R.font.mulish_regular)!!
        val bold=ResourcesCompat.getFont(context,com.riskdetectedan.core.designsystem.R.font.mulish_bold)!!
        fun layout(block: Block,text: String=block.text): StaticLayout {
            val paint=TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize=block.size;typeface=if(block.bold)bold else regular;color=if(block.bold)Color.rgb(20,38,64) else Color.BLACK }
            return StaticLayout.Builder.obtain(text,0,text.length,paint,527).setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).setLineSpacing(2f,1f).build()
        }
        fun signature(text: String) = Block(text,reserved=layout(Block(text)).height+64)
        val timeFormat=DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(EducationRules.zone)
        val endFormat=DateTimeFormatter.ofPattern("HH:mm").withZone(EducationRules.zone)
        val times=scope.objects("lessons").groupBy { Instant.parse(it.text("starts_at")).atZone(EducationRules.zone).toLocalDate() }.toSortedMap().map { (_,list)->
            val sorted=list.sortedBy { it.text("starts_at") };val first=Instant.parse(sorted.first().text("starts_at"));val last=sorted.last()
            timeFormat.format(first)+"–"+endFormat.format(Instant.parse(last.text("starts_at")).plusSeconds((last.number("instruction_minutes")+last.number("break_minutes"))*60L))
        }
        val methods=scope.objects("topics").map { it.text("method") }.toSet()
        val front=mutableListOf(Block(scope.text("legal_name"),15f,true,14),Block((if(s.flag("is_draft"))"TASLAK · " else "")+s.text("title"),21f,true,18),
            Block(person.text("name"),18f,true),Block("Unvan: "+person.text("job_title").ifEmpty { "Eksik" },11f),
            Block("İşyeri: "+scope.text("workplace_name")+" · "+mapOf("low" to "Az tehlikeli","medium" to "Tehlikeli","high" to "Çok tehlikeli")[scope.text("hazard_class")]),
            Block("Düzenleyen: "+s.text("provider_name"),11f),Block("Eğitim: "+EducationRules.cycles[scope.text("cycle")],11f),
            Block("Gerçekleşen gün ve saatler (Europe/Istanbul)\n"+times.joinToString("\n")),
            Block("Süre: ${scope.number("instruction_minutes")} dk öğretim + ${scope.number("break_minutes")} dk ara = ${scope.number("instruction_minutes")+scope.number("break_minutes")} dk",11f,true),
            Block("Yöntem: "+(if(methods.size>1)"Karma" else EducationRules.method(methods.firstOrNull().orEmpty()))+" · Konu bazında yöntem arka yüzde gösterilmiştir."),
            Block("Düzenleme: "+s.text("issued_on")+scope.text("valid_until").let { if(it.isEmpty())"" else " · Tekrar tarihi: $it" }),
            Block(if(s.flag("is_draft"))"TASLAK — Belge numarası tahsis edilmemiştir. Eğitim ve belge bilgileri tamamlanmadan başarı belgesi olarak kullanılamaz." else "Yukarıda bilgileri bulunan çalışan, belirtilen tarihlerde gerçekleştirilen ve içeriği izleyen sayfalarda yer alan eğitimi başarıyla tamamlamıştır.",11f,space=12),
            Block("Eğiticiler ve imza alanları",11f,true))
        s.objects("trainers").forEach { trainer->
            val groups=scope.objects("topics").filter { trainer.text("id") in it.strings("trainer_ids") }.map { it.text("group") }.distinct().sorted()
            front += signature(trainer.text("name")+" · "+trainer.text("title")+"\nKonu kapsamı: "+groups.joinToString(", ")+"\nİmza:")
        }
        front += signature((if(scope.text("employer_capacity")=="employer")"İşveren" else "İşveren vekili")+": "+scope.text("employer_name")+"\nİmza / kaşe:")
        front += Block("Belge, düzenleyen uzmanın kaydına ve beyanına dayanır. İmza alanları fiziki imza için boş bırakılmıştır.",8f)
        val back=mutableListOf(Block("EĞİTİM KONULARI VE SÜRELERİ",16f,true,12))
        mapOf("G1" to "Genel konular","G2" to "Sağlık konuları","G3" to "Teknik konular","G4" to "İşyerine özgü riskler").forEach { (group,name)->
            val topics=scope.objects("topics").filter { it.text("group")==group }
            if(topics.isNotEmpty()) {
                back += Block("$group · $name · ${topics.sumOf { it.number("instruction_minutes") }} dk",11f,true)
                topics.forEach { topic->
                    val parent=topic.text("parent_code")
                    val title=if(parent.isEmpty())topic.text("title") else topic.text("legal_title")+": "+topic.text("title")
                    back += Block((parent.ifEmpty { topic.text("code") })+"  $title — ${topic.number("instruction_minutes")} dk · "+EducationRules.method(topic.text("method")),9f,space=3)
                }
            }
        }
        back += Block("İşyeri / görev bağlamı: "+scope.text("context_note"),9f,space=8)
        back += Block("Öğretim: ${scope.number("instruction_minutes")} dk · Ara: ${scope.number("break_minutes")} dk · Toplam: ${scope.number("instruction_minutes")+scope.number("break_minutes")} dk",10f,true)
        val pages=mutableListOf<List<Placed>>()
        fun paginate(blocks: List<Block>) {
            var rows=mutableListOf<Placed>();var y=52
            blocks.forEach { block->
                var text=block.text
                do {
                    val all=layout(block,text);val available=782-y
                    if(block.reserved>available || all.getLineBottom(0)>available) { pages+=rows;rows=mutableListOf();y=52 }
                    else {
                        var lines=0;while(lines<all.lineCount && all.getLineBottom(lines)<=available)lines++
                        val end=all.getLineEnd(lines-1);val piece=layout(block,text.substring(0,end))
                        rows+=Placed(piece,y);y+=maxOf(piece.height,block.reserved)+block.space;text=text.substring(end)
                        if(text.isNotEmpty()){pages+=rows;rows=mutableListOf();y=52}
                    }
                } while(text.isNotEmpty())
            }
            if(rows.isNotEmpty())pages+=rows
        }
        if(logo!=null)front.add(0,Block(" ",reserved=60))
        paginate(front);paginate(back)
        if(pages.size%2!=0)pages+=listOf(Placed(layout(Block("Bu sayfa çift taraflı baskı düzeni için boş bırakılmıştır.",11f)),400))
        val temp=File(folder,"$name.tmp")
        val pdf=PdfDocument()
        try {
            pages.forEachIndexed { i,rows->
                val page=pdf.startPage(PdfDocument.PageInfo.Builder(595,842,i+1).create());val canvas=page.canvas;canvas.drawColor(Color.WHITE)
                canvas.drawRect(34f,34f,561f,36f,Paint().apply { color=Color.rgb(26,102,115) })
                if(i==0 && logo!=null) { val factor=minOf(120f/logo.width,50f/logo.height);canvas.drawBitmap(logo,null,RectF(34f,52f,34f+logo.width*factor,52f+logo.height*factor),Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)) }
                rows.forEach { row->canvas.save();canvas.translate(34f,row.y.toFloat());row.layout.draw(canvas);canvas.restore() }
                val footer=person.text("name")+" · "+(if(s.flag("is_draft"))"TASLAK" else s.text("number"))+" · R${s.number("revision")} · ${i+1}/${pages.size}"
                canvas.save();canvas.translate(34f,801f);layout(Block(footer,8f)).draw(canvas);canvas.restore();pdf.finishPage(page)
            }
            temp.outputStream().use(pdf::writeTo)
        }
        finally { pdf.close();logo?.recycle() }
        check(temp.renameTo(file));return file
    }
}
