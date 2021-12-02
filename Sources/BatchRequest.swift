import Foundation

///  BatchRequest can be used to batch several Request. Note that when used inside BatchRequest, a single
///  Request will have its own callback and delegate cleared, in favor of the batch request callback.
open class BatchRequest: NSObject, RequesterProtocol {
    
    /// All the requests are stored in this array.
    public private(set) var requestArray: [NetworkRequester]!
    
    /// The delegate object of the batch request. Default is nil.
    weak open var delegate: BatchRequestProtocol?
    
    ///  The success callback. Note this will be called only if all the requests are finished.
    ///  This block will be called on the main queue.
    public var successCompletionBlock: ((_ : BatchRequest)->())?
    
    ///  The failure callback. Note this will be called if one of the requests fails.
    ///  This block will be called on the main queue.
    public var failureCompletionBlock: ((_ : BatchRequest)->())?
    
    ///  Tag can be used to identify batch request. Default value is 0.
    public var tag: Int = 0
    
    /// This can be used to add several accossories object. Note if you use `addAccessory` to add acceesory
    /// this array will be automatically created. Default is empty.
    public var requestAccessories = [RequestAccessory]()
    
    /// The first request that failed (and causing the batch request to fail).
    public private(set) var failedRequest: NetworkRequester?
    
    private var finishedCount = 0
    
    /// Creates a `BatchRequest` with a bunch of requests.
    ///
    /// - Parameter requestArray: requests useds to create batch request.
    public init?(_ requestArray: [NetworkRequester]) {
        super.init()
        self.requestArray = requestArray
        for req in requestArray {
            if req.isKind(of: NetworkRequester.self) {
                BYLog("Error, request item must be NetworkRequest instance.")
                return nil
            }
        }
    }
    
    /// Set completion callbacks
    public func setCompletionBlock(success: @escaping (_ :BatchRequest)->(), failure: @escaping (_ :BatchRequest)->()) {
        successCompletionBlock = success
        failureCompletionBlock = failure
    }
    
    /// Nil out both success and failure callback blocks.
    public func clearCompletionBlock() {
        // nil out to break the retain cycle.
        successCompletionBlock = nil
        failureCompletionBlock = nil
    }
    
    /// Convenience method to add request accessory. See also `requestAccessories`.
    public func addAccessory(_ accessory: RequestAccessory) {
        requestAccessories.append(accessory)
    }
    
    /// Append all the requests to queue.
    public func start() {
        if finishedCount > 0 {
            BYLog("Error! Batch request has already started.")
            return
        }
        
        failedRequest = nil
        BatchRequestAgent.agent.addBatchRequest(self)
        toggleAccessoriesWillStartCallBack()
        for req in requestArray {
            req.delegate = self
            req.clearCompletionBlock()
            req.start()
        }
    }
    
    /// Stop all the requests of the batch request.
    public func stop() {
        toggleAccessoriesWillStopCallBack()
        delegate = nil
        clearRequest()
        toggleAccessoriesDidStopCallBack()
        BatchRequestAgent.agent.removeBatchRequest(self)
    }
    
    /// Convenience method to start the batch request with block callbacks.
    public func startWithCompletionBlock(success: @escaping (_ :BatchRequest)->(), failure: @escaping (_ :BatchRequest)->()) {
        setCompletionBlock(success: success, failure: failure)
        start()
    }
    
    /// Whether all response data is from local cache.
    public func isDataFromCache() -> Bool {
        var result = true
        for request in requestArray {
            if !request.isDataFromCache {
                result = false
            }
        }
        return result
    }
    
    // MARK: Network Request Delegate
    public func requestFailed(_ request: BaseRequester) {
        failedRequest = request as? NetworkRequester
        toggleAccessoriesWillStopCallBack()
        // stop
        for req in requestArray {
            req.stop()
        }
        // callBack
        delegate?.batchRequestFailed(self)
        failureCompletionBlock!(self)
        // clear
        clearCompletionBlock()
        
        toggleAccessoriesDidStopCallBack()
        BatchRequestAgent.agent.removeBatchRequest(self)
    }
    
    public func requestFinished(_ request: BaseRequester) {
        finishedCount += 1
        if finishedCount == requestArray.count {
            toggleAccessoriesWillStopCallBack()
            delegate?.batchRequestFinished(self)
            successCompletionBlock!(self)
            clearCompletionBlock()
            toggleAccessoriesDidStopCallBack()
            BatchRequestAgent.agent.removeBatchRequest(self)
        }
    }
    
    private func clearRequest() {
        for req in requestArray {
            req.stop()
        }
        clearCompletionBlock()
    }
    
    deinit {
        clearRequest()
    }
}
