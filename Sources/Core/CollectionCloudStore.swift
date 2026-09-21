import CloudKit
import Foundation

actor CollectionCloudStore {
    enum Failure: LocalizedError {
        case account, conflict
        var errorDescription:String? {
            switch self {
            case .account:return "iCloudにサインインしてから再試行してください。"
            case .conflict:return "別の端末が更新しました。しばらくして再試行してください。"
            }
        }
    }
    // Created lazily so simulator builds without a provisioned container remain playable.
    func sync(_ local:JewelSave) async throws -> JewelSave {
        let container=CKContainer(identifier:"iCloud.com.marcottlab.tamor")
        guard try await container.accountStatus() == .available else {throw Failure.account}
        let database=container.privateCloudDatabase
        let id=CKRecord.ID(recordName:"collection-v3")
        var merged=local
        for _ in 0..<4 {
            let record:CKRecord
            do {record=try await database.record(for:id)}
            catch let error as CKError where error.code == .unknownItem {
                record=CKRecord(recordType:"TamorCollection",recordID:id)
            }
            if let asset=record["payload"] as? CKAsset,let url=asset.fileURL {
                var remote=try JSONDecoder().decode(JewelSave.self,from:Data(contentsOf:url))
                try remote.validate();try merged.mergeCollection(remote)
            }
            var upload=merged;upload.rotation=0;upload.selectedID=nil
            let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
            try JSONEncoder().encode(upload).write(to:file,options:.atomic)
            defer {try? FileManager.default.removeItem(at:file)}
            record["payload"]=CKAsset(fileURL:file)
            record["schemaVersion"]=3 as CKRecordValue
            do {
                // A stale change tag produces serverRecordChanged; refetch and union immutable IDs.
                _=try await database.save(record)
                return merged
            } catch let error as CKError where error.code == .serverRecordChanged {continue}
        }
        throw Failure.conflict
    }
}
