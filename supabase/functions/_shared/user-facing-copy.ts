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
