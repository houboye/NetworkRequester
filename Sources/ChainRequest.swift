import Foundation

public typealias ChainCallback = (_ : ChainRequest, _: BaseRequester) -> ()

open class ChainRequest: NSObject, RequesterProtocol {
    
    ///  All the requests are stored in this array.
    private(set) var requestArray = [BaseRequester]()
    
    /// The delegate object of the chain request. Default is nil.
    weak public var delegate: ChainRequestProtocol?
    
    /// This can be used to add several accossories object. Note if you use `addAccessory` to add acceesory
    /// this array will be automatically created. Default is empty.
    public var requestAccessories = [RequestAccessory]()
    
    ///  Convenience method to add request accessory. See also `requestAccessories`.
    public func addAccessory(_ accessory: RequestAccessory) {
        requestAccessories.append(accessory)
    }
    
    /// Start the chain request, adding first request in the chain to request queue.
    public func start() {
        if nextRequestIndex > 0 {
            BYLog("Error! Chain request has already started.")
            return
        }
        
        if requestArray.count > 0 {
            toggleAccessoriesWillStartCallBack()
            startNextRequest()
            ChainRequestAgent.agent.addChainRequest(self)
        } else {
            BYLog("Error! Chain request array is empty.")
        }
    }
    
    /// Stop the chain request. Remaining request in chain will be cancelled.
    public func stop() {
        toggleAccessoriesWillStopCallBack()
        clearRequest()
        ChainRequestAgent.agent.removeChainRequest(self)
        toggleAccessoriesDidStopCallBack()
    }
    
    
    /// Add request to request chain.
    ///
    /// - Parameters:
    ///   - request: The request to be chained.
    ///   - callBack: The finish callback
    public func add(_ request: BaseRequester, callBack: ChainCallback?) {
        requestArray.append(request)
        if callBack != nil {
            requestCallbackArray.append(callBack!)
        } else {
            requestCallbackArray.append(emptyCallback!)
        }
    }
    
    override init() {
        super.init()
        emptyCallback = { (chainRequest, requester) in
            // do nothing
        }
    }
    
    /// RequestDelegate
    public func requestFinished(_ request: BaseRequester) {
        let currentRequestIndex = nextRequestIndex - 1
        let callBack = requestCallbackArray[currentRequestIndex]
        callBack(self, request)
        if !startNextRequest() {
            toggleAccessoriesWillStopCallBack()
            delegate?.chainRequestFinished(self)
            ChainRequestAgent.agent.removeChainRequest(self)
            toggleAccessoriesDidStopCallBack()
        }
    }
    
    public func requestFailed(_ request: BaseRequester) {
        toggleAccessoriesWillStopCallBack()
        delegate?.chainRequestFailed(self, failed: request)
        ChainRequestAgent.agent.removeChainRequest(self)
        toggleAccessoriesDidStopCallBack()
    }
    
    /// private
    private var requestCallbackArray = [ChainCallback]()
    private var nextRequestIndex: Int = 0
    private var emptyCallback: ChainCallback?
    
    @discardableResult
    private func startNextRequest() -> Bool {
        if nextRequestIndex < requestArray.count {
            let request = requestArray[nextRequestIndex]
            nextRequestIndex += 1
            request.delegate = self
            request.clearCompletionBlock()
            request.start()
            return true
        } else {
            return false
        }
    }
    
    private func clearRequest() {
        let currentRequestIndex = nextRequestIndex - 1
        if currentRequestIndex < requestArray.count {
            let request = requestArray[currentRequestIndex]
            request.stop()
        }
        requestArray.removeAll()
        requestCallbackArray.removeAll()
    }
}
