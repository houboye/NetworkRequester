import Foundation
import Alamofire

///  BaseRequester is the abstract class of network request. It provides many options
///  for constructing request. It's the base class of `YTKRequest`.
open class BaseRequester: NSObject {
    override public init() {
        super.init()
    }
    // MARK: - Request and Response Information
    
    /// The underlying Request.
    /// **warning** This value is actually nil and should not be accessed before the request starts.
    open var requestTask: Request!
    
    /// Shortcut for `requestTask.currentRequest`.
    open var currentRequest: URLRequest? {
        return requestTask.request
    }
    
    /// Shortcut for `requestTask.response`.
    open var response: HTTPURLResponse? {
        return requestTask.response
    }
    
    /// The response status code.
    open var responseStatusCode: Int {
        return response?.statusCode ?? 0
    }
    
    /// The response header fields.
    open var responseHeaders: [AnyHashable: Any]? {
        return response?.allHeaderFields
    }
    
    /// The raw data representation of response. Note this value can be nil if request failed.
    public var responseData: Data?
    
    /// The string representation of response. Note this value can be nil if request failed.
    public var responseString: String?
    
    /// This serialized response object. The actual type of this object is determined by
    /// `ResponseSerializerType`. Note this value can be nil if request failed.
    ///
    /// **discussion** If `resumableDownloadPath` and DownloadTask is using, this value will
    ///                be the path to which file is successfully saved (URL), or nil if request failed.
    public var responseObject: Any?
    
    /// If you use `ResponseSerializerTypeJSON`, this is a convenience (and sematic) getter
    /// for the response object. Otherwise this value is nil.
    public var responseJSONObject: Any?
    
    /// This error can be either serialization error or network error. If nothing wrong happens
    /// this value will be nil.
    public var error: Error?
    
    /// Return cancelled state of request task.
    public var isCancelled: Bool {
        if let task = requestTask {
            return task.state == .cancelled
        }
        return false
    }
    
    /// Executing state of request task.
    public var isExecuting: Bool {
        if let task = requestTask {
            return task.state == .resumed
        }
        return false
    }
    
    // MARK: - Request Configuration
    
    /// Tag can be used to identify request. Default value is 0.
    public var tag = 0
    
    /// The userInfo can be used to store additional info about the request. Default is nil.
    public var userInfo: [AnyHashable: Any]?
    
    /// The delegate object of the request. If you choose block style callback you can ignore this.
    /// Default is nil.
    weak public var delegate: RequesterProtocol?
    
    /// The success callback. Note if this value is not nil and `requestFinished` delegate method is
    /// also implemented, both will be executed but delegate method is first called. This block
    /// will be called on the main queue.
    public var successCompletionBlock: RequestCompletionBlock?
    
    ///  The failure callback. Note if this value is not nil and `requestFailed` delegate method is
    ///  also implemented, both will be executed but delegate method is first called. This block
    ///  will be called on the main queue.
    public var failureCompletionBlock: RequestCompletionBlock?
    
    ///  This can be used to add several accossories object. Note if you use `addAccessory` to add acceesory
    ///  this array will be automatically created. Default is nil.
    lazy public var requestAccessories = [RequestAccessory]()
    
    /// This can be use to construct HTTP body when needed in POST request. Default is nil.
    public var constructingBodyBlock: ConstructingBlock?
    
    /// This value is used to perform resumable download request. Default is nil.
    ///
    /// **discussion** URLSessionDownloadTask is used when this value is not nil.
    ///                The exist file at the path will be removed before the request starts. If request succeed, file will
    ///                be saved to this path automatically, otherwise the response will be saved to `responseData`
    ///                and `responseString`. For this to work, server must support `Range` and response with
    ///                proper `Last-Modified` and/or `Etag`. See `URLSessionDownloadTask` for more detail.
    open var resumableDownloadPath: String? {
        return nil
    }
    
    /// You can use this block to track the download progress. See also `resumableDownloadPath`.
    public var resumableDownloadProgressBlock: URLSessionTaskProgressBlock?
    
    /// The priority of the request. Default is `normal`.
    public var requestPriority: RequestPriority = .default
    
    /// Set completion callbacks
    public func setCompletionBlock(success: @escaping RequestCompletionBlock, failure: @escaping RequestCompletionBlock) {
        successCompletionBlock = success
        failureCompletionBlock = failure
    }
    
    /// Nil out both success and failure callback blocks.
    public func clearCompletionBlock() {
        successCompletionBlock = nil
        failureCompletionBlock = nil
    }
    
    /// Convenience method to add request accessory. See also `requestAccessories`.
    public func addAccessory(_ accessory: RequestAccessory) {
        requestAccessories.append(accessory)
    }
    
    // MARK: - Action
    
