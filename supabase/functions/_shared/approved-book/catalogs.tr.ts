// Turkish surface forms, one entry per canonical code.
//
// Every string here is written once, by hand, and reviewed as book language --
// not derived from anything the model said. That is what makes the output
// defensible: the code decides WHICH sentence, the catalogue decides HOW it
// reads, and neither step can be steered by the provider.
//
// Surfaces are stored inflected, not as roots. Turkish agglutination makes
// runtime stem-plus-suffix assembly a reliable source of wrong vowels and wrong
// buffer consonants; writing the surface out is longer and correct. Where a
// location has to be attached, the template does it with a fixed pattern rather
// than by inflecting the catalogue entry.
//
// Verb choice carries the evidence claim and is not stylistic:
//   gözlenmiştir      - the specialist can state they saw it
//   tespit edilmiştir - same strength, used for a measured or counted condition
//   doğrulanmalıdır   - a record or measurement must be checked; nothing is
//                       being asserted about whether it exists
//   sağlanmalıdır     - a physical control must be put in place
//
// A photograph can never support "yapılmamıştır" about a document, an
// inspection or a measurement. No surface in this file says that.

export type ObservationSurface = {
  /** Noun phrase naming the condition, ready for a sentence subject. */
  condition: string;
  /** What the condition exposes people to. No score, no band, no number. */
  consequence: string;
};

export type ActionSurface = {
  /** Highest control in the hierarchy that this catalogue can name. */
  primary: string;
  /** Optional supporting control, always weaker than `primary`. */
  supporting?: string;
  /** What closing the action looks like on paper. */
  closure: string;
};

export type VerificationSurface = {
  /** What must be examined. Never "is missing" -- only "must be verified". */
  subject: string;
  closure: string;
};

// ---------------------------------------------------------------------------
// Observed conditions, keyed by mechanism code from the analysis engine.
// ---------------------------------------------------------------------------

export const OBSERVATION_BY_MECHANISM: Record<string, ObservationSurface> = {
  fall_from_height: {
    condition: "yüksekte çalışma yüzeyinin kenarında toplu koruma eksikliği",
    consequence: "çalışanların yüksekten düşmesi",
  },
  falling_object: {
    condition: "yüksekteki çalışma yüzeyinden malzeme düşmesine karşı koruma eksikliği",
    consequence: "alt kotta bulunan çalışanların üzerine malzeme düşmesi",
  },
  caught_in_pinch_shear: {
    condition: "hareketli makine parçalarına erişimi engelleyen koruyucunun bulunmaması",
    consequence: "çalışanın hareketli parçaya kaptırılması veya uzuv sıkışması",
  },
  sharp_edge_contact: {
    condition: "açıkta kalan sivri uçlara ve keskin kenarlara doğrudan erişim",
    consequence: "çalışanların saplanma veya kesilme yoluyla yaralanması",
  },
  electrical_contact_arc: {
    condition: "elektrik hattına doğrudan temas yolunun açık olması",
    consequence: "çalışanların elektrik çarpması veya ark yoluyla yaralanması",
  },
  mechanical_separation_release: {
    condition: "bağlantı elemanının emniyetinin üretici parçası dışındaki bir düzenle sağlanmış olması",
    consequence: "hattın basınç altında ayrılması ve madde salınımı",
  },
  hydraulic_pneumatic_release: {
    condition: "basınçlı hat üzerinde hasar ve emniyetsiz bağlantı",
    consequence: "basınçlı akışkanın boşalması ve çalışanın yaralanması",
  },
  fall_same_level: {
    condition: "geçiş güzergâhında malzeme birikmesi ve zemin düzensizliği",
    consequence: "çalışanların takılarak veya kayarak düşmesi",
  },
  vehicle_equipment_strike: {
    condition: "yaya güzergâhı ile araç güzergâhının fiziksel olarak ayrılmamış olması",
    consequence: "yayaların iş makinesi veya araç çarpması sonucu yaralanması",
  },
  structural_collapse: {
    condition: "taşıyıcı düzende kararsızlık belirtisi",
    consequence: "yapı veya istif elemanlarının göçmesi",
  },
  thermal_contact: {
    condition: "sıcak yüzeye korumasız erişim",
    consequence: "çalışanların yanma yoluyla yaralanması",
  },
  chemical_contact_release: {
    condition: "kimyasal maddeye korumasız temas yolu",
    consequence: "çalışanların kimyasal temas veya soluma yoluyla etkilenmesi",
  },
};

/**
 * Barrier members, named individually.
 *
 * The analysis engine decides WHICH member is missing and has a dedicated gate
 * for the case where it is guessing; here we only need the Turkish name. Order
 * matters: a paragraph reads top rail, mid rail, toeboard, in that order, the
 * way the components sit on the rail.
 */
