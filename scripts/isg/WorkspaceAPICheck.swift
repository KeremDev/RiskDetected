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
