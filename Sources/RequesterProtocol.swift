import Foundation
import Alamofire

public typealias UploadMultipartFormData = MultipartFormData

public typealias ConstructingBlock = (_ : UploadMultipartFormData)->()
public typealias URLSessionTaskProgressBlock = (_ :Progress)->()
public typealias RequestCompletionBlock = (_ : BaseRequester)->()


/// The RequestDelegate protocol defines several optional methods you can use
/// to receive network-related messages. All the delegate methods will be called
/// on the main queue.
public protocol RequesterProtocol: AnyObject {
    /// Tell the delegate that the request has finished successfully.
    ///
    /// - Parameter request: request The corresponding request.
    func requestFinished(_ request: BaseRequester)
    
    /// Tell the delegate that the request has failed.
    ///
    /// - Parameter request: request The corresponding request.
    func requestFailed(_ request: BaseRequester)
}

extension RequesterProtocol {
    func requestFinished(_ request: BaseRequester) { }
    func requestFailed(_ request: BaseRequester) { }
}

///  The RequestAccessory protocol defines several optional methods that can be
///  used to track the status of a request. Objects that conforms this protocol
///  ("accessories") can perform additional configurations accordingly. All the
///  accessory methods will be called on the main queue.
public protocol RequestAccessory {
    /// Inform the accessory that the request is about to start.
    ///
    /// - Parameter request: request The corresponding request.
    func requestWillStart(_ request: Any)
    
    /// Inform the accessory that the request is about to stop. This method is called
    /// before executing `requestFinished` and `successCompletionBlock`.
    ///
    /// - Parameter request: request The corresponding request.
    func requestWillStop(_ request: Any)
    
    /// Inform the accessory that the request has already stoped. This method is called
    /// after executing `requestFinished` and `successCompletionBlock`.
    ///
    /// - Parameter request: request The corresponding request.
    func requestDidStop(_ request: Any)
}

extension RequestAccessory {
    func requestWillStart(_ request: Any) { }
    func requestWillStop(_ request: Any) { }
    func requestDidStop(_ request: Any) { }
}
