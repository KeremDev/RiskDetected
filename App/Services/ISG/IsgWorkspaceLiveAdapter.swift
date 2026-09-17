import Foundation
import Supabase

extension IsgWorkspaceAPI {
    /// Real transport composition for the dark OSGB client. The selection
    /// closure is read before and after every RPC by IsgWorkspaceAPI.
    static func live(currentIdentity: @escaping () -> NovaSessionIdentity?,
                     currentSelection: @escaping () -> NovaWorkspaceSelection?,
                     currentEpoch: @escaping () -> UUID?) -> IsgWorkspaceAPI {
        let client = SupabaseService.shared.client
        return IsgWorkspaceAPI(rpc: { function, arguments in
            try await client.rpc(function, params: arguments).execute().data
        }, currentIdentity: {
            novaCurrentSessionIdentity() == currentIdentity() ? currentIdentity() : nil
        }, isCurrentWorkspace: { expected in
            currentSelection() == expected && currentIdentity()?.userID == expected.userID &&
                novaCurrentSessionIdentity() == currentIdentity()
        }, currentEpoch: currentEpoch, upload: { bucket, path, data, mediaType in
            _ = try await client.storage.from(bucket).upload(
                path, data: data, options: FileOptions(contentType: mediaType, upsert: false))
        }, finalizeUpload: { token in
            struct Request: Encodable { let upload_token: String }
            return try await client.functions.invoke(
                "isg-workspace-file-finalize",
                options: FunctionInvokeOptions(body: Request(upload_token: token))) { data, _ in data }
        }, download: { token in
            struct Request: Encodable { let download_token: String }
            return try await client.functions.invoke(
                "isg-workspace-file-download",
                options: FunctionInvokeOptions(body: Request(download_token: token))) { data, _ in data }
        })
    }
}

extension IsgWorkspaceContext {
    var selection: NovaWorkspaceSelection {
        .init(workspaceID: workspaceID, membershipID: membership.membershipID,
              userID: membership.userID, kind: kind,
              permissionRevision: membership.permissionRevision,
              workspaceVersion: workspaceVersion, canRead: canRead, canOperate: canOperate)
    }
}
