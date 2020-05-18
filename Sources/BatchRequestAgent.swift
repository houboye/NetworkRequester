import Foundation

///  BatchRequestAgent handles batch request management. It keeps track of all
///  the batch requests.
class BatchRequestAgent: NSObject {
    ///  Get the shared batch request agent.
    static let agent = BatchRequestAgent()
    
    private var requestArray = [BatchRequest]()
    
    ///  Add a batch request.
    func addBatchRequest(_ request: BatchRequest) {
        objc_sync_enter(self)
        requestArray.append(request)
        objc_sync_exit(self)
    }
    
    ///  Remove a previously added batch request.
    func removeBatchRequest(_ request: BatchRequest) {
        objc_sync_enter(self)
        let index = requestArray.firstIndex(of: request)!
        requestArray.remove(at: index)
        objc_sync_exit(self)
    }
    
    private override init() {
        super.init()
    }
}
