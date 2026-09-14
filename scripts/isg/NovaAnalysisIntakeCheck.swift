import Foundation

@main struct Check {
    // The real catalogue, written out here by hand rather than imported, so a
    // change to the product list cannot silently rewrite the expectations.
    static let catalog: [NovaSectorCandidate] = [
        .init(id: "general", labels: ["Genel İSG", "General safety"]),
        .init(id: "construction", labels: ["İnşaat", "Construction"]),
        .init(id: "manufacturing", labels: ["İmalat / Fabrika", "Manufacturing / Factory"]),
        .init(id: "mining", labels: ["Maden", "Mining"]),
        .init(id: "energy", labels: ["Enerji", "Energy"]),
        .init(id: "office", labels: ["Ofis", "Office"]),
        .init(id: "logistics_warehouse", labels: ["Depo / Lojistik", "Warehouse / Logistics"]),
        .init(id: "chemical_laboratory", labels: ["Kimya / Laboratuvar", "Chemical / Laboratory"]),
        .init(id: "healthcare", labels: ["Sağlık / Hastane", "Healthcare / Hospital"]),
        .init(id: "food_production", labels: ["Gıda Üretimi", "Food production"]),
        .init(id: "agriculture_livestock", labels: ["Tarım / Hayvancılık", "Agriculture / Livestock"]),
        .init(id: "retail", labels: ["Perakende / Mağaza", "Retail / Store"]),
        .init(id: "municipal_field_services", labels: ["Belediye / Kamu Saha İşleri", "Municipal / Public field services"]),
        .init(id: "education", labels: ["Eğitim Kurumu", "Education"]),
        .init(id: "hospitality", labels: ["Otel / Konaklama", "Hotel / Hospitality"]),
    ]
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        precondition(condition, message)
    }

    static func main() {
        // A name typed exactly, in either language, matches.
        expect(NovaSectorMatch.suggestion(for: "İnşaat", in: catalog) == "construction", "tr label")
        expect(NovaSectorMatch.suggestion(for: "Construction", in: catalog) == "construction", "en label")
        // Missing diacritics, stray case, spacing and punctuation still match.
        expect(NovaSectorMatch.suggestion(for: "insaat", in: catalog) == "construction", "folded")
        expect(NovaSectorMatch.suggestion(for: "  İNŞAAT  ", in: catalog) == "construction", "spacing")
        expect(NovaSectorMatch.suggestion(for: "Tarim", in: catalog) == "agriculture_livestock", "dotless i")
        expect(NovaSectorMatch.suggestion(for: "Tarım / Hayvancılık", in: catalog) == "agriculture_livestock", "whole label")
        // Either side of a two-part label answers on its own.
        expect(NovaSectorMatch.suggestion(for: "Fabrika", in: catalog) == "manufacturing", "second half")
        expect(NovaSectorMatch.suggestion(for: "lojistik", in: catalog) == "logistics_warehouse", "second half tr")
        // The stored identifier itself answers.
        expect(NovaSectorMatch.suggestion(for: "food_production", in: catalog) == "food_production", "identifier")
        expect(NovaSectorMatch.suggestion(for: "chemical laboratory", in: catalog) == "chemical_laboratory", "identifier spaced")
        // Nothing recognised means nothing is pre-selected.
        expect(NovaSectorMatch.suggestion(for: "Tekstil", in: catalog) == nil, "unknown")
        expect(NovaSectorMatch.suggestion(for: "İnşaat ve taahhüt", in: catalog) == nil, "partial is not a match")
        expect(NovaSectorMatch.suggestion(for: "", in: catalog) == nil, "empty")
        expect(NovaSectorMatch.suggestion(for: "   ", in: catalog) == nil, "blank")
        expect(NovaSectorMatch.suggestion(for: nil, in: catalog) == nil, "absent")
        // Two sectors claiming the same word is an ambiguity, not a guess.
        let ambiguous = catalog + [.init(id: "site_services", labels: ["İnşaat"])]
        expect(NovaSectorMatch.suggestion(for: "inşaat", in: ambiguous) == nil, "ambiguous")

        // The draft only carries the note while the suggestion still stands.
        var draft = NovaAnalysisIntakeDraft()
        expect(draft.isReady == false, "empty draft is not ready")
        draft.photoCount = 2
        draft.choose(owner: .company(id: UUID(), name: "Deneme", sector: "İmalat / Fabrika"), catalog: catalog)
        expect(draft.sectorID == "manufacturing" && draft.sectorCameFromCompany, "suggested")
        draft.choose(sector: "manufacturing")
        expect(draft.sectorCameFromCompany, "re-tapping the same sector changes nothing")
        draft.choose(sector: "office")
        expect(draft.sectorID == "office" && !draft.sectorCameFromCompany, "manual choice drops the note")
        draft.choose(sector: "manufacturing")
        expect(!draft.sectorCameFromCompany, "coming back by hand is still a manual choice")

        // Continuing without a company keeps the sector the expert picked.
        draft.choose(owner: .unassigned, catalog: catalog)
        expect(draft.sectorID == "manufacturing" && !draft.sectorCameFromCompany, "manual answer survives")
        expect(draft.owner.companyID == nil && draft.owner.companyName == nil, "unassigned carries no company")
        // Switching to a company whose sector nobody recognises leaves it alone too.
        draft.choose(owner: .company(id: UUID(), name: "Bilinmeyen", sector: "Tekstil"), catalog: catalog)
        expect(draft.sectorID == "manufacturing" && !draft.sectorCameFromCompany, "unrecognised keeps the manual answer")
        // But a suggestion that is replaced by another company's unknown sector
        // is withdrawn: the screen must not keep showing a company's sector.
        draft.choose(owner: .company(id: UUID(), name: "Maden", sector: "Maden"), catalog: catalog)
        expect(draft.sectorID == "mining" && draft.sectorCameFromCompany, "second suggestion")
        draft.choose(owner: .company(id: UUID(), name: "Bilinmeyen", sector: "Tekstil"), catalog: catalog)
        expect(draft.sectorID == nil && !draft.sectorCameFromCompany, "withdrawn suggestion clears")

        draft.choose(sector: "mining")
        expect(draft.isReady == false, "a sector without a focus is not ready")
        draft.toggle(focus: "general")
        draft.toggle(focus: "ppe")
        expect(draft.focusIDs == ["general", "ppe"] && draft.isReady, "focus order is the order chosen")
        draft.toggle(focus: "general")
        expect(draft.focusIDs == ["ppe"], "toggle removes")
        draft.toggle(focus: "ppe")
        expect(draft.focusIDs.isEmpty && !draft.isReady, "no focus is not ready")
        draft.toggle(focus: "ppe")
        draft.photoCount = 0
        expect(!draft.isReady, "no photo is not ready")

        print("\(checks) analysis intake checks PASS")
    }
}
