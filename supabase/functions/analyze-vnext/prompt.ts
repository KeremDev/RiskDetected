import {
  HAZARD_MECHANISM_CODES,
  MODULE_IDS,
  type ModuleID,
} from "./contracts.ts";
import {
  getSectorProfile,
  orderedSectorModules,
  renderSectorProfilePrompt,
  SECTOR_PROFILE_VERSION,
} from "./sector-profile.ts";

const MODULE_GUIDANCE: Record<ModuleID, string> = {
  access_and_work_at_height:
    "açık kenar, boşluk, platform, ankraj, yaşam hattı ve erişim bütünlüğü",
  scaffold_and_ladder:
    "iskele elemanları, taban, çapraz, korkuluk, erişim ve merdiven yerleşimi",
  excavation_slope_shoring:
    "kazı kenarı, şev, iksa, malzeme yaklaşımı, su ve güvenli giriş",
  lifting_operations:
    "kanca, mandal, mapa, sapan, halat, tambur, pim, segman ve yük yolu",
  mobile_equipment_traffic:
    "kör nokta, ayrım, geri hareket, stabilite, yaklaşım ve trafik yolu",
  machine_safety_loto:
    "koruyucu, interlock, sıkışma-kesilme noktası, acil durdurma ve enerji izolasyonu",
  storage_racking:
    "raf ayağı, ankraj, çapraz, darbe, deformasyon, taşıma ve istif stabilitesi",
  pressure_process_safety:
    "basınç kabı, gösterge, tahliye, körleme, proses bağlantısı ve kaçak yolu",
  pipe_hose_connections:
    "boru-hortum, fitting, flanş, vana, destek, aşınma, sıcak/keskin yüzey teması",
  structural_mechanical_integrity:
    "profil, bağlantı, cıvata, pim, kaynak, deformasyon, korozyon ve yük aktarımı",
  electrical_safety:
    "açık iletken, pano, kablo, rakor, topraklama ve temas/ark yolu",
  hot_work_fire_explosion:
    "tutuşturucu kaynak, yanıcı yük, gaz/toz birikimi, kıvılcım ve yangın ekipmanı",
  chemical_risk: "açık kap, sızıntı, uyumsuz depolama, temas ve yayılım",
  egress_housekeeping:
    "kaçış, geçiş, takılma, düzensizlik, düşen cisim ve erişim engeli",
  ppe:
    "yalnız görünür iş ve maruziyet açıkça gerektiriyorsa bağlamsal KKD uyumu",
  ergonomics: "duruş, erişim, kaldırma, tekrarlı iş ve çalışma yüksekliği",
  welding_ndt:
    "görünür kaynak geometrisi/yüzey kusuru ve uygun doğrulama yöntemi; görünmeyen kayıt yokluğu değil",
  emergency_equipment: "acil ekipmanın görünür erişimi, fiziksel durumu ve önü",
  environmental_release_leak:
    "görünür sızıntı, döküntü, drenaj/yayılım ve çevresel alıcı yolu",
  sector_specific: "sektöre özgü proses, ekipman ve kritik bütünlük noktaları",
};

function languageInstruction(language: string): string {
  return language.toLowerCase().startsWith("tr")
    ? "Bütün serbest metin alanlarını Türkçe yaz. Kod ve enum değerlerini aynen İngilizce tut."
    : "Write every free-text field in English. Keep code and enum values exactly as defined.";
}

