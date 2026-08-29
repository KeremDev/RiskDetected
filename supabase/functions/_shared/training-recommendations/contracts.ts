// Training recommendations: what the people in this photograph should be taught.
//
// A parallel consumer of the analysis, alongside the approved-book engine, and
// built on the same premise: the text is planned from codes, never rewritten
// from the model's sentences. Here the premise carries extra weight, because a
// small wording slip in this domain sends someone to the wrong certificate
// body. "MYK kursu" is not a thing. A forklift authorisation is not a driving
// licence. An electrical panel is not a high-voltage installation.
//
// So the engine picks from a catalogue and fills approved templates. It cannot
// invent a training name, and it cannot invent a legal obligation.
//
// Three things it must never say, whatever the photograph shows:
//   that a person is untrained, uncertified or working without authority --
//   a photograph is not evidence of what is in someone's file;
//   that a training replaces a physical control -- a guard is a guard;
//   a score, a deadline, or who is responsible.

export type TrainingRecommendationClass =
  | "statutory_ohs_training"
  | "site_or_job_induction"
  | "task_specific_practical_training"
  | "equipment_specific_training"
  | "vocational_education_requirement"
  | "myk_qualification_verification"
  | "meb_operator_authorization"
  | "special_regulated_role_training"
  | "emergency_response_training"
  | "toolbox_talk"
  | "personal_development";

/**
 * How firmly the photograph supports the recommendation.
 *
 * Never shown to the reader and never a number. It decides the mood of the
 * sentence: a visible task earns "görev yapan personele", a visible machine
 * with nobody at the controls earns "kullanacak personele".
 */
export type TrainingApplicability =
  | "direct_task_match"
  | "direct_hazard_exposure_match"
  | "conditional_if_task_performed"
  | "conditional_if_special_role_assigned"
  | "sector_role_match";

export type AudienceCode =
  | "all_employees"
  | "new_or_transferred_employees"
  | "equipment_operators"
  | "maintenance_personnel"
  | "electrical_personnel"
  | "welders_and_hot_work_team"
  | "riggers_slingers_signalers"
  | "work_at_height_personnel"
  | "confined_space_entrants"
  | "rescue_team"
  | "chemical_handlers"
  | "supervisors";

export type TrainingGroupCode =
  | "general_and_induction"
  | "task_and_equipment"
  | "qualification_and_authorization"
  | "emergency_and_rescue"
  | "toolbox";

/** What the analysis showed, reduced to the codes the rules may read. */
export interface TrainingContext {
  sectorId: string | null;
  mechanismCodes: string[];
  assuranceTopicIds: string[];
  moduleIds: string[];
  /** Equipment families resolved from asset refs: forklift, crane, scaffold... */
  equipmentFamilies: string[];
  barrierComponentsAbsent: string[];
  peopleVisible: number;
  /** Source item ids per trigger code, for the audit trail. */
  sourceItemIdsByTrigger: Record<string, string[]>;
}

export interface TrainingRecommendation {
  catalogCode: string;
  recommendationClass: TrainingRecommendationClass;
  groupCode: TrainingGroupCode;
  title: string;
  categoryLabel: string;
  audienceLabel: string;
  text: string;
  /** Audit only; never rendered. */
  applicability: TrainingApplicability;
  triggerCodes: string[];
  sourceItemIds: string[];
  displayOrder: number;
}

export const GROUP_TITLES_TR: Record<TrainingGroupCode, string> = {
  general_and_induction: "Genel ve uyum eğitimleri",
  task_and_equipment: "Göreve ve ekipmana özgü eğitimler",
  qualification_and_authorization: "Yeterlilik ve yetki doğrulaması",
  emergency_and_rescue: "Acil durum ve kurtarma",
  toolbox: "Saha bilgilendirmeleri",
};

export const AUDIENCE_TR: Record<AudienceCode, string> = {
  all_employees: "Tüm çalışanlar",
  new_or_transferred_employees: "Yeni ve görev değiştiren çalışanlar",
  equipment_operators: "Ekipman operatörleri",
  maintenance_personnel: "Bakım personeli",
  electrical_personnel: "Elektrik personeli",
  welders_and_hot_work_team: "Kaynak ve sıcak çalışma ekibi",
  riggers_slingers_signalers: "Sapancı ve işaretçiler",
  work_at_height_personnel: "Yüksekte çalışan personel",
  confined_space_entrants: "Kapalı alana giren personel",
  rescue_team: "Kurtarma ekibi",
  chemical_handlers: "Kimyasal ile çalışan personel",
  supervisors: "Saha amirleri",
};

export const CLASS_LABEL_TR: Record<TrainingRecommendationClass, string> = {
  statutory_ohs_training: "Temel İSG eğitimi",
  site_or_job_induction: "İşe ve işyerine uyum eğitimi",
  task_specific_practical_training: "Göreve özgü uygulamalı eğitim",
  equipment_specific_training: "Ekipmana özgü uygulamalı eğitim",
  vocational_education_requirement: "Mesleki eğitim belgesi",
  myk_qualification_verification: "Mesleki yeterlilik doğrulaması",
  meb_operator_authorization: "Operatörlük yetkisi",
  special_regulated_role_training: "Özel görev eğitimi",
  emergency_response_training: "Acil durum eğitimi",
  toolbox_talk: "Saha bilgilendirmesi",
  personal_development: "Güvenlik kültürü",
};
