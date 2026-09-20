import Foundation

enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key:String,table:RDLocalizationTable,fallback:String)->String { fallback }
}

@main @MainActor enum WorkspaceAPICheck {
    static func main() async throws {
        let user=UUID(uuidString:"20000000-0000-4000-8000-000000000001")!
        let session=UUID(uuidString:"21000000-0000-4000-8000-000000000001")!
        let workspace=UUID(uuidString:"22000000-0000-4000-8000-000000000001")!
        let membership=UUID(uuidString:"23000000-0000-4000-8000-000000000001")!
        let company=UUID(uuidString:"24000000-0000-4000-8000-000000000001")!
        let workplace=UUID(uuidString:"25000000-0000-4000-8000-000000000001")!
        let analysis=UUID(uuidString:"26000000-0000-4000-8000-000000000001")!
        let finding=UUID(uuidString:"27000000-0000-4000-8000-000000000001")!
        let nonconformity=UUID(uuidString:"28000000-0000-4000-8000-000000000001")!
        let exportJob=UUID(uuidString:"29000000-0000-4000-8000-000000000001")!
        let mutation=UUID(uuidString:"30000000-0000-4000-8000-000000000001")!
        let assignment=UUID(uuidString:"31000000-0000-4000-8000-000000000001")!
        let identity=NovaSessionIdentity(userID:user,sessionID:session)
        let selection=NovaWorkspaceSelection(workspaceID:workspace,membershipID:membership,userID:user,
            kind:"osgb",permissionRevision:4,workspaceVersion:2,canRead:true,canOperate:true)
        var currentIdentity:NovaSessionIdentity?=identity
        var currentSelection:NovaWorkspaceSelection?=selection
        let context="""
        {"schema_version":1,"workspace_id":"\(workspace)","kind":"osgb","name":"OSGB","status":"active","timezone":"Europe/Istanbul","workspace_version":2,"membership":{"membership_id":"\(membership)","user_id":"\(user)","role":"expert","status":"active","is_practicing_expert":true,"permission_revision":4,"membership_version":1},"can_read":true,"can_operate":true,"can_manage_members":false,"can_manage_billing":false}
        """
        var makeStale=false
        var epoch=UUID()
        var changeEpoch=false
        var changeIdentity=false
        var wrongAssignmentMember=false
        let api=IsgWorkspaceAPI(rpc:{ endpoint,args in
            let body:String
            switch endpoint {
            case "isg_workspace_list_v1": body="""
                {"schema_version":1,"user_id":"\(user)","workspaces":[\(context)]}
                """
            case "isg_workspace_context_v1":
                precondition(args["p_workspace"] == .string(workspace.uuidString.lowercased())); body=context
            case "isg_workspace_company_list_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","rows":[{"company_id":"\(company)","name":"Firma","hazard_class":"high","status":"active","version":0}],"next":null}
                """
            case "isg_workspace_assignment_list_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","rows":[{"assignment_id":"\(assignment)","workspace_id":"\(workspace)","company_id":"\(company)","membership_id":"\(membership)","user_id":"\(user)","assignment_role":"primary","membership_role":"expert","membership_status":"active","starts_at":"2026-09-17T08:00:00.123Z","ends_at":null,"version":0}],"next":null}
                """
            case "isg_workspace_assignment_mutate_v1":
                body="""
                {"schema_version":1,"assignment_id":"\(assignment)","workspace_id":"\(workspace)","company_id":"\(company)","membership_id":"\(membership)","user_id":"\(user)","assignment_role":"support","membership_role":"expert","membership_status":"active","starts_at":"2026-09-17T08:00:00.123Z","ends_at":null,"version":0}
                """
            case "isg_workspace_personnel_metrics_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","measured":true,"workplaces":{"active":1,"archived":0},"departments":{"active":2,"archived":0},"employees":{"active":7,"archived":1}}
                """
            case "isg_workspace_dashboard_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","measured":true,"companies":{"total":1,"unassigned":0},"experts":{"active":2},"nonconformities":{"open":1,"overdue":0},"visits":{"total":4,"last_30_days":2},"training":{"planned":1,"completed":3},"deadlines":{"equipment_due_soon":1,"risk_due_soon":0}}
                """
            case "isg_workspace_search_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","rows":[{"kind":"nonconformity","id":"\(nonconformity)","title":"Bulgu","subtitle":"open"}],"returned":1,"next":null}
                """
            case "isg_workspace_analysis_list_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","offset":0,"returned":1,"has_more":false,"rows":[{"id":"\(analysis)","title":"Analiz","kind":"photo","status":"ready","primary_method":"fine_kinney","created_at":"2026-09-17T09:00:00Z","version":1,"finding_count":1,"highest_band":"high"}]}
                """
            case "isg_workspace_analysis_read_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","analysis":{"id":"\(analysis)","title":"Analiz","primary_method":"fine_kinney","created_at":"2026-09-17T09:00:00Z"},"risk_findings":[{"id":"\(finding)","kind":"finding","title":"Risk","ordinal":1,"is_scored":true,"fk_score":135,"m5_score":12,"source_photo_indices":[0]}],"expert_items":[{"id":"\(finding)","kind":"unscored_finding","title":"Uzman görüşü","display_order":2}],"training_items":[],"counts":{"risk":1,"expert":1,"training":0}}
                """
            case "isg_workspace_analysis_file_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","nonconformity_id":"\(nonconformity)","created":true,"commit_state":"committed_and_visible","success_message_key":"analysis_finding_filed"}
                """
            case "isg_workspace_export_create_v1", "isg_workspace_export_get_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","row":{"id":"\(exportJob)","status":"queued","output_asset_id":null}}
                """
            case "isg_workspace_change_read_v1":
                body="""
                {"schema_version":1,"workspace_id":"\(workspace)","company_id":"\(company)","rows":[{"sequence":9,"event_type":"nonconformity.created","aggregate_type":"nonconformity","aggregate_id":"\(nonconformity)","aggregate_version":0}],"next":9}
                """
            default: fatalError("unexpected endpoint")
            }
            if makeStale { currentSelection=nil }
            if changeEpoch { epoch=UUID() }
            if changeIdentity { currentIdentity=nil }
            if wrongAssignmentMember && endpoint == "isg_workspace_assignment_mutate_v1" {
                return Data(body.replacingOccurrences(of: membership.uuidString, with: UUID().uuidString).utf8)
            }
            return Data(body.utf8)
        },currentIdentity:{currentIdentity},isCurrentWorkspace:{currentSelection == $0}, currentEpoch:{epoch})
        let listed=try await api.list(identity:identity)
        let loadedContext=try await api.context(identity:identity,workspaceID:workspace)
        let companies=try await api.companies(selection:selection)
        let assignments=try await api.assignments(selection:selection,companyID:company,status:"current")
        let createdAssignment=try await api.mutateAssignment(selection:selection,mutationID:mutation,
            companyID:company,action:"create",assignmentID:nil,membershipID:membership,
            expectedVersion:0,role:"support",startsAt:"2026-09-17T08:00:00Z",endsAt:nil,reason:"Atama")
        let metrics=try await api.personnelMetrics(selection:selection,companyID:company)
        let dashboard=try await api.dashboard(selection:selection,companyID:company)
        let search=try await api.search(selection:selection,companyID:company,query:"Bulgu")
        let analysisPage=try await api.analyses(selection:selection,companyID:company)
        let result=try await api.analysis(selection:selection,companyID:company,analysisID:analysis)
        let filed=try await api.fileAnalysisItem(selection:selection,mutationID:mutation,companyID:company,
            workplaceID:workplace,sourceScope:"workspace",analysisID:analysis,itemKind:"finding",itemID:finding,
            severity:"medium",openedOn:"2026-09-17",dueOn:nil)
        let createdExport=try await api.createExport(selection:selection,mutationID:mutation,companyID:company,
            analysisID:analysis,format:"pdf",findingIDs:[finding],expertItemIDs:[],trainingItemIDs:[])
        let loadedExport=try await api.export(selection:selection,companyID:company,jobID:exportJob)
        let changes=try await api.changes(selection:selection,companyID:company,after:0,limit:10)
        precondition(listed.count == 1)
        precondition(loadedContext.membership.permissionRevision == 4)
        precondition(companies.first?.id == company)
        precondition(assignments.rows.first?.userID == user && assignments.rows.first?.membershipStatus == "active")
        precondition(createdAssignment.id == assignment && createdAssignment.assignmentRole == "support")
        precondition(metrics.employees.active == 7)
        precondition(dashboard.nonconformities.first == 1)
        precondition(search.rows.first?.id == nonconformity)
        precondition(analysisPage.rows.first?.id == analysis && !analysisPage.hasMore)
        precondition(result.expertItems.count == 1)
        precondition(result.riskFindings.first?.fkScore == 135 && result.riskFindings.first?.m5Score == 12)
        precondition(result.riskFindings.first?.sourcePhotoIndices == [0])
        precondition(filed.created && filed.nonconformityID == nonconformity)
        precondition(createdExport.id == exportJob && loadedExport.id == exportJob)
        precondition(changes.next == 9)
        wrongAssignmentMember=true
        do {
            _ = try await api.mutateAssignment(selection:selection,mutationID:mutation,
                companyID:company,action:"create",assignmentID:nil,membershipID:membership,
                expectedVersion:0,role:"support",startsAt:"2026-09-17T08:00:00Z",endsAt:nil,reason:"Atama")
            fatalError("Wrong assigned member accepted")
        } catch IsgWorkspaceAPIFailure.invalidResponse {}
        wrongAssignmentMember=false

        let now=ISO8601DateFormatter().date(from:"2026-09-17T12:00:00Z")!
        for (start,end,expected) in [
            ("2026-09-16T08:00:00.123Z","2026-09-18T08:00:00Z",IsgWorkspaceCompanyAssignment.PeriodState.current),
            ("2026-09-18T08:00:00Z","2026-09-19T08:00:00Z",.future),
            ("2026-09-18T08:00:00Z","2026-09-18T08:00:00Z",.ended),
            ("2026-09-16T08:00:00Z","2026-09-17T12:00:00Z",.ended)
        ] {
            let row=IsgWorkspaceCompanyAssignment(id:assignment,companyID:company,membershipID:membership,
                userID:user,assignmentRole:"support",membershipRole:"expert",membershipStatus:"active",
                startsAt:start,endsAt:end,version:0)
            precondition(row.periodState(at:now) == expected)
        }

        // Exercise real decoding with more than one page; a repeated cursor is
        // rejected instead of displaying a silently incomplete or duplicate list.
        let ids=(1...101).map { UUID(uuidString:String(format:"40000000-0000-4000-8000-%012d",$0))! }
        var repeatPage=false
        let personnelAPI=IsgWorkspaceAPI(rpc:{ endpoint,args in
            precondition(endpoint == "isg_workspace_personnel_read_v1")
            let first = args["p_after"] == .null || repeatPage
            if !first { precondition(args["p_after"] == .id(ids[99])) }
            let employees = args["p_kind"] == .string("employees")
            let rows=(first ? Array(ids.prefix(100)) : [ids[100]]).map { id -> [String:Any] in
                var row:[String:Any]=["code":"TEST", "name":"Synthetic", "is_archived":false,"version":0]
                row[employees ? "employee_id" : "workplace_id"] = id.uuidString
                if !employees { row["hazard_class"]="high" }
                return row
            }
            return try JSONSerialization.data(withJSONObject:["schema_version":1,
                "workspace_id":workspace.uuidString,"company_id":company.uuidString,
                "rows":rows,"next":first ? ids[99].uuidString as Any : NSNull()])
        },currentIdentity:{currentIdentity},isCurrentWorkspace:{currentSelection == $0},currentEpoch:{epoch})
        let allEmployees=try await personnelAPI.employees(selection:selection,companyID:company)
        let allWorkplaces=try await personnelAPI.directory(selection:selection,companyID:company,kind:.workplace)
        precondition(allEmployees.count == 101 && allEmployees.last?.id == ids[100])
        precondition(allWorkplaces.count == 101 && allWorkplaces.last?.id == ids[100])
        repeatPage=true
        do { _=try await personnelAPI.employees(selection:selection,companyID:company); fatalError("Repeated page accepted") }
        catch IsgWorkspaceAPIFailure.invalidResponse {}

        // Every D1-D7 route consumes the same cursor contract. Verify 101 rows
        // for every route so adding `p_after` to SQL without wiring one client
        // cannot regress to a silent first-page-only list.
        func domainRow(_ domain:IsgWorkspaceDomain,_ id:UUID)->[String:Any] {
            switch domain {
            case .personnel: return ["employee_id":id.uuidString,"name":"Personel"]
            case .training: return ["training_id":id.uuidString,"title":"Eğitim"]
            case .risk: return ["assessment_id":id.uuidString]
            case .nonconformity: return ["nonconformity_id":id.uuidString,"title":"Uygunsuzluk"]
            case .checklist: return ["run_id":id.uuidString,"template_code":"KONTROL"]
            case .emergencyPlan: return ["plan_id":id.uuidString,"scope":"Acil durum"]
            case .drill: return ["drill_id":id.uuidString,"planned_on":"2026-09-17"]
            case .appointment: return ["appointment_id":id.uuidString,"kind":"representative"]
            case .ppe: return ["handover_id":id.uuidString,"item":"Baret"]
            case .equipment: return ["equipment_id":id.uuidString,"equipment_type":"forklift"]
            case .katip: return ["contract_id":id.uuidString,"counterparty":"OSGB"]
            case .annualPlan: return ["plan_id":id.uuidString,"plan_year":2026]
            case .board: return ["meeting_id":id.uuidString,"planned_on":"2026-09-17"]
            case .workPermit: return ["permit_id":id.uuidString,"job_description":"Çalışma"]
            case .visit: return ["visit_id":id.uuidString,"visited_on":"2026-09-17"]
            case .files: return ["entry_id":id.uuidString,"title":"Belge","original_filename":"belge.pdf"]
            }
        }
        let pagedDomainAPI=IsgWorkspaceAPI(rpc:{ endpoint,args in
            if endpoint == "isg_workspace_checklist_read_v1", args["p_limit"] == .number(1) {
                return try JSONSerialization.data(withJSONObject:["schema_version":1,
                    "workspace_id":workspace.uuidString,"company_id":company.uuidString,
                    "rows":[],"next":NSNull(),"templates":[[
                        "code":"integration_check","version":1,"title":"Entegrasyon kontrolü","item_count":2
                    ]]])
            }
            if endpoint.hasSuffix("_metrics_v1") {
                return try JSONSerialization.data(withJSONObject:["schema_version":1,
                    "workspace_id":workspace.uuidString,"company_id":company.uuidString,"measured":true,"total":101])
            }
            let after = args["p_after"]
            let first = after == .null
            if !first { precondition(after == .id(ids[99])) }
            let domain:IsgWorkspaceDomain
            switch endpoint {
            case "isg_workspace_personnel_read_v1": domain = .personnel
            case "isg_workspace_training_read_v1": domain = .training
            case "isg_workspace_risk_read_v1": domain = .risk
            case "isg_workspace_nonconformity_read_v1": domain = .nonconformity
            case "isg_workspace_checklist_read_v1": domain = .checklist
            case "isg_workspace_safety_read_v1":
                switch args["p_kind"] {
                case .string("plans"): domain = .emergencyPlan
                case .string("drills"): domain = .drill
                case .string("appointments"): domain = .appointment
                default: domain = .ppe
                }
            case "isg_workspace_equipment_read_v1": domain = .equipment
            case "isg_workspace_operations_read_v1":
                switch args["p_kind"] {
                case .string("katip_contract"): domain = .katip
                case .string("annual_plan"): domain = .annualPlan
                case .string("board"): domain = .board
                case .string("work_permit"): domain = .workPermit
                default: domain = .visit
                }
            case "isg_workspace_file_read_v1": domain = .files
            default: fatalError("unexpected paged endpoint \(endpoint)")
            }
            let pageIDs = first ? Array(ids.prefix(100)) : [ids[100]]
            return try JSONSerialization.data(withJSONObject:["schema_version":1,
                "workspace_id":workspace.uuidString,"company_id":company.uuidString,
                "rows":pageIDs.map { domainRow(domain,$0) },
                "next":first ? ids[99].uuidString as Any : NSNull()])
        },currentIdentity:{currentIdentity},isCurrentWorkspace:{currentSelection == $0},currentEpoch:{epoch})
        for domain in [IsgWorkspaceDomain.personnel,.training,.risk,.nonconformity,.checklist,
            .emergencyPlan,.drill,.appointment,.ppe,.equipment,.katip,.annualPlan,.board,.workPermit,.visit,.files] {
            let snapshot=try await pagedDomainAPI.domain(selection:selection,companyID:company,domain:domain)
            precondition(snapshot.rows.count == 101 && snapshot.rows.last?.id == ids[100])
        }
        let templates=try await pagedDomainAPI.checklistTemplates(selection:selection,companyID:company)
        precondition(templates == [.init(code:"integration_check",version:1,
                                         title:"Entegrasyon kontrolü",itemCount:2)])

        let topic=UUID(uuidString:"42000000-0000-4000-8000-000000000001")!
        let advancedAPI=IsgWorkspaceAPI(rpc:{ endpoint,args in
            if endpoint.hasSuffix("_advanced_mutate_v1") {
                guard case .object(let payload)?=args["p_payload"],
                      case .string(let action)?=payload["action"] else { fatalError("advanced payload") }
                return try JSONSerialization.data(withJSONObject:["schema_version":1,
                    "workspace_id":workspace.uuidString,"company_id":company.uuidString,
                    "action":action,"entity_id":ids[0].uuidString,"version":1])
            }
            let kind:String
            guard case .string(let requested)?=args["p_kind"] else { fatalError("advanced kind") }
            kind=requested
            let row:[String:Any]
            if endpoint == "isg_workspace_training_advanced_read_v1" {
                row=["id":ids[0].uuidString,"kind":"curriculum","title":"Temel eğitim",
                     "state":"draft","version":1,"topics":[[
                        "id":topic.uuidString,"position":1,"title":"Riskler",
                        "description":"Saha riskleri","duration_minutes":45]]]
            } else {
                row=["id":ids[1].uuidString,"kind":"assignment","employee_name":"Ayşe Uzman",
                     "effective_from":"2026-09-17","is_current":true,"version":0]
            }
            return try JSONSerialization.data(withJSONObject:["schema_version":1,
                "workspace_id":workspace.uuidString,"company_id":company.uuidString,
                "kind":kind,"rows":[row],"next":NSNull()])
        },currentIdentity:{currentIdentity},isCurrentWorkspace:{currentSelection == $0},currentEpoch:{epoch})
        let curricula=try await advancedAPI.trainingAdvanced(selection:selection,companyID:company,kind:.curricula)
        let personnelHistory=try await advancedAPI.personnelAdvanced(selection:selection,companyID:company,kind:.assignments)
        precondition(curricula.first?.topics.first?.id == topic && curricula.first?.topics.first?.durationMinutes == 45)
        precondition(personnelHistory.first?.flag("is_current") == true)
        try await advancedAPI.mutateTrainingAdvanced(selection:selection,mutationID:mutation,companyID:company,
            payload:["action":.string("curriculum_publish"),"id":.id(ids[0]),"expected_version":.number(1)])
        try await advancedAPI.mutatePersonnelAdvanced(selection:selection,mutationID:mutation,companyID:company,
            payload:["action":.string("assignment_end"),"id":.id(ids[1]),"expected_version":.number(0),
                     "effective_before":.string("2026-09-18")])

        var attempt=IsgWorkspaceMutationAttempt()
        let original=attempt.id(namespace:"training.save",payload:["action":.string("save"),"title":.string("A")])
        let replay=attempt.id(namespace:"training.save",payload:["title":.string("A"),"action":.string("save")])
        let changed=attempt.id(namespace:"training.save",payload:["action":.string("save"),"title":.string("B")])
        precondition(original == replay && changed != original)
        do { _=try await api.export(selection:selection,companyID:company,jobID:UUID()); fatalError("wrong export job accepted") }
        catch IsgWorkspaceAPIFailure.invalidResponse {}
        changeEpoch=true
        do { _=try await api.companies(selection:selection); fatalError("A-B-A scope response accepted") }
        catch IsgWorkspaceAPIFailure.staleSession {}
        changeEpoch=false; changeIdentity=true
        do { _=try await api.companies(selection:selection); fatalError("old auth response accepted") }
        catch IsgWorkspaceAPIFailure.staleSession {}
        changeIdentity=false; currentIdentity=identity
        makeStale=true; currentSelection=selection
        do { _=try await api.companies(selection:selection); fatalError("stale response accepted") }
        catch IsgWorkspaceAPIFailure.staleSession {}
        currentIdentity=nil
        do { _=try await api.list(identity:identity); fatalError("signed-out response accepted") }
        catch IsgWorkspaceAPIFailure.staleSession {}
        print("PASS Swift workspace API: strict scope, canonical endpoints and stale-response rejection")
    }
}
