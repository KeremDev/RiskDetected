package com.riskdetectedan.feature.onboarding.nova

import com.riskdetectedan.core.data.onboarding.OnboardingAnswerChoice
import com.riskdetectedan.core.data.onboarding.OnboardingAnswersDraft
import com.riskdetectedan.core.data.onboarding.OnboardingNovaAnswers

/** The eleven-question catalogue from the prototype, verbatim: same ids, order, copy and icon geometry as iOS. */
internal object NovaOBIcon {
    const val doc = "M8 3h6l4 4v14H8zM14 3v4h4"
    const val list = "M4 7h4M4 12h4M4 17h4M11 7h9M11 12h9M11 17h9"
    const val cal = "M4 6h16v15H4zM4 11h16M8 3v4M16 3v4"
    const val shield = "M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z"
    const val chat = "M4 5h16v11H9l-5 4z"
    const val rule = "M4 4h16v16H4zM8 9h8M8 14h5"
    const val flame = "M12 3c4 5 6 7 6 10a6 6 0 01-12 0c0-3 3-4 3-7 1 2 3 2 3 4"
    const val tools = "M4 20l7-7M14 4l6 6-3 3-6-6zM7 4l3 3-3 3-3-3z"
    const val chart = "M4 20V9M10 20V4M16 20v-8M22 20H2"
    const val spark = "M12 3v5M12 16v5M3 12h5M16 12h5M6 6l3 3M15 15l3 3M18 6l-3 3M9 15l-3 3"
    const val truck = "M2 7h11v8H2zM13 11h5l3 4v0h-8M6 19a2 2 0 100-4 2 2 0 000 4zM17 19a2 2 0 100-4 2 2 0 000 4z"
    const val bolt = "M13 3L5 14h6l-1 7 8-11h-6z"
    const val flask = "M9 3h6M10 3v6l-5 9a2 2 0 002 3h10a2 2 0 002-3l-5-9V3"
    const val bell = "M6 16V11a6 6 0 1112 0v5l2 3H4zM10 19a2 2 0 004 0"
    const val users = "M9 11a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM2 20c0-3.5 3.2-5.5 7-5.5s7 2 7 5.5M17 6.5a3 3 0 010 6M18 20h4c0-2.6-1.4-4.3-3.5-5"
    const val file = "M7 3h7l4 4v14H7zM10 12h6M10 16h4"
    const val dots = "M6 12h.01M12 12h.01M18 12h.01"
    const val ban = "M4 12a8 8 0 1016 0 8 8 0 00-16 0zM6.5 6.5l11 11"
    const val certA = "M12 3l7 3v5.5c0 4.2-2.9 7.3-7 8.5-4.1-1.2-7-4.3-7-8.5V6zM9 11.5l2.2 2.2L15.5 9"
    const val certB = "M12 3.5a4.5 4.5 0 100 9 4.5 4.5 0 000-9zM9.6 12.2L8 21l4-2 4 2-1.6-8.8"
    const val certC = "M4 6h16v12H4zM7.5 10.5h5M7.5 14h3.5M17 14.5a2 2 0 100-4 2 2 0 000 4z"
    const val helmetPro = "M4 12a8 8 0 0116 0zM2.5 12h19M9 12V9a3 3 0 016 0v3"
    const val briefcase = "M3 8.5h18V20H3zM9 8.5V5.5h6v3M3 13.5h18M11 14h2v2h-2z"
    const val wrench = "M14.5 6.5l3 3-8.5 8.5H5.5v-3.5zM16 4l4 4M6 20.5h12"
    const val officeLead = "M5 21V5h10v16M8.5 9h3M8.5 13h3M18 21v-6.5a2 2 0 00-2-2M3 21h18"
    const val multiBuilding = "M4 21V8l6-2.5V21M10 11l7-2.5V21M17 13.5l3-1V21M2.5 21h19"
    const val oneBuilding = "M6 21V4h12v17M10 8h4M10 12h4M10 16h4M3.5 21h17"
    const val freelance = "M12 10a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM5 21v-1.5A5.5 5.5 0 0110.5 14h3a5.5 5.5 0 015.5 5.5V21"
    const val pickaxe = "M4 20l7.5-7.5M3.5 9.5c3-4.5 9.5-5.5 12.5-3M15 3c2.5 3 1.5 9.5-3 12.5"
    const val crane = "M5 21h14M7 21V4h9M7 8h11l-2.5 4.5M16 4l4.5 4.5"
    const val factory = "M3 21V11l5 3V11l5 3V9l6 4v8zM3 21h18M9.5 21v-3h3v3"
    const val health = "M12 20.5S4.5 16 4.5 10.8A4.3 4.3 0 0112 8a4.3 4.3 0 017.5 2.8c0 5.2-7.5 9.7-7.5 9.7zM12 11.5v4M10 13.5h4"
    const val spool = "M7 3h10v3l-3 2v10a2 2 0 01-4 0V8L7 6zM10 12h4"
    const val wheat = "M8 3v7.5a2 2 0 004 0V3M10 12v9M16.5 3c2 2.2 2 6.3 0 8.5-2-2.2-2-6.3 0-8.5M16.5 11.5V21"
    const val anvil = "M4 9h13l3 3-3 1.5H9L7 19h7M9 9V6h5.5v3"
    const val headset = "M5 14v-2a7 7 0 0114 0v2M5 14h3v5.5H6.5A1.5 1.5 0 015 18zM19 14h-3v5.5h1.5A1.5 1.5 0 0019 18z"
    const val gavel = "M4 20h9M6.5 12.5l6-6M9.5 3.5l6 6-3 3-6-6zM13.5 11.5L19 17l-2 2-5.5-5.5"
    const val docChart = "M7 3h10v18H7zM10 17v-5M13.5 17V9"
    const val clipboard = "M8 4.5h8V21H8zM10 2.5h4v3h-4zM10.5 12l1.8 1.8L15.5 10"
    const val magnifier = "M11 12a4.5 4.5 0 100-9 4.5 4.5 0 000 9zM14.5 11l6 6M3 20.5h7"
    const val exit = "M4 4h6v16H4zM13 12h7M16.5 8.5L20 12l-3.5 3.5"
    const val gear = "M12 15a3 3 0 100-6 3 3 0 000 6zM12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.5 5.5l2 2M16.5 16.5l2 2M18.5 5.5l-2 2M7.5 16.5l-2 2"
    const val speak = "M4 5h16v10H10l-4 3.5V15H4zM8 9h8M8 12h5"
    const val meeting = "M12 7.5a2.5 2.5 0 100-5 2.5 2.5 0 000 5M4.5 20a7.5 7.5 0 0115 0M6.5 12.5a2 2 0 100-4M17.5 12.5a2 2 0 100-4"
}

