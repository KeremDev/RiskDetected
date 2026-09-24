"""Acil kart saha alanları için içerik editörüne ait Türkçe etiket sözlüğü."""
TOKENS = dict(pair.split('=',1) for pair in '''CO=CO;CO2=CO₂;H2S=H₂S;OED=OED/AED;acik=açık;acma=açma;adi=adı;agirligi=ağırlığı;akinti=akıntı;akiskan=akışkan;alani=alanı;alarmi=alarmı;alcak=alçak;algilama=algılama;algilayici=algılayıcı;alti=altı;arac=araç;araci=aracı;asansor=asansör;asil=asıl;askili=askılı;atik=atık;aydinlatma=aydınlatma;ayirici=ayırıcı;ayirma=ayırma;basinc=basınç;baslama=başlama;basvuru=başvuru;bosalma=boşalma;cati=çatı;cevre=çevre;cikis=çıkış;cikisi=çıkışı;dis=dış;dislama=dışlama;dokulme=dökülme;donanimi=donanımı;durus=duruş;dus=duş;dusme=düşme;duzeni=düzeni;emisleri=emişleri;erisim=erişim;firin=fırın;gecici=geçici;giris=giriş;goz=göz;gozcu=gözcü;guvenli=güvenli;guvenlik=güvenlik;haberlesme=haberleşme;hatti=hattı;ic=iç;ihtiyaci=ihtiyacı;iletisim=iletişim;ilkyardim=ilkyardım;ilkyardimci=ilkyardımcı;isaretleri=işaretleri;isi=ısı;isinma=ısınma;isletme=işletme;jenerator=jeneratör;kabi=kabı;kacak=kaçak;kacis=kaçış;kaldirma=kaldırma;kanali=kanalı;karsilama=karşılama;kaydi=kaydı;kayit=kayıt;kaynagi=kaynağı;kazi=kazı;kisi=kişi;kiyi=kıyı;komsu=komşu;konteyner=konteyner;kontrolu=kontrolü;kucuk=küçük;menu=menü;mudahale=müdahale;noktalari=noktaları;noktasi=noktası;odasi=odası;olcum=ölçüm;olcumler=ölçümler;on=ön;onarim=onarım;ozel=özel;plani=planı;reaktor=reaktör;resmi=resmî;ruzgar=rüzgâr;saglam=sağlam;saglik=sağlık;salim=salım;sarj=şarj;sayim=sayım;sayimi=sayımı;sayisi=sayısı;sensoru=sensörü;sev=şev;sicak=sıcak;sicaklik=sıcaklık;siginma=sığınma;siniri=sınırı;sinirlari=sınırları;sirasi=sırası;sogutma=soğutma;sondurucu=söndürücü;supheli=şüpheli;talimati=talimatı;tasarim=tasarım;taskin=taşkın;tedarikci=tedarikçi;tuketim=tüketim;tup=tüp;turu=türü;urun=ürün;ust=üst;uyari=uyarı;uyarisi=uyarısı;uzmani=uzmanı;vanasi=vanası;varligi=varlığı;vinc=vinç;yag=yağ;yakit=yakıt;yangin=yangın;yangini=yangını;yanik=yanık;yanmali=yanmalı;yapi=yapı;yapisi=yapısı;yarali=yaralı;yardim=yardım;yikama=yıkama;yildirim=yıldırım;yonu=yönü;yuk=yük;yukler=yükler;yuksek=yüksek;yuku=yükü'''.split(';'))
OVERRIDES = {
 '112_adres':'112 çağrısında verilecek açık adres', '112_erisim':'112 çağrısı için erişim yöntemi',
 '112_konum':'112 çağrısında bildirilecek konum', 'OED_varsa_yeri':'OED/AED varsa bulunduğu yer',
 'OED_yeri':'OED/AED konumu (varsa)', 'GBF':'Güvenlik bilgi formu (GBF)',
 'GBF_erisim':'Güvenlik bilgi formuna erişim', 'GBF_ilkyardim':'GBF ilkyardım bilgisi',
 'giris_siz_kurtarma':'İçeri girmeden kurtarma düzeni', 'CO2_sistem_turu':'CO₂ sistemi türü',
 'MR_uyumlu_kurtarma':'MR ortamına uygun kurtarma düzeni', 'PV_varligi':'Fotovoltaik (PV) sistem bilgisi',
 'UPS_jenerator':'UPS ve jeneratör bilgisi', 'quench_hatti':'MR quench tahliye hattı',
 'asil_yedek':'Asıl / yedek görevli', 'sondurucu_turu_yeri':'Söndürücü türü ve konumu',
 'atmosfer_bilgisi':'Ortam atmosferi ve ölçüm bilgisi', 'yuk_turu_agirligi':'Yük türü ve ağırlığı',
}
def label(key):
    if key in OVERRIDES:return OVERRIDES[key]
    parts=[TOKENS.get(w,w) for w in key.split('_')]
    text=' '.join(parts)
    return text if parts[0].isupper() else text[:1].replace('i','İ').upper()+text[1:]
