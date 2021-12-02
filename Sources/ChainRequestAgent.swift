import Foundation

///  ChainRequestAgent handles chain request management. It keeps track of all
///  the chain requests.
class ChainRequestAgent: NSObject {
    static let agent = ChainRequestAgent()
    
    private var requestArray = [ChainRequest]()
    
    ///  Add a chain request.
    func addChainRequest(_ request: ChainRequest) {
        objc_sync_enter(self)
        requestArray.append(request)
        objc_sync_exit(self)
    }
    
    ///  Remove a previously added chain request.
    func removeChainRequest(_ request: ChainRequest) {
        objc_sync_enter(self)
        if let index = requestArray.firstIndex(of: request) {
            requestArray.remove(at: index)
        }
        objc_sync_exit(self)
    }
    
    private override init() {
        super.init()
    }
}