internal data class NovaOBOption(
    val value: String,
    val label: String,
    val icon: String,
    val sub: String = "",
    /** Full-width row under the grid (the prototype's `small` flag). */
    val small: Boolean = false,
    /** Suggests this option when the matching growth area was picked. */
    val suggestedBy: String? = null,
)

internal enum class NovaOBQuestionKind { Text, Single, Multi, Slider, Counter }

internal data class NovaOBQuestion(
    val id: String,
    val kind: NovaOBQuestionKind,
    val title: String,
    val desc: String = "",
    val skippable: Boolean = true,
    val options: List<NovaOBOption> = emptyList(),
    val max: Int? = null,
    val searchable: Boolean = false,
    val grid: Boolean = false,
    /** Columns when [grid] is on; the sector step needs a denser row. */
    val gridColumns: Int = 2,
    /** The option value that clears every other choice when picked. */
    val exclusive: String? = null,
    /** The option value that reveals the free-text field. */
    val other: String? = null,
)

internal object NovaOBCatalogue {
    val sections = listOf(
        "SENİ TANIYALIM" to 0..3,
        "DENEYİMİN VE ÇALIŞMA ALANIN" to 4..6,
        "İHTİYAÇLARIN VE TERCİHLERİN" to 7..10,
    )

    val experienceStops = listOf(
        "1–3 yıl" to "1 yıl ile 3 yıl arası deneyim",
        "3–7 yıl" to "3 yıl dahil, 7 yıla kadar",
        "7–10 yıl" to "7 yıl dahil, 10 yıla kadar",
        "10+ yıl" to "10 yıl ve üzeri",
    )

