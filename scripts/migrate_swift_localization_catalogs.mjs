#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const INVENTORY_PATH = join(
  ROOT,
  "localization/content-inventory/app-content.csv",
);
const TRANSLATIONS_PATH = join(
  ROOT,
  "localization/translations/ios-machine-draft.json",
);
const LOCALIZATION_DIRECTORY = join(ROOT, "App/Localization");

const UI_PATTERNS = [
  {
    context: "swiftui_text",
    regex:
      /\b(?:Text|Button|Label|TextField|SecureField|Picker|Toggle|Section|GroupBox|Link|Menu)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swiftui_modifier",
    regex:
      /\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "custom_ui_copy",
    regex:
      /\b(?:title|subtitle|message|text|placeholder|emptyTitle|emptyMessage|buttonTitle|label|prompt|detail|formula|points|loadingTitle|fallbackTitle)\s*:\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swift_ui_helper_copy",
    regex:
      /\b(?:field|profileField|sectionHeader|sectionLabel|sectionTitle|settingsSection)\(\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "computed_ui_copy",
    regex: /\breturn\s+"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "localized_error_description",
    regex:
      /\bNSLocalizedDescriptionKey\s*:\s*"((?:\\.|[^"\\])*)"/g,
  },
  {
    context: "swift_user_copy",
    regex: /"((?:\\.|[^"\\])*)"/g,
  },
];