export const BARRIER_MEMBER_TR: Record<string, string> = {
  top_rail: "ana korkuluk",
  mid_rail: "ara korkuluk",
  toeboard: "topuk levhası",
  guard: "koruyucu",
};

export const BARRIER_MEMBER_ORDER = ["top_rail", "mid_rail", "toeboard", "guard"];

// ---------------------------------------------------------------------------
// Corrective actions, keyed by mechanism. Control hierarchy is baked into the
// order: `primary` is always the collective or engineering control.
// ---------------------------------------------------------------------------

export const ACTION_BY_MECHANISM: Record<string, ActionSurface> = {
  fall_from_height: {
    primary:
      "açık kenar boyunca ana korkuluk, ara korkuluk ve topuk levhasından oluşan toplu koruma kesintisiz olarak sağlanmalı",
    supporting:
      "toplu koruma teknik olarak uygulanamayan bölümlerde hesaplanmış ankraj noktası üzerinden kişisel düşme durdurma sistemi kullandırılmalı",
    closure:
      "korumanın tamamlandığı yetkili kişi tarafından yerinde görülerek tutanağa bağlanmalıdır",
  },
  falling_object: {
    primary:
      "çalışma yüzeyinin kenarında topuk levhası ve gerektiğinde malzeme tutucu ağ sağlanmalı",
    supporting: "alt kottaki geçiş alanı fiziksel olarak kapatılmalı",
    closure:
      "uygulamanın tamamlandığı yerinde görülerek tutanağa bağlanmalıdır",
  },
  caught_in_pinch_shear: {
    primary:
      "hareketli parçalara erişimi engelleyen sabit veya kilitlemeli koruyucu takılmalı",
    supporting:
      "koruyucu sökülmeden makinenin çalışmasını engelleyen kilitleme düzeni işler hâle getirilmeli",
    closure:
      "koruyucunun takıldığı ve kilitlemenin çalıştığı işlevsel deneme ile doğrulanıp kayda geçirilmelidir",
  },
  sharp_edge_contact: {
    primary:
      "açıkta kalan uçlar kesilerek kaldırılmalı veya darbe emici başlıkla kapatılmalı",
    supporting: "alan geçiş güzergâhından fiziksel olarak ayrılmalı",
    closure: "uygulamanın tamamlandığı yerinde görülerek kayda geçirilmelidir",
  },
  electrical_contact_arc: {
    primary:
      "hat enerjisiz hâle getirilerek yalıtımı onarılmalı, güzergâh temas ve mekanik hasar riski bulunmayan biçimde yeniden düzenlenmeli",
    supporting:
      "onarım tamamlanana kadar alana erişim fiziksel olarak engellenmeli",
    closure:
      "yalıtım ve topraklama sürekliliği yetkili kişi tarafından ölçülerek kayda geçirilmelidir",
  },
  mechanical_separation_release: {
    primary:
      "geçici emniyet düzeni kaldırılarak üreticinin öngördüğü emniyet pimi veya kilit takılmalı",
    supporting:
      "bağlantı elemanı ile hortumun tip ve basınç sınıfı uyumu sağlanmalı",
    closure:
      "değişimin yapıldığı ve hattın basınç altında sızdırmazlığının denendiği kayda geçirilmelidir",
  },
  hydraulic_pneumatic_release: {
    primary:
      "hat basıncı boşaltılarak hasarlı bölüm değiştirilmeli, bağlantılar üretici talimatına göre yeniden yapılmalı",
    supporting: "hat üzerinde kamçı emniyeti sağlanmalı",
    closure: "basınç denemesi sonucu kayda geçirilmelidir",
  },
  fall_same_level: {
    primary:
      "geçiş güzergâhı üzerindeki malzeme kaldırılarak yüzey düzgün ve kuru hâle getirilmeli",
    supporting:
      "malzeme için belirlenmiş istif alanı tanımlanmalı ve güzergâh işaretlenmeli",
    closure: "düzenlemenin sürekliliği vardiya kontrolüyle izlenmelidir",
  },
  vehicle_equipment_strike: {
    primary:
      "yaya güzergâhı araç güzergâhından fiziksel bariyerle ayrılmalı",
    supporting: "geçiş noktalarında görüş ve öncelik düzeni tanımlanmalı",
    closure: "ayrımın uygulandığı yerinde görülerek kayda geçirilmelidir",
  },
  structural_collapse: {
    primary:
      "taşıyıcı düzenin yeterliliği yetkili kişi tarafından değerlendirilerek gerekli destekleme yapılmalı",
    supporting: "değerlendirme tamamlanana kadar alan boşaltılmalı",
    closure: "destekleme sonrası kabul yetkili kişi tarafından kayda geçirilmelidir",
  },
  thermal_contact: {
    primary: "sıcak yüzey yalıtılmalı veya erişim fiziksel olarak engellenmeli",
    supporting: "uyarı işaretlemesi tamamlanmalı",
    closure: "uygulamanın tamamlandığı yerinde görülerek kayda geçirilmelidir",
  },
  chemical_contact_release: {
    primary:
      "kimyasal madde kapalı sistemde tutulmalı, dökülme toplama düzeni sağlanmalı",
    supporting:
      "malzeme güvenlik bilgi formuna uygun kişisel koruyucu donanım kullandırılmalı",
    closure: "düzenlemenin tamamlandığı kayda geçirilmelidir",
  },
};

