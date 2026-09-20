export const NOTIFICATION_LOCALES = [
  "tr-TR",
  "en-001",
  "en-GB",
  "en-US",
  "en-AU",
  "en-CA",
] as const;

export type NotificationLocale = typeof NOTIFICATION_LOCALES[number];

export const TRANSACTIONAL_NOTIFICATION_EVENT_KEYS = [
  "analysis_complete",
  "report_ready",
  "trial_reminder",
  "progress_weekly_summary",
  "progress_monthly_summary",
  "progress_milestones",
  "account_update.cancellation",
  "account_update.expiration",
  "account_update.billing_issue",
  "account_update.subscription_paused",
  "workspace_deadline_due",
  "workspace_deadline_soon",
  "workspace_assignment_changed",
  "workspace_export_ready",
  "workspace_handover_ready",
] as const;

export type TransactionalNotificationEventKey =
  typeof TRANSACTIONAL_NOTIFICATION_EVENT_KEYS[number];

type NotificationCopy = Readonly<{ title: string; body: string }>;

const TURKISH_COPY: Readonly<
  Record<TransactionalNotificationEventKey, NotificationCopy>
> = Object.freeze({
  analysis_complete: {
    title: "Analiz hazır",
    body: "Risk analizin hazır. Sonuçlarını şimdi inceleyebilirsin.",
  },
  report_ready: {
    title: "Rapor hazır",
    body: "Risk raporun oluşturuldu. Raporlar bölümünden inceleyebilirsin.",
  },
  trial_reminder: {
    title: "Detaylı analiz denemen yakında sona eriyor",
    body: "Plus deneme sürenin bitmesine 2 gün kaldı.",
  },
  progress_weekly_summary: {
    title: "Haftalık ilerleme özetin hazır",
    body: "Bu haftaki mesleki ilerlemeni şimdi inceleyebilirsin.",
  },
  progress_monthly_summary: {
    title: "Aylık ilerleme özetin hazır",
    body: "Bu ayki mesleki ilerlemeni şimdi inceleyebilirsin.",
  },
  progress_milestones: {
    title: "Yeni bir ilerleme adımına ulaştın",
    body: "Mesleki ilerleme ayrıntılarını profilinden inceleyebilirsin.",
  },
  "account_update.cancellation": {
    title: "Üyelik iptali alındı",
    body: "Planın dönem sonuna kadar aktif kalmaya devam edecek.",
  },
  "account_update.expiration": {
    title: "Üyelik süren doldu",
    body: "RiskDetected hesabın ücretsiz plana geçirildi.",
  },
  "account_update.billing_issue": {
    title: "Ödeme kontrolü gerekiyor",
    body:
      "Üyeliğinin devam etmesi için App Store ödeme bilgilerini kontrol et.",
  },
  "account_update.subscription_paused": {
    title: "Üyelik duraklatıldı",
    body: "RiskDetected hesabın geçici olarak ücretsiz plana alındı.",
  },
  workspace_deadline_due: {
    title: "İSG görevinin süresi doldu",
    body: "Süresi dolan kaydı OSGB çalışma alanından inceleyin.",
  },
  workspace_deadline_soon: {
    title: "İSG görevinin süresi yaklaşıyor",
    body: "Yaklaşan kaydı OSGB çalışma alanından inceleyin.",
  },
  workspace_assignment_changed: {
    title: "Firma ataması güncellendi",
    body: "Güncel sorumluluklarınızı OSGB çalışma alanından inceleyin.",
  },
  workspace_export_ready: {
    title: "OSGB raporu hazır",
    body: "Hazırlanan raporu OSGB çalışma alanından indirebilirsiniz.",
  },
  workspace_handover_ready: {
    title: "Devir işlemi hazır",
    body: "Firma devir işlemini OSGB çalışma alanından inceleyin.",
  },
});

const ENGLISH_COPY: Readonly<
  Record<TransactionalNotificationEventKey, NotificationCopy>