const INTERPOLATED_START_PATTERNS = [
  {
    context: "swiftui_text",
    regex:
      /\b(?:Text|Button|Label|TextField|SecureField|Picker|Toggle|Section|GroupBox|Link|Menu)\(\s*"/g,
  },
  {
    context: "swiftui_modifier",
    regex:
      /\.(?:navigationTitle|alert|confirmationDialog|accessibilityLabel|accessibilityHint)\(\s*"/g,
  },
  {
    context: "custom_ui_copy",
    regex:
      /\b(?:title|subtitle|message|text|placeholder|emptyTitle|emptyMessage|buttonTitle|label|prompt|detail|formula|points|loadingTitle|fallbackTitle)\s*:\s*"/g,
  },
  {
    context: "swift_ui_helper_copy",
    regex:
      /\b(?:field|profileField|sectionHeader|sectionLabel|sectionTitle|settingsSection)\(\s*"/g,
  },
  {
    context: "computed_ui_copy",
    regex: /\breturn\s*"/g,
  },
  {
    context: "localized_error_description",
    regex: /\bNSLocalizedDescriptionKey\s*:\s*"/g,
  },
  {
    context: "swift_user_copy",
    regex: /"/g,
  },
];

const CATALOGS = [
  "Localizable",
  "Auth",
  "Onboarding",
  "Paywall",
  "Analysis",
  "Reports",
  "Notifications",
  "ProfessionalProgress",
  "Legal",
  "SafetyTerminology",
  "InfoPlist",
];

const REPORT_SEEDS = [
  ["reports.create.title", "Rapor Oluştur", "Create report"],
  ["reports.language.section", "RAPOR DİLİ", "REPORT LANGUAGE"],
  [
    "reports.language.turkish.subtitle",
    "PDF ve Excel çıktıları Türkçe hazırlanır.",
    "The report uses the language captured by the analysis.",
  ],
  [
    "reports.language.future.note",
    "Rapor dili analiz kaydının diliyle aynıdır.",
    "The report language is fixed to the analysis language.",
  ],
  ["reports.pdf.standard.title", "Standart PDF", "Standard PDF"],
  [
    "reports.pdf.standard.subtitle",
    "RiskDetected şablonu ile hızlı saha raporu.",
    "A quick site report using the RiskDetected template.",
  ],
  [
    "reports.pdf.risk_analysis.title",
    "Detaylı risk analizi",
    "Detailed risk assessment",
  ],
  [
    "reports.pdf.risk_analysis.subtitle",
    "Fine-Kinney veya 5×5 metoduna göre denetim çıktısı.",
    "Inspection output using the Fine-Kinney or 5×5 method.",
  ],
  ["reports.pdf.standard.header", "SAHA TARAMA RAPORU", "SITE INSPECTION REPORT"],
  [
    "reports.pdf.risk_analysis.header",
    "İŞ GÜVENLİĞİ RİSK ANALİZİ",
    "WORKPLACE SAFETY RISK ASSESSMENT",
  ],
  ["reports.pdf.finding_details.header", "BULGU DETAYLARI", "FINDING DETAILS"],
  ["reports.pdf.risk_table.header", "RİSK ANALİZİ TABLOSU", "RISK ASSESSMENT TABLE"],
];

const ONBOARDING_SEEDS = [
  [
    "onboarding.pain.report_writing",
    "Saatlerce süren rapor yazımı.",
    "Hours spent writing reports.",
  ],
  [
    "onboarding.pain.scattered_material",
    "Dağınık fotoğraflar ve notlar.",
    "Scattered photos and notes.",
  ],
  [
    "onboarding.pain.late_assessments",
    "Geç teslim edilen değerlendirmeler.",
    "Late assessments.",
  ],
  ["onboarding.pain.mirror.prefix", "Bunu ", "We will change this "],
  ["onboarding.pain.mirror.emphasis", "birlikte", "together"],
  ["onboarding.pain.mirror.suffix", " değiştireceğiz.", "."],
];

const ANALYSIS_SEEDS = [
  [
    "analysis.analysis.service.output.language.contract.failed",
    "Analiz, seçilen çıktı diliyle güvenli biçimde tamamlanamadı. Lütfen tekrar dene.",
    "The analysis could not be completed safely in the selected output language. Please try again.",
  ],
  ["analysis.photo_tray.add_photo", "Fotoğraf ekle", "Add photo"],
  [
    "analysis.photo_tray.continue_to_analysis",
    "Analize geç",
    "Continue to analysis",
  ],
  [
    "analysis.history.historical_analysis",
    "Geçmiş analiz",
    "Historical analysis",
  ],
];

const PLURAL_SEEDS = [
  [
    "Analysis",
    "analysis.count.findings",
    { one: "%lld bulgu", other: "%lld bulgu" },
    { one: "%lld finding", other: "%lld findings" },
  ],
  [
    "Analysis",
    "analysis.count.photos_added",
    { one: "%lld fotoğraf eklendi", other: "%lld fotoğraf eklendi" },
    { one: "%lld photo added", other: "%lld photos added" },
  ],
  [
    "Analysis",
    "analysis.count.analysis_photos",
    { one: "%lld analiz fotoğrafı", other: "%lld analiz fotoğrafı" },
    { one: "%lld analysis photo", other: "%lld analysis photos" },
  ],
  [
    "Analysis",
    "analysis.count.records",
    { one: "%lld kayıt", other: "%lld kayıt" },
    { one: "%lld record", other: "%lld records" },
  ],
  [
    "Reports",
    "reports.count.findings",
    { one: "%lld bulgu", other: "%lld bulgu" },
    { one: "%lld finding", other: "%lld findings" },
  ],
  [
    "Reports",
    "reports.count.files",
    { one: "%lld dosya", other: "%lld dosya" },
    { one: "%lld file", other: "%lld files" },
  ],
];

const AUTH_SEEDS = [
  ["auth.google.continue", "Google ile devam et", "Continue with Google"],
];

const PAYWALL_SEEDS = [
  [
    "paywall.plus.yearly.subtitle",
    "7 gün ücretsiz Plus, sonrasında yıllık %1$@.",
    "Try Plus free for 7 days, then %1$@ per year.",
  ],
  [
    "paywall.plus.monthly.subtitle",
    "Tüm Plus özellikleri aylık %1$@.",
    "All Plus features for %1$@ per month.",
  ],
  [
    "paywall.pro.yearly.subtitle",
    "Yıllık %1$@ ile tüm Pro özellikleri.",
    "All Pro features for %1$@ per year.",
  ],
  [
    "paywall.pro.monthly.subtitle",
    "Tüm Pro özellikleri aylık %1$@ ile.",
    "All Pro features for %1$@ per month.",
  ],
];

const LOCALIZABLE_SEEDS = [
  [
    "localizable.release.update_required",
    "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
    "A new version is available. Please update the app to continue.",
  ],
  ["localizable.history.status.open", "Açık", "Open"],
  ["localizable.history.status.reviewed", "İncelendi", "Reviewed"],
  ["localizable.history.status.closed", "Kapandı", "Closed"],
  ["localizable.history.filter.all", "Tümü", "All"],
  ["localizable.history.filter.this_week", "Bu hafta", "This week"],
  ["localizable.history.filter.critical", "Kritik", "Critical"],
  ["localizable.history.filter.ppe", "KKD", "PPE"],
  ["localizable.history.filter.general", "Genel", "General"],
];

const LEGAL_SEEDS = [
  [
    "legal.acceptance.en.prefix",
    "By signing up or signing in, you accept the ",
    "By signing up or signing in, you accept the ",
  ],
  [
    "legal.acceptance.en.privacy_joiner",
    ", acknowledge the ",
    ", acknowledge the ",
  ],
  [
    "legal.acceptance.en.consent_joiner",
    " and the ",
    " and the ",
  ],
  [
    "legal.acceptance.en.ai_notice",
    "AI and Data Processing Notice",
    "AI and Data Processing Notice",
  ],
  ["legal.acceptance.en.suffix", ".", "."],
  ["legal.document.kvkk.short_title", "KVKK", "Privacy"],
  ["legal.document.consent.short_title", "Rıza", "Consent"],
  ["legal.document.terms.short_title", "Koşullar", "Terms"],
  ["legal.document.privacy.short_title", "Gizlilik", "Privacy"],
  ["legal.document.kvkk.title", "KVKK Aydınlatma Metni", "Privacy Notice"],
  ["legal.document.consent.title", "Açık Rıza Beyanı", "Explicit Consent"],
  ["legal.document.terms.title", "Kullanım Koşulları", "Terms of Use"],
  ["legal.document.privacy.title", "Gizlilik Politikası", "Privacy Policy"],
  ["legal.update.info.title", "Yasal metinler güncellendi", "Legal documents updated"],
  ["legal.update.material.title", "Şartlarımız güncellendi", "Our terms have been updated"],
  ["legal.update.consent.title", "Açık rıza metni güncellendi", "Consent notice updated"],
  [
    "legal.update.privacy.title",
    "Gizlilik politikamız güncellendi",
    "Our Privacy Policy has been updated",
  ],
  [
    "legal.update.privacy.message",
    "Güncel gizlilik politikasını inceleyerek uygulamayı kullanmaya devam edebilirsin.",
    "Review the updated Privacy Policy before continuing to use the app.",
  ],
  [
    "legal.update.info.message",
    "Dilersen güncel metinleri uygulama içinde inceleyebilirsin.",
    "You can review the updated documents in the app.",
  ],
  [
    "legal.update.material.message",
    "Uygulamayı kullanmaya devam ederek güncel şartları kabul etmiş olursun.",
    "Continuing to use the app means you accept the updated terms.",
  ],
  [
    "legal.update.consent.message",
    "Yeni açık rıza kapsamını uygulama içinde inceleyip ayrıca onaylayabilirsin.",
    "Review the updated consent scope in the app before making a separate choice.",
  ],
  ["legal.info.title", "Yasal Bilgilendirme", "Legal information"],
  [
    "legal.document.show.accessibility",
    "%@ belgesini göster",
    "Show the %@ document",
  ],
  [
    "legal.english_unavailable.title",
    "İngilizce yasal metinler henüz kullanıma hazır değil",
    "English legal documents are not yet available",
  ],
  [
    "legal.english_unavailable.message",
    "İngilizce Kullanım Koşulları ve Gizlilik Politikası hukuk ve dil incelemesi tamamlanana kadar bu sürümde yayımlanmaz.",
    "Terms of Use and the Privacy Policy will remain unavailable in English until legal and language review is complete.",
  ],
  [
    "legal.english_unavailable.action",
    "Türkçe metinleri görüntülemek için uygulama dilini iOS Ayarları’ndan Türkçe seçebilirsin.",
    "To view the current Turkish documents, choose Turkish as the app language in iOS Settings.",
  ],
];

const SAFETY_SEEDS = [
  [
    "safety.profile.title",
    "İş güvenliği terminolojini seç",
    "Choose your safety terminology",
  ],
  [
    "safety.profile.body",
    "Çalışmanda kullanılan terminolojiyi seç. Bu seçim analiz ve rapor ifadelerini değiştirir; yasal uyumluluğu belgelemez.",
    "Select the terminology used for your work. This changes wording in analyses and reports; it does not certify legal compliance.",
  ],
  [
    "safety.profile.footer",
    "Gelecekteki analizler için bu seçimi Profil’den değiştirebilirsin.",
    "You can change this for future analyses in Profile.",
  ],
  ["safety.profile.tr.title", "Türkiye", "Türkiye"],
  [
    "safety.profile.tr.subtitle",
    "Mevcut Türkiye İSG terminolojisi ve ürün davranışı.",
    "Current Türkiye workplace-safety terminology and product behaviour.",
  ],
  ["safety.profile.intl.title", "Uluslararası", "International"],
  [
    "safety.profile.intl.subtitle",
    "Bölgeler arası çalışmalar için tarafsız iş güvenliği terminolojisi.",
    "Neutral workplace-safety terminology for work across regions.",
  ],
  ["safety.profile.gb.title", "Birleşik Krallık", "UK"],
  [
    "safety.profile.gb.subtitle",
    "Yasal uyumluluk iddiası içermeyen Birleşik Krallık iş sağlığı ve güvenliği terminolojisi.",
    "UK health and safety terminology. This does not certify compliance.",
  ],
  ["safety.profile.us.title", "Amerika Birleşik Devletleri", "US"],
  [
    "safety.profile.us.subtitle",
    "Yasal uyumluluk iddiası içermeyen ABD iş güvenliği terminolojisi.",
    "US occupational safety and health terminology. This does not certify compliance.",
  ],
  ["safety.profile.au.title", "Avustralya", "AU"],
  [
    "safety.profile.au.subtitle",
    "Yasal uyumluluk iddiası içermeyen Avustralya iş sağlığı ve güvenliği terminolojisi.",
    "Australian WHS terminology. This does not certify compliance.",
  ],
  ["safety.profile.ca.title", "Kanada", "CA"],
  [
    "safety.profile.ca.subtitle",
    "Kanada çapında uyumluluk iddiası içermeyen iş sağlığı ve güvenliği terminolojisi.",
    "Canadian OHS terminology. This does not certify Canada-wide compliance.",
  ],
];

const PROFESSIONAL_PROGRESS_SEEDS = [
  ["progress.accessibility.earned", "kazanıldı", "earned"],
  ["progress.accessibility.not_earned", "henüz kazanılmadı", "not yet earned"],
  ["progress.accessibility.title_status", "%1$@, %2$@", "%1$@, %2$@"],
];

const CATALOG_OVERRIDES = [
  [
    "Analysis",
    "analysis.finding.6331.4857.csgb.yuksekte.calisma.eaa40dbd",
    "6331/4857 · ÇSGB Yüksekte Çalışma",
    "Türkiye-only regulatory reference",
  ],
  ["Analysis", "analysis.analysis.canvas.kkd.b445e9f1", "KKD", "PPE"],
  ["Analysis", "analysis.result.view.5x5.matris.9e1e0b52", "5x5 Matris", "5×5 Matrix"],
  [
    "Analysis",
    "analysis.result.view.o.1.f.2.s.3.846b0b14",
    "O %1$@ × F %2$@ × Ş %3$@",
    "P %1$@ × F %2$@ × S %3$@",
  ],
  [
    "Analysis",
    "analysis.result.view.o.1.s.2.e16b73b6",
    "O %1$@ × Ş %2$@",
    "P %1$@ × S %2$@",
  ],
  ["Analysis", "analysis.result.view.pdf.rapor.09e48cb8", "PDF rapor", "PDF report"],
  ["Analysis", "analysis.result.view.r.o.f.s.07ef9b6f", "R = O × F × Ş", "R = P × F × S"],
  ["Analysis", "analysis.result.view.r.o.s.cb33905c", "R = O × Ş", "R = P × S"],
  ["Analysis", "analysis.result.view.sil.18b17908", "Sil", "Delete"],
  ["Analysis", "analysis.result.view.sil.aa01ae25", "Sil", "Delete"],
  ["Analysis", "analysis.risk.detail.view.o.f.s.d293e41e", "O × F × Ş", "P × F × S"],
  ["Localizable", "localizable.analyzing.view.kkd.c193486a", "KKD", "PPE"],
  ["Localizable", "localizable.profile.view.dil.5398169b", "Dil", "Language"],
  ["Localizable", "localizable.profile.view.dil.e163b631", "Dil", "Language"],
  ["Localizable", "localizable.company.picker.sheet.kaydediliyor.ff126ef4", "Kaydediliyor...", "Saving..."],
  ["Localizable", "localizable.company.picker.sheet.varsayilan.sorumlu.db86c4e1", "Varsayılan sorumlu", "Default responsible person"],
  ["Localizable", "localizable.profile.view.apple.40533c0b", "Apple", "Apple"],
  ["Localizable", "localizable.profile.view.hesap.c8de18a3", "Hesap", "Account"],
  ["Localizable", "localizable.profile.view.kaydediliyor.7948588e", "Kaydediliyor...", "Saving..."],
  ["Localizable", "localizable.profile.view.telefon.6c1f670a", "Telefon", "Phone"],
  ["Localizable", "localizable.support.contact.sheet.ek.c7e0a951", "Ek", "Attachment"],
  ["Localizable", "localizable.support.contact.sheet.kayitli.degil.076de3b1", "Kayıtlı değil", "Not provided"],
  ["Localizable", "localizable.support.contact.sheet.kayitli.degil.d9c4334d", "Kayıtlı değil", "Not provided"],
  ["Localizable", "localizable.support.contact.sheet.kayitli.degil.f107e88e", "Kayıtlı değil", "Not provided"],
  ["Localizable", "localizable.rdbutton.pdf.rapor.7aded467", "PDF Rapor", "PDF Report"],
  ["Localizable", "localizable.rdbutton.sil.683f0e22", "Sil", "Delete"],
  ["Localizable", "localizable.rdcard.saha.da63570e", "Saha", "Site"],
  [
    "Localizable",
    "localizable.rdplan.upsell.card.fine.kinney.5x5.matris.1e70bf1b",
    "Fine-Kinney + 5x5 matris",
    "Fine-Kinney + 5×5 matrix",
  ],
  [
    "Onboarding",
    "onboarding.obpaywall.view.fine.kinney.5.5.l.s.4ac3cf81",
    "Fine-Kinney · 5×5 · L×Ş",
    "Fine-Kinney · 5×5 · L×S",
  ],
  ["Onboarding", "onboarding.obsplash.view.12.tehlike.5f66303d", "12 Tehlike", "12 hazards"],
  ["Onboarding", "onboarding.obsplash.view.atla.d0c256d2", "Atla", "Skip"],
  [
    "Onboarding",
    "onboarding.obsplash.view.bilgisi.hazirlaniyor.6b055b9b",
    "bilgisi hazırlanıyor…",
    "are being prepared…",
  ],
  [
    "Onboarding",
    "onboarding.obsplash.view.fotograf.cek.yapay.zeka.tehlikeleri.otomatik.tes.2173ee63",
    "Fotoğraf çek; yapay zekâ tehlikeleri otomatik tespit etsin, raporun anında oluşsun ve tek tıklama ile paylaş.",
    "Take a photo. AI detects hazards, creates a report, and makes it ready to share.",
  ],
  [
    "Onboarding",
    "onboarding.obsplash.view.kok.neden.ve.mevzuat.22ab9903",
    "Kök Neden ve Mevzuat",
    "Root causes and references",
  ],
  [
    "Onboarding",
    "onboarding.obsplash.view.profesyonel.isg.asistani.138cfae2",
    "Profesyonel İSG Asistanı",
    "Professional Safety Assistant",
  ],
  ["Onboarding", "onboarding.onboarding.view.atla.e25539b1", "Atla", "Skip"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.pdf.excel.rapor.95bfded2", "PDF/Excel Rapor", "PDF/Excel Report"],
  [
    "Onboarding",
    "onboarding.obtimeline.paywall.view.risk.analizi.fine.kinney.ve.5.5.b43a3cfb",
    "Risk Analizi (Fine-Kinney ve 5*5)",
    "Risk assessment (Fine-Kinney and 5×5)",
  ],
  ["Onboarding", "onboarding.onboarding.view.pdf.excel.rapor.adbe8847", "PDF & Excel rapor", "PDF & Excel report"],
  ["Onboarding", "onboarding.onboarding.view.r.o.f.s.c031ebce", "R = O × F × Ş", "R = P × F × S"],
  ["Onboarding", "onboarding.onboarding.view.r.o.s.0fc90694", "R = O × Ş", "R = P × S"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.fiyat.yukleniyor.23a52d93", "Fiyat yükleniyor...", "Loading price..."],
  ["Onboarding", "onboarding.onboarding.view.s.1a3e180d", "Ş", "S"],
  ["Onboarding", "onboarding.onboarding.view.s.89da2339", "Ş", "S"],
  ["Paywall", "paywall.in.app.paywall.view.denemenizin.bittigine.dair.hatirlatma.alin.6eea147c", "Denemenizin bittiğine dair hatırlatma alın.", "Get a reminder before your trial ends."],
  ["Paywall", "paywall.in.app.paywall.view.yillik.1.odeme.alinir.10a000c7", "Yıllık %1$@ ödeme alınır.", "Your annual plan is charged at %1$@."],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.badges.view.5.alan.a1a0b74f",
    "5 Alan",
    "5 Areas",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.competency.map.view.alan.dffbc276",
    "alan",
    "area",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.home.card.saha.fd1acd53",
    "Saha",
    "Site",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.home.card.usta.0e4c515a",
    "Usta",
    "Master",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.her.yeni.rapor.bir.kez.puan.verir.e2c8fe15",
    "Her yeni rapor bir kez puan verir.",
    "Each new report earns points once.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.standart.rapor.puanina.eklenir.2fbe2c93",
    "Standart rapor puanına eklenir.",
    "Added to the standard report score.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.tehlikeyi.gorunur.kildiginda.kazanilir.8c66d951",
    "Tehlikeyi görünür kıldığında kazanılır.",
    "Earned when you identify a hazard.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.standart.disi.detayli.analizlerde.isler.2aa4f581",
    "Standart dışı detaylı analizlerde işler.",
    "Applies to non-standard detailed analyses.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.her.alan.icin.yalnizca.ilk.kez.verilir.c2b98db3",
    "Her alan için yalnızca ilk kez verilir.",
    "Awarded only the first time for each competency area.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.haftada.bir.kez.takip.disiplini.bonusu.e4efaa1c",
    "Haftada bir kez takip disiplini bonusu.",
    "Once per week as a consistency bonus.",
  ],
  [
    "ProfessionalProgress",
    "professionalprogress.professional.progress.titles.sheet.risk.analizi.pdf.xlsx.910caae2",
    "Risk analizi PDF/XLSX",
    "Risk assessment PDF/XLSX",
  ],
  [
    "Reports",
    "reports.report.view.1.2.rapor.92b1ec5c",
    "%1$@, %2$@ rapor",
    "%1$@, %2$@ report",
  ],
  [
    "Reports",
    "reports.report.view.1.2.gosteriliyor.dd210f2b",
    "%1$@/%2$@ gösteriliyor",
    "%1$@/%2$@ shown",
  ],
  [
    "Reports",
    "reports.report.view.1.bulgu.raporun.devaminda.d7f885e4",
    "+ %1$@ bulgu raporun devamında",
    "+ %1$@ more findings continue in the report",
  ],
  ["Reports", "reports.report.view.risk.3424dae6", "RİSK", "RISK"],
  ["Reports", "reports.report.view.risk.495b7f20", "RİSK", "RISK"],
  [
    "Analysis",
    "analysis.finding.o.1.f.2.s.3.d1f790bc",
    "O %1$@ × F %2$@ × Ş %3$@",
    "P %1$@ × F %2$@ × S %3$@",
  ],
  [
    "Analysis",
    "analysis.finding.o.1.s.2.cd44f90d",
    "O %1$@ × Ş %2$@",
    "P %1$@ × S %2$@",
  ],
  ["Analysis", "analysis.finding.o.f.s.1a128241", "O × F × Ş", "P × F × S"],
  [
    "Analysis",
    "analysis.result.view.o.1.f.2.s.3.f40a6d85",
    "O %1$@ × F %2$@ × Ş %3$@",
    "P %1$@ × F %2$@ × S %3$@",
  ],
  [
    "Analysis",
    "analysis.result.view.o.1.s.2.91be1266",
    "O %1$@ × Ş %2$@",
    "P %1$@ × S %2$@",
  ],
];

// Values already shipped in Build 79. These lock the approved Turkish copy and
// the previously corrected English copy against stale machine-draft entries.
const CATALOG_BUILD79_PRESERVATION_OVERRIDES = [
  ["Analysis", "analysis.finding.tolerans.disi.d50498c6", "Tolerans dışı", "Intolerable"],
  ["Analysis", "analysis.result.view.en.yuksek.risk.3729eaec", "en yüksek risk", "highest risk score"],
  ["Analysis", "analysis.finding.calismayi.derhal.durdur.uygun.emniyet.kemeri.ve..7dc9e5cf", "Çalışmayı derhal durdur. Uygun emniyet kemeri ve çift kancalı lanyard temin et. Sertifikalı sabitleme noktası belirle.", "Stop the work immediately. Provide a suitable fall-arrest harness and twin-leg lanyard. Identify a certified anchor point."],
  ["Analysis", "analysis.result.view.tolerans.disi.durum.56bc92b4", "Tolerans dışı durum", "Intolerable"],
  ["Analysis", "analysis.home.view.yukselt.679408d0", "Yükselt", "Upgrade"],
  ["Analysis", "analysis.result.view.ai.guveni.1.39308927", "AI güveni %%%1$@", "AI confidence %1$@%%"],
  ["Analysis", "analysis.finding.yuksekte.calisma.izin.formuna.ankraj.ve.kkd.kont.232b38e3", "Yüksekte çalışma izin formuna ankraj ve KKD kontrol adımı ekle; vardiya başlangıcında saha sorumlusu doğrulaması iste.", "Add anchorage and PPE checks to the work-at-height permit, with supervisor verification at the start of each shift."],
  ["Analysis", "analysis.result.view.yukselt.069b8203", "Yükselt", "Upgrade"],
  ["Analysis", "analysis.result.view.pro.ile.daha.yuksek.kapasite.ve.gelismis.analiz.a07cb655", "Pro ile daha yüksek kapasite ve gelişmiş analiz", "Unlock higher limits and advanced analysis with Pro"],
  ["Analysis", "analysis.finding.yuksekte.calismada.emniyet.kemeri.kullanilmiyor.d3cc6656", "Yüksekte çalışmada emniyet kemeri kullanılmıyor", "Elevated work lacks a visible fall-arrest system"],
  ["Analysis", "analysis.home.view.genel.ui.test.a58b1874", "Genel · UI Test", "General · UI Test"],
  ["Analysis", "analysis.finding.calismayi.derhal.durdur.uygun.emniyet.kemeri.ve..24b118f1", "Çalışmayı derhal durdur. Uygun emniyet kemeri ve çift kancalı lanyard temin et. Sertifikalı sabitleme noktası belirle.", "Stop the work immediately. Provide a suitable fall-arrest harness and twin-leg lanyard. Identify a certified anchor point."],
  ["Analysis", "analysis.finding.5.5.l.tipi.f434fdf5", "5×5 L-Tipi", "5×5 L-Type"],
  ["Analysis", "analysis.result.view.excel.tablo.eb8142ee", "Excel tablo", "Excel spreadsheet"],
  ["Analysis", "analysis.finding.tolerans.disi.3f8f17ca", "Tolerans dışı", "Intolerable"],
  ["Analysis", "analysis.result.view.pro.ai.guveni.1.8a8860ad", "Pro AI güveni %%%1$@", "Pro AI confidence %1$@%%"],
  ["Analysis", "analysis.risk.detail.view.ai.guveni.1.3c5aa13f", "AI güveni %%%1$@", "AI confidence %1$@%%"],
  ["Analysis", "analysis.finding.isci.3.metre.uzerinde.calisiyor.parasut.tipi.emn.3ef9d38c", "İşçi 3 metre üzerinde çalışıyor; paraşüt tipi emniyet kemeri ve sabitleme noktası görünmüyor.", "A worker is more than 3 m above ground; no fall-arrest harness or anchor point is visible."],
  ["Analysis", "analysis.finding.yuksekte.calisma.alaninda.toplu.koruma.ve.ankraj.4ca66593", "Yüksekte çalışma alanında toplu koruma ve ankraj planı eksik.", "The work-at-height area lacks a collective protection and anchorage plan."],
  ["Analysis", "analysis.analysis.sector.son.36d6b5b2", "Son", "Last"],
  ["Analysis", "analysis.main.tab.view.yukselt.a7a8cbd7", "Yükselt", "Upgrade"],
  ["Analysis", "analysis.risk.detail.view.5.5.l.tipi.3cb7030d", "5×5 L-Tipi", "5×5 L-Type"],
  ["Analysis", "analysis.home.view.excel.tablo.84e74224", "Excel tablo", "Excel spreadsheet"],
  ["Legal", "legal.english_unavailable.message", "İngilizce Kullanım Koşulları ve Gizlilik Politikası hukuk ve dil incelemesi tamamlanana kadar bu sürümde yayımlanmaz.", "English Terms, Privacy and AI/Data Processing notices are awaiting legal approval. Sign-in and purchases remain unavailable in English until approval."],
  ["Localizable", "localizable.profile.view.ios.ayarlari.nda.uygulama.dilini.ac.db4cf363", "iOS Ayarları'nda uygulama dilini aç", "Manage the app language in iOS Settings"],
  ["Localizable", "localizable.rdcolor.yuk.d70f8614", "YÜK", "HIGH"],
  ["Localizable", "localizable.app.state.her.zaman.koyu.tema.aa37f82a", "Her zaman koyu tema.", "Always use the dark theme."],
  ["Localizable", "localizable.profile.view.ios.ayarlari.nda.uygulama.dilini.ac.10562d1d", "iOS Ayarları'nda uygulama dilini aç", "Manage the app language in iOS Settings"],
  ["Localizable", "localizable.annotation.ok.3c52bae8", "Ok", "Arrow"],
  ["Localizable", "localizable.app.state.her.zaman.acik.tema.04d1e49b", "Her zaman açık tema.", "Always use the light theme."],
  ["Localizable", "localizable.app.state.karanlik.e3c9f637", "Karanlık", "Dark"],
  ["Localizable", "localizable.rdupgrade.cta.yukselt.72b0d588", "Yükselt", "Upgrade"],
  ["Localizable", "localizable.profile.view.tema.9fd5ac1b", "Tema", "Appearance"],
  ["Localizable", "localizable.app.state.aydinlik.af1a2800", "Aydınlık", "Light"],
  ["Localizable", "localizable.profile.view.tema.80e8d059", "Tema", "Appearance"],
  ["Localizable", "localizable.rdcolor.dus.3e9b9792", "DÜŞ", "LOW"],
  ["Onboarding", "onboarding.obnotification.permission.view.simdi.odeme.alinmayacak.39364ad1", "Bu adımda satın alma yapılmaz", "No purchase is made at this step"],
  ["Onboarding", "onboarding.obtrial.invite.view.uygulamayi.faee4cf2", "Ücretsiz ", "Free "],
  ["Onboarding", "onboarding.obpaywall.view.ucretsiz.denemeyi.baslat.a308f2c3", "Devam et", "Continue"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.ucretsiz.denemeyi.baslat.dc125184", "Devam Et", "Continue"],
  ["Onboarding", "onboarding.obtrial.invite.view.su.an.odeme.yok.5ab25673", "Herhangi bir ücret alınmaz.", "You won't be charged."],
  ["Onboarding", "onboarding.obtrial.invite.view.uygulamayi.ucretsiz.denemeni.istiyoruz.2cbb5618", "Ücretsiz denemenizi istiyoruz", "We want you to try it for free"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.denemen.bitmeden.sana.hatirlatma.gondeririz.cc0144c2", "Deneme süresinin 5. gününde size hatırlatma gönderilir.", "We will send you a reminder on the fifth day of your trial."],
  ["Onboarding", "onboarding.obtrial.invite.view.denemeni.istiyoruz.59a5e56c", "birlikte seçelim", "together"],
  ["Onboarding", "onboarding.obplan.summary.view.planini.hesabina.kaydedelim.7.gun.ucretsiz.denem.ae67c90f", "Planını hesabına kaydedelim; fiyat ve uygun teklifleri App Store'da doğrula.", "Save your plan to your account, then verify prices and eligible offers in the App Store."],
  ["Onboarding", "onboarding.obtimeline.paywall.view.ucretsiz.deneme.nasil.calisir.030529b1", "Yıllık Plan Nasıl Çalışır", "How the Annual Plan Works"],
  ["Onboarding", "onboarding.obpaywall.view.planin.hazir.7.gun.ucretsiz.dene.77c5ffa7", "Fiyat ve uygun teklifler App Store'da doğrulanır", "Price and eligible offers are verified in the App Store"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.7.gun.ucretsiz.sonra.1.2.55ea6bc2", "Yıllık %1$@ (%2$@) · varsa teklif App Store'da uygulanır", "%1$@ per year (%2$@) · eligible offers are applied by the App Store"],
  ["Onboarding", "onboarding.obtrial.invite.view.ucretsiz.84c94af9", "Denemenizi İstiyoruz", "Trial"],
  ["Onboarding", "onboarding.obpaywall.view.mevzuat.referanslari.ile.927c6758", "Mevzuat referansları ile", "Structured safety review"],
  ["Onboarding", "onboarding.obnotification.permission.view.deneme.suresi.ve.uygulama.hatirlatmalari.icin.bi.8fffda58", "Plan, teklif ve uygulama hatırlatmaları için bildirimleri aç.", "Turn on notifications for plan, offer and app reminders."],
  ["Onboarding", "onboarding.obtimeline.paywall.view.7.gun.5bf94fa7", "Hesabınız Aktif", "Your Account Is Active"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.devam.edersen.yillik.plan.baslar.istedigin.zaman.68e836a8", "Deneme süresi sonunda hesabınız Plus olarak aktiflenir.", "Your account becomes active on Plus when the trial period ends."],
  ["Onboarding", "onboarding.obtimeline.paywall.view.7.gun.ucretsiz.sonra.1.1c216e89", "Yıllık %1$@ · varsa teklif App Store'da uygulanır", "%1$@ per year · eligible offers are applied by the App Store"],
  ["Onboarding", "onboarding.obnotification.permission.view.ucretsiz.denemeniz.bitmeden.once.size.hatirlatac.21ab39bb", "Deneme süren bitmeden sana haber verelim", "We'll remind you before your trial ends"],
  ["Onboarding", "onboarding.obnotification.permission.view.ucretsiz.devam.et.c00788c5", "Bildirimleri Aç", "Turn On Notifications"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.simdilik.ucretsiz.devam.et.b59d7d99", "Ücretsiz Devam Et", "Continue for Free"],
  ["Onboarding", "onboarding.obtrial.invite.view.0.00.ye.dene.c364ad31", "0.00 TL'ye dene", "Try for free"],
  ["Onboarding", "onboarding.obpaywall.view.ilk.7.gun.ucretsiz.fiyat.app.store.uzerinden.yuk.7d822ee9", "Fiyat ve uygun teklifler App Store'da gösterilir", "Price and eligible offers are shown in the App Store"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.plus.ozellikleri.acilir.ucret.alinmaz.c93f0f8d", "Yıllık Plus özelliklerini ve App Store fiyatını incele.", "Review annual Plus features and the App Store price."],
  ["Onboarding", "onboarding.obpaywall.view.ilk.7.gun.ucretsiz.sonra.1.yil.92cf2208", "Yıllık %1$@ · varsa teklif App Store'da uygulanır", "%1$@ per year · eligible offers are applied by the App Store"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.5.gun.a1306735", "Hatırlatma Gönderilir", "Reminder Sent"],
  ["Paywall", "paywall.in.app.paywall.view.yillik.1.odeme.alinir.10a000c7", "Yıllık fiyat %1$@; App Store şartları geçerlidir.", "The annual price is %1$@; App Store terms apply."],
  ["Paywall", "paywall.in.app.paywall.view.7.gun.ucretsiz.sonra.yillik.1.7e510489", "Yıllık %1$@. Varsa uygun teklif App Store'da uygulanır.", "%1$@ per year. Eligible offers are applied by the App Store."],
  ["Paywall", "paywall.in.app.paywall.view.ucretsiz.denemeyi.baslat.8b61966d", "Devam et", "Continue"],
  ["Paywall", "paywall.plus.yearly.subtitle", "Yıllık Plus %1$@. Varsa uygun teklif App Store'da uygulanır.", "Annual Plus is %1$@. Eligible offers are applied by the App Store."],
  ["Paywall", "paywall.in.app.paywall.view.7.gun.ec8fc3fe", "Yıllık plan", "Annual plan"],
  ["Paywall", "paywall.in.app.paywall.view.7.gun.ucretsiz.plus.sonrasinda.yillik.30411629", "Yıllık Plus · varsa teklif App Store'da uygulanır", "Annual Plus · eligible offers apply in the App Store"],
  ["Paywall", "paywall.in.app.paywall.view.su.an.odeme.yok.52dc209d", "Fiyat ve uygun teklifler App Store'da doğrulanır", "Price and eligible offers are verified in the App Store"],
  ["Paywall", "paywall.in.app.paywall.view.5.gun.d7dc9e6f", "App Store", "App Store"],
  ["Paywall", "paywall.in.app.paywall.view.denemenizin.bittigine.dair.hatirlatma.alin.6eea147c", "Fiyatı ve varsa uygun teklifi App Store onay ekranında doğrulayın.", "Verify the price and any eligible offer on the App Store confirmation screen."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.home.card.str.4e8cc96c", "Str.", "Str."],
  ["Reports", "reports.report.view.test.aktif.firma.5d72481d", "Aktif Test Firması", "Active Test Company"],
  ["Reports", "reports.report.view.excel.tablo.6d31e397", "Excel tablo", "Excel spreadsheet"],
];

const CATALOG_ENGLISH_QUALITY_OVERRIDES = [
  ["Analysis", "analysis.analysis.sector.picker.view.devam.et.04ec7e11", "Continue"],
  ["Analysis", "analysis.analysis.sector.picker.view.kapat.c36ab4f2", "Close"],
  ["Analysis", "analysis.canvas.sheet.kapat.3bb9ffb8", "Close"],
  ["Analysis", "analysis.home.view.kapat.349873ed", "Close"],
  ["Analysis", "analysis.result.view.bulguyu.sil.c2bef2d5", "Delete finding"],
  ["Analysis", "analysis.analysis.canvas.baret.gozluk.eldiven.emniyet.kemeri.ve.yelek.kon.62e26e79", "Focus on hard hats, safety glasses, gloves, safety harnesses and high-visibility vests."],
  ["Analysis", "analysis.analysis.canvas.dusme.korkuluk.iskele.emniyet.kemeri.yasam.hatti.a5d68fd8", "Focus on falls, guardrails, scaffolding, safety harnesses, lifelines and work-at-height risks."],
  ["Analysis", "analysis.analysis.canvas.standart.saha.taramasi.yap.ana.risk.alanlarini.d.bf94a9b4", "Perform a standard site inspection and assess the main risk areas evenly."],
  ["Analysis", "analysis.analysis.sector.insaat.d202ed82", "Construction"],
  ["Analysis", "analysis.analysis.sector.kimya.laboratuvar.ee199171", "Chemical / Laboratory"],
  ["Analysis", "analysis.analysis.sector.maden.87eb5434", "Mining"],
  ["Analysis", "analysis.analysis.sector.saglik.hastane.8ba8ae32", "Healthcare / Hospital"],
  ["Analysis", "analysis.analysis.sector.otel.konaklama.ee928560", "Hotel / Hospitality"],
  ["Analysis", "analysis.analysis.sector.son.kullanilan.e4c2b96c", "Recently used"],
  ["Analysis", "analysis.analysis.service.ai.degerlendiriyor.6fb12004", "AI is assessing"],
  ["Analysis", "analysis.analysis.service.ai.servisi.yogun.1ad27216", "AI service is busy"],
  ["Analysis", "analysis.analysis.service.alternatif.model.deneniyor.4cae5391", "Trying an alternative model"],
  ["Analysis", "analysis.analysis.service.analiz.hata.durumu.guncellenirken.baglanti.zaman.37c7975a", "The connection timed out while updating the analysis error status."],
  ["Analysis", "analysis.analysis.service.analiz.kaydi.aciliyor.63173bd6", "Creating analysis record"],
  ["Analysis", "analysis.analysis.service.analiz.kotan.doldu.cf5ccd2e", "You have reached your analysis limit."],
  ["Analysis", "analysis.analysis.service.analiz.sonucu.hazir.ama.bulgular.yuklenemedi.lut.d92d4f00", "The analysis result is ready, but the findings could not be loaded. Please try opening it again from Analysis History."],
  ["Analysis", "analysis.analysis.service.analiz.tamamlandi.bulgular.guvenli.sekilde.yukle.290e3c64", "Analysis complete. Loading findings securely."],
  ["Analysis", "analysis.analysis.service.analizler.silinemedi.destek.kodu.1.4c948c01", "Analyses could not be deleted. Support code: %1$@"],
  ["Analysis", "analysis.analysis.service.depo.veya.sunucu.baglantisi.koptu.ayni.analizi.t.6d3ebe27", "The connection to storage or the server was interrupted. We are retrying the same analysis."],
  ["Analysis", "analysis.analysis.service.fotograf.paketi.cok.buyuk.kaliteyi.korumak.icin..410a35fa", "The photo package is too large. To maintain quality, please try again with fewer photos."],
  ["Analysis", "analysis.analysis.service.fotograf.paketi.cok.buyuk.lutfen.daha.az.fotogra.f9d64c24", "The photo package is too large. Please try fewer photos or lower-resolution images."],
  ["Analysis", "analysis.analysis.service.fotograflar.guvenli.depoya.kaydediliyor.52cadbe9", "Saving photos to secure storage."],
  ["Analysis", "analysis.analysis.service.fotograflar.yukleniyor.01c07e4e", "Uploading photos"],
  ["Analysis", "analysis.analysis.service.gemini.modeli.su.anda.yogun.biraz.sonra.tekrar.d.a4d34a5c", "The Gemini model is busy right now. Please try again shortly."],
  ["Analysis", "analysis.analysis.service.model.yanit.vermedi.ayni.analizi.otomatik.tekrar.30fea459", "The model did not respond. We are automatically retrying the same analysis."],
  ["Analysis", "analysis.analysis.service.yukleme.hatasi.1.76bb6558", "Upload error: %1$@"],
  ["Analysis", "analysis.finding.cevresel.duzen.75f97bc9", "Housekeeping"],
  ["Analysis", "analysis.finding.gozetim.altinda.izle.50e72c41", "Monitor under supervision"],
  ["Analysis", "analysis.finding.gozetim.altinda.izle.8a959e54", "Monitor under supervision"],
  ["Analysis", "analysis.finding.izleme.yeterli.9d551384", "Monitoring is sufficient"],
  ["Analysis", "analysis.finding.izleme.yeterli.a9ae63e4", "Monitoring is sufficient"],
  ["Analysis", "analysis.finding.kisa.vadede.onlem.8afb5ba2", "Short-term action"],
  ["Analysis", "analysis.finding.o.s.e9e53958", "P × S"],
  ["Analysis", "analysis.finding.plan.dahilinde.onlem.9e4f0c32", "Action within the plan"],
  ["Analysis", "analysis.home.view.1.fotografi.sil.63339467", "Delete photo %1$@"],
  ["Analysis", "analysis.home.view.1.slot.kilitli.plus.veya.pro.ile.acilir.55383064", "Photo slot %1$@ is locked. Upgrade to Plus or Pro to unlock it."],
  ["Analysis", "analysis.home.view.bu.planda.en.fazla.1.fotograf.analiz.edilebilir.03d1b16d", "This plan supports up to %1$@ photos per analysis."],
  ["Analysis", "analysis.home.view.bugunku.hakkin.doldu.daha.fazlasi.icin.hesabini..2f42126c", "You have used today's analysis allowance. Upgrade your plan for more."],
  ["Analysis", "analysis.home.view.coklu.fotograf.ozelligi.icin.hesabinizi.yukselti.14166947", "Upgrade your plan to use multi-photo analysis"],
  ["Analysis", "analysis.home.view.en.fazla.1.fotograf.eklenebilir.fazla.secimler.a.dddd1ee5", "You can add up to %1$@ photos. Extra selections were ignored."],
  ["Analysis", "analysis.home.view.fotograf.limiti.03ab1131", "Photo limit"],
  ["Analysis", "analysis.home.view.fotograf.limiti.1a3eb0a6", "Photo limit"],
  ["Analysis", "analysis.home.view.fotografi.sil.caa00980", "Delete photo"],
  ["Analysis", "analysis.home.view.gunde.1.ucretsiz.analiz.hakkin.doldu.plus.veya.p.54c5c949", "You have used today's free analysis. Upgrade to Plus or Pro to continue."],
  ["Analysis", "analysis.home.view.gunde.1.ucretsiz.analiz.hakkin.hazir.904ba1c3", "Your free daily analysis is ready."],
  ["Analysis", "analysis.home.view.isaretli.alanlari.analiz.et.20a08616", "Analyze marked areas"],
  ["Analysis", "analysis.home.view.son.uygunsuzluklar.4f75d259", "Recent nonconformities"],
  ["Analysis", "analysis.home.view.standart.rapor.e78add8a", "Standard report"],
  ["Analysis", "analysis.home.view.tamam.b16fe160", "OK"],
  ["Analysis", "analysis.home.view.tarih.yok.6cb91bbc", "No date"],
  ["Analysis", "analysis.home.view.ucretsiz.analiz.hakki.795e8ebb", "Free analysis allowance"],
  ["Analysis", "analysis.home.view.ucretsiz.hak.doldu.c16fcce9", "Free analysis used"],
  ["Analysis", "analysis.main.tab.view.gunde.1.ucretsiz.analiz.hakkinizi.kullandiniz.pl.c4387499", "You have used your free daily analysis. Upgrade to Plus or Pro to continue."],
  ["Analysis", "analysis.main.tab.view.tamam.ce1433e3", "OK"],
  ["Analysis", "analysis.main.tab.view.ucretsiz.hak.doldu.02b7d919", "Free analysis used"],
  ["Analysis", "analysis.result.view.1.ta.acik.0b59a603", "Available with %1$@"],
  ["Analysis", "analysis.result.view.ad.soyad.77272696", "Full name"],
  ["Analysis", "analysis.result.view.aktif.yontem.1addeb33", "Active method"],
  ["Analysis", "analysis.result.view.analiz.fotografi.b7c69b0d", "Analysis photo"],
  ["Analysis", "analysis.result.view.analiz.gorseli.5f4a007d", "Analysis image"],
  ["Analysis", "analysis.result.view.belge.no.12de966a", "Document no."],
  ["Analysis", "analysis.result.view.bir.kez.tanimlanan.hakkini.kullandin.risk.analiz.493c362c", "You have used your one-time risk assessment allowance. Upgrade to Plus to continue using risk assessment tables."],
  ["Analysis", "analysis.result.view.bu.rapora.ozel.duzenle.731b3c76", "EDIT THIS REPORT ONLY"],
  ["Analysis", "analysis.result.view.bugunku.standart.rapor.hakkin.doldu.haklarin.yar.07b11a93", "You have used today's standard report allowance. Your allowance renews tomorrow."],
  ["Analysis", "analysis.result.view.bulgu.guncellenemedi.ed17861e", "Finding Could Not Be Updated"],
  ["Analysis", "analysis.result.view.bulgu.sil.adf79f0d", "Delete finding"],
  ["Analysis", "analysis.result.view.denetim.raporu.6422a4a1", "Audit report"],
  ["Analysis", "analysis.result.view.detayli.aciklama.pro.ile.acilir.c1b2f22a", "Detailed descriptions are available with Pro."],
  ["Analysis", "analysis.result.view.detayli.risk.hesabi.pro.ile.acilir.41cbd0fa", "Detailed risk scoring is available with Pro."],
  ["Analysis", "analysis.result.view.ek.saha.riski.9d2c5e65", "Additional site risk"],
  ["Analysis", "analysis.result.view.fine.kinney.ve.5.5.hesabi.kilitli.7d4314a9", "Fine-Kinney and 5×5 risk scoring are locked."],
  ["Analysis", "analysis.result.view.firma.bazli.rapor.plus.ve.pro.da.c873ee2c", "Company reports are available with Plus and Pro"],
  ["Analysis", "analysis.result.view.firma.eklemeden.yalnizca.bu.raporda.gorunecek.fi.26e346fa", "Without adding a company, you can enter a company name, information or logo that appears only in this report."],
  ["Analysis", "analysis.result.view.fotografi.kapat.806656a8", "Close photo"],
  ["Analysis", "analysis.result.view.hazirlayan.bilgileri.22c0d76a", "Prepared by"],
  ["Analysis", "analysis.result.view.kaynak.ve.standart.bilgisi.plus.ta.acilir.dc29b69f", "Source and standards information is available with Plus."],
  ["Analysis", "analysis.result.view.limit.doldu.8438e873", "LIMIT REACHED"],
  ["Analysis", "analysis.result.view.olasilik.1a6488cd", "Probability"],
  ["Analysis", "analysis.result.view.olasilik.cca9d55c", "Probability"],
  ["Analysis", "analysis.result.view.olasilik.d9d3070a", "PROBABILITY →"],
  ["Analysis", "analysis.result.view.rapor.firmasi.1e7269c7", "Report company"],
  ["Analysis", "analysis.result.view.secili.firma.korunur.sadece.bu.raporun.gorunen.m.8425069a", "The selected company is preserved; you can change only the visible text or logo for this report."],
  ["Analysis", "analysis.result.view.secili.firma.logosu.korunur.istersen.bu.rapor.ic.0972eb5b", "The selected company logo is preserved; you can choose a different logo for this report if needed."],
  ["Analysis", "analysis.result.view.siddet.833f9fd6", "Severity"],
  ["Analysis", "analysis.result.view.siddet.909c47dd", "Severity"],
  ["Analysis", "analysis.result.view.tamam.00f850c4", "OK"],
  ["Analysis", "analysis.result.view.tamam.408b59a7", "OK"],
  ["Analysis", "analysis.result.view.tamam.ccfef1dc", "OK"],
  ["Analysis", "analysis.result.view.tebrikler.bir.tane.risk.analizi.olusturma.hakki..3802b18c", "Congratulations! You have received one risk assessment allowance. Try it now."],
  ["Analysis", "analysis.result.view.tehlike.tespit.edilmedi.6e805751", "No hazard detected"],
  ["Analysis", "analysis.result.view.tespit.edilen.tehlikeler.risk.hesaplamasi.f60bde3e", "Detected hazards · risk scoring"],
  ["Analysis", "analysis.risk.detail.view.mevzuat.referanslari.plus.ta.aciktir.11771944", "Regulatory references are available with Plus"],
  ["Analysis", "analysis.risk.detail.view.o.s.ed0493f9", "P × S"],
  ["Analysis", "analysis.risk.detail.view.pencereyi.kapat.cde23dc0", "Close window"],

  ["Auth", "auth.auth.view.1.adresine.gonderildi.a08ac01d", "Sent to %1$@"],
  ["Auth", "auth.auth.view.dogrulama.kodu.95aeac29", "Verification code"],
  ["Auth", "auth.auth.view.mailinizi.yaziniz.0b6f66bd", "Enter your email address..."],
  ["Auth", "auth.auth.view.saha.icin.yapay.zeka.destekli.is.guvenligi.asist.73caffd7", "AI-powered workplace-safety assistant for the field"],
  ["Auth", "auth.obauth.view.1.adresine.gonderildi.c6eb060c", "Sent to %1$@"],
  ["Auth", "auth.obauth.view.dogrulama.kodu.2178a0be", "Verification code"],
  ["Auth", "auth.obauth.view.dogrulama.kodu.49151fab", "Verification code"],
  ["Auth", "auth.obauth.view.giris.yap.58e1b061", "Sign In"],
  ["Auth", "auth.obauth.view.mailinizi.yaziniz.03d0e7cf", "Enter your email address..."],

  ["Localizable", "localizable.analyzing.view.1.fotograf.79ece311", "%1$@ photo"],
  ["Localizable", "localizable.analyzing.view.ai.servisi.yogun.analiz.otomatik.tekrar.deneniyo.a2e67967", "AI service is busy; the analysis is being retried automatically."],
  ["Localizable", "localizable.analyzing.view.analiz.ediliyor.0f05c1de", "Analyzing"],
  ["Localizable", "localizable.analyzing.view.analiz.ilerleme.38fdc176", "Analysis progress"],
  ["Localizable", "localizable.analyzing.view.goruntu.kalitesi.okunuyor.3ec81981", "Checking image quality"],
  ["Localizable", "localizable.annotation.ciz.7d56ba39", "Draw"],
  ["Localizable", "localizable.annotation.daire.a28877ec", "Circle"],
  ["Localizable", "localizable.annotation.kutu.ed6d70b4", "Rectangle"],
  ["Localizable", "localizable.app.error.message.ai.servisi.yogun.95477ca2", "AI service is busy"],
  ["Localizable", "localizable.app.error.message.analiz.hakki.doldu.5a3d3836", "Analysis allowance used"],
  ["Localizable", "localizable.app.error.message.analiz.hakki.doldu.ae2015d8", "Analysis allowance used"],
  ["Localizable", "localizable.app.error.message.ayni.analizi.tekrar.baslatmadan.once.gecmis.anal.0eb2a0c7", "Refresh Analysis History after a few minutes before starting the same analysis again."],
  ["Localizable", "localizable.app.error.message.bir.kez.tanimlanan.risk.analizi.tablosu.hakkini..821d2cac", "You have used your one-time risk assessment table allowance."],
  ["Localizable", "localizable.app.error.message.risk.analizi.hakki.kullanildi.250c0860", "Risk assessment allowance used"],
  ["Localizable", "localizable.company.az.563adf3d", "Low"],
  ["Localizable", "localizable.company.az.tehlikeli.5a7188a4", "Low Hazard"],
  ["Localizable", "localizable.company.cok.tehlikeli.66f7a10e", "Very High Hazard"],
  ["Localizable", "localizable.company.cok.tehlikeli.b663cc01", "Very High Hazard"],
  ["Localizable", "localizable.company.ilgili.1.2f721c63", "Contact: %1$@"],
  ["Localizable", "localizable.company.picker.sheet.analizlerini.firmalara.bagla.raporlarini.firma.l.0124f450", "Link your analyses to companies and share reports with company logos and hazard classes."],
  ["Localizable", "localizable.company.picker.sheet.arsivle.8d9aafc3", "Archive"],
  ["Localizable", "localizable.company.picker.sheet.arsivle.e740a0ce", "Archive"],
  ["Localizable", "localizable.company.picker.sheet.eski.analiz.ve.rapor.baglantilari.korunur.firma..3ddbac8b", "Existing analysis and report links are preserved; the company will not appear in new selections."],
  ["Localizable", "localizable.company.picker.sheet.firmalari.yenile.a94d30d6", "Refresh companies"],
  ["Localizable", "localizable.company.picker.sheet.firmayi.kaydet.d6d3b0f2", "Save company"],
  ["Localizable", "localizable.company.picker.sheet.orn.30.710ccf45", "e.g. 30"],
  ["Localizable", "localizable.company.picker.sheet.tamam.f3dc324e", "OK"],
  ["Localizable", "localizable.company.picker.sheet.tekrar.dene.5c9f2cfe", "Try again"],
  ["Localizable", "localizable.company.picker.sheet.yeni.firma.a8263565", "New company"],
  ["Localizable", "localizable.document.preview.onizlemeyi.kapat.206e4722", "Close preview"],
  ["Localizable", "localizable.filter.sheet.analizleri.filtrele.a9296aa3", "Filter analyses"],
  ["Localizable", "localizable.filter.sheet.sifirla.77de5bea", "Reset"],
  ["Localizable", "localizable.history.view.analiz.ara.39912a48", "Search analyses"],
  ["Localizable", "localizable.history.view.analizi.sil.24e7f3a8", "Delete analysis"],
  ["Localizable", "localizable.history.view.analizi.sil.2c80616e", "Delete analysis"],
  ["Localizable", "localizable.history.view.analizi.sil.93bad064", "Delete analysis"],
  ["Localizable", "localizable.history.view.analizler.yuklenemedi.c6417635", "Analyses could not be loaded"],
  ["Localizable", "localizable.history.view.analizler.yuklenemedi.da2ab2d1", "Analyses could not be loaded"],
  ["Localizable", "localizable.history.view.analizler.yukleniyor.45550383", "Loading analyses"],
  ["Localizable", "localizable.history.view.kritik.955bc760", "Critical"],
  ["Localizable", "localizable.profile.view.1.aboneligin.dogrulandi.a377fb83", "Your %1$@ subscription has been verified."],
  ["Localizable", "localizable.profile.view.analizler.bulgular.fotograf.kayitlari.ve.bagli.r.0d69927f", "Analyses, findings, photo records and linked reports are deleted."],
  ["Localizable", "localizable.profile.view.analizler.bulgular.fotograf.kayitlari.ve.bagli.r.0dde7277", "Analyses, findings, photo records and linked reports are deleted."],
  ["Localizable", "localizable.profile.view.analizler.silinemedi.1c906fb1", "Analyses could not be deleted"],
  ["Localizable", "localizable.profile.view.gecmis.analizler.e108c786", "Analysis history"],
  ["Localizable", "localizable.profile.view.gecmis.analizler.e936d553", "Analysis history"],
  ["Localizable", "localizable.profile.view.kontrol.et.50c9c5d5", "Check"],
  ["Localizable", "localizable.profile.view.kur.1bf320eb", "Set up"],
  ["Localizable", "localizable.profile.view.logo.ekle.c6da0e71", "Add logo"],
  ["Localizable", "localizable.profile.view.logo.sec.4a97bac8", "Select logo"],
  ["Localizable", "localizable.profile.view.logoyu.degistir.b6bc49d0", "Change logo"],
  ["Localizable", "localizable.profile.view.mesleki.ilerleme.43c5ddd9", "Professional progress"],
  ["Localizable", "localizable.profile.view.mesleki.ilerleme.b4db90fe", "Professional progress"],
  ["Localizable", "localizable.profile.view.mesleki.ilerleme.penceresini.acar.20f2951f", "Opens the Professional Progress screen"],
  ["Localizable", "localizable.profile.view.mesleki.ilerleme.penceresini.acar.9e348be4", "Opens the Professional Progress screen"],
  ["Localizable", "localizable.profile.view.pdf.dosyalari.ve.rapor.arsiv.kayitlari.silinir.a.4c3468b2", "PDF files and report archive records are deleted. Analyses remain."],
  ["Localizable", "localizable.profile.view.pdf.dosyalari.ve.rapor.arsiv.kayitlari.silinir.a.ab674614", "PDF files and report archive records are deleted. Analyses remain."],
  ["Localizable", "localizable.profile.view.requestaccountdeletion.4e909399", "Request account deletion"],
  ["Localizable", "localizable.profile.view.tamam.8c55612a", "OK"],
  ["Localizable", "localizable.profile.view.tamam.cbe8c3b1", "OK"],
  ["Localizable", "localizable.profile.view.tamam.dd979b9f", "OK"],
  ["Localizable", "localizable.profile.view.tamam.fff8c2ae", "OK"],
  ["Localizable", "localizable.profile.view.tum.analizler.bulgular.fotograf.kayitlari.ve.bu..8555a6ef", "All analyses, findings, photo records and associated reports are deleted. This action cannot be undone."],
  ["Localizable", "localizable.profile.view.tum.analizler.silinsin.mi.ccdb36aa", "Delete all analyses?"],
  ["Localizable", "localizable.profile.view.tum.analizleri.sil.ba2f5c47", "Delete all analyses"],
  ["Localizable", "localizable.profile.view.tum.analizlerimi.sil.46e2a08f", "Delete all my analyses"],
  ["Localizable", "localizable.profile.view.tum.analizlerimi.sil.a1edc808", "Delete all my analyses"],
  ["Localizable", "localizable.profile.view.tum.analizlerin.ve.iliskili.bulgular.fotograflar.0277c8eb", "All analyses and associated findings and photos have been deleted."],
  ["Localizable", "localizable.rdbutton.pencereyi.kapat.947e31c3", "Close window"],
  ["Localizable", "localizable.rdchip.ozel.etiket.1351fb66", "Custom label"],
  ["Localizable", "localizable.rdcolor.kritik.7e9236f2", "Critical"],
  ["Localizable", "localizable.rdtab.bar.analizler.55bc5133", "Analyses"],
  ["Localizable", "localizable.rdupgrade.cta.1.a.gec.9c575241", "Switch to %1$@"],
  ["Localizable", "localizable.rdupgrade.cta.1.uyesiniz.d6d4c039", "Your %1$@ plan is active"],
  ["Localizable", "localizable.rdupgrade.cta.analizlerim.51ca6988", "My analyses"],
  ["Localizable", "localizable.rdupgrade.cta.aydinlik.mod.fe8c009c", "Light mode"],
  ["Localizable", "localizable.rdupgrade.cta.karanlik.mod.07170435", "Dark mode"],
  ["Localizable", "localizable.root.view.guncel.metinleri.incele.7f371307", "Review updated documents"],
  ["Localizable", "localizable.root.view.devam.et.3ce8f48e", "Continue"],
  ["Localizable", "localizable.support.contact.sheet.ad.soyad.76ebaa37", "Full name"],
  ["Localizable", "localizable.support.contact.sheet.ad.soyad.9e5be156", "Full name"],
  ["Localizable", "localizable.support.contact.sheet.kisa.bir.konu.yaz.765f1671", "Enter a short subject"],
  ["Localizable", "localizable.support.contact.sheet.kisa.bir.konu.yaz.a702e863", "Enter a short subject"],
  ["Localizable", "localizable.user.profile.sinirli.54922517", "Limited"],

  ["Notifications", "notifications.notification.service.bildirim.tercihi.acilmadi.lutfen.tekrar.dene.f4d3fae0", "Notification preference could not be enabled. Please try again."],
  ["Notifications", "notifications.notification.service.mesleki.bildirim.tercihi.kaydedilemedi.9b5fbbd3", "Failed to save professional notification preference."],

  ["Onboarding", "onboarding.obcertificate.view.az.tehlikeli.sinifta.yetkili.23a20492", "Authorised for low-hazard workplaces."],
  ["Onboarding", "onboarding.obcertificate.view.cok.tehlikeli.sinifta.yetkili.aaaf50c7", "Authorised for very-high-hazard workplaces."],
  ["Onboarding", "onboarding.obcertificate.view.sana.ozel.risk.sablonlari.hazirlayacagiz.671e73ee", "We will prepare tailored risk templates for you."],
  ["Onboarding", "onboarding.obloading.view.sana.ozel.kurulum.hazirlaniyor.a7043077", "Preparing your personalised setup..."],
  ["Onboarding", "onboarding.obpain.point.view.sahada.gorduklerini.aksam.ofiste.mi.yaziyorsun.4ae8a20e", "Do you write up your site observations later at the office?"],
  ["Onboarding", "onboarding.obpaywall.view.1.uzmanlari.icin.hazirlandi.1895b300", "BUILT FOR %1$@ PROFESSIONALS"],
  ["Onboarding", "onboarding.obpaywall.view.gizlilik.120a8da1", "Privacy"],
  ["Onboarding", "onboarding.obpaywall.view.sartlar.9a992598", "Terms"],
  ["Onboarding", "onboarding.obpaywall.view.sinirsiz.fotograf.analizi.d14fa9d7", "Multi-photo analysis"],
  ["Onboarding", "onboarding.obpaywall.view.turkce.24.saat.icinde.yanit.b7483600", "Priority response within 24 hours"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.app.store.odeme.ekrani.aciliyor.af128c75", "Opening App Store payment screen..."],
  ["Onboarding", "onboarding.obtimeline.paywall.view.aylik.fiyat.app.store.uzerinden.yuklenecek.1c047937", "The monthly price will load from the App Store."],
  ["Onboarding", "onboarding.obtimeline.paywall.view.coklu.fotograf.analizi.3c6f6a3d", "Multi-Photo Analysis"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.geri.yukle.1fe47fe9", "Restore"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.her.ay.e9db7612", "Every month"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.plus.aboneligin.gucunu.hemen.kullanin.655cca4a", "Unlock the Power of Plus"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.sektor.bazli.analiz.f645149d", "Sector-Based Analysis"],
  ["Onboarding", "onboarding.obtimeline.paywall.view.tekrar.dene.f8ced812", "Try again"],
  ["Onboarding", "onboarding.obtrial.invite.view.sartlar.de56b87b", "Terms"],
  ["Onboarding", "onboarding.obtrial.invite.view.uygulamayi.faee4cf2", "Choose the right "],
  ["Onboarding", "onboarding.obtrial.invite.view.yuksekte.calisma.faca06c7", "Working at height"],
  ["Onboarding", "onboarding.onboarding.personal.plan.1.akisina.uygun.ilerle.a26399c3", "Follow the %1$@ workflow."],
  ["Onboarding", "onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.aninda.rapor.914d7f50", "A system tailored to %1$@, with instant reports."],
  ["Onboarding", "onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.denetime.hazir.rapor.acda2ffe", "A system tailored to %1$@, with audit-ready reports."],
  ["Onboarding", "onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.sade.rapor.91133a60", "A system tailored to %1$@, with clear reports."],
  ["Onboarding", "onboarding.onboarding.personal.plan.1.rolune.gore.anlasilir.bulgu.dili.ve.duzenli.do.936186a5", "For the %1$@ role, we created a workflow focused on clear findings and consistent documentation. Team communication and archiving stay in one place."],
  ["Onboarding", "onboarding.onboarding.personal.plan.fine.kinnet.5.5.rapor.hazir.638e04ee", "Fine-Kinney / 5×5 report ready."],
  ["Onboarding", "onboarding.onboarding.personal.plan.isg.icin.egitilmis.sistem.1.temposunda.7ef96c1d", "A workplace-safety system matched to a %1$@ pace."],
  ["Onboarding", "onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.00cf0ce0", "Export the risk assessment to PDF or Excel with one tap."],
  ["Onboarding", "onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.81f86a73", "Export the risk assessment to PDF or Excel with one tap."],
  ["Onboarding", "onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.ef23bc9f", "Export the risk assessment to PDF or Excel with one tap."],
  ["Onboarding", "onboarding.onboarding.personal.plan.yogun.denetim.temponla.yarisacak.planin.hazir.4258cfff", "Your plan is ready for a demanding inspection schedule."],
  ["Onboarding", "onboarding.onboarding.v2.state.az.tehlikeli.af92fef7", "Low Hazard"],
  ["Onboarding", "onboarding.onboarding.v2.state.cok.tehlikeli.ea365d68", "Very High Hazard"],
  ["Onboarding", "onboarding.onboarding.v2.state.cok.tehlikeli.eababa99", "Very High Hazard"],
  ["Onboarding", "onboarding.onboarding.v2.state.insaat.00734e7a", "Construction"],
  ["Onboarding", "onboarding.onboarding.v2.state.saglik.personeli.a48c2086", "Healthcare professional"],
  ["Onboarding", "onboarding.onboarding.v2.state.standart.yogunluk.5f3fb070", "Standard pace"],
  ["Onboarding", "onboarding.onboarding.v2.state.tehlikeli.ff529f2c", "Hazardous"],
  ["Onboarding", "onboarding.onboarding.v2.state.tek.odak.30bd054c", "Single focus"],
  ["Onboarding", "onboarding.onboarding.v2.state.yogun.osgb.endustri.grubu.497fbbfb", "High-volume safety service / industry group"],
  ["Onboarding", "onboarding.onboarding.v2.state.yogun.saha.9c5b0a16", "High-volume field work"],
  ["Onboarding", "onboarding.onboarding.v2.state.yuksek.tempo.ea428772", "High pace"],
  ["Onboarding", "onboarding.onboarding.view.fine.kinney.5.5.risk.skoru.37dfd9ef", "Fine-Kinney & 5×5 risk scoring"],
  ["Onboarding", "onboarding.onboarding.view.risk.hesaplamasi.91234ce8", "RISK SCORING"],
  ["Onboarding", "onboarding.onboarding.view.saha.fotograf.e741ee23", "Site · Photo"],
  ["Onboarding", "onboarding.onboarding.view.v2.cevaplamaya.devam.et.7cad3cb1", "Continue answering"],
  ["Onboarding", "onboarding.onboarding.view.v2.sana.ozel.sonuclar.veremeyecegiz.38eef1fd", "We will not be able to personalise your results"],
  ["Onboarding", "onboarding.onboarding.view.v2.yine.de.atla.de185fdb", "Skip anyway"],
  ["Onboarding", "onboarding.onboarding.view.yetersiz.aydinlatma.39df16b2", "Insufficient lighting"],

  ["Paywall", "paywall.in.app.paywall.view.app.store.abonelik.paketleri.yukleniyor.a764aab2", "Loading App Store subscription options..."],
  ["Paywall", "paywall.in.app.paywall.view.app.store.hesabindaki.abonelik.kayitlari.kontrol.33625ca8", "Checking subscriptions in your App Store account."],
  ["Paywall", "paywall.in.app.paywall.view.app.store.odeme.ekrani.aciliyor.2017db3c", "Opening App Store payment screen..."],
  ["Paywall", "paywall.in.app.paywall.view.app.store.odeme.ekrani.aciliyor.ea863cb0", "Opening App Store payment screen..."],
  ["Paywall", "paywall.in.app.paywall.view.bu.plan.icin.app.store.paketi.henuz.yuklenmedi.3c3253d4", "The App Store product for this plan has not loaded yet."],
  ["Paywall", "paywall.in.app.paywall.view.coklu.fotograf.analizi.c5d7318b", "Multi-Photo Analysis"],
  ["Paywall", "paywall.in.app.paywall.view.fiyat.alinamadi.50d6ae8c", "Price unavailable"],
  ["Paywall", "paywall.in.app.paywall.view.fiyat.yukleniyor.91a8a0da", "Loading price"],
  ["Paywall", "paywall.in.app.paywall.view.geri.yukle.848d560c", "Restore"],
  ["Paywall", "paywall.in.app.paywall.view.iptal.hakki.fd1920ba", "Cancel anytime"],
  ["Paywall", "paywall.in.app.paywall.view.paywall.ekranini.kapat.92144bcc", "Close paywall"],
  ["Paywall", "paywall.in.app.paywall.view.plus.aboneligini.incele.847e9604", "View Plus subscription"],
  ["Paywall", "paywall.in.app.paywall.view.pro.yu.incele.8f867e6b", "View Pro"],
  ["Paywall", "paywall.in.app.paywall.view.sartlar.f0fe46a2", "Terms"],
  ["Paywall", "paywall.in.app.paywall.view.satin.alimlar.kontrol.ediliyor.74b29de4", "Checking purchases..."],
  ["Paywall", "paywall.in.app.paywall.view.tekrar.dene.a5447e51", "Try again"],

  ["ProfessionalProgress", "professionalprogress.professional.progress.badges.view.basarilarim.6622e74c", "My Achievements"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.badges.view.yuz.rapor.a212662d", "One Hundred Reports"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.celebration.sheet.ilk.raporunu.olusturdun.mesleki.takip.izin.basla.6d73be4e", "You created your first report. Your Professional Progress journey has started."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.celebration.sheet.tamam.76cd1dbd", "OK"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.beyan.edilen.alan.3907d53e", "Declared area"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.insaat.9d956dcf", "Construction"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.kritik.5681ba04", "Critical"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.maden.cba516d8", "Mining"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.mekanik.03fb4ae4", "Mechanical"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.psikososyal.2eadcac8", "Psychosocial"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.competency.map.view.yuksekte.ab77d7f0", "Work at Height"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.home.card.aday.d654b3d8", "Candidate"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.home.card.en.ust.riskdetected.unvanindasin.7c85a239", "You have reached the highest RiskDetected title"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.home.card.hedef.1.2.mdp.kaldi.2439b9e9", "Goal: %1$@ · %2$@ MDP remaining"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.home.card.kidemini.yukselt.6f180187", "Advance your rank"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.1.analiz.tamamladin.simdi.rapora.donustur.2ba431b2", "You completed %1$@ analyses. Now turn one into a report."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.bu.hafta.1.rapor.tamamladin.ea8ca37d", "You completed %1$@ reports this week. 💪"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.guvenlik.stratejisti.be6b9332", "Safety Strategist"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.ilk.rapor.tamam.devam.et.663e1cfb", "First report complete. Keep going."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.insaat.d9446df6", "Construction"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.maden.653693ae", "Mining"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.mekanik.6824d368", "Mechanical"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.models.psikososyal.404024f2", "Psychosocial"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.profile.section.analiz.ve.raporlarin.arttikca.yetkinlik.alanlari.b5934c21", "Your competency areas will appear here as you complete more analyses and reports."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.1.analiz.tamamlandi.birini.rapora.donusturerek.6.8619c6e0", "%1$@ analyses completed. Turn one into a report to earn +60 MDP."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.1.icin.2.mdp.kaldi.7f112857", "%2$@ MDP remaining for %1$@."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.en.ust.rutbedesin.birikimin.profilinde.korunur.32f9a051", "You are at the highest rank. Your progress is preserved in your profile."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.en.ust.rutbedesin.birikimin.profilinde.korunur.82263343", "You are at the highest rank. Your progress is preserved in your profile."],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.ilk.yetkinlik.alani.42920cb0", "First competency area"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.mdp.nasil.kazanilir.6d3aeefc", "How do I earn MDP?"],
  ["ProfessionalProgress", "professionalprogress.professional.progress.titles.sheet.uygulamaya.giris.yapmak.puan.vermez.ayni.analiz..3eefe37a", "Signing in does not earn points. Reprocessing the same analysis or report does not award MDP again. Analyses and reports from the same site visit are capped to keep progress fair."],

  ["Reports", "reports.report.view.aramayi.temizle.0f3e5a22", "Clear search"],
  ["Reports", "reports.report.view.aramayi.temizle.7b76195f", "Clear search"],
  ["Reports", "reports.report.view.d.mmm.ss.dd.b8b69074", "d MMM HH:mm"],
  ["Reports", "reports.report.view.d.mmm.yyyy.ss.dd.db7ff9b1", "d MMM yyyy · HH:mm"],
  ["Reports", "reports.report.view.fine.kinney.toplam.1.5.5.toplam.2.24785862", "Fine-Kinney total: %1$@ · 5×5 total: %2$@"],
  ["Reports", "reports.report.view.pencereyi.kapat.42ff6afc", "Close window"],
  ["Reports", "reports.report.view.pencereyi.kapat.7ae53ee2", "Close window"],
  ["Reports", "reports.report.view.rapor.kaynagi.bekleniyor.1ad81b3e", "Waiting for report source"],
  ["Reports", "reports.report.view.rapor.kaynagi.bekleniyor.8b552051", "Waiting for report source"],
  ["Reports", "reports.report.view.raporu.sil.2d768ded", "Delete report"],
  ["Reports", "reports.report.view.raporu.sil.b9373641", "Delete report"],
  ["Reports", "reports.report.view.raporu.sil.db5653f5", "Delete report"],
  ["Reports", "reports.report.view.son.tamamlanan.analizler.getiriliyor.8dd7d1d4", "Loading recently completed analyses."],
  ["Reports", "reports.report.view.son.tamamlanan.analizler.getiriliyor.c768118f", "Loading recently completed analyses."],
  ["Reports", "reports.report.view.standart.rapor.380caa82", "Standard report"],
  ["Reports", "reports.report.view.tamam.8d82c31b", "OK"],
  ["Reports", "reports.report.view.tarih.yok.13758df5", "No date"],
  ["Reports", "reports.report.view.tarih.yok.204e2241", "No date"],
  ["Reports", "reports.report.view.tarih.yok.215533e0", "No date"],
  ["Reports", "reports.report.view.tarih.yok.2e16a37f", "No date"],
  ["Reports", "reports.report.view.tarih.yok.b95f2b1f", "No date"],
  ["Reports", "reports.report.view.tehlike.tespit.edilmedi.69a999af", "No hazard detected"],
  ["Reports", "reports.report.view.tehlike.tespit.edilmedi.8c212742", "No hazard detected"],
  ["Reports", "reports.report.view.tekrar.dene.84b0ba25", "Try again"],
];

function parseCSV(text) {
  const rows = [];
  let row = [];
  let value = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quoted) {
      if (character === '"' && text[index + 1] === '"') {
        value += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        value += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      row.push(value);
      value = "";
    } else if (character === "\n") {
      row.push(value);
      rows.push(row);
      row = [];
      value = "";
    } else if (character !== "\r") {
      value += character;
    }
  }
  const [headers, ...body] = rows;
  return body
    .filter((cells) => cells.length === headers.length)
    .map((cells) =>
      Object.fromEntries(headers.map((header, index) => [header, cells[index]]))
    );
}

function decodeLiteral(value) {
  return value
    .replaceAll('\\"', '"')
    .replaceAll("\\n", " ")
    .replaceAll("\\t", " ")
    .trim();
}

function catalogFor(sourceFile) {
  if (/ProfessionalProgress/u.test(sourceFile)) return "ProfessionalProgress";
  if (/(?:Auth|AppleSignIn|GoogleSignIn)/u.test(sourceFile)) return "Auth";
  if (/Onboarding/u.test(sourceFile)) return "Onboarding";
  if (/(?:Paywall|Subscription|Purchase)/u.test(sourceFile)) return "Paywall";
  if (/(?:Report|PDF)/u.test(sourceFile)) return "Reports";
  if (/(?:Result|RiskDetail|Analysis|Home|Canvas|Annotate|Finding)/u.test(sourceFile)) {
    return "Analysis";
  }
  if (/Notification/u.test(sourceFile)) return "Notifications";
  if (/(?:Legal|Consent|Privacy)/u.test(sourceFile)) return "Legal";
  if (/(?:Safety|Sector|RiskBand)/u.test(sourceFile)) return "SafetyTerminology";
  return "Localizable";
}

function swiftTableCase(catalog) {
  return {
    Localizable: "localizable",
    Auth: "auth",
    Onboarding: "onboarding",
    Paywall: "paywall",
    Analysis: "analysis",
    Reports: "reports",
    Notifications: "notifications",
    ProfessionalProgress: "professionalProgress",
    Legal: "legal",
    SafetyTerminology: "safetyTerminology",
  }[catalog];
}

function slug(value) {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLocaleLowerCase("tr")
    .replaceAll("ı", "i")
    .replaceAll("ş", "s")
    .replaceAll("ğ", "g")
    .replaceAll("ü", "u")
    .replaceAll("ö", "o")
    .replaceAll("ç", "c")
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "")
    .slice(0, 48) || "copy";
}

function keyFor(entry) {
  const sourceBase = basename(entry.source_file, ".swift")
    .replace(/([a-z0-9])([A-Z])/g, "$1.$2")
    .toLowerCase();
  const hash = createHash("sha256")
    .update(
      `${entry.source_file}\0${entry.context}\0${entry.source_tr}\0${entry.line}`,
    )
    .digest("hex")
    .slice(0, 8);
  return `${catalogFor(entry.source_file).toLowerCase()}.${sourceBase}.${slug(entry.source_tr)}.${hash}`;
}

function loadEntries() {
  return parseCSV(readFileSync(INVENTORY_PATH, "utf8"))
    .filter((entry) => entry.surface === "ios_ui")
    .filter((entry) => !entry.source_tr.includes("\\("))
    .map((entry) => ({
      ...entry,
      catalog: catalogFor(entry.source_file),
      localization_key: keyFor(entry),
    }));
}

function parseSwiftString(line, quoteStart) {
  let index = quoteStart + 1;
  let staticPart = "";
  const parts = [];
  const expressions = [];
  while (index < line.length) {
    const character = line[index];
    if (character === '"' && line[index - 1] !== "\\") {
      parts.push(staticPart);
      return {
        end: index + 1,
        raw: line.slice(quoteStart + 1, index),
        parts,
        expressions,
      };
    }
    if (character === "\\" && line[index + 1] === "(") {
      parts.push(staticPart);
      staticPart = "";
      let cursor = index + 2;
      let depth = 1;
      let inString = false;
      while (cursor < line.length && depth > 0) {
        const nested = line[cursor];
        if (nested === '"' && line[cursor - 1] !== "\\") {
          inString = !inString;
        } else if (!inString && nested === "(") {
          depth += 1;
        } else if (!inString && nested === ")") {
          depth -= 1;
        }
        cursor += 1;
      }
      if (depth !== 0) return null;
      expressions.push(line.slice(index + 2, cursor - 1).trim());
      index = cursor;
      continue;
    }
    staticPart += character;
    index += 1;
  }
  return null;
}

function decodedStaticText(parts) {
  return parts.map((part) => decodeLiteral(part)).join(" ");
}

function decodeLiteralPreservingWhitespace(value) {
  return value
    .replaceAll('\\"', '"')
    .replaceAll("\\n", "\n")
    .replaceAll("\\t", "\t");
}

function formattedTemplate(parts) {
  return parts.map((part, index) => {
    const escapedPercent = decodeLiteralPreservingWhitespace(part)
      .replaceAll("%", "%%");
    const placeholder = index < parts.length - 1 ? `%${index + 1}$@` : "";
    return `${escapedPercent}${placeholder}`;
  }).join("");
}

function interpolatedKey(entry) {
  const sourceBase = basename(entry.source_file, ".swift")
    .replace(/([a-z0-9])([A-Z])/g, "$1.$2")
    .toLowerCase();
  const hash = createHash("sha256")
    .update(`${entry.source_file}\0${entry.context}\0${entry.raw}`)
    .digest("hex")
    .slice(0, 8);
  return `${entry.catalog.toLowerCase()}.${sourceBase}.${slug(entry.template)}.${hash}`;
}

function collectInterpolatedEntries() {
  const inventory = parseCSV(readFileSync(INVENTORY_PATH, "utf8"));
  const interpolatedInventory = inventory
    .filter((entry) => entry.surface === "ios_ui")
    .filter((entry) => entry.source_tr.includes("\\("));
  const inventoryKeys = new Set(
    interpolatedInventory.map(
      (entry) =>
        `${entry.source_file}\0${entry.line}\0${entry.context}\0${entry.source_tr}`,
    ),
  );
  const sourceFiles = [...new Set(
    interpolatedInventory.map((entry) => entry.source_file),
  )];
  const results = [];

  for (const sourceFile of sourceFiles) {
    const path = join(ROOT, sourceFile);
    const lines = readFileSync(path, "utf8").split(/\r?\n/);
    lines.forEach((line, lineIndex) => {
      if (/(?:logger\.|Self\.logger\.|privacy:\s*\.)/u.test(line)) return;
      const candidates = [];
      for (const pattern of INTERPOLATED_START_PATTERNS) {
        pattern.regex.lastIndex = 0;
        for (const match of line.matchAll(pattern.regex)) {
          const quoteStart = match.index + match[0].lastIndexOf('"');
          const parsed = parseSwiftString(line, quoteStart);
          if (!parsed || parsed.expressions.length === 0) continue;
          candidates.push({
            ...parsed,
            start: quoteStart,
            context: pattern.context,
          });
        }
      }

      if (/(?:PDF|Report)/u.test(sourceFile)) {
        for (let quoteStart = 0; quoteStart < line.length; quoteStart += 1) {
          if (line[quoteStart] !== '"' || line[quoteStart - 1] === "\\") continue;
          const parsed = parseSwiftString(line, quoteStart);
          if (!parsed || parsed.expressions.length === 0) continue;
          candidates.push({
            ...parsed,
            start: quoteStart,
            context: "swift_output_copy",
          });
          quoteStart = parsed.end - 1;
        }
      }

      const uniqueCandidates = new Map();
      for (const candidate of candidates) {
        const identity = `${candidate.start}:${candidate.end}`;
        if (!uniqueCandidates.has(identity)) {
          uniqueCandidates.set(identity, candidate);
        }
      }
      for (const candidate of uniqueCandidates.values()) {
        const inventoryKey =
          `${sourceFile}\0${lineIndex + 1}\0${candidate.context}\0` +
          decodeLiteral(candidate.raw);
        if (!inventoryKeys.has(inventoryKey)) continue;
        const staticText = decodedStaticText(candidate.parts);
        if (!/[A-Za-zÇĞİÖŞÜçğıöşü]/u.test(staticText)) continue;
        const entry = {
          source_file: sourceFile,
          line: lineIndex + 1,
          context: candidate.context,
          catalog: catalogFor(sourceFile),
          raw: candidate.raw,
          template: formattedTemplate(candidate.parts),
          expressions: candidate.expressions,
          start: candidate.start,
          end: candidate.end,
        };
        entry.localization_key = interpolatedKey(entry);
        results.push(entry);
      }
    });
  }
  return results;
}

function readTranslationStore() {
  if (!existsSync(TRANSLATIONS_PATH)) {
    return {
      schema_version: 1,
      provider: "Google Translate machine draft",
      generated_at: new Date().toISOString(),
      review_status: {
        language_review: "not_started",
        safety_review: "not_started",
        product_approval: "not_started",
      },
      entries: {},
    };
  }
  return JSON.parse(readFileSync(TRANSLATIONS_PATH, "utf8"));
}

function writeTranslationStore(store) {
  store.generated_at = new Date().toISOString();
  mkdirSync(dirname(TRANSLATIONS_PATH), { recursive: true });
  writeFileSync(TRANSLATIONS_PATH, `${JSON.stringify(store, null, 2)}\n`);
}

async function translate(text, source, target) {
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    const url = new URL("https://translate.googleapis.com/translate_a/single");
    url.searchParams.set("client", "gtx");
    url.searchParams.set("sl", source);
    url.searchParams.set("tl", target);
    url.searchParams.set("dt", "t");
    url.searchParams.set("q", text);
    const response = await fetch(url);
    if (!response.ok) {
      if (attempt < 4 && response.status >= 500) {
        await new Promise((resolvePromise) =>
          setTimeout(resolvePromise, attempt * 350)
        );
        continue;
      }
      throw new Error(`translation HTTP ${response.status}`);
    }
    const payload = await response.json();
    const translated = (payload[0] ?? [])
      .map((part) => part?.[0] ?? "")
      .join("")
      .trim();
    return { translated, detected: payload[2] ?? source };
  }
  throw new Error("translation retry budget exhausted");
}

function normalizeEnglish(value) {
  return value
    .replace(/\bOsgb\b/giu, "workplace safety service")
    .replace(/\bİsg\b/giu, "workplace safety")
    .replace(/\bIsg\b/gu, "workplace safety")
    .replace(/\bKVKK\b/gu, "Privacy Notice")
    .replace(/\boccupational safety specialist\b/giu, "safety professional")
    .replace(/\bjob security\b/giu, "workplace safety")
    .replace(/\blegislation compliance\b/giu, "regulatory references")
    .replace(/\s+/g, " ")
    .trim();
}

async function translateEntries(entries) {
  const store = readTranslationStore();
  let completed = 0;
  for (const entry of entries) {
    if (store.entries[entry.localization_key]) continue;
    let tr;
    let en;
    const englishAttempt = await translate(entry.source_tr, "auto", "en");
    if (englishAttempt.detected === "en") {
      en = entry.source_tr;
      tr = (await translate(entry.source_tr, "en", "tr")).translated;
    } else {
      tr = entry.source_tr;
      en = englishAttempt.translated;
    }
    store.entries[entry.localization_key] = {
      catalog: entry.catalog,
      source_file: entry.source_file,
      source_line: Number(entry.line),
      context: entry.context,
      source_language: englishAttempt.detected === "en" ? "en" : "tr",
      source: entry.source_tr,
      tr,
      en: normalizeEnglish(en),
      translation_status: "machine_draft",
      language_review: "not_started",
      safety_review: entry.safety_review_required === "true"
        ? "not_started"
        : "not_required",
      product_approval: "not_started",
    };
    completed += 1;
    if (completed % 10 === 0) {
      writeTranslationStore(store);
      process.stdout.write(
        `Translated ${completed}; cached ${Object.keys(store.entries).length}/${entries.length}\n`,
      );
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 90));
  }
  writeTranslationStore(store);
  console.log(
    `Translation store ready: ${Object.keys(store.entries).length} entries.`,
  );
}

async function translateTemplate(text, source, target) {
  const chunks = text.split(/(%\d+\$@)/g);
  let detected = source;
  const translatedChunks = [];
  for (const chunk of chunks) {
    if (/^%\d+\$@$/.test(chunk) || chunk.length === 0) {
      translatedChunks.push(chunk);
      continue;
    }
    const leading = chunk.match(/^\s*/)?.[0] ?? "";
    const trailing = chunk.match(/\s*$/)?.[0] ?? "";
    const core = chunk.slice(leading.length, chunk.length - trailing.length);
    if (!core) {
      translatedChunks.push(chunk);
      continue;
    }
    const result = await translate(core, source, target);
    if (detected === source) detected = result.detected;
    translatedChunks.push(`${leading}${result.translated}${trailing}`);
  }
  return { translated: translatedChunks.join(""), detected };
}

async function translateInterpolatedEntries(entries, force = false) {
  const store = readTranslationStore();
  let completed = 0;
  for (const entry of entries) {
    if (!force && store.entries[entry.localization_key]) continue;
    let tr;
    let en;
    const englishAttempt = await translateTemplate(entry.template, "auto", "en");
    if (englishAttempt.detected === "en") {
      en = entry.template;
      tr = (await translateTemplate(entry.template, "en", "tr")).translated;
    } else {
      tr = entry.template;
      en = englishAttempt.translated;
    }
    store.entries[entry.localization_key] = {
      catalog: entry.catalog,
      source_file: entry.source_file,
      source_line: Number(entry.line),
      context: entry.context,
      source_language: englishAttempt.detected === "en" ? "en" : "tr",
      source: entry.raw,
      tr,
      en: normalizeEnglish(en),
      placeholders: entry.template.match(/%\d+\$@/g) ?? [],
      translation_status: "machine_draft",
      language_review: "not_started",
      safety_review: /(?:risk|hazard|safety|İSG|güvenli|tehlike)/iu.test(entry.raw)
        ? "not_started"
        : "not_required",
      product_approval: "not_started",
    };
    completed += 1;
    if (completed % 10 === 0) {
      writeTranslationStore(store);
      process.stdout.write(
        `Translated ${completed} interpolated entr${completed === 1 ? "y" : "ies"}.\n`,
      );
    }
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 90));
  }
  writeTranslationStore(store);
  console.log(`Interpolated translation store ready: ${entries.length} entries.`);
}

async function repairEnglishMachineDrafts() {
  const store = readTranslationStore();
  const turkishLeak =
    /[çğıöşüÇĞİÖŞÜ]|\b(?:ad soyad|alan|analiz|bulgu|bu|devam|dil|dene|fotoğraf|henüz|için|ile|kalan|matris|orta|rapor|saha|sil|üyesiniz|veya)\b/iu;
  const technicalAllow =
    /^(?:Risk|Normal|excel|F-KINNEY|JPG · PNG · HEIC|TrialPreview[A-C]|[rR] = %1\$@|%1\$@ · R %2\$@|\/ %1\$@ MDP|%1\$@ MDP|RiskDetected)$/u;
  let repaired = 0;
  for (const translation of Object.values(store.entries)) {
    if (
      translation.source_language === "en" ||
      technicalAllow.test(translation.en) ||
      !turkishLeak.test(translation.en)
    ) {
      continue;
    }
    translation.en = normalizeEnglish(
      (await translate(translation.tr, "tr", "en")).translated,
    );
    repaired += 1;
    if (repaired % 10 === 0) writeTranslationStore(store);
    await new Promise((resolvePromise) => setTimeout(resolvePromise, 90));
  }
  writeTranslationStore(store);
  console.log(`Repaired ${repaired} English machine draft(s).`);
}

function inventoryLookup(entries) {
  const lookup = new Map();
  for (const entry of entries) {
    const key =
      `${entry.source_file}\0${entry.line}\0${entry.context}\0${entry.source_tr}`;
    lookup.set(key, entry);
  }
  return lookup;
}

function matchLineCandidates(line, sourceFile, lineNumber, lookup) {
  const matches = [];
  const seen = new Set();
  const existingLocalizationSpans = [
    ...line.matchAll(
      /RDLocalization\.string\("(?:\\.|[^"\\])*", table: \.[A-Za-z]+, fallback: "(?:\\.|[^"\\])*"\)/g,
    ),
    ...line.matchAll(
      /RDLocalization\.format\("(?:\\.|[^"\\])*", table: \.[A-Za-z]+, fallback: "(?:\\.|[^"\\])*", arguments: \[[^\]]*\]\)/g,
    ),
  ].map((match) => ({
    start: match.index,
    end: match.index + match[0].length,
  }));
  for (const pattern of UI_PATTERNS) {
    pattern.regex.lastIndex = 0;
    for (const match of line.matchAll(pattern.regex)) {
      const decoded = decodeLiteral(match[1]);
      const relativeQuote = match[0].indexOf('"');
      const start = match.index + relativeQuote;
      const identity = `${start}:${match[1]}`;
      if (seen.has(identity)) continue;
      seen.add(identity);
      const inventoryKey =
        `${sourceFile}\0${lineNumber}\0${pattern.context}\0${decoded}`;
      const entry = lookup.get(inventoryKey);
      if (!entry) continue;
      const end = match.index + match[0].length;
      if (
        existingLocalizationSpans.some(
          (span) => start >= span.start && end <= span.end,
        )
      ) {
        continue;
      }
      matches.push({ start, end, entry });
    }
  }

  // Swift report/PDF output literals are inventoried by a second scanner.
  for (const entry of lookup.values()) {
    if (
      entry.source_file !== sourceFile ||
      Number(entry.line) !== lineNumber ||
      entry.context !== "swift_output_copy"
    ) {
      continue;
    }
    const literalRegex = /"((?:\\.|[^"\\])*)"/g;
    for (const match of line.matchAll(literalRegex)) {
      if (decodeLiteral(match[1]) !== entry.source_tr) continue;
      matches.push({
        start: match.index,
        end: match.index + match[0].length,
        entry,
      });
      break;
    }
  }
  return [
    ...new Map(matches.map((match) => [`${match.start}:${match.end}`, match]))
      .values(),
  ];
}

function swiftStringLiteral(value) {
  return `"${value
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll("\n", "\\n")}"`;
}

function applySourceMigration(entries, store) {
  const lookup = inventoryLookup(entries);
  const byFile = Map.groupBy(entries, (entry) => entry.source_file);
  let replacementCount = 0;
  for (const [sourceFile] of byFile) {
    const path = join(ROOT, sourceFile);
    const lines = readFileSync(path, "utf8").split(/\r?\n/);
    const output = lines.map((line, index) => {
      const matches = matchLineCandidates(
        line,
        sourceFile,
        index + 1,
        lookup,
      ).filter((match) => store.entries[match.entry.localization_key]);
      if (matches.length === 0) return line;
      let transformed = line;
      for (const match of matches.sort((left, right) => right.start - left.start)) {
        const translation = store.entries[match.entry.localization_key];
        const fallback = translation.tr;
        const expression =
          `RDLocalization.string(${swiftStringLiteral(match.entry.localization_key)}, ` +
          `table: .${swiftTableCase(match.entry.catalog)}, ` +
          `fallback: ${swiftStringLiteral(fallback)})`;
        transformed =
          transformed.slice(0, match.start) + expression +
          transformed.slice(match.end);
        replacementCount += 1;
      }
      return transformed;
    });
    writeFileSync(path, output.join("\n"));
  }
  console.log(`Migrated ${replacementCount} Swift literal occurrence(s).`);
}

function applyInterpolatedSourceMigration(entries, store) {
  const byFile = Map.groupBy(entries, (entry) => entry.source_file);
  let replacementCount = 0;
  for (const [sourceFile, fileEntries] of byFile) {
    const path = join(ROOT, sourceFile);
    const lines = readFileSync(path, "utf8").split(/\r?\n/);
    const entriesByLine = Map.groupBy(fileEntries, (entry) => entry.line);
    const output = lines.map((line, index) => {
      const matches = entriesByLine.get(index + 1) ?? [];
      let transformed = line;
      for (const entry of matches.sort((left, right) => right.start - left.start)) {
        const translation = store.entries[entry.localization_key];
        if (!translation) continue;
        const argumentsList = entry.expressions
          .map((expression) => `String(describing: ${expression})`)
          .join(", ");
        const expression =
          `RDLocalization.format(${swiftStringLiteral(entry.localization_key)}, ` +
          `table: .${swiftTableCase(entry.catalog)}, ` +
          `fallback: ${swiftStringLiteral(translation.tr)}, ` +
          `arguments: [${argumentsList}])`;
        transformed =
          transformed.slice(0, entry.start) + expression +
          transformed.slice(entry.end);
        replacementCount += 1;
      }
      return transformed;
    });
    writeFileSync(path, output.join("\n"));
  }
  console.log(`Migrated ${replacementCount} interpolated Swift literal(s).`);
}

function cleanupNestedLocalizationCalls() {
  const sourceFiles = [...new Set(
    Object.values(readTranslationStore().entries)
      .map((entry) => entry.source_file)
      .filter((sourceFile) => sourceFile?.endsWith(".swift")),
  )];
  const nested =
    /RDLocalization\.string\("([^"]+)", table: \.([A-Za-z]+), fallback: RDLocalization\.string\("\1", table: \.\2, fallback: ("(?:\\.|[^"\\])*")\)\)/g;
  let replacementCount = 0;
  for (const sourceFile of sourceFiles) {
    const path = join(ROOT, sourceFile);
    if (!existsSync(path)) continue;
    const source = readFileSync(path, "utf8");
    const cleaned = source.replace(
      nested,
      (_match, key, table, fallback) => {
        replacementCount += 1;
        return `RDLocalization.string("${key}", table: .${table}, fallback: ${fallback})`;
      },
    );
    if (cleaned !== source) writeFileSync(path, cleaned);
  }
  console.log(`Collapsed ${replacementCount} nested localization fallback(s).`);
}

function originalConsumedCharacter(entry) {
  try {
    const original = execFileSync(
      "git",
      ["show", `HEAD:${entry.source_file}`],
      { cwd: ROOT, encoding: "utf8" },
    );
    const literal = swiftStringLiteral(entry.source_tr);
    const candidates = original.split(/\r?\n/)
      .map((line, index) => ({ line, lineNumber: index + 1 }))
      .filter(({ line }) => line.includes(literal));
    if (candidates.length === 0) return null;
    candidates.sort(
      (left, right) =>
        Math.abs(left.lineNumber - Number(entry.line)) -
        Math.abs(right.lineNumber - Number(entry.line)),
    );
    const line = candidates[0].line;
    const index = line.indexOf(literal);
    return line[index + literal.length] ?? "";
  } catch {
    return null;
  }
}

function revertBrokenSourceMigration(entries, store) {
  const byFile = Map.groupBy(entries, (entry) => entry.source_file);
  let reverted = 0;
  for (const [sourceFile, fileEntries] of byFile) {
    const path = join(ROOT, sourceFile);
    let source = readFileSync(path, "utf8");
    for (const entry of fileEntries) {
      const translation = store.entries[entry.localization_key];
      if (!translation) continue;
      const expression =
        `RDLocalization.string(${swiftStringLiteral(entry.localization_key)}, ` +
        `table: .${swiftTableCase(entry.catalog)}, ` +
        `fallback: ${swiftStringLiteral(translation.tr)})`;
      if (!source.includes(expression)) continue;
      const consumed = originalConsumedCharacter(entry);
      source = source.split(expression).join(
        `${swiftStringLiteral(entry.source_tr)}${consumed ?? ""}`,
      );
      reverted += 1;
    }

    // Duplicate inventory contexts could overlap on the same literal. The first
    // broken migration retained a suffix of the second generated expression.
    source = source.replace(
      /(?:\.)?(?:ization\.)?string\("[a-z]+(?:\.[^"]+)+\.[0-9a-f]{8}", table: \.[A-Za-z]+, fallback: "(?:\\.|[^"\\])*"\)/g,
      "",
    );

    if (/[a-z]+(?:\.[^"\s]+)+\.[0-9a-f]{8}/u.test(source)) {
      try {
        const originalLines = execFileSync(
          "git",
          ["show", `HEAD:${sourceFile}`],
          { cwd: ROOT, encoding: "utf8" },
        ).split(/\r?\n/);
        const entryByKey = new Map(
          fileEntries.map((entry) => [entry.localization_key, entry]),
        );
        source = source.split(/\r?\n/).map((line) => {
          const residualKey = [...entryByKey.keys()].find((key) =>
            line.includes(key)
          );
          if (!residualKey) return line;
          const entry = entryByKey.get(residualKey);
          const literal = swiftStringLiteral(entry.source_tr);
          const candidates = originalLines
            .map((originalLine, index) => ({
              originalLine,
              lineNumber: index + 1,
            }))
            .filter(({ originalLine }) => originalLine.includes(literal))
            .sort(
              (left, right) =>
                Math.abs(left.lineNumber - Number(entry.line)) -
                Math.abs(right.lineNumber - Number(entry.line)),
            );
          return candidates[0]?.originalLine ?? line;
        }).join("\n");
      } catch {
        // New files have no HEAD source; their non-overlapping calls were
        // already restored above.
      }
    }

    if (
      /[0-9a-f]{8}"|,,|,zation\b|(?:ports\.report|ng\("reports\.|ring\("reports\.)/u
        .test(source)
    ) {
      try {
        const originalLines = execFileSync(
          "git",
          ["show", `HEAD:${sourceFile}`],
          { cwd: ROOT, encoding: "utf8" },
        ).split(/\r?\n/);
        source = source.split(/\r?\n/).map((line) => {
          const suspicious =
            /[0-9a-f]{8}"|,,|,zation\b|(?:ports\.report|ng\("reports\.|ring\("reports\.)/u
              .test(line);
          if (!suspicious) return line;
          const entry = fileEntries.find((candidate) =>
            line.includes(swiftStringLiteral(candidate.source_tr))
          );
          if (!entry) return line;
          const literal = swiftStringLiteral(entry.source_tr);
          return originalLines
            .map((originalLine, index) => ({
              originalLine,
              lineNumber: index + 1,
            }))
            .filter(({ originalLine }) => originalLine.includes(literal))
            .sort(
              (left, right) =>
                Math.abs(left.lineNumber - Number(entry.line)) -
                Math.abs(right.lineNumber - Number(entry.line)),
            )[0]?.originalLine ?? line;
        }).join("\n");
      } catch {
        // See the new-file note above.
      }
    }
    writeFileSync(path, source);
  }
  console.log(`Reverted ${reverted} broken generated localization call(s).`);
}

function catalogEntry(comment, tr, en) {
  return {
    comment,
    extractionState: "manual",
    localizations: {
      en: {
        stringUnit: {
          state: "translated",
          value: en,
        },
      },
      tr: {
        stringUnit: {
          state: "translated",
          value: tr,
        },
      },
    },
  };
}

function pluralCatalogEntry(comment, tr, en) {
  const localization = (forms) => ({
    variations: {
      plural: Object.fromEntries(
        Object.entries(forms).map(([category, value]) => [
          category,
          {
            stringUnit: {
              state: "translated",
              value,
            },
          },
        ]),
      ),
    },
  });
  return {
    comment,
    extractionState: "manual",
    localizations: {
      en: localization(en),
      tr: localization(tr),
    },
  };
}

function writeCatalogs(entries, store) {
  const catalogStrings = Object.fromEntries(
    CATALOGS.map((catalog) => [catalog, {}]),
  );
  for (const [key, translation] of Object.entries(store.entries)) {
    if (!catalogStrings[translation.catalog]) continue;
    const shippingGate = translation.catalog === "ProfessionalProgress"
      ? "; shipping: native_language_and_safety_review_required"
      : "";
    catalogStrings[translation.catalog][key] = catalogEntry(
      `${translation.context}; ${translation.source_file}:${translation.source_line}; placeholders: ${(translation.placeholders ?? []).join("|") || "none"}; review: machine_draft${shippingGate}`,
      translation.tr,
      translation.en,
    );
  }
  for (const [key, tr, en] of REPORT_SEEDS) {
    catalogStrings.Reports[key] = catalogEntry(
      "Report localization contract; placeholders: none; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of ONBOARDING_SEEDS) {
    catalogStrings.Onboarding[key] = catalogEntry(
      "Onboarding product-copy contract; placeholders: none; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of ANALYSIS_SEEDS) {
    catalogStrings.Analysis[key] = catalogEntry(
      "Analysis UI product-copy contract; placeholders: none; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [catalog, key, tr, en] of PLURAL_SEEDS) {
    catalogStrings[catalog][key] = pluralCatalogEntry(
      "Native plural contract; placeholder: %lld; one/other required.",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of AUTH_SEEDS) {
    catalogStrings.Auth[key] = catalogEntry(
      "Authentication product-copy contract; placeholders: none; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of PAYWALL_SEEDS) {
    catalogStrings.Paywall[key] = catalogEntry(
      "Paywall price copy; placeholders: %1$@; StoreKit supplies the localized price; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of LOCALIZABLE_SEEDS) {
    catalogStrings.Localizable[key] = catalogEntry(
      "Core application copy contract; placeholders: none; review: machine_draft",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of LEGAL_SEEDS) {
    catalogStrings.Legal[key] = catalogEntry(
      `Legal UI localization contract; placeholders: ${key.includes("accessibility") ? "%@" : "none"}; review: machine_draft; shipping: legal_review_required`,
      tr,
      en,
    );
  }
  for (const [key, tr, en] of SAFETY_SEEDS) {
    catalogStrings.SafetyTerminology[key] = catalogEntry(
      "Safety terminology contract; placeholders: none; review: machine_draft; shipping: safety_review_required",
      tr,
      en,
    );
  }
  for (const [key, tr, en] of PROFESSIONAL_PROGRESS_SEEDS) {
    catalogStrings.ProfessionalProgress[key] = catalogEntry(
      `Professional Progress draft; placeholders: ${key.endsWith("title_status") ? "%1$@|%2$@" : "none"}; review: machine_draft; shipping: native_language_and_safety_review_required`,
      tr,
      en,
    );
  }
  for (const [catalog, key, tr, en] of CATALOG_OVERRIDES) {
    const shippingGate = catalog === "ProfessionalProgress"
      ? " review: machine_draft; shipping: native_language_and_safety_review_required"
      : "";
    catalogStrings[catalog][key] = catalogEntry(
      `Deterministic terminology/quality override; placeholders preserved;${shippingGate}`,
      tr,
      en,
    );
  }
  for (const [catalog, key, tr, en] of CATALOG_BUILD79_PRESERVATION_OVERRIDES) {
    const entry = catalogStrings[catalog]?.[key];
    if (!entry?.localizations?.tr?.stringUnit || !entry?.localizations?.en?.stringUnit) {
      throw new Error(`Build 79 preservation target missing: ${catalog}:${key}`);
    }
    entry.localizations.tr.stringUnit.value = tr;
    entry.localizations.en.stringUnit.value = en;
    entry.comment = `${entry.comment}; review: build79_copy_preserved`;
  }
  for (const [catalog, key, en] of CATALOG_ENGLISH_QUALITY_OVERRIDES) {
    const entry = catalogStrings[catalog]?.[key];
    if (!entry?.localizations?.en?.stringUnit) {
      throw new Error(`English quality override target missing: ${catalog}:${key}`);
    }
    entry.localizations.en.stringUnit.value = en;
    entry.comment = `${entry.comment}; review: deterministic_english_quality_override`;
  }
  catalogStrings.InfoPlist.NSCameraUsageDescription = catalogEntry(
    "Camera permission purpose string; placeholders: none; review: machine_draft",
    "RiskDetected, saha fotoğrafları çekerek iş güvenliği analizi yapabilmek için kamerana ihtiyaç duyar.",
    "RiskDetected needs camera access to capture site photos for workplace-safety analysis.",
  );
  catalogStrings.InfoPlist.NSPhotoLibraryUsageDescription = catalogEntry(
    "Photo library permission purpose string; placeholders: none; review: machine_draft",
    "Saha fotoğraflarını analiz edebilmek için galerine erişim izni gerekiyor.",
    "RiskDetected needs photo-library access so you can select site photos for analysis.",
  );
  catalogStrings.InfoPlist.CFBundleDisplayName = catalogEntry(
    "Application display name; do not translate the product name; placeholders: none.",
    "RiskDetected",
    "RiskDetected",
  );

  mkdirSync(LOCALIZATION_DIRECTORY, { recursive: true });
  for (const catalog of CATALOGS) {
    const path = join(LOCALIZATION_DIRECTORY, `${catalog}.xcstrings`);
    const content = {
      sourceLanguage: "tr",
      strings: Object.fromEntries(
        Object.entries(catalogStrings[catalog])
          .sort(([left], [right]) => left.localeCompare(right)),
      ),
      version: "1.0",
    };
    writeFileSync(path, `${JSON.stringify(content, null, 2)}\n`);
  }
}

function validate(entries, store) {
  const missing = entries.filter(
    (entry) => !store.entries[entry.localization_key],
  );
  if (missing.length > 0) {
    throw new Error(
      `${missing.length} translation(s) missing; run --translate first.`,
    );
  }
  for (const catalog of CATALOGS) {
    const path = join(LOCALIZATION_DIRECTORY, `${catalog}.xcstrings`);
    if (!existsSync(path)) throw new Error(`${relative(ROOT, path)} missing`);
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    for (const [key, value] of Object.entries(parsed.strings ?? {})) {
      const trLocalization = value.localizations?.tr;
      const enLocalization = value.localizations?.en;
      const tr = trLocalization?.stringUnit?.value;
      const en = enLocalization?.stringUnit?.value;
      if (tr || en) {
        if (!tr || !en) {
          throw new Error(`${catalog}:${key} lacks tr/en parity`);
        }
        continue;
      }
      const trPlural = trLocalization?.variations?.plural;
      const enPlural = enLocalization?.variations?.plural;
      for (const category of ["one", "other"]) {
        if (
          !trPlural?.[category]?.stringUnit?.value ||
          !enPlural?.[category]?.stringUnit?.value
        ) {
          throw new Error(
            `${catalog}:${key} lacks tr/en ${category} plural parity`,
          );
        }
      }
    }
  }
  console.log(`Localization migration validation passed: ${entries.length} entries.`);
}

const args = new Set(process.argv.slice(2));
const entries = loadEntries();
const interpolatedEntries = collectInterpolatedEntries();
const store = readTranslationStore();

if (args.has("--translate")) {
  await translateEntries(entries);
}
if (args.has("--apply")) {
  const currentStore = readTranslationStore();
  applySourceMigration(entries, currentStore);
  writeCatalogs(entries, currentStore);
}
if (args.has("--translate-interpolations")) {
  await translateInterpolatedEntries(interpolatedEntries, args.has("--force"));
}
if (args.has("--apply-interpolations")) {
  const currentStore = readTranslationStore();
  applyInterpolatedSourceMigration(interpolatedEntries, currentStore);
  writeCatalogs(entries, currentStore);
}
if (args.has("--write-catalogs")) {
  writeCatalogs(entries, readTranslationStore());
}
if (args.has("--cleanup-nested")) {
  cleanupNestedLocalizationCalls();
}
if (args.has("--repair-english-drafts")) {
  await repairEnglishMachineDrafts();
}
if (args.has("--revert-broken-apply")) {
  revertBrokenSourceMigration(entries, readTranslationStore());
}
if (args.has("--check")) {
  validate(entries, readTranslationStore());
}
if (args.size === 0) {
  console.log(
    "Usage: node scripts/migrate_swift_localization_catalogs.mjs --translate|--apply|--write-catalogs|--check",
  );
}
