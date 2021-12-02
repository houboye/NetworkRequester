import Foundation

public enum RequestCacheError: Int {
    case expired = -1
    case versionMismatch = -2
    case sensitiveDataMismatch = -3
    case appVersionMismatch = -4
    case invalidCacheTime = -5
    case invalidMetadata = -6
    case invalidCacheData = -7
}

let RequestCacheErrorDomain = "com.houboye.request.caching"

///  NetworkRequest is the base class you should inherit to create your own request class.
///  Based on BaseRequester, NetworkRequest adds local caching feature. Note download
///  request will not be cached whatsoever, because download request may involve complicated
///  cache control policy controlled by `Cache-Control`, `Last-Modified`, etc.
open class NetworkRequester: BaseRequester {
    
    ///  Whether to use cache as response or not.
    ///  Default is NO, which means caching will take effect with specific arguments.
    ///  Note that `cacheTimeInSeconds` default is -1. As a result cache data is not actually
    ///  used as response unless you return a positive value in `cacheTimeInSeconds`.
    ///
    ///  Also note that this option does not affect storing the response, which means response will always be saved
    ///  even `isIgnoreCache` is YES.
    public var isIgnoreCache = false
    
    ///  Whether data is from local cache.
    public var isDataFromCache = false
    
    /// Manually load cache from storage.
    ///
    /// - Returns: Whether cache is successfully loaded.
    public func loadCache() -> Error? {
        // Make sure cache time in valid.
        if cacheTimeInSeconds() < 0 {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.invalidCacheTime.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid cache time"])
        }
        
        // Try load metadata.
        if !loadCacheMetadata() {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.invalidMetadata.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid metadata. Cache may not exist"])
        }
        
        // Check if cache is still valid.
        if let error = validateCache() {
            return error
        }
        
        // Try load cache.
        if !loadCacheData() {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.invalidCacheData.rawValue, userInfo: [NSLocalizedDescriptionKey: "Invalid cache data"])
        }
        
        
        return nil
    }
    
    ///  Start request without reading local cache even if it exists. Use this to update local cache.
    public func startWithoutCache() {
        clearCacheVariables()
        super.start()
    }
    
    ///  Save response data (probably from another request) to this request's cache location
    public func saveResponseDataToCacheFile(_ data: Data) {
        if cacheTimeInSeconds() > 0 && !isDataFromCache {
            do {
                try data.write(to: URL(fileURLWithPath: cacheFilePath()))
                
                let matedata = CacheMetadata(version: cacheVersion(),
                                             sensitiveDataString: cacheSensitiveDataString(),
                                             stringEncodingRawValue: RequesterUtils.stringEncoding(self).rawValue,
                                             creationDate: Date(),
                                             appVersionString: RequesterUtils.appVersionString())
                let tmp = try JSONEncoder().encode(matedata)
                try tmp.write(to: URL(fileURLWithPath: cacheMetadataFilePath()))
            } catch let err {
                debugPrint("Save cache failed, reason = \(err.localizedDescription)")
            }
        }
    }
    
    // MARK - Subclass Override
    
    ///  The max time duration that cache can stay in disk until it's considered expired.
    ///  Default is -1, which means response is not actually saved as cache.
    open func cacheTimeInSeconds() -> Int {
        return -1
    }
    
    ///  Version can be used to identify and invalidate local cache. Default is 0.
    open func cacheVersion() -> Int {
        return 0
    }
    
    /// This can be used as additional identifier that tells the cache needs updating.
    ///
    /// - Discussion: The `description` string of this object will be used as an identifier to verify whether cache
    ///               is invalid. Using `NSArray` or `NSDictionary` as return value type is recommended. However,
    ///               If you intend to use your custom class type, make sure that `description` is correctly implemented.
    open func cacheSensitiveDataString() -> String? {
        return nil
    }
    
    ///  Whether cache is asynchronously written to storage. Default is YES.
    open func isWriteCacheAsynchronously() -> Bool {
        return true
    }
    
    // MARK - override
    override public func start() {
        if isIgnoreCache {
            startWithoutCache()
            return
        }
        
        // Do not cache download request.
        if resumableDownloadPath != nil {
            startWithoutCache()
            return
        }
        
        if loadCache() != nil {
            startWithoutCache()
            return
        }
        
        isDataFromCache = true
        
        DispatchQueue.main.async {
            self.requestCompletePreprocessor()
            self.requestCompleteFilter()
            self.delegate?.requestFinished(self)
            self.successCompletionBlock?(self)
            self.clearCompletionBlock()
        }
    }
    
    public override func requestCompletePreprocessor() {
        super.requestCompletePreprocessor()
        guard let superResponseData = super.responseData else {
            return
        }
        if isWriteCacheAsynchronously() {
            request_cache_writing_queue.async {
                self.saveResponseDataToCacheFile(superResponseData)
            }
        } else {
            saveResponseDataToCacheFile(superResponseData)
        }
    }
    
    public override var responseData: Data? {
        get {
            if cacheData != nil {
                return cacheData
            }
            return super.responseData
        }
        set {
            super.responseData = newValue
        }
    }
    
    public override var responseString: String? {
        get {
            if cacheString != nil {
                return cacheString
            }
            return super.responseString
        }
        set {
            super.responseString = newValue
        }
    }
    
    public override var responseJSONObject: Any? {
        get {
            if cacheJSON != nil {
                return cacheJSON
            }
            return super.responseJSONObject
        }
        set {
            super.responseJSONObject = newValue
        }
    }
    
    public override var responseObject: Any? {
        get {
            if cacheJSON != nil {
                return cacheJSON
            }
            if cacheXML != nil {
                return cacheXML
            }
            if cacheData != nil {
                return cacheData
            }
            return super.responseObject
        }
        set {
            super.responseObject = newValue
        }
    }
    
    // MARK - private
    private var cacheData: Data?
    private var cacheString: String?
    private var cacheJSON: Any?
    private var cacheXML: XMLParser?
    
    private var cacheMetadata: CacheMetadata?
    
    private var request_cache_writing_queue: DispatchQueue {
        return DispatchQueue(label: "com.houboye.byrequest.caching")
    }
}