> = Object.freeze({
  analysis_complete: {
    title: "Analysis ready",
    body: "Your risk assessment is ready to review.",
  },
  report_ready: {
    title: "Report ready",
    body: "Your risk report is ready in the Reports section.",
  },
  trial_reminder: {
    title: "Your detailed-analysis trial ends soon",
    body: "There are 2 days left in your Plus trial.",
  },
  progress_weekly_summary: {
    title: "Your weekly progress summary is ready",
    body: "Review your professional progress for this week.",
  },
  progress_monthly_summary: {
    title: "Your monthly progress summary is ready",
    body: "Review your professional progress for this month.",
  },
  progress_milestones: {
    title: "You reached a new progress milestone",
    body: "Review the details of your professional progress in Profile.",
  },
  "account_update.cancellation": {
    title: "Subscription cancellation received",
    body: "Your plan will remain active until the end of the billing period.",
  },
  "account_update.expiration": {
    title: "Your subscription has ended",
    body: "Your RiskDetected account has moved to the free plan.",
  },
  "account_update.billing_issue": {
    title: "Payment details need attention",
    body:
      "Check your App Store payment details to keep your subscription active.",
  },
  "account_update.subscription_paused": {
    title: "Subscription paused",
    body: "Your RiskDetected account has temporarily moved to the free plan.",
  },
  workspace_deadline_due: {
    title: "OHS task overdue",
    body: "Review the overdue record in your OSGB workspace.",
  },
  workspace_deadline_soon: {
    title: "OHS task due soon",
    body: "Review the upcoming record in your OSGB workspace.",
  },
  workspace_assignment_changed: {
    title: "Company assignment updated",
    body: "Review your current responsibilities in the OSGB workspace.",
  },
  workspace_export_ready: {
    title: "OSGB report ready",
    body: "Your report is ready to download from the OSGB workspace.",
  },
  workspace_handover_ready: {
    title: "Handover ready",
    body: "Review the company handover in your OSGB workspace.",
  },
});

const CATALOG: Readonly<
  Record<
    NotificationLocale,
    Readonly<Record<TransactionalNotificationEventKey, NotificationCopy>>
  >
> = Object.freeze({
  "tr-TR": TURKISH_COPY,
  "en-001": ENGLISH_COPY,
  "en-GB": ENGLISH_COPY,
  "en-US": ENGLISH_COPY,
  "en-AU": ENGLISH_COPY,
  "en-CA": ENGLISH_COPY,
});

export type TransactionalNotificationResolution =
  | {
    ok: true;
    eventKey: TransactionalNotificationEventKey;
    locale: NotificationLocale;
    language: "tr" | "en";
    title: string;
    body: string;
    checksum: string;
  }
  | {
    ok: false;
    code:
      | "NOTIFICATION_EVENT_KEY_UNKNOWN"
      | "NOTIFICATION_LOCALE_UNSUPPORTED"
      | "NOTIFICATION_EXACT_LOCALE_TEMPLATE_MISSING";
  };

function isNotificationLocale(value: unknown): value is NotificationLocale {
  return typeof value === "string" &&
    (NOTIFICATION_LOCALES as readonly string[]).includes(value);
}

function isEventKey(
  value: unknown,
): value is TransactionalNotificationEventKey {
  return typeof value === "string" &&
    (TRANSACTIONAL_NOTIFICATION_EVENT_KEYS as readonly string[]).includes(
      value,
    );
}

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function resolveTransactionalNotificationTemplate(params: {
  eventKey: unknown;
  locale: unknown;
}): Promise<TransactionalNotificationResolution> {
  if (!isEventKey(params.eventKey)) {
    return { ok: false, code: "NOTIFICATION_EVENT_KEY_UNKNOWN" };
  }
  if (!isNotificationLocale(params.locale)) {
    return { ok: false, code: "NOTIFICATION_LOCALE_UNSUPPORTED" };
  }
  const copy = CATALOG[params.locale]?.[params.eventKey];
  if (!copy) {
    return {
      ok: false,
      code: "NOTIFICATION_EXACT_LOCALE_TEMPLATE_MISSING",
    };
  }
  return {
    ok: true,
    eventKey: params.eventKey,
    locale: params.locale,
    language: params.locale === "tr-TR" ? "tr" : "en",
    title: copy.title,
    body: copy.body,
    checksum: await sha256(
      [
        params.eventKey,
        params.locale,
        copy.title,
        copy.body,
      ].join("\n"),
    ),
  };
}