// ---------------------------------------------------------------------------
// Assurance topics: things a photograph can raise but never settle.
// ---------------------------------------------------------------------------

export const VERIFICATION_BY_TOPIC: Record<string, VerificationSurface> = {
  process_containment_integrity: {
    subject:
      "tank ve borulama hattının hizmet sınıfı, tasarım basıncı, kalınlık ölçümü ve muayene kayıtları ile emniyet valfi kalibrasyon durumu",
    closure:
      "muayene kapsamı, tarihi ve bir sonraki muayene zamanı ekipman dosyasına işlenmelidir",
  },
  hose_assembly_integrity: {
    subject:
      "hortum grubunun basınç sınıfı, üretim ve basınç test kayıtları ile bağlantı elemanının uyumu",
    closure:
      "test tarihi ve bir sonraki test zamanı hortum kayıt listesine işlenmelidir",
  },
  machine_protective_systems: {
    subject:
      "makinenin koruyucu düzeni, kilitleme işlevi ve acil durdurma erişilebilirliği",
    closure:
      "işlevsel deneme sonucu tarih ve sorumlusuyla kayda geçirilmelidir",
  },
  electrical_internal_integrity: {
    subject:
      "elektrik tesisatının topraklama sürekliliği, yalıtım direnci ve kaçak akım koruma ölçüm kayıtları",
    closure: "ölçüm raporu tarihiyle birlikte dosyalanmalıdır",
  },
  energy_isolation_controls: {
    subject:
      "tehlikeli enerji kaynaklarının izolasyon noktaları, kilitleme-etiketleme düzeni ve birikmiş enerjinin boşaltma yöntemi",
    closure:
      "izolasyon prosedürü ekipman bazında yazılı hâle getirilmelidir",
  },
  lifting_inspection: {
    subject:
      "kaldırma ekipmanının kapasite bilgisi, periyodik kontrol raporu ve kaldırma aksesuarlarının uygunluğu",
    closure:
      "periyodik kontrol raporu tarihiyle birlikte dosyalanmalıdır",
  },
  working_at_height_access: {
    subject:
      "yüksekteki çalışma platformuna erişim düzeni, platform kurulum uygunluğu ve ankraj noktalarının yeterliliği",
    closure:
      "kurulum ve kabul kaydı yetkili kişi tarafından imzalanmalıdır",
  },
  chemical_identity_and_exposure: {
    subject:
      "kaptaki maddenin kimliği, malzeme güvenlik bilgi formu ve depolama uyumluluğu",
    closure:
      "madde listesi ve bilgi formları güncel hâlde bulundurulmalıdır",
  },
  mobile_equipment_controls: {
    subject:
      "iş makinesinin periyodik kontrolü, operatör yetki belgesi ve saha trafik düzeni",
    closure: "kontrol ve yetki kayıtları dosyalanmalıdır",
  },
  fire_emergency_readiness: {
    subject:
      "yangın söndürme ekipmanının erişilebilirliği, kontrol kayıtları ve acil çıkış güzergâhının açıklığı",
    closure: "kontrol kayıtları güncel tutulmalıdır",
  },
  asset_assurance_generic: {
    subject:
      "görülen ekipmanın periyodik kontrol, bakım ve uygunluk kayıtları",
    closure:
      "doğrulama sonucu tarih, sorumlu ve kabul ölçütüyle kayda geçirilmelidir",
  },
};

// ---------------------------------------------------------------------------
// Observation basis. The specialist chooses this; the engine never infers it.
// ---------------------------------------------------------------------------

export const OBSERVATION_BASIS_TR: Record<string, string> = {
  direct_site_observation: "saha incelemesinde",
  employer_supplied_visual_record: "işyerince iletilen görsel kayıt üzerinde",
  document_review: "belge incelemesinde",
  follow_up_check: "takip kontrolünde",
};

export const URGENCY_TR: Record<string, string> = {
  immediate: "derhal",
  short_term: "gecikmeksizin",
  planned: "planlanarak",
};