extension NetworkRequester {
    private func loadCacheMetadata() -> Bool {
        let path = cacheMetadataFilePath()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                cacheMetadata = try JSONDecoder().decode(CacheMetadata.self, from: data)
                return true
            } catch let exception {
                debugPrint("Load cache metadata failed, reason = \(exception.localizedDescription)")
                return false
            }
        }
        return false
    }
    
    private func validateCache() -> Error? {
        guard let cacheMetadata = cacheMetadata else {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.versionMismatch.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cache metadata is nil"])
        }
        // Date
        let creationDate = cacheMetadata.creationDate
        let duration = -creationDate.timeIntervalSinceNow
        if duration < 0 || duration > Double(cacheTimeInSeconds()) {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.expired.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cache expired"])
        }
        // Version
        let cacheVersionFileContent = cacheMetadata.version
        if cacheVersionFileContent != cacheVersion() {
            return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.versionMismatch.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cache version mismatch"])
        }
        // Sensitive data
        let sensitiveDataString = cacheMetadata.sensitiveDataString
        let currentSensitiveDataString = cacheSensitiveDataString()
        if sensitiveDataString != nil || currentSensitiveDataString != nil {
            // If one of the strings is nil, short-circuit evaluation will trigger
            if sensitiveDataString!.count != currentSensitiveDataString!.count || sensitiveDataString != currentSensitiveDataString {
                return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.sensitiveDataMismatch.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cache sensitive data mismatch"])
            }
        }
        // App version
        let appVersionString = cacheMetadata.appVersionString
        let currentAppVersionString = RequesterUtils.appVersionString()
        if appVersionString != nil || currentAppVersionString != nil {
            if appVersionString!.count != currentAppVersionString!.count || appVersionString != currentAppVersionString {
                return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.appVersionMismatch.rawValue, userInfo: [NSLocalizedDescriptionKey: "App version mismatch"])
            }
        }
        return nil
    }
    
    private func loadCacheData() -> Bool {
        let path = cacheFilePath()
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: path) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return false
            }
            
            cacheData = data
            if let stringEncodingRawValue = cacheMetadata?.stringEncodingRawValue {
                cacheString = String(data: data, encoding: String.Encoding(rawValue: stringEncodingRawValue))
            }
            switch responseSerializerType() {
            case .data:
                // Do nothing
                return true
            case .json:
                do {
                    try cacheJSON = JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.init(rawValue: 0))
                    return true
                } catch {
                    return false
                }
            case .xmlParser:
                cacheXML = XMLParser(data: data)
                return true
            }
        }
        return false
    }
    
    private func createDirectoryIfNeeded(_ path: String) {
        let fileManager = FileManager.default
        var isDir = ObjCBool(true)
        if !fileManager.fileExists(atPath: path, isDirectory: &isDir) {
            createBaseDirectory(atPath: path)
        } else {
            if !isDir.boolValue {
                try? fileManager.removeItem(atPath: path)
                createBaseDirectory(atPath: path)
            }
        }
        
    }
    
    private func createBaseDirectory(atPath: String) {
        do {
            try FileManager.default.createDirectory(atPath: atPath, withIntermediateDirectories: true, attributes: nil)
            RequesterUtils.addDoNotBackupAttribute(atPath)
        } catch let error {
            debugPrint("create cache directory failed, error = %@", error)
        }
    }
    
    private func cacheFilePath() -> String {
        let _cacheFileName = cacheFileName()
        var path = cacheBasePath()
        path = path + "/\(_cacheFileName)"
        return path
    }
    
    private func cacheFileName() -> String {
        let _requestUrl = requestUrl()
        let baseUrl = RequesterDefaultConfig.config.baseUrl
        let argument = cacheFileNameFilterForRequestArgument(requestArgument() as Any)
        let requestInfo = "Method:\(requestMethod()) Host:\(baseUrl) Url:\(_requestUrl) Argument:\(argument)"
        let cacheFileName = RequesterUtils.md5StringFromString(requestInfo)
        
        return cacheFileName
    }
    
    private func cacheMetadataFilePath() -> String {
        let cacheMetadataFileName = String(format: "%@.metadata",  cacheFileName())
        var path = cacheBasePath()
        path = path + "/\(cacheMetadataFileName)"
        return path
    }
    
    private func cacheBasePath() -> String {
        let pathOfLibrary = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.libraryDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        var path = pathOfLibrary + "/LazyRequestCache"
        
        // Filter cache base path
        let filters = RequesterDefaultConfig.config.cacheDirPathFilters
        for f in filters {
            path = f.filterCacheDirPath(path, request: self)
        }
        createDirectoryIfNeeded(path)
        return path
    }
    
    private func clearCacheVariables() {
        cacheData = nil
        cacheXML = nil
        cacheJSON = nil
        cacheString = nil
        cacheMetadata = nil
        isDataFromCache = false
    }
}

class CacheMetadata: Codable {
    static var supportsSecureCoding: Bool = true
    
    var version: Int
    var sensitiveDataString: String?
    var stringEncodingRawValue: UInt
    var creationDate: Date
    var appVersionString: String?
    
    init(version: Int,
         sensitiveDataString: String?,
         stringEncodingRawValue: UInt,
         creationDate: Date,
         appVersionString: String?) {
        self.version = version
        self.sensitiveDataString = sensitiveDataString
        self.stringEncodingRawValue = stringEncodingRawValue
        self.creationDate = creationDate
        self.appVersionString = appVersionString
    }
}
