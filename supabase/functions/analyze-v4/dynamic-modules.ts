import {
  CORE_MODULE_IDS,
  DYNAMIC_MODULE_IDS,
  type ModuleCoverage,
  type ProviderPhotoOutput,
  type V4ModuleID,
} from "./contracts.ts";

/**
 * The note on a coverage row the server invented because the model omitted the
 * module entirely.
 *
 * Not a finding about the photograph -- a record that the provider's answer was
 * short. Exported so the router can drop these rather than publish them.
 */
export const SERVER_SYNTHESIZED_COVERAGE_NOTE =
  "Provider kapsam sonucu teknik olarak eksikti; olumlu tehlike varsayılmadı.";

const SIGNALS: Record<string, string[]> = {
  work_at_height: [
    "scaffold",
    "iskele",
    "roof",
    "çatı",
    "platform",
    "ladder",
    "merdiven",
    "edge",
    "kenar",
  ],
  process_integrity: [
    "tank",
    "vessel",
    "boru",
    "pipe",
    "valve",
    "vana",
    "reactor",
  ],
  lifting: ["crane", "vinç", "hoist", "forklift", "sapan", "hook", "kanca"],
  machinery: [
    "machine",
    "makine",
    "conveyor",
    "konveyör",
    "press",
    "pres",
    "lathe",
    "torna",
  ],
  logistics: [
    "forklift",
    "truck",
    "kamyon",
    "depo",
    "warehouse",
    "pallet",
    "palet",
  ],
  electrical: [
    "panel",
    "pano",
    "cable",
    "kablo",
    "transformer",
    "trafo",
    "socket",
    "priz",
  ],
  confined_space: [
    "confined",
    "kapalı alan",
    "pit",
    "çukur",
    "manhole",
    "tank interior",
  ],
  hot_work: ["welding", "kaynak", "torch", "şaloma", "grinding", "taşlama"],
  excavation: ["excavation", "kazı", "trench", "hendek"],
  chemical: [
    "chemical",
    "kimyasal",
    "drum",
    "varil",
    "laboratory",
    "laboratuvar",
  ],
  combustible_dust: ["dust", "toz", "silo", "mill", "değirmen"],
  biosecurity: [
    "clinical",
    "klinik",
    "patient",
    "hasta",
    "animal",
    "hayvan",
    "bio",
    "numune",
  ],
};

const SECTOR_MODULES: Record<string, V4ModuleID[]> = {
  construction: [
    "work_at_height",
    "lifting",
    "electrical",
    "excavation",
    "hot_work",
  ],
  manufacturing: [
    "machinery",
    "electrical",
    "lifting",
    "hot_work",
    "process_integrity",
  ],
  mining: [
    "excavation",
    "lifting",
    "machinery",
    "electrical",
    "confined_space",
    "combustible_dust",
  ],
  energy: ["electrical", "process_integrity", "hot_work", "confined_space"],
  logistics_warehouse: ["logistics", "lifting", "fire_explosion_release"],
  chemical_laboratory: [
    "chemical",
    "process_integrity",
    "fire_explosion_release",
    "biosecurity",
  ],
  healthcare: ["biosecurity", "chemical", "electrical"],
  food_production: ["machinery", "biosecurity", "chemical", "combustible_dust"],
  agriculture_livestock: [
    "biosecurity",
    "machinery",
    "chemical",
    "vehicles_mobile_equipment",
  ],
  municipal_field_services: [
    "excavation",
    "vehicles_mobile_equipment",
    "work_at_height",
    "confined_space",
  ],
};

export function initialActiveModules(sectorID: string | null): V4ModuleID[] {
  return [
    ...new Set<V4ModuleID>([
      ...CORE_MODULE_IDS,
      ...(sectorID ? SECTOR_MODULES[sectorID] ?? [] : []),
    ]),
  ];
}

export function activatedModulesFromScene(
  output: ProviderPhotoOutput,
  sectorID: string | null,
): V4ModuleID[] {
  const haystack = output.scene_entities.map((entity) =>
    `${entity.kind} ${entity.label} ${(entity.cues ?? []).join(" ")}`
  ).join(" ").toLocaleLowerCase("tr-TR");
  const active = new Set<V4ModuleID>(initialActiveModules(sectorID));
  for (const id of DYNAMIC_MODULE_IDS) {
    if ((SIGNALS[id] ?? []).some((signal) => haystack.includes(signal))) {
      active.add(id);
    }
  }
  return [...active];
}

export function missingCoreCoverage(output: ProviderPhotoOutput): string[] {
  const covered = new Set(output.module_coverage.map((item) => item.module_id));
  return CORE_MODULE_IDS.filter((moduleID) => !covered.has(moduleID));
}