    /// Append self to request queue and start the request.
    public func start() {
        toggleAccessoriesWillStartCallBack()
        RequesterAgent.agent.add(self)
    }
    
    /// Remove self from request queue and cancel the request.
    public func stop() {
        toggleAccessoriesWillStopCallBack()
        delegate = nil
        RequesterAgent.agent.cancel(self)
        toggleAccessoriesDidStopCallBack()
    }
    
    // MARK: - Subclass Override
    
    /// Called on background thread after request succeded but before switching to main thread. Note if
    /// cache is loaded, this method WILL be called on the main thread, just like `requestCompleteFilter`.
    open func requestCompletePreprocessor() {}
    
    /// Called on the main thread after request succeeded.
    open func requestCompleteFilter() {}
    
    /// Called on background thread after request failed but before switching to main thread. See also
    /// `requestCompletePreprocessor`.
    open func requestFailedPreprocessor() {}
    
    /// Called on the main thread when request failed.
    open func requestFailedFilter() {}
    
    /// The baseURL of request. This should only contain the host part of URL, e.g., http://www.example.com.
    /// See also `requestUrl`
    open func baseUrl() -> String {
        return ""
    }
    
    /// The URL path of request. This should only contain the path part of URL, e.g., /v1/user. See alse `baseUrl`.
    ///
    /// **discussion** This will be concated with `baseUrl` using [NSURL URLWithString:relativeToURL].
    ///                Because of this, it is recommended that the usage should stick to rules stated above.
    ///                Otherwise the result URL may not be correctly formed. See also `URLString:relativeToURL`
    ///                for more information.
    ///
    ///                Additionaly, if `requestUrl` itself is a valid URL, it will be used as the result URL and
    ///                `baseUrl` will be ignored.
    open func requestUrl() -> String {
        return ""
    }
    
    /// Optional CDN URL for request.
    open func cdnUrl() -> String {
        return ""
    }
    
    /// Requset timeout interval. Default is 60s.
    ///
    /// **discussion** When using `resumableDownloadPath`(URLSessionDownloadTask), the session seems to completely ignore
    ///                `timeoutInterval` property of `URLRequest`. One effective way to set timeout would be using
    ///                `timeoutIntervalForResource` of `URLSessionConfiguration`.
    open func requestTimeoutInterval() -> TimeInterval {
        return 60
    }
    
    /// Additional request argument.
    open func requestArgument() -> Any? {
        return nil
    }
    
    /// Override this method to filter requests with certain arguments when caching.
    open func cacheFileNameFilterForRequestArgument(_ argument: Any) -> String {
        return "\(type(of: self))"
    }
    
    /// HTTP request method.
    open func requestMethod() -> RequestMethod {
        return .get
    }
    
    /// Request serializer type.
    open func parameterEncoder() -> RequestParameterEncoder {
        return .urlDefault
    }
    
    /// Response serializer type. See also `responseObject`.
    open func responseSerializerType() -> ResponseSerializerType {
        return .json
    }
    
    /// Username and password used for HTTP authorization. Should be formed as @[@"Username", @"Password"].
    open func requestAuthorizationHeaderFieldArray() -> [String]? {
        return nil
    }
    
    /// Additional HTTP request header field.
    open func requestHeaderFieldValueDictionary() -> [String: String] {
        return [String: String]()
    }
    
    ///  Use this to build custom request. If this method return non-nil value, `requestUrl`, `requestTimeoutInterval`,
    ///  `requestArgument`, `allowsCellularAccess`, `requestMethod` and `requestSerializerType` will all be ignored.
    open func buildCustomUrlRequest() -> URLRequest? {
        return nil
    }
    
    /// Should use CDN when sending request.
    open func isUseCDN() -> Bool {
        return false
    }
    
    /// Whether the request is allowed to use the cellular radio (if present). Default is YES.
    open func isAllowsCellularAccess() -> Bool {
        return true
    }
    
    /// The validator will be used to test if `responseJSONObject` is correctly formed.
    open func jsonValidator() -> Any? {
        return nil
    }
    
    /// This validator will be used to test if `responseStatusCode` is valid.
    open func isStatusCodeValidator() -> Bool {
        let statusCode = responseStatusCode
        return (statusCode >= 200 && statusCode <= 299)
    }
    
    /// Convenience method to start the request with block callbacks.
    public func start(success: @escaping RequestCompletionBlock, failure: @escaping RequestCompletionBlock) {
        setCompletionBlock(success: success, failure: failure)
        start()
    }
    
    // MARK: NSObject
    override public var description: String {
        return String(format: "<%@: %p>{ URL: %@ } { method: %@ } { arguments: %@ }", NSStringFromClass(self.classForCoder), self, currentRequest!.url! as CVarArg, currentRequest!.httpMethod!, requestArgument() as! CVarArg)
    }
}