    val questions = listOf(
        NovaOBQuestion("name", NovaOBQuestionKind.Text, "Sana nasıl hitap edelim?",
            desc = "Çalışma alanını senin için kişiselleştirelim.", skippable = false),
        NovaOBQuestion("cert", NovaOBQuestionKind.Single, "Hangi sertifikaya sahipsin?",
            desc = "Bu kapsamda bilgiler/belgeler sunacağız.",
            options = listOf(
                NovaOBOption("A", "A Sınıfı", NovaOBIcon.certA),
                NovaOBOption("B", "B Sınıfı", NovaOBIcon.certB),
                NovaOBOption("C", "C Sınıfı", NovaOBIcon.certC),
                NovaOBOption("none", "Henüz sertifikam yok", NovaOBIcon.dots, small = true),
            )),
        NovaOBQuestion("work", NovaOBQuestionKind.Single, "Çalışma şeklin nedir?",
            options = listOf(
                NovaOBOption("osgb", "OSGB", NovaOBIcon.multiBuilding, sub = "Birden fazla firmayla çalışıyorum"),
                NovaOBOption("tek", "Tek firma", NovaOBIcon.oneBuilding, sub = "Bir firmanın bünyesinde çalışıyorum"),
                NovaOBOption("serbest", "Serbest çalışma", NovaOBIcon.freelance, sub = "Bağımsız hizmet veriyorum"),
                NovaOBOption("yok", "Şu an çalışmıyorum", NovaOBIcon.dots, small = true),
            )),
        NovaOBQuestion("role", NovaOBQuestionKind.Single, "Çalıştığın yerdeki pozisyonun nedir?",
            desc = "Bu bilgi yalnızca kişiselleştirme içindir; hesap yetkisi vermez.",
            options = listOf(
                NovaOBOption("uzman", "İş Güvenliği Uzmanı", NovaOBIcon.helmetPro),
                NovaOBOption("mudur", "İş Güvenliği Müdürü", NovaOBIcon.briefcase),
                NovaOBOption("tekniker", "İş Güvenliği Teknikeri", NovaOBIcon.wrench),
                NovaOBOption("koordinator", "İSG Koordinatörü", NovaOBIcon.users),
                NovaOBOption("osgbyonetici", "OSGB Yöneticisi / Sorumlusu", NovaOBIcon.officeLead),
                NovaOBOption("diger", "Diğer", NovaOBIcon.dots),
            ), other = "diger"),
        NovaOBQuestion("exp", NovaOBQuestionKind.Slider, "Toplam mesleki tecrüben ne kadar?",
            desc = "Aralığı sürükleyerek veya duraklara dokunarak seç."),
        NovaOBQuestion("sectors", NovaOBQuestionKind.Multi, "Hangi sektörlerde çalışıyorsun?",
            desc = "Birden fazla sektör seçebilirsin.",
            options = listOf(
                NovaOBOption("maden", "Maden", NovaOBIcon.pickaxe),
                NovaOBOption("insaat", "İnşaat", NovaOBIcon.crane),
                NovaOBOption("imalat", "İmalat", NovaOBIcon.factory),
                NovaOBOption("saglik", "Sağlık", NovaOBIcon.health),
                NovaOBOption("enerji", "Enerji", NovaOBIcon.bolt),
                NovaOBOption("tekstil", "Tekstil", NovaOBIcon.spool),
                NovaOBOption("gida", "Gıda", NovaOBIcon.wheat),
                NovaOBOption("lojistik", "Lojistik", NovaOBIcon.truck),
                NovaOBOption("kimya", "Kimya", NovaOBIcon.flask),
                NovaOBOption("metal", "Metal", NovaOBIcon.anvil),
                NovaOBOption("hizmet", "Hizmet", NovaOBIcon.headset),
                NovaOBOption("diger", "Diğer", NovaOBIcon.dots),
            ), searchable = true, grid = true, gridColumns = 3, other = "diger"),
        NovaOBQuestion("trainings", NovaOBQuestionKind.Multi, "Hangi eğitimleri aldın?",
            desc = "Birden fazla seçebilirsin.",
            options = listOf(
                NovaOBOption("nebosh", "NEBOSH", NovaOBIcon.doc),
                NovaOBOption("acil", "Acil Durum", NovaOBIcon.bell),
                NovaOBOption("yangin", "Yangın", NovaOBIcon.flame),
                NovaOBOption("kokneden", "Kök Neden Analizi", NovaOBIcon.chart),
                NovaOBOption("makine", "Makine Emniyeti", NovaOBIcon.tools),
                NovaOBOption("diger", "Diğer", NovaOBIcon.dots),
                NovaOBOption("yok", "Henüz bu eğitimlerden birini almadım", NovaOBIcon.ban, small = true),
            ), exclusive = "yok", other = "diger"),
        NovaOBQuestion("approach", NovaOBQuestionKind.Multi, "İş güvenliğini yönetirken yaklaşımın nasıl?",
            desc = "Sana en yakın iki yaklaşımı seçebilirsin.",
            options = listOf(
                NovaOBOption("iletisim", "İletişim odaklı", NovaOBIcon.chat, sub = "Diyalog ve katılım"),
                NovaOBOption("kuralci", "Kuralcı", NovaOBIcon.rule, sub = "Net kurallar ve uygulama"),
                NovaOBOption("mevzuat", "Mevzuat odaklı", NovaOBIcon.file, sub = "Gereklilikleri yakından takip"),
                NovaOBOption("disiplinli", "Disiplinli", NovaOBIcon.list, sub = "Düzenli kontrol ve takip"),
                NovaOBOption("esnek", "Rahat / esnek", NovaOBIcon.spark, sub = "Duruma uyum sağlayan iletişim"),
            ), max = 2),
        NovaOBQuestion("inspections", NovaOBQuestionKind.Counter, "Son 1 yılda kaç kez Bakanlık teftişi geçirdin?",
            desc = "Görev aldığın işyerlerinde katıldığın teftişleri düşün."),
        NovaOBQuestion("growth", NovaOBQuestionKind.Multi, "Hangi konularda güçlenmek istersin?",
            desc = "Daha fazla destek istediğin alanları seç.",
            options = listOf(
                NovaOBOption("risk", "Risk analizi", NovaOBIcon.shield),
                NovaOBOption("mevzuat", "Mevzuat takibi", NovaOBIcon.gavel),
                NovaOBOption("rapor", "Raporlama ve dokümantasyon", NovaOBIcon.docChart),
                NovaOBOption("saha", "Saha denetimleri", NovaOBIcon.clipboard),
                NovaOBOption("egitim", "Eğitim planlama", NovaOBIcon.cal),
                NovaOBOption("kaza", "Kaza / kök neden analizi", NovaOBIcon.magnifier),
                NovaOBOption("acil", "Acil durum planları", NovaOBIcon.exit),
                NovaOBOption("makine", "Makine emniyeti", NovaOBIcon.gear),
                NovaOBOption("calisan", "Çalışanlarla iletişim", NovaOBIcon.speak),
                NovaOBOption("diger", "Diğer", NovaOBIcon.dots),
                NovaOBOption("yok", "Belirli bir alan yok", NovaOBIcon.ban, small = true),
            ), grid = true, exclusive = "yok", other = "diger"),
        NovaOBQuestion("assist", NovaOBQuestionKind.Multi, "Hangi konularda asistanlık yapalım?",
            desc = "İhtiyaç duyduğun alanları seç.",
            options = listOf(
                NovaOBOption("risk", "Risk Analizi", NovaOBIcon.shield, sub = "Analiz taslakları, revizyon hatırlatmaları", suggestedBy = "risk"),
                NovaOBOption("kontrol", "Kontrol Listeleri", NovaOBIcon.clipboard, sub = "Sahaya göre hazır listeler", suggestedBy = "saha"),
                NovaOBOption("egitim", "Eğitim Takibi", NovaOBIcon.cal, sub = "Tarih ve tekrar takibi", suggestedBy = "egitim"),
                NovaOBOption("firma", "Firma Yönetimi", NovaOBIcon.oneBuilding, sub = "Firma dosyaları tek yerde"),
                NovaOBOption("osgb", "OSGB Yönetimi", NovaOBIcon.multiBuilding, sub = "Atama ve görev dağılımı"),
                NovaOBOption("acil", "Acil Durum Planları", NovaOBIcon.exit, sub = "Plan şablonu, tatbikat takvimi", suggestedBy = "acil"),
                NovaOBOption("toplanti", "Toplantılar", NovaOBIcon.meeting, sub = "Gündem ve karar kaydı"),
                NovaOBOption("mevzuat", "Mevzuat Takibi", NovaOBIcon.gavel, sub = "Değişiklik bildirimleri", suggestedBy = "mevzuat"),
                NovaOBOption("rapor", "Raporlama", NovaOBIcon.docChart, sub = "Dönemsel rapor çıktıları", suggestedBy = "rapor"),
            ), grid = true),
    )

