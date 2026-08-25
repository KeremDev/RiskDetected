import type { NormalizedCandidate, V4ModuleID } from "./contracts.ts";

export type AssuranceTopic = {
  id: string;
  title: string;
  description: string;
  action: string;
};

const BY_MODULE: Record<string, AssuranceTopic> = {
  falls_falling_objects: {
    id: "working_at_height_access",
    title: "Düşme ve düşen cisim güvenceleri saha teyidi",
    description:
      "Görünen çalışma alanının tüm kenar, platform, sabitleme ve düşen cisim koruma düzeni fotoğraftan kesinleştirilemiyor.",
    action:
      "Erişim, kenar koruması, platform bütünlüğü ve düşen cisim önlemlerini sahada birlikte doğrulayın.",
  },
  work_at_height: {
    id: "working_at_height_access",
    title: "Yüksekte çalışma erişimi ve koruması saha teyidi",
    description:
      "Görünen çalışma alanında erişim ve koruma düzeninin tüm geometrisi fotoğraftan kesinleştirilemiyor.",
    action:
      "Erişim, kenar koruması, platform bütünlüğü ve düşen cisim önlemlerini sahada birlikte doğrulayın.",
  },
  machinery: {
    id: "machine_protective_systems",
    title: "Makine koruyucu sistemleri saha teyidi",
    description:
      "Makinenin koruyucu düzeni, kilitlemeleri veya durdurma işlevi görüntüden bütünüyle doğrulanamıyor.",
    action:
      "Koruyucuları, kilitlemeleri ve acil durdurma işlevini yetkili kişiyle sahada doğrulayın.",
  },
  electrical: {
    id: "electrical_internal_integrity",
    title: "Elektriksel iç bütünlük saha teyidi",
    description:
      "Görünen elektrik ekipmanının iç bağlantıları, koruma düzeni ve test durumu fotoğraftan doğrulanamaz.",
    action:
      "Yetkili elektrik personeliyle koruma, topraklama ve test durumunu sahada doğrulayın.",
  },
  energy: {
    id: "energy_isolation_controls",
    title: "Tehlikeli enerji izolasyonu saha teyidi",
    description:
      "İzolasyon noktaları, birikmiş enerji ve yeniden enerjilenmeyi önleyen güvenceler görüntüden bütünüyle doğrulanamaz.",
    action:
      "Tüm enerji kaynaklarını, izolasyon noktalarını, kilitleme düzenini ve sıfır enerji doğrulamasını sahada kontrol edin.",
  },
  vehicles_mobile_equipment: {
    id: "mobile_equipment_controls",
    title: "Hareketli ekipman güvenceleri saha teyidi",
    description:
      "Görünen hareketli ekipmanın kapasitesi, kör nokta kontrolleri, bakım ve yetkilendirme durumu fotoğraftan kesinleştirilemez.",
    action:
      "Ekipman kimliğini, çalışma sınırlarını, bakım durumunu ve yaya–araç yönetimini sahada doğrulayın.",
  },
  logistics: {
    id: "mobile_equipment_controls",
    title: "Lojistik hareket ve ekipman güvenceleri saha teyidi",
    description:
      "Görünen trafik düzeninin işletim kuralları, kör nokta kontrolleri ve ekipman güvenceleri fotoğraftan bütünüyle doğrulanamaz.",
    action:
      "Yaya–araç ayrımını, trafik kurallarını, ekipman sınırlarını ve bakım durumunu sahada doğrulayın.",
  },
  lifting: {
    id: "lifting_inspection",
    title: "Kaldırma ekipmanı güvencesi saha teyidi",
    description:
      "Görünen kaldırma ekipmanının kapasitesi, iç bütünlüğü ve kontrol durumu fotoğraftan belirlenemez.",
    action:
      "Ekipman kimliği, kapasite, aksesuar uygunluğu ve kontrol durumunu sahada doğrulayın.",
  },
  process_integrity: {
    id: "process_containment_integrity",
    title: "Proses bütünlüğü saha teyidi",
    description:
      "Görünen tank veya borulama sisteminin iç bütünlüğü, proses koşulları ve koruma katmanları görüntüden kesinleştirilemez.",
    action:
      "İç bütünlük, proses parametreleri, izolasyon ve acil durum düzenini sahada doğrulayın.",
  },
  chemical: {
    id: "chemical_identity_and_exposure",
    title: "Kimyasal kimlik ve maruziyet saha teyidi",
    description:
      "Maddenin kimliği, konsantrasyonu veya maruziyet düzeyi görüntüden güvenilir biçimde belirlenemez.",
    action:
      "Etiket, güvenlik bilgi formu, proses bilgisi ve gerekli ölçümleri sahada doğrulayın.",
  },
  confined_space: {
    id: "confined_space_controls",
    title: "Kapalı alan güvenceleri saha teyidi",
    description:
      "Atmosfer, izolasyon, kurtarma ve izin düzeni tek görüntüyle doğrulanamaz.",
    action:
      "Atmosfer ölçümü, enerji izolasyonu, gözcü, iletişim ve kurtarma planını sahada doğrulayın.",
  },
  excavation: {
    id: "excavation_stability_controls",
    title: "Kazı ve zemin stabilitesi saha teyidi",
    description:
      "Zemin özellikleri, iksa yeterliliği, yeraltı hizmetleri ve stabilite hesabı tek görüntüyle doğrulanamaz.",
    action:
      "Zemin, iksa, yaklaşma mesafeleri, yeraltı hizmetleri ve yetkili kontrolü sahada doğrulayın.",
  },
  hot_work: {
    id: "hot_work_controls",
    title: "Sıcak çalışma güvenceleri saha teyidi",
    description:
      "İzin, gaz ölçümü, yangın gözcüsü ve çalışma sonrası izleme görüntüden doğrulanamaz.",
    action:
      "Sıcak çalışma izin ve gözetim düzenini, yanıcı kontrolünü ve yangın hazırlığını sahada doğrulayın.",
  },
  biosecurity: {
    id: "biosecurity_controls",
    title: "Biyogüvenlik güvenceleri saha teyidi",
    description:
      "Maruziyet sınıfı, dekontaminasyon ve prosedürel kontroller fotoğraftan bütünüyle doğrulanamaz.",
    action:
      "Biyolojik risk sınıfını, dekontaminasyon akışını ve koruyucu prosedürleri sahada doğrulayın.",
  },
  combustible_dust: {
    id: "combustible_dust_controls",
    title: "Yanıcı toz güvenceleri saha teyidi",
    description:
      "Tozun patlayıcılık özellikleri, konsantrasyonu, zon sınıflandırması ve koruma performansı fotoğraftan belirlenemez.",
    action:
      "Malzeme özelliklerini, toz kontrolünü, tutuşturucu kaynakları ve patlamadan korunma düzenini sahada doğrulayın.",
  },
  fire_explosion_release: {
    id: "fire_emergency_readiness",
    title: "Yangın, patlama ve acil durum güvenceleri saha teyidi",
    description:
      "Bakım, kapasite, organizasyonel hazırlık ve görünmeyen koruma işlevleri tek görüntüyle doğrulanamaz.",
    action:
      "Tutuşturucu kaynak kontrolünü, bakım kayıtlarını, görevleri ve acil durum düzenini sahada doğrulayın.",
  },
};

export function assuranceTopicForModule(
  moduleID: V4ModuleID,
  fallbackLabel = "Görünen varlık",
): AssuranceTopic {
  return BY_MODULE[moduleID] ?? {
    id: "asset_assurance_generic",
    title: `${fallbackLabel} saha teyidi`,
    description:
      "Görünen varlığın belge, ölçüm, test veya iç bütünlük gerektiren yönü fotoğraftan kesinleştirilemez.",
    action: "Varlığa özgü güvenceyi yetkili kişiyle sahada doğrulayın.",
  };
}

export function assuranceTopic(candidate: NormalizedCandidate): AssuranceTopic {
  return assuranceTopicForModule(
    candidate.module_id,
    candidate.normalized_label,
  );
}
