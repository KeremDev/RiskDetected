// Scored findings drew their root cause and their measures from catalogs keyed
// by module that only covered six of the nineteen modules. Everything else fell
// through to one generic pair, so a crane hook with no latch, an excavator's
// articulated arm and an unguarded rotating shaft all published the identical
// sentence "Tehlike yoluna erişimi durdurun ve görünen fiziksel koşulu güvenli
// hale getirin." Unscored assurance items, which now carry five numbered field
// steps, ended up more useful than the scored findings above them.
//
// Module is also the wrong key. Material falling out of an excavator bucket was
// given the guardrail root cause "Görünen çalışma kenarında toplu düşmeye karşı
// koruma sürekliliği sağlanmamıştır" because it shares a module with edge
// protection. The causal axis is the mechanism, which is what the control text
// and the severity cap already key on.

export type ControlPlaybook = {
  /** Why the condition exists, stated as a control failure, not a restatement. */
  rootCause: string;
  /** One-line recommended action. Module-keyed text gave a missing safety pin,
   * a corroded coupling and a cracked hose the same sentence. */
  control: string;
  /** Immediate steps, published as the corrective measure. */
  corrective: string[];
  /** The standing arrangement that stops the condition returning. */
  preventive: string;
};

const GENERIC: ControlPlaybook = {
  rootCause:
    "Görünen çalışma koşulu, tehlike ile çalışan arasındaki yolu fiziksel olarak kesecek biçimde düzenlenmemiştir.",
  control:
    "Tehlike yoluna erişimi durdurun ve görünen fiziksel koşulu güvenli hale getirin.",
  corrective: [
    "Tehlike yoluna erişimi durdurun ve alanı fiziksel olarak sınırlandırın.",
    "Görünen koşulu güvenli hale getirecek mühendislik önlemini uygulayın.",
    "Önlem tamamlanana kadar çalışmayı yeniden başlatmayın; sorumluyu ve süreyi yazılı olarak belirleyin.",
  ],
  preventive:
    "Aynı koşulun tekrarını önleyecek sorumluluk, kontrol sıklığı ve fiziksel koruma standardını yazılı hale getirip periyodik kontrol listesine ekleyin.",
};