    fun question(id: String): NovaOBQuestion? = questions.firstOrNull { it.id == id }

    fun label(questionId: String, value: String): String =
        question(questionId)?.options?.firstOrNull { it.value == value }?.label.orEmpty()
}

/** Every answer the funnel collects, mirroring the prototype's `EMPTY` shape. */
internal data class NovaOBAnswers(
    val name: String = "",
    val cert: String? = null,
    val work: String? = null,
    val role: String? = null,
    val roleOther: String = "",
    /** Index into [NovaOBCatalogue.experienceStops], or null when unanswered. */
    val exp: Int? = null,
    val expLess: Boolean = false,
    val sectors: List<String> = emptyList(),
    val sectorsOther: String = "",
    val trainings: List<String> = emptyList(),
    val trainingsOther: String = "",
    val approach: List<String> = emptyList(),
    val inspections: Int = 0,
    val growth: List<String> = emptyList(),
    val growthOther: String = "",
    val assist: List<String> = emptyList(),
) {
    fun list(questionId: String): List<String> = when (questionId) {
        "sectors" -> sectors
        "trainings" -> trainings
        "approach" -> approach
        "growth" -> growth
        "assist" -> assist
        else -> emptyList()
    }

    fun withList(questionId: String, values: List<String>): NovaOBAnswers = when (questionId) {
        "sectors" -> copy(sectors = values)
        "trainings" -> copy(trainings = values)
        "approach" -> copy(approach = values)
        "growth" -> copy(growth = values)
        "assist" -> copy(assist = values)
        else -> this
    }

    fun single(questionId: String): String? = when (questionId) {
        "cert" -> cert
        "work" -> work
        "role" -> role
        else -> null
    }

    fun withSingle(questionId: String, value: String?): NovaOBAnswers = when (questionId) {
        "cert" -> copy(cert = value)
        "work" -> copy(work = value)
        "role" -> copy(role = value)
        else -> this
    }

    fun other(questionId: String): String = when (questionId) {
        "sectors" -> sectorsOther
        "trainings" -> trainingsOther
        "growth" -> growthOther
        else -> roleOther
    }

    fun withOther(questionId: String, value: String): NovaOBAnswers = when (questionId) {
        "sectors" -> copy(sectorsOther = value)
        "trainings" -> copy(trainingsOther = value)
        "growth" -> copy(growthOther = value)
        else -> copy(roleOther = value)
    }

    private fun choice(questionId: String, value: String) = OnboardingAnswerChoice(value, NovaOBCatalogue.label(questionId, value))

    /** A "Diğer" choice carries the text the user wrote, when there is one. */
    private fun choices(questionId: String, values: List<String>, other: String) = values.map { value ->
        if (value == "diger" && other.isNotBlank()) OnboardingAnswerChoice(value, other.trim()) else choice(questionId, value)
    }

    private val experienceChoice: OnboardingAnswerChoice?
        get() = when {
            expLess -> OnboardingAnswerChoice("0-1", "1 yıldan az")
            exp != null && exp in EXPERIENCE_VALUES.indices ->
                OnboardingAnswerChoice(EXPERIENCE_VALUES[exp], NovaOBCatalogue.experienceStops[exp].first)
            else -> null
        }

    /** The server's audit-frequency buckets; no inspection is no answer there. */
    private val auditFrequency: OnboardingAnswerChoice?
        get() = when {
            inspections < 1 -> null
            inspections == 1 -> "1"
            inspections <= 5 -> "2-5"
            inspections <= 15 -> "6-15"
            else -> "15+"
        }?.let { OnboardingAnswerChoice(it, "$inspections teftiş") }

    /**
     * The draft [com.riskdetectedan.core.data.onboarding.OnboardingAnswersRepository] keeps on the
     * device until an account exists, then sends (iOS `NovaOBAnswers.makeDraft`). The server takes
     * one answer schema ("v2") and checks its columns, so the answers that fit are mapped onto them;
     * every answer also goes whole into `raw_answers.nova`.
     */
    fun makeDraft(skipped: Set<String> = emptySet(), marketing: Boolean? = null): OnboardingAnswersDraft {
        val sectorChoices = choices("sectors", sectors, sectorsOther)
        val serverSectors = sectorChoices.mapNotNull { sector -> SERVER_SECTORS[sector.value]?.let { OnboardingAnswerChoice(it, sector.label) } }
            .distinctBy { it.value }
        val roleChoice = role?.let { value ->
            if (value == "diger" && roleOther.isNotBlank()) OnboardingAnswerChoice(value, roleOther.trim()) else choice("role", value)
        }
        return OnboardingAnswersDraft(
            onboardingVersion = "v2",
            certificateClass = cert?.takeIf { it in listOf("A", "B", "C") }?.let { choice("cert", it) },
            hazardClasses = emptyList(),
            professionalRole = roleChoice,
            safetyProfileId = null,
            sectors = serverSectors,
            auditFrequency = auditFrequency,
            selectedPlan = null,
            nova = OnboardingNovaAnswers(
                flow = "nova-v1",
                name = name.trim().ifEmpty { null },
                certificate = cert?.let { choice("cert", it) },
                work = work?.let { choice("work", it) },
                role = roleChoice,
                experience = experienceChoice,
                sectors = sectorChoices,
                trainings = choices("trainings", trainings, trainingsOther),
                approach = approach.map { choice("approach", it) },
                inspections = inspections,
                growth = choices("growth", growth, growthOther),
                assist = assist.map { choice("assist", it) },
                skipped = skipped.sorted(),
                marketingEmailOptIn = marketing,
            ),
        )
    }

    companion object {
        /** Nova sector keys onto the server's sector list. Textile and metal are manufacturing there,
         * services has no match; `raw_answers.nova.sectors` keeps the Nova keys either way. */
        val SERVER_SECTORS = mapOf(
            "maden" to "mining", "insaat" to "construction", "imalat" to "manufacturing", "saglik" to "healthcare",
            "enerji" to "energy", "tekstil" to "manufacturing", "gida" to "food_production",
            "lojistik" to "logistics_warehouse", "kimya" to "chemical_laboratory", "metal" to "manufacturing",
            "hizmet" to "other", "diger" to "other",
        )
        val EXPERIENCE_VALUES = listOf("1-3", "3-7", "7-10", "10+")
    }
}