export function coverageIsStructurallyValid(
  output: ProviderPhotoOutput,
  requiredModules: readonly V4ModuleID[] = CORE_MODULE_IDS,
): boolean {
  return coverageValidationIssues(output, requiredModules).length === 0;
}

function expectedCoverageModules(
  output: ProviderPhotoOutput,
  requiredModules: readonly V4ModuleID[],
): V4ModuleID[] {
  return [
    ...new Set<V4ModuleID>([
      ...CORE_MODULE_IDS,
      ...requiredModules,
      ...activatedModulesFromScene(output, null),
      ...output.candidates.map((candidate) => candidate.module_id),
      ...output.positive_controls.map((control) => control.module_id),
    ]),
  ];
}

export function coverageValidationIssues(
  output: ProviderPhotoOutput,
  requiredModules: readonly V4ModuleID[] = CORE_MODULE_IDS,
): string[] {
  const issues: string[] = [];
  const occurrences = new Map<V4ModuleID, number>();
  for (const coverage of output.module_coverage) {
    occurrences.set(
      coverage.module_id,
      (occurrences.get(coverage.module_id) ?? 0) + 1,
    );
  }
  for (const [moduleID, count] of occurrences) {
    if (count > 1) issues.push(`duplicate_module:${moduleID}`);
  }
  for (const moduleID of expectedCoverageModules(output, requiredModules)) {
    if (!occurrences.has(moduleID)) issues.push(`missing_module:${moduleID}`);
  }
/**
 * Modules whose finding_present a candidate from another module can close.
 *
 * One physical hazard belongs to several of these at once. A worker at an
 * unguarded slab edge is work_at_height by task, falls_falling_objects by
 * mechanism and people_exposure because a person is standing in it. The model
 * can only give the candidate one module_id, so demanding exact equality asked
 * it to solve something unsolvable: bind the candidate to one module and every
 * other row naming the same hazard is rejected.
 *
 * That is what three successive Gemini 3 prompt versions kept failing at, each
 * in a different way -- core-v1 downgraded the extra rows to not_assessable,
 * core-v2 closed them empty, core-v3 wrote finding_present without a binding.
 * The same four modules every time: access_egress, energy,
 * falls_falling_objects, people_exposure. The prompt was never the problem.
 *
 * The pairs mirror the ones imageAnswersThisModule already uses to drop a
 * contradictory not_assessable row, so the two places now agree about which
 * modules share a hazard. people_exposure takes any module, because any hazard
 * with a person in it is that module's subject.
 */
const COVERAGE_MODULE_AFFINITY: Record<string, readonly string[] | "any"> = {
  falls_falling_objects: ["work_at_height"],
  work_at_height: ["falls_falling_objects"],
  access_egress: ["housekeeping_physical_contact", "work_at_height"],
  energy: ["electrical"],
  people_exposure: "any",
};

function acceptedCandidateModules(
  moduleID: string,
): readonly string[] | "any" {
  return COVERAGE_MODULE_AFFINITY[moduleID] ?? [];
}

  const candidateModules = new Map(
    output.candidates.map((candidate) => [
      candidate.candidate_key,
      candidate.module_id,
    ]),
  );
  const controlModules = new Map(
    output.positive_controls.map((control) => [
      control.control_key,
      control.module_id,
    ]),
  );
  for (const coverage of output.module_coverage) {
    if (coverage.outcome === "finding_present") {
      const accepted = acceptedCandidateModules(coverage.module_id);
      if (
        !coverage.candidate_keys.some((key) => {
          const moduleID = candidateModules.get(key);
          return moduleID !== undefined &&
            (moduleID === coverage.module_id || accepted === "any" ||
              accepted.includes(moduleID));
        })
      ) issues.push(`finding_without_candidate:${coverage.module_id}`);
    } else if (coverage.outcome === "positive_control_present") {
      if (
        ![...controlModules.values()].some((moduleID) =>
          moduleID === coverage.module_id
        )
      ) issues.push(`positive_control_without_control:${coverage.module_id}`);
    } else if (
      !coverage.note?.trim() && coverage.entity_refs.length === 0 &&
      coverage.outcome !== "module_activation_false_positive"
    ) {
      issues.push(`empty_closure_evidence:${coverage.module_id}`);
    }
  }
  return [...new Set(issues)].sort();
}

