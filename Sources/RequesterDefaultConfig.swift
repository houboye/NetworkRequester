import Foundation

public protocol UrlFilterProtocol {
    /// Preprocess request URL before actually sending them.
    ///
    /// - Parameters:
    ///   - originUrl: originUrl request's origin URL, which is returned by `requestUrl`
    ///   - request: request   request itself
    /// - Returns: A new url which will be used as a new `requestUrl`
    func filterUrl(_ originUrl: String, request: BaseRequester) -> String
}

public protocol CacheDirPathFilterProtocol {
    /// Preprocess cache path before actually saving them.
    ///
    /// - Parameters:
    ///   - originPath: originPath original base cache path, which is generated in `Request` class.
    ///   - request: request    request itself
    /// - Returns: A new path which will be used as base path when caching.
    func filterCacheDirPath(_ originPath: String, request: BaseRequester) -> String
}

///  NetworkConfig stored global network-related configurations, which will be used in `RequesterAgent`
///  to form and filter requests, as well as caching response.
public class RequesterDefaultConfig: NSObject {
    public static let config = RequesterDefaultConfig()
    
    /// Request base URL, such as "http://www.example.com". Default is empty string.
    public var baseUrl = ""
    /// Request CDN URL. Default is empty string.
    public var cdnUrl = ""
    /// URL filters. See also `UrlFilterProtocol`.
    private(set) var urlFilters = [UrlFilterProtocol]()
    /// Cache path filters. See also `CacheDirPathFilterProtocol`.
    private(set) var cacheDirPathFilters = [CacheDirPathFilterProtocol]()
//    /// Security policy will be used by AFNetworking. See also `AFSecurityPolicy`.
//    var securityPolicy = ""
    
    /// Whether to log debug info. Default is NO;
    public var debugLogEnabled = false
    
    /// SessionConfiguration will be used to initialize Alamofire. Default is .default.
    public var sessionConfiguration = URLSessionConfiguration.default
    
    /// Add a new URL filter.
    public func addUrlFilter(_ filter: UrlFilterProtocol) {
        urlFilters.append(filter)
    }
    
    /// Remove all URL filters.
    public func clearUrlFilter() {
        urlFilters.removeAll()
    }
    
    /// Add a new cache path filter
    public func addCacheDirPathFilter(_ filter: CacheDirPathFilterProtocol) {
        cacheDirPathFilters.append(filter)
    }
    
    /// Clear all cache path filters.
    public func clearCacheDirPathFilter() {
        cacheDirPathFilters.removeAll()
    }
    
    open override var description: String {
        return String(format: "<%@: %p>{ baseURL: %@ } { cdnURL: %@ }", self.classForCoder as! CVarArg, self, baseUrl, cdnUrl)
    }
    
    // MARK: - private
    private override init() {
        super.init()
    }
}