const BY_MECHANISM: Record<string, ControlPlaybook> = {
  fall_from_height: {
    rootCause:
      "Açık kenarda toplu koruma sürekliliği sağlanmamış; düşme yolu kesilmeden çalışma alanı erişime açık bırakılmıştır.",
    control:
      "Kenardaki erişimi durdurun; açık kenarı ana korkuluk, ara korkuluk ve topuk levhası sürekliliğiyle kapatın.",
    corrective: [
      "Kenar çevresindeki çalışmayı durdurun ve alana girişi fiziksel bariyerle kapatın.",
      "Ana korkuluk, ara korkuluk ve topuk levhasını kenarın tamamında kesintisiz olarak tamamlayın; korkuluk yüksekliğini ve boşluk mesafelerini ölçerek doğrulayın.",
      "Toplu koruma teknik olarak uygulanamıyorsa hesaplanmış ankraj noktası üzerinden kişisel düşme durdurma sistemi kurun ve serbest düşüş mesafesini kontrol edin.",
      "Platform döşemesindeki boşlukları kapatın veya sabit kapakla emniyete alın.",
      "Koruma tamamlanmadan çalışmayı yeniden başlatmayın; kabulü yetkili kişiye yaptırıp kayda geçirin.",
    ],
    preventive:
      "Kenar koruma planını iş programına bağlayın; kurulum, değişiklik ve söküm yetkisini tek sorumluya verin, vardiya öncesi kenar bütünlüğü kontrolünü zorunlu kılın ve korkuluğun geçici olarak sökülmesini izin sistemine tabi tutun.",
  },
  falling_object: {
    rootCause:
      "Yükün veya malzemenin düşme yolu ile altındaki çalışma alanı arasında fiziksel bir ayrım kurulmamıştır.",
    control:
      "Alt bölgeyi boşaltın; düşen cisim yolunu topuk levhası, ağ veya kapalı platform ile fiziksel olarak kesin.",
    corrective: [
      "Yükün altını ve salınım alanını boşaltın; alanı bariyer ve uyarı ile kapatın.",
      "Malzemenin kaynağını emniyete alın: topuk levhası, koruma ağı, kapalı platform veya yük emniyet mandalı ile ayrılma yolunu kesin.",
      "Kaldırma yapılıyorsa kanca mandalını, sapan durumunu ve bağlama noktasını kullanım öncesi muayene edin; uygun olmayan aksesuarı hizmet dışı bırakın.",
      "Alt seviyede çalışma zorunluysa çalışmaları zaman olarak ayırın; aynı düşeyde eş zamanlı çalışmayı yasaklayın.",
      "Serbest kalan malzemeyi kaldırın veya sabitleyin; istifleri devrilmeye karşı emniyete alın.",
    ],
    preventive:
      "Aynı düşeyde çalışma yasağını iş planına yazın; kaldırma operasyonlarında yük altı boşaltma kuralını ve işaretçi görevlendirmesini standart hale getirin, kaldırma aksesuarlarını periyodik kontrol ve kullanım öncesi muayene kaydına bağlayın.",
  },
  caught_in_pinch_shear: {
    rootCause:
      "Tehlikeli hareketin bulunduğu bölge, temas yolunu kesecek sabit veya kilitlemeli koruyucu ile kapatılmamıştır.",
    control:
      "Makineyi durdurup enerjisini izole edin; hareketli parçaları sabit veya kilitlemeli koruyucuyla kapatın.",
    corrective: [
      "Makineyi durdurun ve enerjisini izole edin; birikmiş enerjiyi boşaltarak sıfır enerji durumunu doğrulayın.",
      "Dönen ve hareketli parçaların tamamını (şaft, kaplin, kayış, kasnak, dişli) alet gerektiren sabit koruyucu ile kapatın.",
      "Sık erişim gereken noktalarda kilitlemeli koruyucu kullanın; kapak açıldığında hareketin durduğunu fiilen deneyin.",
      "Acil durdurma butonunun erişilebilirliğini ve durdurma süresini test edin.",
      "Koruyucu tamamlanana kadar makineyi etiketleyerek kullanım dışı bırakın.",
    ],
    preventive:
      "Koruyucu, kilitleme ve acil durdurma işlevlerini vardiya öncesi kontrol listesine ve periyodik bakıma bağlayın; koruyucunun devre dışı bırakılmasını yasaklayan yazılı kural ve yaptırım tanımlayın, bakım ve temizlik için ekipmana özgü izolasyon talimatı hazırlayın.",
  },
  vehicle_equipment_strike: {
    rootCause:
      "Yaya ile hareketli ekipmanın çalışma alanları fiziksel olarak ayrılmamış; makinenin hareket ve dönüş alanı kontrol altına alınmamıştır.",
    control:
      "Ekipmanın hareket ve dönüş alanına yaya girişini fiziksel olarak kapatın; görüş ve iletişim düzenini kurun.",
    corrective: [
      "Ekipmanın hareket ve dönüş alanını bariyer, şerit veya konikle işaretleyip yaya girişini kapatın.",
      "Alanda görev dışı personel varsa çalışmayı durdurun; operatörle görsel veya telsiz iletişimi kurulmadan alana girilmesini yasaklayın.",
      "Fren, korna, geri ikaz sesi, ikaz lambası, ayna ve kamera işlevlerini kullanım öncesi test ettirin.",
      "Operatörün ekipmana özgü yetki belgesini ve günlük kontrol formunu doğrulayın.",
      "Kör nokta kalıyorsa işaretçi görevlendirin veya hız sınırı ve tek yön düzeni uygulayın.",
    ],
    preventive:
      "Saha trafik planı hazırlayıp yaya yollarını fiziksel olarak ayırın; hız sınırı, geri manevra kuralı ve işaretçi görevlendirmesini yazılı hale getirin, kullanım öncesi kontrol ve periyodik bakım kayıtlarını takip edin.",
  },
  electrical_contact_arc: {
    rootCause:
      "Enerjili bölüm ile çalışana açık temas yolu bırakılmış; koruma, izolasyon ve topraklama düzeninin sürekliliği sağlanmamıştır.",
    control:
      "Enerjili bölgeye erişimi engelleyin; yetkili kişiyle kapatma, izolasyon ve topraklama doğrulaması yaptırın.",
    corrective: [
      "Bölgeye erişimi engelleyin ve işlemi yalnız yetkili elektrik personeline yaptırın.",
      "Mümkünse enerjiyi kesin, kilitleyip etiketleyin ve gerilimsizliği ölçerek doğrulayın.",
      "Hasarlı kabloyu, açık klemensi veya eksik pano kapağını değiştirin; geçici hattı ıslak yüzey ve geçiş yolundan fiziksel olarak ayırın.",
      "Topraklama sürekliliğini ve kaçak akım korumasının açma süresini ölçtürün.",
      "Ölçüm ve test sonuçlarını tarih ve sorumlu ile kayda geçirin.",
    ],
    preventive:
      "Elektrik tesisinin periyodik ölçüm ve muayene takvimini oluşturun; pano açma yetkisini sınırlandırın, geçici hat güzergâhlarını standarda bağlayın ve değişiklikleri tek hat şemasına işleyin.",
  },
  hydraulic_pneumatic_release: {
    rootCause:
      "Basınçlı akışkan hattının bütünlüğü ve basınç boşaltma düzeni, ani salım yolunu kesecek biçimde güvence altına alınmamıştır.",
    control:
      "Hattı izole edip basıncı kontrollü boşaltın; sızıntıyı elle aramayın ve hasarlı hortumu değiştirin.",
    corrective: [
      "Ekipmanı durdurun; hattı izole edip basıncı kontrollü biçimde boşaltın ve sıfır basıncı gösterge ile doğrulayın.",
      "Hortum, rakor ve silindirleri aşınma, kabarma, sızıntı ve dış hasar yönünden muayene edin; şüpheli olanı değiştirin.",
      "Sızıntıyı asla elle veya çıplak deri ile aramayın; karton veya uygun dedektör kullanın.",
      "Hortum patlamasına karşı koruyucu kılıf, kelepçe veya hortum tutucu takın.",
      "Yüksek basınçlı sıvı enjeksiyonu şüphesinde çalışanı derhal cerrahi değerlendirmeye yönlendirin.",
    ],
    preventive:
      "Hidrolik ve pnömatik hatlar için hortum ömrü takibi, periyodik muayene ve planlı değiştirme programı kurun; bakım öncesi basınç boşaltma adımını ekipman talimatına yazın.",
  },
  mechanical_separation_release: {
    rootCause:
      "Basınç veya proses içeren ekipmanın bütünlüğü ve koruma katmanları, ani ayrılma ve salım yolunu kesecek biçimde güvence altına alınmamıştır.",
    control:
      "Prosesi güvenli duruma alın; hattı izole edip boşaltın ve ayrılma yolunu yetkili muayeneden geçirmeden basınç vermeyin.",
    corrective: [
      "Prosesi güvenli duruma alın; hattı izole edip içeriği kontrollü biçimde boşaltın.",
      "Görünen korozyon, deformasyon, sızıntı veya bağlantı gevşekliğini yetkili kişiye muayene ettirin.",
      "Emniyet valfi ve tahliye hattının açıklığını, ayar basıncını ve son test tarihini doğrulayın.",
      "İkincil muhafaza ve drenaj düzeninin yeterliliğini kontrol edin.",
      "Muayene tamamlanana kadar ekipmanı servis dışı bırakın ve etiketleyin.",
    ],
    preventive:
      "Ekipmanı risk bazlı muayene programına alın; kalınlık ölçüm noktalarını, kabul sınırlarını ve muayene aralığını yazılı hale getirip periyodik kontrol takvimine işleyin.",
  },
  fire_explosion: {
    rootCause:
      "Yanıcı madde, tutuşturucu kaynak ve oksijen bir arada bulunurken bunları ayıran fiziksel ve yönetsel kontroller kurulmamıştır.",
    control:
      "Tutuşturucu kaynağı kaldırın; yanıcı yükü ayırın ve alanı boşaltarak yangın hazırlığını sağlayın.",
    corrective: [
      "Tutuşturucu kaynağı ortadan kaldırın; sıcak çalışma varsa durdurun.",
      "Yanıcı ve parlayıcı malzemeyi alandan uzaklaştırın veya yanmaz örtü ile ayırın.",
      "Gaz ölçümü yaptırın; patlayıcı ortam ihtimalinde alanı boşaltıp havalandırın.",
      "Uygun sınıf söndürücüyü alanda bulundurun ve yangın gözcüsü görevlendirin.",
      "Alanı bariyerle kapatın ve acil durum ekibini bilgilendirin.",
    ],
    preventive:
      "Sıcak çalışma izin sistemini yazılı hale getirin; yanıcı madde depolama kurallarını, statik topraklamayı ve ekipman seçimini patlamadan korunma dokümanına bağlayın, tatbikatları planlayın.",
  },
  chemical_contact_release: {
    rootCause:
      "Maddenin yayılma ve temas yolu, muhafaza, havalandırma ve koruyucu donanım katmanlarıyla kesilmemiştir.",
    control:
      "Teması ve yayılımı durdurun; kaynağı kapatıp alanı sınırlandırın ve maddeyi güvenlik bilgi formundan tanımlayın.",
    corrective: [
      "Teması ve yayılımı durdurun; kaynağı güvenli biçimde kapatın ve alanı sınırlandırın.",
      "Etiketten ve güvenlik bilgi formundan maddeyi tanımlayın; belirlenmeden müdahale etmeyin.",
      "Dökülmeyi uygun emici ve nötralizasyon malzemesiyle toplayın; atığı ayrı biriktirin.",
      "Havalandırmayı çalıştırın; göz duşu ve acil duşun erişilebilir ve çalışır olduğunu doğrulayın.",
      "Maruz kalan çalışanı güvenlik bilgi formundaki ilk yardım talimatına göre yönlendirin.",
    ],
    preventive:
      "Kimyasal envanterini ve güvenlik bilgi formlarını güncel tutun; geçimsiz maddeler için ayrık depolama, ikincil muhafaza ve maruziyet ölçüm planı tanımlayın.",
  },
  excavation_collapse_rockfall: {
    rootCause:
      "Kazı yüzeyinin stabilitesi zemin özelliğine göre güvence altına alınmamış; göçük ve kaya düşmesi yolu açık bırakılmıştır.",
    control:
      "Kazıdaki çalışmayı durdurup personeli tahliye edin; şev veya iksa düzenini yetkili kişiye kurdurun.",
    corrective: [
      "Kazı içindeki çalışmayı durdurun ve personeli tahliye edin.",
      "Zemin sınıfını ve kazı derinliğini yetkili kişiye tespit ettirin; şevi güvenli açıya getirin veya iksa kurun.",
      "Kazı kenarına malzeme ve araç yaklaşma mesafesini işaretleyip fiziksel bariyerle ayırın.",
      "Gevşek kaya ve sarkan blokları kontrollü biçimde temizleyin.",
      "Güvenli giriş-çıkış düzenini (merdiven, rampa) kurun ve mesafesini sınırlayın.",
    ],
    preventive:
      "Kazı için yetkili kişi görevlendirin; günlük muayene kaydı, yağış ve titreşim sonrası yeniden değerlendirme kuralı ve yeraltı hizmet tespiti prosedürü tanımlayın.",
  },
  structural_collapse: {
    rootCause:
      "Taşıyıcı düzenin yük aktarımı ve stabilitesi doğrulanmamış; çökme yolu ile çalışma alanı arasında ayrım kurulmamıştır.",
    control:
      "Alanı boşaltıp girişi kapatın; taşıyıcı sistemi mühendis değerlendirmesinden geçirin.",
    corrective: [
      "Alanı boşaltın ve girişi fiziksel olarak kapatın.",
      "Taşıyıcı elemanların durumunu yetkili mühendise değerlendirtin.",
      "Gerekli askı, destek veya geçici takviyeyi hesap ile uygulayın.",
      "Yük kaynağını (istif, ekipman, su birikimi) kaldırın.",
      "Değerlendirme tamamlanmadan alana girişi yeniden açmayın.",
    ],
    preventive:
      "Yapısal değişiklik ve geçici yükleme işlemlerini mühendislik onayına bağlayın; taşıyıcı sistem muayenesini periyodik kontrol planına ekleyin.",
  },
  equipment_overturn: {
    rootCause:
      "Ekipmanın stabilite sınırları zemin, eğim ve yükleme koşuluna göre güvence altına alınmamıştır.",
    control:
      "Operasyonu durdurun; ekipmanı taşıma gücü yeterli düz zemine alıp destek ve yük sınırlarını doğrulayın.",
    corrective: [
      "Operasyonu durdurun; ekipmanı düz ve taşıma kapasitesi yeterli zemine alın.",
      "Destek ayaklarını, karşı ağırlığı ve yük diyagramını kontrol edin.",
      "Devrilme alanına yaya girişini kapatın.",
      "Zemin taşıma gücü şüpheliyse plaka veya takviye uygulayın.",
      "Operatörün yetki ve eğitim durumunu doğrulayın.",
    ],
    preventive:
      "Ekipman kurulum yerlerini zemin etüdüne bağlayın; yük diyagramı, destek ayağı ve eğim sınırı kurallarını operatör talimatına yazın.",
  },
  thermal_contact: {
    rootCause:
      "Sıcak yüzey veya kıvılcım kaynağı ile çalışan arasındaki temas yolu fiziksel olarak kesilmemiştir.",
    control:
      "Isı kaynağını durdurun veya soğutun; sıcak yüzeyi izolasyon ya da koruyucuyla kapatın.",
    corrective: [
      "Isı kaynağını durdurun veya soğumasını bekleyin; alanı işaretleyin.",
      "Sıcak yüzeyi izolasyon veya koruyucu ile kapatın.",
      "Kıvılcım yayılımını yanmaz perde ile sınırlandırın.",
      "Uygun ısıya dayanıklı koruyucu donanımı sağlayın.",
      "Alanda yanıcı malzeme kalmadığını doğrulayın.",
    ],
    preventive:
      "Sıcak yüzeyler için kalıcı izolasyon ve işaretleme standardı belirleyin; sıcak çalışma izin ve gözetim düzenini uygulayın.",
  },
  sharp_edge_contact: {
    rootCause:
      "Açıkta kalan sivri veya keskin uçlar, temas ve saplanma yolunu kesecek biçimde kapatılmamıştır.",
    control:
      "Alana girişi sınırlandırın; açıkta kalan sivri uçları uygun başlık veya kapakla kapatın.",
    corrective: [
      "Alana girişi sınırlandırın.",
      "Açıkta kalan donatı, filiz ve sivri uçları uygun başlık, kapak veya bükme ile kapatın.",
      "Kapatma mümkün değilse yatay koruma veya fiziksel bariyer uygulayın.",
      "Keskin kenarlı hurda ve malzemeyi alandan kaldırın.",
      "Kapatmanın tamamlandığını gözle doğrulayıp kayda geçirin.",
    ],
    preventive:
      "Donatı ucu kapatmayı imalat sırasının parçası haline getirin; günlük saha turunda açıkta uç kalmadığını kontrol listesine bağlayın.",
  },
  fall_same_level: {
    rootCause:
      "Yürüme yüzeyinin sürekliliği ve temizliği korunmamış; takılma ve kayma yolu açık bırakılmıştır.",
    // Asserting a wet surface in every same-level finding repeats the
    // over-claim the housekeeping title already had to lose.
    control:
      "Geçiş yolundaki malzemeyi kaldırın veya sabitleyin; yürüme yüzeyini düzgün ve kaymaz durumda tutun.",
    corrective: [
      "Geçiş yolundaki malzeme, kablo ve hortumları kaldırın veya kanal ile sabitleyin.",
      "Islak veya kaygan yüzeyi kurutun; kaynağını giderin.",
      "Kesintisiz ve görünür bir yürüme yolu oluşturup işaretleyin.",
      "Giderilene kadar uyarı levhası koyun ve alternatif güzergâh belirleyin.",
      "Aydınlatmanın geçiş yolu boyunca yeterli olduğunu doğrulayın.",
    ],
    preventive:
      "Günlük düzen-temizlik sorumluluğu belirleyin; yürüme alanlarını malzeme depolamasından fiziksel olarak ayırın ve drenaj ile sızıntı kaynaklarını takip edin.",
  },
  ergonomic_overexertion: {
    rootCause:
      "Taşıma ve zorlanma yükü, mekanik yardım ve yöntem düzenlemesiyle azaltılmamıştır.",
    control:
      "Elle taşımayı durdurup mekanik taşıma sağlayın; güzergâhı temizleyip görüşü kapatmayan yöntem belirleyin.",
    corrective: [
      "Elle taşımayı durdurun; mekanik taşıma ekipmanı sağlayın.",
      "Yük ağır veya hacimliyse ekip halinde taşıma düzenleyin.",
      "Güzergâhı temizleyip görüşü kapatmayan taşıma yöntemi belirleyin.",
      "Taşıma yüksekliğini ve mesafesini azaltacak ara depolama noktası kurun.",
    ],
    preventive:
      "Elle taşıma sınırlarını ve mekanik yardım zorunluluğunu yazılı hale getirin; iş istasyonu yerleşimini taşıma mesafesini azaltacak biçimde düzenleyin.",
  },
  environmental_release: {
    rootCause:
      "Salımın çevreye yayılma yolu, muhafaza ve toplama düzeniyle kesilmemiştir.",
    control:
      "Kaynağı durdurun; drenaja ulaşımı kapatıp dökülen maddeyi uygun ekipmanla toplayın.",
    corrective: [
      "Kaynağı durdurun ve salımı sınırlandırın.",
      "Drenaj ve yağmur suyu hatlarına ulaşımı fiziksel olarak kapatın.",
      "Dökülen maddeyi uygun ekipmanla toplayın ve atık olarak ayırın.",
      "Etkilenen alanı temizleyip kaydını tutun.",
    ],
    preventive:
      "İkincil muhafaza, drenaj kapatma ekipmanı ve dökülme müdahale setini standart hale getirin; müdahale tatbikatını planlayın.",
  },
  other_visible_physical: GENERIC,
};

export function controlPlaybook(mechanism: string): ControlPlaybook {
  return BY_MECHANISM[mechanism] ?? GENERIC;
}

export function correctiveSteps(playbook: ControlPlaybook): string {
  return playbook.corrective
    .map((step, index) => `${index + 1}. ${step}`)
    .join("\n");
}