export function recoverCoverageDeterministically(
  output: ProviderPhotoOutput,
  requiredModules: readonly V4ModuleID[] = CORE_MODULE_IDS,
): {
  output: ProviderPhotoOutput;
  issues: string[];
  recoveredModules: V4ModuleID[];
} {
  const issues = coverageValidationIssues(output, requiredModules);
  const existing = new Map<V4ModuleID, ModuleCoverage>();
  for (const coverage of output.module_coverage) {
    const current = existing.get(coverage.module_id);
    if (!current) {
      existing.set(coverage.module_id, {
        ...coverage,
        activated_by: [...new Set(coverage.activated_by)],
        entity_refs: [...new Set(coverage.entity_refs)],
        candidate_keys: [...new Set(coverage.candidate_keys)],
      });
      continue;
    }
    current.activated_by = [
      ...new Set([
        ...current.activated_by,
        ...coverage.activated_by,
      ]),
    ];
    current.entity_refs = [
      ...new Set([
        ...current.entity_refs,
        ...coverage.entity_refs,
      ]),
    ];
    current.candidate_keys = [
      ...new Set([
        ...current.candidate_keys,
        ...coverage.candidate_keys,
      ]),
    ];
    current.note = current.note?.trim() || coverage.note?.trim() || undefined;
  }

  const recoveredModules: V4ModuleID[] = [];
  const allModules = [
    ...new Set<V4ModuleID>([
      ...expectedCoverageModules(output, requiredModules),
      ...existing.keys(),
    ]),
  ];
  const recoveredCoverage = allModules.map((moduleID): ModuleCoverage => {
    const candidateKeys = output.candidates.filter((candidate) =>
      candidate.module_id === moduleID
    ).map((candidate) => candidate.candidate_key);
    const controls = output.positive_controls.filter((control) =>
      control.module_id === moduleID
    );
    const current = existing.get(moduleID);
    if (!current) {
      recoveredModules.push(moduleID);
      if (candidateKeys.length > 0) {
        return {
          module_id: moduleID,
          activated_by: ["server_coverage_recovery"],
          outcome: "finding_present",
          entity_refs: [],
          candidate_keys: candidateKeys,
          note: "Aday bağlantısı sunucu tarafından geri kazanıldı.",
        };
      }
      if (controls.length > 0) {
        return {
          module_id: moduleID,
          activated_by: ["server_coverage_recovery"],
          outcome: "positive_control_present",
          entity_refs: [],
          candidate_keys: [],
          note: "Olumlu kontrol bağlantısı sunucu tarafından geri kazanıldı.",
        };
      }
      // The model said nothing at all about this module, so there is no verdict
      // to record -- this row exists to keep the coverage map complete, not to
      // report a judgement about the image. The router must not publish it as
      // one, and this note is how it tells them apart.
      return {
        module_id: moduleID,
        activated_by: ["server_coverage_recovery"],
        outcome: "not_assessable_due_to_image",
        entity_refs: [],
        candidate_keys: [],
        note: SERVER_SYNTHESIZED_COVERAGE_NOTE,
      };
    }

    const repaired: ModuleCoverage = {
      ...current,
      activated_by: current.activated_by.length > 0
        ? current.activated_by
        : ["server_coverage_recovery"],
      entity_refs: [...new Set(current.entity_refs)],
      candidate_keys: [
        ...new Set(
          current.candidate_keys.filter((key) =>
            output.candidates.some((candidate) =>
              candidate.candidate_key === key &&
              candidate.module_id === moduleID
            )
          ),
        ),
      ],
    };
    if (
      repaired.outcome === "finding_present" &&
      repaired.candidate_keys.length === 0
    ) {
      recoveredModules.push(moduleID);
      if (candidateKeys.length > 0) repaired.candidate_keys = candidateKeys;
      else {
        repaired.outcome = "not_assessable_due_to_image";
        repaired.note =
          "Bağlı görsel aday bulunamadı; olumlu tehlike varsayılmadı.";
      }
    }
    if (
      repaired.outcome === "positive_control_present" && controls.length === 0
    ) {
      recoveredModules.push(moduleID);
      repaired.outcome = "not_assessable_due_to_image";
      repaired.note = "Bağlı görünür kontrol bulunamadı; kontrol varsayılmadı.";
    }
    if (
      repaired.outcome !== "finding_present" &&
      repaired.outcome !== "positive_control_present" &&
      repaired.outcome !== "module_activation_false_positive" &&
      repaired.entity_refs.length === 0 && !repaired.note?.trim()
    ) {
      recoveredModules.push(moduleID);
      repaired.note =
        "Kapsam kapanışı sunucu tarafından teknik olarak tamamlandı.";
    }
    return repaired;
  });
  const recoveredOutput = { ...output, module_coverage: recoveredCoverage };
  const remaining = coverageValidationIssues(recoveredOutput, requiredModules);
  if (remaining.length > 0) {
    throw new Error(`coverage_recovery_failed:${remaining.join(",")}`);
  }
  return {
    output: recoveredOutput,
    issues,
    recoveredModules: [...new Set(recoveredModules)],
  };
}
