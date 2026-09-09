// The Uzman Görüşü section: what a specialist says about equipment they can see
// but whose paperwork they cannot.
//
// The model is never asked for a standard number. It answers one perception
// question -- which equipment families are in the photograph -- and every
// sentence below is written here, by hand, in advance. That split is the whole
// design: "API 653 kapsamında et kalınlığı ultrasonik olarak ölçülmelidir" is
// worth reading precisely because no language model chose the 653.

export type ExpertRecommendationClass =
  /** A record the regulation requires and the photograph cannot show. */
  | "periodic_inspection_record"
  /** A measurement whose result, not just its existence, has to be checked. */
  | "measurement_record"
  /** A condition of storage or installation a specialist verifies on site. */
  | "site_verification";

/**
 * A figure carried in the registry.
 *
 * `verified` marks whether the number was read off the source text or supplied
 * by a domain expert and not yet checked. It is the same convention the
 * training catalogue uses, and for the same reason: an unverified interval
 * still helps the reader, but nothing in the rendered card may claim a basis
 * the entry does not have.
 */
export type ExpertInterval = {
  textTr: string;
  basisCode: string;
  verified: boolean;
};

export type ExpertRegistryEntry = {
  family: string;
  recommendationClass: ExpertRecommendationClass;
  /** Section heading in the app. */
  titleTr: string;
  categoryLabelTr: string;
  /** How the specialist names the thing they saw, mid-sentence. */
  assetLabelTr: string;
  /** Opening line: what is visible and what must therefore exist. */
  observationTr: string;
  /** The records, measurements and checks that have to be on file. */
  requirementsTr: string[];
  /** What to ask for when the record exists. */
  ifPresentTr: string;
  /** What to arrange when it does not. */
  ifAbsentTr: string;
  /** One per line, rendered as "Dayanak". */
  referencesTr: string[];
  interval?: ExpertInterval;
  /** Layers whose hazard makes this card more urgent, not what triggers it. */
  relatedLayers?: number[];
  /**
   * One sentence for the Onaylı Defter, not a trim of the specialist card.
   *
   * The card above is written for the reader who wants "et kalınlığı ultrasonik
   * olarak ölçülmelidir"; the log entry is written for the employer who wants
   * to know, in one line, what to ask for. Truncating `observationTr` or
   * `requirementsTr` at render time was tried and rejected -- a paragraph cut
   * mid-clause is worse than a fresh sentence, and the log entry's job is
   * different enough (name the record, not teach the standard) that it earns
   * its own text rather than a slice of someone else's.
   */
  notebookTespitTr: string;
  /** The single instruction: what to ask for, one sentence, imperative. */
  notebookOneriTr: string;
};

export type ExpertRecommendation = {
  family: string;
  recommendationClass: ExpertRecommendationClass;
  title: string;
  categoryLabel: string;
  /** The specialist's paragraph. */
  text: string;
  /** The one thing to do first. */
  action: string;
  /** Rendered as the corrective measure. */
  ifAbsent: string;
  /** Rendered as the preventive measure. */
  ongoing: string;
  references: string;
  displayOrder: number;
  /** The Onaylı Defter's one-line pair, carried through unchanged. */
  notebookTespit: string;
  notebookOneri: string;
};