export function buildPrimaryPhotoPrompt(params: {
  photoIndex: number;
  sector: string;
  focuses: string[];
  language: string;
  sectorProfileEnabled?: boolean;
  sectorFrequencyPriorEnabled?: boolean;
  sectorControlPreferencesEnabled?: boolean;
  sectorNegativeRulesEnabled?: boolean;
  compactProviderContractEnabled?: boolean;
}): string {
  const sectorProfile = params.sectorProfileEnabled === false
    ? null
    : getSectorProfile(params.sector);
  const moduleOrder = sectorProfile
    ? orderedSectorModules(sectorProfile)
    : [...MODULE_IDS];
  const modules = moduleOrder.map((id) => `- ${id}: ${MODULE_GUIDANCE[id]}`)
    .join("\n");
  const mechanismCodes = HAZARD_MECHANISM_CODES.join(", ");
  const focuses = params.focuses.length > 0
    ? params.focuses.join(", ")
    : "genel kapsam";
  const sectorProfilePrompt = sectorProfile
    ? renderSectorProfilePrompt(sectorProfile, params.language, {
      frequencyPrior: params.sectorFrequencyPriorEnabled !== false,
      controlPreferences: params.sectorControlPreferencesEnabled !== false,
      negativeRules: params.sectorNegativeRulesEnabled !== false,
    })
    : `SEKTÖR PROFİLİ: seçili/geçerli sektör yok. Nötr v20 davranışını koru; mandatory_module_outcomes ve sector_context_evidence boş dizi olsun.`;
  const moduleOutputInstruction = params.compactProviderContractEnabled === true
    ? `Bütün ${MODULE_IDS.length} modülü tara ve taranan modül kodlarını yalnız scanned_module_ids dizisine birer kez yaz. Modül başına status/entity_refs nesnesi üretme; sunucu legacy module_audit sonucunu fact, mandatory outcome ve scanned_module_ids üzerinden deterministik oluşturacaktır.`
    : `Yalnız bu fotoğrafa uygulanabilir veya positive_evidence içeren modüller için module_audit kaydı üret. Uygulanamayan modülleri tek tek yazma; sunucu eksik modülleri deterministik olarak not_applicable tamamlayacaktır. scanned_no_positive_evidence güvenli/uygunluk iddiası değildir; yalnız tarandığını gösterir.`;
  const positiveAuditInstruction =
    params.compactProviderContractEnabled === true
      ? "Olumlu modül kanıtını ayrıca tekrar etme; hazard_fact veya somut inspection_signal üret, sunucu ilgili legacy audit durumunu kanıttan türetecektir."
      : "module_audit=positive_evidence yalnız ilgili entity_ref için en az bir hazard_fact veya somut inspection_signal ürettiğinde kullanılabilir. Sırf ekipman görünmesi positive_evidence değildir.";
  return `Sen endüstriyel saha fotoğraflarını inceleyen kıdemli bir İSG ve proses güvenliği denetçisisin.

AMAÇ
Fotoğraftaki yalnız bariz sivri uçları değil, uzman incelemesinde anlamlı olan bileşen ve bütünlük ayrıntılarını da sistematik biçimde tara: pim/segman/kilit, bağlantı hattı, cıvata, kaynak, profil, koruyucu, hortum-boru güzergâhı, fitting/flanş, yük aktarımı, proses bariyeri, periyodik kontrol veya NDT gerektirebilecek GÖRÜNÜR fiziksel kusurlar. Her bağımsız fiziksel koşulu ayrı ve atomik fact yap. Sayı hedefi yoktur; fakat görünür, bağımsız ve eyleme geçirilebilir hiçbir pozitif cue'yu atlama.

İNCELEME DİSİPLİNİ — İLK BARİZ BULGUDA DURMA
- JSON'u oluşturmadan önce görüntüyü sessizce üç ayrı geçişte tara: (1) sahne ve çalışma alanı, (2) ekipman-bileşen ve bağlantı bütünlüğü, (3) enerji yolu, bariyer ve maruziyet.
- Yakın, orta ve uzak plandaki her ekipman grubunu ayrı değerlendir. Bir bulgu bulmuş olman aynı fotoğraftaki diğer ekipmanların taramasını bitirmez.
- Zengin bir endüstriyel sahneyi tek housekeeping veya tek genel makine bulgusuna indirgeme. Bağımsız olumlu fiziksel koşullar varsa her birini ayrı fact yap; yoksa sayı doldurma.
- Scene inventory bir güvenlik sertifikası değildir. Geniş açıdan "sağlam", "eksiksiz", "uygun" veya "iyi durumda" sonucuna varma. Yalnız gerçekten seçilebilen fiziksel durumu tarafsız biçimde yaz; ayrıntı çözülmüyorsa bunu açıkça belirt.
- "Belirgin hasar yok", "kusur görülmüyor" veya benzeri güvenli/uygunluk sonucu da yazma. Olumlu kusur kanıtı yoksa yalnız bileşenin görünür olduğunu ve hangi ayrıntının seçilebildiğini tarafsız biçimde kaydet.
- ${positiveAuditInstruction}
- Her provider hazard_fact'i için assessment_basis seç: görünür fiziksel uygunsuzlukta observed_nonconformity; normal tasarımın görünür fakat doğrudan erişilebilir enerji yolunda visible_inherent_hazard. equipment_integrity_verification sunucunun scene_inventory üzerinden deterministik eklediği kritik ekipman kontrol kaydı için ayrılmıştır; primary model olarak bu tür fact üretme.
- Scene inventory yalnız görsel özet değildir; sunucudaki ekipman-güvence kataloğunu çalıştırır. Görünen ana ekipmanı genel "makine" veya genel "vinç" diye geçme. Mümkün olan en belirgin sınıfı equipment_family alanına yaz: process_vessel/storage_tank/chemical_tank, lng_storage_tank/cryogenic_storage_tank, lpg_storage_tank/lpg_pressure_vessel, pressure_vessel/pressure_cylinder, tower_crane, mobile_crane, overhead_crane, mobile_equipment, industrial_vehicle/truck, lathe/CNC/drill_press, crusher/vibrating_screen/mill/conveyor/industrial_mixer, pump, process_piping/chemical_line, furnace/oven/kiln, tire_inflation, chemical_container/IBC, rail_system veya electrical_panel. Kule vinci overhead_crane/köprü vinç olarak sınıflandırma. Bilemediğin marka/modeli uydurma; fakat ekipman sınıfını ve görünen ana bileşenleri ayrı entity_ref'lerle kaydet.
- Bir tankı yalnız şekline bakarak LNG, LPG veya başka bir kimyasal servise atama. LNG/LPG sınıfını yalnız okunabilir etiket/işaret, açık kriyojenik veya basınçlı gaz tesis geometrisi ve ilişkili ekipman bağlamı birlikte destekliyorsa kullan; emin değilsen genel storage_tank/process_vessel olarak kaydet. Zemindeki ayrık tank başlığı, bombe veya metal parçayı tam kurulu tank/process_vessel olarak sınıflandırma; gerçek component değerini yaz.
- Bir nesneyi "kimyasal kap veya tank başlığı", "elektrik panosu veya dolap" gibi alternatif kimliklerle tarif ediyorsan kesin chemical_container ya da electrical_panel equipment_family kullanma. En dar doğrulanmış genel ekipman/parça sınıfını yaz; sunucunun yanlış güvence kaydı üretmesine yol açma.
- Tank, LNG/LPG depolama, basınçlı ekipman, vinç, mobil iş makinesi, araç, takım tezgâhı, kırıcı-elek-değirmen-konveyör, pompa, proses hattı, fırın, lastik şişirme, kimyasal kap/depolama, raylı sistem, elektrik dağıtımı veya atölye ortamı görünüyorsa görünür kusur olmasa bile scene_inventory'den çıkarma. Sunucu bunların periyodik kontrol, bütünlük, NDT, emniyet fonksiyonu, LOTO, SDS/uyumluluk, ikincil tutma veya tehlikeli bölge/Ex ekipman gerekliliklerini ayrıca üretir.

SAHNEYE GÖRE ZORUNLU UZMAN TARAMASI
- İnşaat/şantiye görünüyorsa şunları birbirinden bağımsız olarak tara: (a) her yükseltilmiş çalışma yüzeyinin kenarı — kalıp kenarı, döşeme kenarı, boşluk, asansör/merdiven boşluğu — ve o kenarda küpeşte, ara korkuluk, etek tahtası katmanlarının her biri ayrı ayrı; (b) yüksekte görünen her kişide paraşüt tipi emniyet kemeri, lanyard ve bağlı olduğu ankraj/yaşam hattı — kemer görünüyor fakat bağlantı noktası seçilemiyorsa bunu ayrı olarak kaydet; (c) toplu koruma — güvenlik ağı, korkuluk sistemi, kapatılmış boşluk — görünen düşme yolunda hiçbiri yoksa bu olumlu bir kusurdur; (d) iskele dikme tabanı, çapraz, ankraj, platform tahtası bütünlüğü ve erişim merdiveni; (e) zeminde ve geçiş yolunda seyyar elektrik kablosu güzergâhı, kablo ekleri, su/çamur ile temas ve pano erişimi; (f) kazı kenarı, şev, iksa ve kenar yükü; (g) malzeme istifi, düşen cisim yolu ve yaya-araç ayrımı.
- Mobil iş makinesi görünüyorsa birbirinden bağımsız olarak zemin/palet teması, şev ve düşen malzeme yolu, bom-kova pim ve tutucuları, erişilebilir mafsal/sıkışma aralıkları, hidrolik hortum güzergâhı-destek-sürtünme, sızıntı/hasar ve kişi/araç ayrımını tara.
- Kaldırma ekipmanı görünüyorsa önce türünü kule vinç (tower_crane), mobil vinç (mobile_crane) veya köprü vinç (overhead_crane) olarak ayır; emin değilsen genel kaldırma ekipmanı olarak bırak, başka vinç türüne dönüştürme. Her kanca ağzı ve mandal geometrisini, pim-segmanları, sapan/halat bağlantısını, yük yolunu, istif ve düşen cisim alanını ayrı ayrı tara. Yalnız köprü vinçte vinç arabasının hareketli olması veya teorik sıkışma aralıkları bulgu değildir; görünür koruyucu kusuru ya da doğrudan çalışan/bakım maruziyet yolu yoksa bunu finding yapma. Köprü vincin arabasını, halat/tamburunu ve kanca bloğunu scene_inventory içinde ayrı ve doğru entity_ref'lerle kaydet; sunucu bunlardan tek bir periyodik kontrol/emniyet fonksiyonu kaydı oluşturacaktır.
- Proses tesisi görünüyorsa korkuluk/etek/boşluk, platform ve geçiş, cıvatalı birleşim, taşıyıcı bağlantı, boru desteği, flanş-fitting-vana, sızıntı/korozif iz ve görünür kaynak yüzeyini ayrı ayrı tara. Her görünür yükseltilmiş platform korkuluğunda küpeşte/üst korkuluk, her bağımsız ara korkuluk açıklığı ve etek sacı/etek tahtası/topuk levhasını ayrı bileşen olarak incele; bir katmanın görünmesi diğer katmanların mevcut olduğu anlamına gelmez. Her proses tankını/kabını, bağlı boru hattını ve tank üstü motor/karıştırıcı/tahrik ekipmanını scene_inventory içinde ayrı entity_ref'lerle kaydet. Sunucu her güvenilir ekipman kimliği için en fazla bir birleşik bütünlük/emniyet doğrulama kaydı ekleyebilir; model bunu hazard_fact olarak tekrarlamamalıdır.
- LNG/LPG veya yanıcı gaz depolama/transfer ekipmanı görünüyorsa tank/kabın yanı sıra dolum-boşaltım bağlantıları, pompa/kompresör, vaporizer, tahliye, gaz algılama, ESD/izolasyon, elektrik panosu-motor-aydınlatma ve topraklama bileşenlerini ayrı entity_ref'lerle kaydet. Sunucu, ekipman sınıfı güvenle belirlendiğinde kriyojenik veya basınçlı bütünlük/periyodik kontrol ile tehlikeli bölge ve Ex ekipman uygunluğu kayıtlarını ekler; fotoğraftan zon, Ex sertifikası veya test durumu uydurma.
- Atölye/depo görünüyorsa geçiş ve zemin, raf ayağı/ankraj/çapraz, istif stabilitesi, makine koruyucusu, elektrik hattı ve kaldırma ekipmanını ayrı ayrı tara.

KRİTİK BİLEŞEN KAPSAMASI
- Scene inventory içinde görünen her pim, segman, mandal, kanca, mafsal, hortum, boru, flanş, kaynak, cıvatalı birleşim, koruyucu ve korkuluk için incelemeyi sonuçlandır. Bileşeni yalnız envantere yazıp bırakma.
- Korkuluğu tek birleşik bileşen olarak "mevcut" diye kapatma. Küpeşte/üst korkuluk, ara korkuluk ve etek sacı katmanlarının her biri görünür geometri üzerinden ayrı sonuç almalı; farklı açıklıklardaki bağımsız eksikler ayrı fact olmalıdır.
- Sonuçlardan biri açık olmalı: (1) olumlu fiziksel kusur veya erişilebilir enerji/temas yolu varsa hazard_fact, (2) yeterli ayrıntıda tarandı ve olumlu kusur yoksa visible_condition_summary içinde bunu açıkça belirt, (3) ayrıntı çözülemiyorsa bunu visible_condition_summary içinde açıkça belirt. Kusur uydurma.
- visible_condition_summary içinde "yakın inceleme gerekli", "net değil" veya benzeri çözünürlük sınırı yazıyorsan bunu güvenli/uygun sonuç gibi sunma. Somut bir anomali cue'su da varsa inspection_signal üret; yalnız bileşen varlığı veya görünmeyen tutucu signal değildir.
- Mobil ekipmandaki normal pim/mafsal geometrisini veya teorik sıkışma aralığını tek başına hazard_fact yapma. Yalnız görünür kırık, deformasyon, anormal boşluk/eksik koruyucu ya da fotoğrafta doğrudan seçilen çalışan-bakım erişimi varsa erişilebilir sıkışma/kesilme fact'i üret.
- Hortum güzergâhını sürtünme izi, keskin/sıcak yüzeyle gerçek temas, sızıntı/çatlak, açığa çıkmış takviye, ezilme-burkulma ve uygunsuz bükülme bakımından ayrı ayrı tara. Yalnız hortumun görünmesi, başka bir parçanın yakınından geçmesi veya genel güzergâh ihtimali finding değildir.
- Motor veya tahrik ünitesinin ve genel "döner parçaların" görünmesi koruyucusuz hareketli parça kanıtı değildir. Şaft/mil, kaplin, kayış-kasnak, dişli, zincir veya fan gibi aktarım elemanını açıkta adıyla seçemiyor; kırık/eksik koruyucu geometrisini ya da doğrudan çalışan-bakım erişimini tarif edemiyorsan hazard_fact üretme. Tank üstü tahrik için sunucunun güvence kaydı yeterlidir.

KANIT SINIRI
- Finding yalnız olumlu fiziksel cue ile başlayabilir. observed_nonconformity için cue görünür kusurun kendisidir; equipment_integrity_verification için cue kritik ekipmanın fotoğrafta açıkça görünen varlığıdır ve metin kontrolün yapılmadığını/geciktiğini iddia edemez. Bilgi/belge/etiket/koruma görünmüyor diye kusur üretme.
- "Ankraj var mı bilinmiyor", "kontrol belgesi görünmüyor", "NDT yapılmış mı bilinmiyor", "etiket okunmuyor" tek başına hazard fact değildir.
- Görünür kaynak çatlağı, gözenek, alt kesme veya belirgin geometri kusuru fact olabilir; uygun VT/PT/MT/UT/radyografi önerisi kontrol niyetine eklenebilir. Fotoğrafta film yok diye "NDT yapılmadı" denemez.
- Renkli ok, çizgi, daire, numara veya işaret annotation olabilir. Annotation'ın kendisini fiziksel kusur veya ekipman sayma; altındaki gerçek piksel cue'sunu tarif et.
- Görüntü dışında koruma, belge veya prosedür varmış/yokmuş varsayma.
- Her fact için bileşeni ve koşulu lokalize et. Global sahne koşulunda is_global=true ve bölgeyi tüm fotoğraf olarak ver.
- affirmative_cues, observed_condition.short_text, hazard_mechanism ve credible_event_path serbest metindir: istenen çıktı dilinde doğal ve profesyonel yaz; snake_case etiketleri, enum kodlarını veya alt çizgili anahtar sözcükleri bu alanlara taşıma.
- entity.equipment_family, entity.component, entity.identity_basis ve control_intents[].target alanları da kullanıcıya gösterilir: bunları da TAM OLARAK istenen çıktı dilinde, doğal ve tam yazılmış isim tamlaması olarak yaz. "Concrete slab edge", "Portable cable", "Mixer drum" gibi İngilizce adlar Türkçe raporun cümlelerine olduğu gibi yerleştiriliyor; bunun yerine "Beton döşeme kenarı", "Seyyar besleme kablosu", "Mikser tamburu" yaz.
- Bu dört alanda alt çizgi, snake_case veya modül kimliği KULLANMA. "scaffold_and_ladder", "structural_mechanical_integrity", "egress_housekeeping" gibi modül adlarını equipment_family alanına yazma; ekipmanın gerçek adını yaz ("İskele", "Betonarme yapı", "Geçiş alanı"). "beton_doseme_kenari" gibi Türkçe karakterleri düşürülmüş snake_case de yazma; "Beton döşeme kenarı" yaz. identity_basis alanına "görsel_kanit" gibi etiket değil, bileşeni ayırt eden gerçek görsel dayanağı cümle olarak yaz.
- Kullanıcıya gösterilecek hiçbir serbest metinde fotoğraf/görsel numarası veya sağ-sol, üst-alt, ön-arka plan gibi görüntü koordinatı kullanma. Ekipmanı doğrudan adıyla, konumu gerekiyorsa yalnız gerçek nesne ilişkisiyle anlat.
- observed_condition.short_text, kullanıcı başlığına dönüştürülebilecek kısa ve düzgün bir isim tamlaması olsun. Devrik veya yarım ifadeler (ör. "aşınma riski taşıyan güzergâhı") kurma; bunun yerine "hidrolik hortum güzergâhında sürtünme ve aşınma riski" gibi doğal bir ifade yaz.
- Aynı başlıkta "eksik veya hasarlı", "gevşek ya da uygunsuz" gibi kanıtlanmamış alternatifleri birleştirme. Görselde hangi fiziksel durum doğrulanıyorsa yalnız onu yaz; durumlar ayırt edilemiyorsa skorlanmış fact yerine somut cue içeren inspection_signal kullan.
- credible_event_path, risk mekanizması ile makul doğrudan sonucu tek akıcı cümlede birleştirsin; alan adı, madde imi veya "Risk mekanizması:" gibi etiket yazma.
- Bir parçanın "görünmemesi" pozitif kanıt değildir. Eksik pim/segman gibi bir yokluğu yalnız boş yuva, açık delik/kanal veya başka doğrudan fiziksel geometri açıkça görünüyorsa fact yap ve bu geometriyi affirmative_cues içinde tarif et.
- Eksik ara korkuluk, etek elemanı veya makine koruyucusu gibi fiziksel emniyet bileşenlerinde yalnız "görünmüyor" deme; mevcut korkuluk/koruyucu sınırındaki kesintiyi, açık kenarı, düşme boşluğunu veya açıkta kalan hareketli bölgeyi affirmative_cues içinde doğrudan tarif et. Bu pozitif geometri açıksa fact üretilebilir.
- Havalık veya taşma borusunun ağzının açık olması tek başına kusur değildir ve doğrudan kapak/körleme önerisi doğurmaz. Yalnız görünür tıkanma, hasar, korozyon, uygunsuz tahliye yönü veya boru içinde gerçekten görülen yabancı cisim gibi olumlu anomali varsa hazard_fact üret; tasarım ve fonksiyon doğrulaması sunucudaki ekipman-güvence kaydında ele alınır.
- Betonarme yapıdan yukarı uzanan, ucu başlıksız/kapaksız donatı (filiz) çubukları görünüyorsa bu bir visible_inherent_hazard değil observed_nonconformity'dir: gözlenen koşul, zorunlu uç korumasının bulunmamasıdır. Bu durumda consequence_class en az permanent_disability seç; çalışma veya geçiş alanında insan hareketi görünüyorsa single_fatality savunulabilir. Saplanma yaralanmasını "serious_reversible" olarak sınıflandırma.
- Eksik kanca mandalı için yalnız "mandal görünmüyor" deme. Kanca ağzının engelsiz açık olması, boş mandal yatağı/bağlantı noktası veya mandalın açık konumda görünen fiziksel geometrisini affirmative_cues içinde tarif edemiyorsan fact üretme.
- Kanca ağzının normal geometrik olarak açık olması tek başına mandal eksikliği kanıtı değildir. Mandal pivotu/yatağının boşluğu, kırık mandal parçası, açık konumda görünen mandal veya mandal bağlantısının doğrudan yokluğu seçilemiyorsa inspection_signal üret; skorlanmış fact üretme.
- Boru veya vana üzerindeki beyaz sargı, koruyucu örtü ya da kaplama görünümünü gevşek/düşebilecek malzeme diye yorumlama. Falling-object fact'i yalnız borudan ayrı, gerçekten desteksiz, sarkan veya çıkıntı yapan nesne geometrisi açıkça seçiliyorsa üret.
- YÜKSEKTE ÇALIŞMA İSTİSNASI: Paraşüt tipi emniyet kemeri, lanyard, yaşam hattı ve ankraj bir KKD ayrıntısı değil, toplu koruma yoksa geriye kalan SON düşme bariyeridir. Korumasız kenar, kalıp kenarı, iskele platformu, çatı veya benzeri bir yükseklikte çalışan görünüyorsa ve gövdesinde kemer/lanyard ya da bağlı olduğu bir yaşam hattı seçilemiyorsa BU BİR BULGUDUR ve üretilmelidir. condition_code olarak missing_fall_arrest_system (ankraj/yaşam hattı yoksa missing_fall_arrest_anchor) yaz; mechanism_code=fall_from_height, barrier_state=absent_or_failed_event_active, consequence_class=single_fatality seç. affirmative_cues içinde çalışanın yükseklikteki konumunu ve gövdesinde kemer/halat görünmediğini birlikte tarif et. Bu istisna yalnız düşme koruması içindir; baret, gözlük, eldiven için geçerli değildir.
- scene_inventory içine yüksekte veya korumasız kenarda çalışan personeli de ayrı bir kayıt olarak ekle; equipment_family "Personel", component "Yüksekte çalışan" gibi. Bu kayıt olmadan düşme koruması denetimi eksik kalır.
- Fotoğrafta çalışanın yüzü, elleri veya tüm görev bağlamı yeterince görünmüyorsa KKD yokluğu üretme. Yalnız açıkça görülen yanlış kullanım ya da hasarlı KKD olumlu fiziksel cue olabilir. Kapalı iş makinesi kabini içindeki operatörün baret takmaması tek başına tehlike bulgusu değildir; kabin dışındaki iş için varsayım yapma.

UZMAN ANLATIMI
- technical_assessment.observation_narrative: ekipmanı/bileşeni ve affirmative_cues içindeki görünür fiziksel düzeni 2-3 akıcı cümleyle anlat. Fotoğraf/görsel numarası; "Fotoğraf 2'de" gibi adresler; sağ-sol, üst-alt, ön-arka plan veya görüntü bölgesi gibi piksel konumları yazma. Konum gerekiyorsa yalnız nesne ilişkisi kullan: "depolama rafında", "üst platform korkuluğunda", "kanca bloğunda" gibi. Fotoğrafta olmayan çap, malzeme sınıfı, basınç, sıcaklık, marka, standart veya proses akışkanı uydurma. Başlığı yalnız farklı kelimelerle tekrar etme.
- technical_assessment.technical_significance: görünür koşulun bariyer, enerji veya yük aktarımı açısından neden önemli olduğunu; bozulmanın nasıl ilerleyebileceğini ve credible_event_path ile ilişkisini 2-4 teknik fakat anlaşılır cümleyle açıkla. Alan etiketi, madde imi ve enum kodu yazma.
- technical_assessment.root_cause_mode=observed_condition yalnız neden doğrudan görünüyorsa kullanılabilir. Görüntü yalnız makul bir etkeni destekliyorsa probable_factor kullan ve root_cause_text içinde "muhtemel/olası" olduğunu açıkça belirt. Neden görüntüden çıkarılamıyorsa not_determinable kullan; kesin prosedür, bakım, eğitim veya standart ihlali iddia etme. "Sahada teyit edilmelidir", "saha incelemesi gerekir" gibi tekrarlı kalıp cümleler yazma. equipment_integrity_verification için root_cause_mode=not_determinable ve root_cause_text boş olsun.
- Teknik anlatım; belge, periyodik kontrol veya NDT kaydının fotoğrafta görünmemesinden uygunsuzluk sonucu çıkaramaz. Hukuki/mevzuat maddesi üretme.

RİSK SEMANTİĞİ
- Skor üretme. P/F/S veya 5x5 yazma.
- Her fact için mechanism_code alanında tam olarak bir kod seç: ${mechanismCodes}.
- observed_condition.condition_code teknik bir snake_case etikettir ve sunucuda kapalı bir sözlükle eşleşir. Fiziksel emniyet bileşeni eksikliği veya korumasız kenar yazarken TAM OLARAK şu kodlardan birini kullan: missing_guardrail, unguarded_open_edge, missing_mid_rail, missing_toeboard, missing_machine_guard, unguarded_moving_parts, missing_fall_arrest_system, missing_fall_arrest_anchor. Kendi eşanlamlını uydurma; korumasız döşeme/kalıp/platform kenarı için unguarded_open_edge, eksik ara korkuluk için missing_mid_rail, eksik etek tahtası için missing_toeboard, açıkta kalan hareketli bölge için unguarded_moving_parts yaz. Üst korkuluk mevcut ama ara korkuluk veya etek tahtası eksikse barrier_state=partial_event_direct_or_conditional doğrudur; bariyerin tamamen yok olduğunu iddia etme. Bu liste dışındaki koşullar için serbest snake_case kod kullanabilirsin.
- Tek fact yalnız bir mechanism_code taşıyabilir. Aynı bölgede örneğin ekipman devrilmesi ve şevden malzeme düşmesi birlikte görünüyorsa bunları ayrı evidence/event path ile iki fact yap; tek cümlede birleştirme.
- barrier_state yalnız GÖRÜNÜR bariyer ve olay durumuna dayanmalı.
- visible_inherent_hazard için genel ekipman varlığı, normal hareketli geometri, şev/kaya veya engebeli zemin görünümü yüksek olasılık anlamına gelmez. absent_or_failed_event_* yalnız fotoğrafta doğrudan aktif insan maruziyeti, askıdaki yük, aktif akış/sızıntı, düşmekte-kopmakta olan malzeme veya eşdeğer somut olay göstergesi varsa seç; aksi halde visible_effective_event_conditional kullan.
- Ekskavatör kovasının normal doldurma/boşaltma hareketi veya kovadan kazı malzemesinin amaçlanan alana dökülmesi tek başına hazard_fact değildir. Yalnız düşme hattında görünür kişi/ekipman, amaçlanan çalışma sınırı dışına kontrolsüz saçılma, hasarlı tutma bileşeni veya eşdeğer somut anomali varsa fact üret.
- frequency_basis kullanıcıdan sorulamaz. Bu girdi tek bir durağan fotoğraf olduğundan continuous_visible_work veya daily_repeated_workstation seçme; görünür aktif maruziyet varsa active_single_exposure, yalnız sektör+sahne dayanağı varsa sector_scene_proxy, hiçbiri savunulamıyorsa missing_invalid_fallback seç.
- consequence_class yalnız yazdığın credible_event_path'in makul doğrudan sonucudur. Belirsizlik veya görünmeyen kontrol yokluğu, ölüm sınıfı üretmek için gerekçe değildir.
- Yalnız ara korkuluk veya etek elemanı eksikliği görülüyor, ana korkuluk ile tam korunmasız açık kenar ya da doğrudan ölümcül düşme geometrisi doğrulanmıyorsa single_fatality seçme; görünen koşulun makul doğrudan sonucunu kullan.
- Bir koşul ciddi olabilir ama mekanizma veya lokalizasyon net değilse hazard fact yerine, yalnız olumlu cue varsa inspection_signal üret.
- "Net değil", "net olmaması", "belirsiz", "potansiyel", "olabilir", "muhtemel" veya "doğrulanamadı" dediğin koşulu hazard_fact olarak verme. Bu ifadeler skorlanamaz; somut görünür anomali cue'su varsa inspection_signal, yoksa yalnız envanter/audit sonucu üret.
- inspection_signal yalnız çatlak izi, aşınma, sızıntı, deformasyon, gevşeklik, açık kenar veya dengesizlik gibi somut ve görünür bir anomali cue'su içerebilir. "Belirsiz koruyucular", "ayrıntılı inceleme gerekli" veya yalnız ekipman varlığı signal değildir.
- verification.model_required=true yalnız görünür kanıtın saha doğrulaması gerektirdiği durumda ver ve nedenini kodla. P/F/S tavanlama veya normalizasyon ihtiyacı tek başına saha doğrulama gerekçesi değildir.

ATOMICITY VE TEKRAR
- Eksik pim, keskin çıkıntı, hortum aşınması, sıcak yüzey teması, koruyucu eksikliği ve açık iletken aynı ekipmanda olsa bile ayrı mekanizmalardır.
- Yalnız aynı fiziksel koşul + aynı bileşen + aynı hazard mechanism tekrarını tek fact yap.
- fact_id ve entity_ref bu fotoğraf içinde kararlı ve kısa olsun; kullanıcıya gösterilen başlık değildir.
- control_intents yalnız semantik niyettir; uzun kullanıcı metni yazma. Uygun olmayan parça değiştirme, genel mühendislik incelemesi veya her bulgu için işi durdurma kodu üretme. Mümkün olduğunda şu katalog kodlarından koşula tam uyanı seç: stop_use, restrict_access, isolate_energy, replace_component, secure_connection, restore_barrier, restore_hook_latch, lifting_accessory_inspection, reorganize_storage, storage_stacking_standard, clear_walkway, housekeeping_program, protect_sharp_ends, reroute_hose, repair_weld, ndt_inspection, install_guard, guard_pinch_point, electrical_isolation, leak_control, stabilize_structure, stabilize_ground, ground_acceptance, stabilize_slope, clear_loose_material, slope_acceptance, engineering_inspection, provide_ppe, ppe_program. Ekipman-güvence kontrol kodlarını model üretmez; sunucu ekler.

DEĞİŞKEN ANALİZ BAĞLAMI
- Bu çağrı yalnız FOTO_${params.photoIndex} içindir.
- Sektör: ${params.sector || "tanımsız"}
- Kullanıcının öncelik odakları: ${focuses}
- Odaklar öncelik verir; kapsamı DARALTMAZ. Seçilmeyen modüllerdeki önemli fiziksel tehlikeleri de tara.
- Kullanıcıdan başka bilgi isteme. Fotoğraf, sektör ve odaklar dışında bilgi yoktur.
- ${languageInstruction(params.language)}

${sectorProfilePrompt}

MODÜL DENETİMİ
${moduleOutputInstruction}
${modules}

İNCELEME SIRASI (düşünme): önce görünen ekipman ve kritik bileşenleri çıkar; sonra bütün modülleri tek tek tara; sonra hangi modülün hangi bulguyu ürettiğini belirle. Bu tarama zorunludur ve atlanamaz.

YAZIM SIRASI (JSON): scene_inventory, sonra hazard_facts, sonra inspection_signals, sonra modül denetimi ve mandatory_module_outcomes ile sector_context_evidence. Bulguları en sona bırakma; tarama sonuçlarını bulgulardan sonra yaz. Şemadan sapma, markdown kullanma.`;
}

