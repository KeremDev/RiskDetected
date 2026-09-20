import Foundation

/// Converts the stable API vocabulary into product copy. Keeping this mapping
/// at the UI boundary prevents database enum values from leaking into screens.
enum IsgWorkspaceDisplayText {
    static func value(_ raw: String) -> String {
        let key = raw.lowercased()
        if RDLanguage.current == .turkish, let translated = turkishValues[key] { return translated }
        return humanized(raw)
    }

    static func field(_ raw: String) -> String {
        let key = raw.lowercased()
        if RDLanguage.current == .turkish, let translated = turkishFields[key] { return translated }
        return humanized(raw)
    }

    static func metric(_ raw: String) -> String {
        if RDLanguage.current == .turkish, let exact = turkishMetrics[raw.lowercased()] { return exact }
        let last = raw.split(separator: ".").last.map(String.init) ?? raw
        if RDLanguage.current == .turkish, let translated = turkishMetrics[last.lowercased()] { return translated }
        return humanized(last)
    }

    static func event(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "workspace.", with: "")
        return value.split(separator: ".").map { IsgWorkspaceDisplayText.value(String($0)) }.joined(separator: " · ")
    }

    static func metricValue(id: String, value: Int64) -> String {
        guard id.contains("minute") else { return String(value) }
        let hours = Double(value) / 60
        return hours.rounded() == hours ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private static func humanized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static let turkishValues: [String: String] = [
        "active": "Aktif", "archived": "Arşivlendi", "draft": "Taslak", "planned": "Planlandı",
        "completed": "Tamamlandı", "cancelled": "İptal edildi", "open": "Açık", "assigned": "Atandı",
        "in_progress": "İşlemde", "pending_verification": "Doğrulama bekliyor", "closed": "Kapatıldı",
        "reopened": "Yeniden açıldı", "published": "Yayımlandı", "retired": "Kullanımdan kaldırıldı",
        "verified": "Doğrulandı", "realised": "Gerçekleşti", "performed": "Gerçekleştirildi", "done": "Tamamlandı",
        "valid": "Güncel", "overdue": "Süresi geçti", "due_soon": "Yaklaşıyor", "expired": "Süresi doldu",
        "failed": "Başarısız", "pass": "Uygun", "conditional": "Şartlı uygun", "fail": "Olumsuz",
        "conform": "Uygun", "nonconform": "Uygunsuz", "not_applicable": "Uygulanamaz",
        "accepted": "Kabul edildi", "rejected": "Reddedildi", "pending": "Bekliyor",
        "low": "Düşük", "medium": "Orta", "high": "Yüksek", "critical": "Kritik",
        "face_to_face": "Yüz yüze", "online": "Çevrim içi", "mixed": "Karma",
        "representative": "Çalışan temsilcisi", "support_staff": "Destek elemanı",
        "team_member": "Ekip üyesi", "first_aid": "İlk yardımcı", "fire_team": "Yangın ekibi",
        "coordinator": "Koordinatör", "fire": "Yangın", "evacuation": "Tahliye",
        "full": "Tam değerlendirme", "partial": "Kısmi revizyon", "metadata": "Bilgi düzeltmesi",
        "rescan": "Yeniden inceleme", "held": "Gerçekleşti",
        "piece": "Adet", "pair": "Çift", "set": "Takım", "metre": "Metre", "litre": "Litre",
        "mandatory": "Zorunlu", "voluntary": "Gönüllü", "reusable": "Tekrar kullanılabilir",
        "worn": "Yıpranmış", "damaged": "Hasarlı", "lost": "Kayıp",
        "initial": "İlk eğitim", "periodic_repeat": "Periyodik tekrar", "onboarding": "İşe giriş",
        "task_specific": "Göreve özel", "other": "Diğer", "internal_training": "Kurum içi eğitim",
        "external_training": "Harici eğitim", "certificate": "Sertifika",
        "owner": "OSGB sahibi", "admin": "OSGB yöneticisi", "expert": "İSG uzmanı",
        "primary": "Birincil uzman", "support": "Destek uzmanı", "current": "Güncel",
        "future": "İleri tarihli", "upcoming": "Başlayacak", "ended": "Sona erdi",
        "untracked": "Takipsiz", "suspended": "Askıda",
        "never_inspected": "Kontrol yok", "period_unknown": "Süre belirlenmedi",
        "true": "Evet", "false": "Hayır",
        "lifting_equipment": "Kaldırma ekipmanı", "crane": "Vinç", "forklift": "Forklift",
        "pressure_vessel": "Basınçlı kap", "compressor": "Kompresör", "boiler": "Kazan",
        "lift": "Asansör", "scaffold": "İskele", "ladder": "Merdiven",
        "electrical_installation": "Elektrik tesisatı", "earthing": "Topraklama tesisatı",
        "fire_extinguisher": "Yangın söndürücü", "fire_detection": "Yangın algılama sistemi",
        "ventilation": "Havalandırma tesisatı", "power_tool": "Elektrikli el aleti",
        "welding_set": "Kaynak makinesi", "conveyor": "Konveyör", "press_machine": "Pres makinesi",
        "lathe": "Torna tezgâhı", "other_equipment": "Diğer ekipman",
        "regulation_default": "Genel süre", "company_override": "Firma süresi", "expert_override": "Uzman süresi"
    ]

    private static let turkishFields: [String: String] = [
        "code": "Kod", "name": "Ad", "full_name": "Ad soyad", "state": "Durum", "status": "Durum",
        "version": "Sürüm", "current_version": "Güncel sürüm", "draft_version": "Taslak sürümü",
        "draft_kind": "Taslak türü", "assessment_on": "Değerlendirme tarihi", "revision_on": "Revizyon tarihi",
        "scope": "Kapsam", "severity": "Önem", "opened_on": "Açılış tarihi", "due_on": "Termin tarihi",
        "trainer": "Eğitmen", "method": "Eğitim yöntemi", "starts_at": "Başlangıç",
        "duration_minutes": "Süre", "valid_until": "Geçerlilik tarihi", "location": "Konum",
        "notes": "Not", "participant_count": "Katılımcı sayısı", "attended_count": "Katılan sayısı",
        "workplace_id": "İşyeri", "department_id": "Departman", "employee_id": "Personel",
        "hired_on": "İşe giriş tarihi", "ends_before": "Bitiş tarihi", "prepared_on": "Hazırlanma tarihi",
        "planned_on": "Planlanan tarih", "performed_on": "Gerçekleşme tarihi", "visited_on": "Ziyaret tarihi",
        "item": "Ürün", "quantity": "Adet", "returned_quantity": "İade edilen", "unit": "Birim",
        "handed_on": "Teslim tarihi", "return_condition": "İade durumu", "signed_copy": "İmzalı nüsha",
        "equipment_type": "Ekipman türü", "equipment_type_label": "Ekipman türü", "serial_tag": "Seri / kod",
        "acquired_on": "Edinme tarihi", "location_note": "Konum notu", "last_performed_on": "Son kontrol",
        "next_due_on": "Sonraki kontrol", "result": "Sonuç", "inspector": "Kontrolü yapan",
        "counterparty": "Sözleşme tarafı", "expert_contact": "Uzman / iletişim",
        "declared_monthly_minutes": "Aylık dakika", "declared_note": "Beyan notu",
        "plan_year": "Plan yılı", "applicability": "Uygulanma durumu", "job_description": "İş tanımı",
        "work_location": "Çalışma yeri", "risk_precautions": "Risk önlemleri", "responsible_contact": "Sorumlu",
        "category": "Belge türü", "visibility": "Görünürlük", "original_filename": "Dosya adı",
        "verification_outcome": "Doğrulama sonucu", "verification_note": "Doğrulama notu",
        "topic_count": "Konu sayısı", "total_minutes": "Toplam süre", "target_group": "Hedef grup",
        "passing_score": "Geçme puanı", "certificate_number": "Belge numarası",
        "team_size": "Ekip", "team_members": "Ekip üyeleri", "agenda_count": "Gündem maddesi",
        "agenda_summary": "İlk gündem maddesi", "attendance_count": "Katılımcı",
        "decision_count": "Karar", "open_decision_count": "Açık karar",
        "base_assessment_on": "İlk değerlendirme", "period_years": "Geçerlilik süresi",
        "needs_review": "İnceleme gerekiyor", "curriculum_title": "Kayıtlı eğitim",
        "curriculum_revision": "Müfredat sürümü", "assessment_required": "Sınav gerekli",
        "period_months": "Kontrol süresi", "period_source": "Süre kaynağı",
        "last_result": "Son kontrol sonucu", "last_inspector": "Son kontrolü yapan",
        "last_external_ref": "Son rapor no", "inspections": "Kontrol kaydı"
    ]

    private static let turkishMetrics: [String: String] = [
        "total": "Toplam", "active": "Aktif", "archived": "Arşiv", "planned": "Planlanan",
        "completed": "Tamamlanan", "cancelled": "İptal", "open": "Açık", "closed": "Kapatılan",
        "overdue": "Süresi geçen", "expired": "Süresi dolan", "due_soon": "Yaklaşan",
        "valid": "Güncel", "failed": "Olumsuz", "records.total": "Toplam kayıt",
        "records.planned": "Planlanan", "records.completed": "Tamamlanan", "records.cancelled": "İptal",
        "completed_minutes": "Eğitim saati", "trained_people": "Eğitim alan",
        "person_minutes": "Adam × saat", "people_without_completed_training": "Eğitimi eksik",
        "employee_count": "Personel", "workplace_count": "İşyeri", "department_count": "Departman",
        "positive": "Olumlu", "negative": "Olumsuz", "untracked": "Takipsiz", "approaching": "Yaklaşıyor",
        "upcoming": "Başlayacak", "ended": "Sona eren", "held": "Gerçekleşen",
        "board_open_decisions": "Açık karar", "open_decisions": "Açık karar"
    ]
}
