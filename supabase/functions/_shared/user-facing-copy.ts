export type UserCopyLanguage = "tr" | "en";

const COPY = {
  supportAttachmentsInvalid: {
    tr: "Ek dosya verisi geçersiz.",
    en: "The attachment data is invalid.",
  },
  supportAttachmentsTooMany: {
    tr: "En fazla {{max}} ek dosya gönderebilirsin.",
    en: "You can send up to {{max}} attachments.",
  },
  supportAttachmentTooLarge: {
    tr: "Ek dosya 5 MB'dan küçük olmalı.",
    en: "Each attachment must be smaller than 5 MB.",
  },
  supportAttachmentsTotalTooLarge: {
    tr: "Ek dosyaların toplam boyutu çok büyük.",
    en: "The total attachment size is too large.",
  },
  supportAttachmentTypeUnsupported: {
    tr: "Yalnızca doğrulanmış JPEG, PNG veya PDF dosyaları eklenebilir.",
    en: "Only verified JPEG, PNG, or PDF files can be attached.",
  },
  analyzeRequestTooLarge: {
    tr: "İstek gövdesi çok büyük.",
    en: "The request body is too large.",
  },
  analyzeInvalidWorkerRequest: {
    tr: "Geçersiz worker isteği.",
    en: "The worker request is invalid.",
  },
  analyzeAndroidTemporarilyUnavailable: {
    tr: "Android analiz gönderimi geçici olarak kullanılamıyor.",
    en: "Android analysis submission is temporarily unavailable.",
  },
  legalDocumentsUpdated: {
    tr:
      "Hukuki metinlerimiz güncellendi. Devam etmeden önce güncel metinleri inceleyin.",
    en: "Our legal documents have been updated. Review them before continuing.",
  },
  reportCompanyContact: { tr: "İrtibat: {{value}}", en: "Contact: {{value}}" },
  reportCompanyDepartment: {
    tr: "Birim: {{value}}",
    en: "Department: {{value}}",
  },
  reportCompanyResponsible: {
    tr: "Sorumlu: {{value}}",
    en: "Responsible: {{value}}",
  },
  reportCompanyDefaultDueDays: {
    tr: "Varsayılan termin: {{value}} gün",
    en: "Default due date: {{value}} days",
  },
  reportQuotaCheckFailed: {
    tr: "Rapor kotası kontrol edilemedi.",
    en: "The report quota could not be checked.",
  },
  reportQuotaExceeded: {
    tr: "Rapor kotan doldu.",
    en: "Your report quota is full.",
  },
  reportPremiumRequired: {
    tr: "Bu rapor Plus veya Pro aboneliği gerektirir.",
    en: "This report requires a Plus or Pro subscription.",
  },
  reportRetryCheckFailed: {
    tr: "Rapor tekrar deneme kontrolü tamamlanamadı.",
    en: "The report retry check could not be completed.",
  },
  reportScorelessItemLocked: {
    tr: "Saha teyidi kaydına risk skoru eklenemez.",
    en: "A risk score cannot be added to a field-verification item.",
  },
  resultExpertSectionTitle: {
    tr: "Uzman Görüşü Önerileri",
    en: "Expert Recommendations",
  },
  resultNotebookSectionTitle: {
    tr: "Onaylı Defter Önerisi",
    en: "Safety Log Recommendation",
  },
  resultRiskAnalysisTitle: { tr: "Risk Analizi", en: "Risk Analysis" },
  resultExpertDisclaimer: {
    tr:
      "Bağlayıcı uzman görüşü değildir; saha teyidi ve uzman değerlendirmesi gerekir.",
    en:
      "Not a binding expert opinion; field verification and expert review are required.",
  },
  resultNotebookDisclaimer: {
    tr:
      "Taslak çıktıdır; iş güvenliği uzmanı değerlendirmesi ve resmî deftere aktarım gerekir.",
    en:
      "Draft output; expert review and transfer to the applicable official record are required.",
  },
  resultExpertHubDisclaimer: {
    tr:
      "Bu içerik bağlayıcı uzman görüşü değildir; saha teyidi ve uzman değerlendirmesi gerekir.",
    en:
      "This content is not a binding expert opinion; field verification and expert review are required.",
  },
  resultNotebookHubDisclaimer: {
    tr:
      "Onaylı Defter önerisi/taslağıdır; uzman değerlendirmesi ve resmî deftere aktarım gerekir.",
    en:
      "This is a Safety Log recommendation; expert review and transfer to the applicable official record are required.",
  },
  resultExpertIntentDisclaimer: {
    tr: "Bağlayıcı uzman görüşü değildir; saha teyidi gerekir.",
    en: "Not a binding expert opinion; field verification is required.",
  },
  resultNotebookIntentDisclaimer: {
    tr: "Onaylı Defter önerisi/taslağıdır; uzman değerlendirmesi gerekir.",
    en: "Safety Log recommendation; expert review is required.",
  },
  resultHeaderNumber: { tr: "Sıra", en: "No." },
  resultHeaderTitle: { tr: "Başlık", en: "Title" },
  resultHeaderDescription: { tr: "Açıklama", en: "Description" },
  resultHeaderFinding: { tr: "Tespit", en: "Finding" },
  resultHeaderRecommendation: { tr: "Öneri", en: "Recommendation" },
  resultHeaderBasis: { tr: "Dayanak", en: "Basis" },
  resultHeaderSourceItems: { tr: "Kaynak Bulgu", en: "Source Items" },
  resultHeaderExpertRecommendation: {
    tr: "Uzman Önerisi",
    en: "Expert Recommendation",
  },
  resultHeaderCorrectiveAction: {
    tr: "Düzeltici Önlem",
    en: "Corrective Action",
  },
  resultHeaderPreventiveAction: {
    tr: "Önleyici Faaliyet",
    en: "Preventive Action",
  },
  resultHeaderRootCause: { tr: "Kök Neden", en: "Root Cause" },
  resultHeaderRegulatoryReferences: {
    tr: "Mevzuat",
    en: "Regulatory References",
  },
  resultHeaderStatus: { tr: "Durum", en: "Status" },
  resultExpertReviewCompleted: {
    tr: "Uzman değerlendirmesi tamamlandı",
    en: "Expert review completed",
  },
  resultFieldVerificationRequired: {
    tr: "Saha teyidi gerekir",
    en: "Field verification required",
  },
  resultNotebookSheetName: { tr: "Defter Taslağı", en: "Safety Log Draft" },
  resultExpertSheetName: { tr: "Uzman Görüşü", en: "Expert Advice" },
  reportRiskTrialUsed: {
    tr: "Bir kez tanımlanan risk analizi tablosu hakkını kullandın.",
    en: "You have used your one-time risk analysis table allowance.",
  },
  deletionRequestEmailSubject: {
    tr: "RiskDetected hesap silme talebin alındı",
    en: "Your RiskDetected account deletion request was received",
  },
  deletionRequestEmailBody: {
    tr:
      "Hesap ve veri silme talebin alındı. İşlem en geç 24 saat içinde tamamlanacaktır.\n\nDestek kodu: {{supportID}}\nTahmini son zaman: {{estimatedCompletionAt}}\n\nAktif Google Play veya App Store aboneliğini mağaza abonelik ayarlarından ayrıca yönetmelisin.",
    en:
      "Your account and data deletion request was received. It will be completed within 24 hours.\n\nSupport code: {{supportID}}\nEstimated completion: {{estimatedCompletionAt}}\n\nManage any active Google Play or App Store subscription separately in your store subscription settings.",
  },
  deletionRequestAccepted: {
    tr:
      "Hesap ve veri silme talebin alındı. İşlem en geç 24 saat içinde tamamlanacaktır.",
    en:
      "Your account and data deletion request was received. It will be completed within 24 hours.",
  },
  deletionCompleteEmailSubject: {
    tr: "RiskDetected hesabın ve verilerin silindi",
    en: "Your RiskDetected account and data were deleted",
  },
  deletionCompleteEmailBody: {
    tr:
      "Hesabın ve RiskDetected verilerin silindi. Aktif Google Play veya App Store aboneliğin varsa mağaza abonelik ayarlarından ayrıca yönetmelisin.\n\nDestek kodu: {{supportID}}",
    en:
      "Your RiskDetected account and data were deleted. Manage any active Google Play or App Store subscription separately in your store subscription settings.\n\nSupport code: {{supportID}}",
  },
  deletionFailed: {
    tr:
      "Hesap silme işlemi tamamlanamadı. Lütfen tekrar dene; sorun devam ederse destek koduyla bize ulaş.",
    en:
      "Account deletion could not be completed. Try again, and contact support with the support code if the problem continues.",
  },
  deletionCompleted: {
    tr:
      "Hesabın ve verilerin silindi. Aktif {{store}} aboneliğin varsa mağaza abonelik ayarlarından ayrıca yönetebilirsin.",
    en:
      "Your account and data were deleted. Manage any active {{store}} subscription separately in your store subscription settings.",
  },
  analysisFallbackSummary: {
    tr:
      "{{profileTerm}} kapsamında fotoğraftan güvenilir biçimde doğrulanabilen {{count}} bulgu raporlandı.",
    en:
      "{{count}} {{profileTerm}} finding(s) that could be reliably verified from the photo were reported.",
  },
  analysisFallbackZeroFindingsSummary: {
    tr:
      "{{profileTerm}} kapsamında fotoğraftan güvenilir biçimde doğrulanabilen bir bulgu raporlanmadı.",
    en: "No {{profileTerm}} finding could be reliably verified from the photo.",
  },
  analysisFallbackZeroFindingsLimitation: {
    tr:
      "Fotoğraf tek başına güvenilir bir bulguyu doğrulamak için yeterli kanıt sağlamadı; saha doğrulaması gerekebilir.",
    en:
      "The photo alone did not provide enough evidence to verify a finding reliably; field verification may be needed.",
  },
  analysisFallbackCautiousRootCause: {
    tr:
      "Görseldeki koşul olası bir katkı faktörüne işaret ediyor; neden sahada doğrulanmalıdır.",
    en:
      "The visible condition suggests a possible contributing factor; the cause requires field verification.",
  },
  analysisFallbackCoverageGapReason: {
    tr:
      "Fotoğraftan aksiyonlanabilir bir risk kanıtı güvenilir biçimde doğrulanamadı.",
    en:
      "No actionable risk evidence could be reliably verified from the photo.",
  },
  analysisFallbackQuotaReleaseFailed: {
    tr: "Analiz kotası iade edilemedi. Destek kodu: {{supportID}}",
    en: "The analysis quota could not be released. Support code: {{supportID}}",
  },
  analysisQualityNoDistinctAdditionalHazard: {
    tr:
      "İlk bulguların dışında ayrı ve kanıtlanabilir ek bir risk doğrulanmadı.",
    en:
      "No separate, evidence-based risk was verified beyond the initial findings.",
  },
  analysisQualityInsufficientVisualEvidence: {
    tr:
      "Ek bir riski güvenilir biçimde doğrulamak için görsel kanıt yeterli değildi.",
    en:
      "The visual evidence was insufficient to verify an additional risk reliably.",
  },
  analysisQualityExistingFindingsCoverScene: {
    tr: "Görüntüde doğrulanan koşullar mevcut bulgular tarafından kapsanıyor.",
    en:
      "The conditions verified in the image are covered by the existing findings.",
  },
  analysisEquipmentPressure: {
    tr: "basınçlı ekipman veya proses kabı",
    en: "pressure equipment or process vessel",
  },
  analysisEquipmentLifting: {
    tr: "kaldırma ve iletme ekipmanı",
    en: "lifting or conveying equipment",
  },
  analysisEquipmentElectrical: {
    tr: "elektrik tesisatı veya elektrikli ekipman",
    en: "electrical installation or equipment",
  },
  analysisEquipmentMachineTool: {
    tr: "makine tezgâhı",
    en: "machine tool",
  },
  analysisEquipmentRackDoor: {
    tr: "endüstriyel raf veya kapı sistemi",
    en: "industrial racking or door system",
  },
  analysisEquipmentConstructionMachine: {
    tr: "iş makinesi",
    en: "construction machine",
  },
  analysisPeriodicInspectionTitle: {
    tr: "{{equipment}} periyodik kontrol geçerliliği — saha teyidi",
    en: "{{equipment}} periodic inspection validity — field verification",
  },
  analysisPeriodicInspectionEvidence: {
    tr: "Fotoğrafta {{equipment}} sınıfında bir iş ekipmanı görülüyor.",
    en: "The photograph shows work equipment in the {{equipment}} class.",
  },
  analysisPeriodicInspectionDescription: {
    tr:
      "Yetkili kişi raporu, ekipman kimliği eşleşmesi ve sonraki kontrol tarihi bu görüntüden doğrulanamıyor.",
    en:
      "The competent-person report, equipment identity match and next inspection date cannot be verified from this image.",
  },
  analysisPeriodicInspectionRootCause: {
    tr:
      "Bu madde bir uygunsuzluk iddiası değildir; kontrol kaydının güncel durumu fotoğraftan belirlenemez.",
    en:
      "This item is not a non-conformity claim; the current inspection-record status cannot be determined from the photograph.",
  },
  analysisPeriodicInspectionCorrective: {
    tr:
      "Ekipman kullanılmadan önce ekipman kimliğini yetkili kişi raporuyla eşleştir ve kontrol geçerliliğini sahada teyit et.",
    en:
      "Before use, match the equipment identity to the competent-person report and verify inspection validity on site.",
  },
  analysisPeriodicInspectionPreventive: {
    tr:
      "Kontrol son tarihini ekipman envanteri ve kullanım öncesi kontrol süreciyle takip et.",
    en:
      "Track the inspection due date through the equipment register and pre-use control process.",
  },
  analysisApplicableInspectionTitle: {
    tr: "{{equipment}} kontrol ve bakım durumu — saha teyidi",
    en: "{{equipment}} inspection and maintenance status — field verification",
  },
  analysisApplicableInspectionDescription: {
    tr:
      "Ekipmana uygulanabilir yerel kontrol ve bakım kayıtları bu görüntüden doğrulanamıyor.",
    en:
      "The locally applicable inspection and maintenance records cannot be verified from this image.",
  },
  analysisApplicableInspectionCorrective: {
    tr:
      "Ekipman kullanılmadan önce kimlik, kontrol ve bakım kayıtlarını yetkili bir kişiyle sahada doğrula.",
    en:
      "Before use, verify the equipment identity and applicable inspection and maintenance records on site with a competent person.",
  },
  analysisApplicableInspectionPreventive: {
    tr:
      "Uygulanabilir kontrol ve bakım tarihlerini ekipman envanteri ve kullanım öncesi kontrol süreciyle takip et.",
    en:
      "Track applicable inspection and maintenance dates through the equipment register and pre-use control process.",
  },
  analysisFieldVerificationCategory: {
    tr: "Saha doğrulaması",
    en: "Field verification",
  },
  analysisProcessCheckNotVisibleEvidence: {
    tr:
      "Bu proses güvenliği kontrolünü doğrulamak için gereken ayrıntı görüntüde yeterince görünmüyor.",
    en:
      "The detail required to verify this process-safety check is not sufficiently visible in the image.",
  },
  analysisResultPersistenceFailed: {
    tr: "Analiz sonucu kaydedilemedi.",
    en: "The analysis result could not be saved.",
  },
  notebookReminderTitle: {
    tr: "Kişisel hatırlatıcı",
    en: "Personal reminder",
  },
  notebookReminderBody: {
    tr: "Not defterinizdeki hatırlatıcının zamanı geldi.",
    en: "It's time for a reminder in your notebook.",
  },
} as const;

export type UserFacingCopyKey = keyof typeof COPY;
export const USER_FACING_COPY_KEYS = Object.freeze(
  Object.keys(COPY) as UserFacingCopyKey[],
);

export function userFacingCopy(
  key: UserFacingCopyKey,
  language: unknown,
  variables: Record<string, string | number> = {},
): string {
  const resolvedLanguage: UserCopyLanguage = language === "en" ? "en" : "tr";
  return Object.entries(variables).reduce(
    (value, [name, replacement]) =>
      value.replaceAll(`{{${name}}}`, String(replacement)),
    COPY[key][resolvedLanguage] as string,
  );
}