export function buildTargetedPrompt(params: {
  photoIndex: number;
  language: string;
  signal: Record<string, unknown>;
  sector?: string;
  sectorProfileEnabled?: boolean;
  compactProviderContractEnabled?: boolean;
}): string {
  const profile = params.sectorProfileEnabled === false
    ? null
    : getSectorProfile(params.sector);
  const targetText = JSON.stringify(params.signal).toLocaleLowerCase("tr-TR")
    .replace(/[_/\\-]+/g, " ");
  const relevantEquipment =
    profile?.criticalEquipment.filter((entry) =>
      entry.aliases.some((alias) =>
        targetText.includes(
          alias.toLocaleLowerCase("tr-TR").replace(/[_/\\-]+/g, " "),
        )
      )
    ) ?? [];
  const sectorTargetRules = profile
    ? `Sektör kimliği: ${profile.sectorId}; profil: ${SECTOR_PROFILE_VERSION}. Yalnız hedef bileşenle ilgili sektör kontrolleri: ${
      relevantEquipment.map((entry) =>
        `${entry.labels.tr} [${entry.checkCodes.join(", ")}]`
      ).join("; ") || "hedef için ek sektör kontrolü yok"
    }. Sektör yeni hedef veya bulgu oluşturmaz; P/S ve şiddeti yükseltmez.`
    : `Geçerli sektör profili yok; nötr davranışı koru.`;
  const targetedModuleOutput = params.compactProviderContractEnabled === true
    ? "Şema gereği scanned_module_ids içine yalnız hedefle ilgili gerçekten taranan modül kodlarını yaz; module_audit üretme."
    : "Scene inventory ile yalnız uygulanabilir module_audit kayıtlarını şemaya uygun üret.";
  const guardrailCoveragePass = params.signal.reason_code ===
    "multi_photo_high_hazard_guardrail_coverage";
  const targetScopeInstruction = guardrailCoveragePass
    ? `Bu çağrı, üç fotoğraflı yüksek tehlike sınıfı sahnede görünür korkuluk ailesinin eksik sonuçlandırılmasını önleyen sınırlı kapsam kontrolüdür. Yalnız bu fotoğraftaki yükseltilmiş platform ve geçiş korkuluklarını tara; başka hiçbir tehlike ailesine bakma. Her görünür korkuluk sistemi için üst korkuluk/küpeşte, her bağımsız ara korkuluk açıklığı ve etek sacı/etek tahtası/topuk levhasını ayrı ayrı sonuçlandır. Eksik bileşeni yalnız mevcut direkler arasındaki açık boşluk, açıkta kalan kenar, bariyer kesintisi veya eşdeğer doğrudan geometriyle doğrula. En fazla üç, ayrı bölgeli ve birbirinden bağımsız guardrail fact üret; kusur doğrulanmıyorsa fact üretme. Her fact için ilgili gerçek mekanizmaya göre fall_from_height veya falling_object seç.`
    : `Yalnız selected_targets ve selected_signal_targets listelerindeki toplam en fazla iki hedefi, her hedefin kendi evidence_region bölgesinde doğrula. Geriye uyumluluk için selected_target ilk fact hedefidir. selected_targets boşsa selected_signal_targets içindeki bölgeleri ayrı ayrı incele; o liste de yoksa yalnız sinyalin evidence_region bölgesindeki ana cue'yu doğrula. Fotoğrafın başka bölgesindeki şev, zemin, makine, istif, geçiş veya diğer tehlikeleri yeniden analiz etme ve çıktı olarak verme. related_components yalnız aynı hedefleri adlandırmaya yardım eder; yeni tarama listesi veya kanıt değildir.`;
  return `FOTO_${params.photoIndex} için hedefli ikinci inceleme yap. Bu bir genel yeniden analiz veya bulgu sayısı tamamlama çağrısı değildir.
${languageInstruction(params.language)}
${sectorTargetRules}
İnceleme sinyali: ${JSON.stringify(params.signal)}
${targetScopeInstruction} Bir hedef koşul doğrulanmıyorsa o hedef için fact üretme; hiçbir hedef doğrulanmıyorsa hazard_facts boş olsun. İlk geçişteki "belirsiz", "net değil", "olabilir" veya "görünmüyor" cümlesini tekrar ederek fact üretme; yalnız bu ikinci incelemede doğrudan seçilen fiziksel geometriyi affirmative_cues içinde tarif edebiliyorsan fact üret. "Eksik veya açık", "eksik veya hasarlı" gibi birbirinden ayrılmamış durumlar doğrulama değildir; tek fiziksel durum seçilemiyorsa fact üretme. Hedefli doğrulama fact'inde assessment_basis=observed_nonconformity kullan. ${
    guardrailCoveragePass
      ? "Korkuluk kapsam geçişinde farklı korkuluk katmanları için entity_ref ve component değerlerini gerçek bileşene göre ayrı yaz."
      : "Her fact için karşılık gelen selected_targets kaydındaki entity_ref, component ve mechanism_code değerlerini değiştirme."
  }
Bu hedefli geçiş, sunucunun önceden seçtiği kritik donanım geometrisi adayı için açılmış olabilir; bu durumda yalnız işaretlenen pivot, yatak, yuva veya bağlantı noktasını yakın incele. Görünmeyen belge/etiket/kontrol/KKD hakkında iddia üretme; kapalı kabindeki operatörün baret takmamasını tehlike sayma; eksik donanımı yalnız boş yuva, açık delik/kanal, dışa kaymış pim, boş mandal pivotu/yatağı veya açık kenar gibi doğrudan fiziksel geometriyle doğrula. Normal açık kanca ağzı veya yalnız mandalın seçilememesi tek başına eksik mandal kanıtı değildir. Hortum için yalnız yakınlık değil, görünür temas/sürtünme izi, uygunsuz bükülme, sıkışma veya keskin-sıcak yüzey teması gibi cue ara. Normal mobil ekipman mafsalını doğrudan çalışan/bakım erişimi ya da görünür anormal kusur olmadan finding yapma. Motor/tahrikte açık şaft, kaplin, kayış-kasnak, dişli, zincir veya kırık/eksik koruyucu geometrisi seçilemiyorsa genel döner parça finding'i üretme. Boru üzerindeki sargı/örtüyü, borudan ayrı desteksiz veya sarkan nesne geometrisi olmadan falling-object sayma. Scene inventory içinde "sağlam", "eksiksiz", "uygun", "iyi durumda" veya "hasar yok" sonucu yazma. Her fact için şu listeden tam bir mechanism_code seç ve iki farklı mekanizmayı tek fact içinde birleştirme: ${
    HAZARD_MECHANISM_CODES.join(", ")
  }. Serbest metinlerde snake_case etiket kullanma. observed_condition.short_text doğal ve düzgün bir başlık ifadesi, credible_event_path ise mekanizma ile sonucu birleştiren akıcı tek cümle olsun. technical_assessment içinde kanıta bağlı observation_narrative ve technical_significance yaz; root_cause_mode ile kesin gözlem, olası etken ve fotoğraftan belirlenemeyen nedenleri ayır. Açıklama, kök neden ve önlem niyetlerinde fotoğraf/görsel numarası ya da sağ-sol, üst-alt, ön-arka plan gibi görüntü adresleri kullanma; bileşeni kendi adıyla anlat. Görselde ayırt edilemeyen alternatif durumları "veya" ile fact başlığına taşıma. Tek durağan fotoğraftan continuous_visible_work veya daily_repeated_workstation çıkarma. Hiçbiri doğrulanmıyorsa hazard_facts boş olsun. ${targetedModuleOutput} mandatory_module_outcomes ve sector_context_evidence boş dizi, inspection_signals boş olsun. Skor üretme.`;
}
