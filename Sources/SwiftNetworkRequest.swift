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
///  Based on BaseRequest, NetworkRequest adds local caching feature. Note download
///  request will not be cached whatsoever, because download request may involve complicated
///  cache control policy controlled by `Cache-Control`, `Last-Modified`, etc.
open class SwiftNetworkRequest: BaseRequest {
    
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
                
                let matedata = CacheMetadata()
                matedata.version = cacheVersion()
                //            matedata.sensitiveDataString = (cacheSensitiveData() as! NSObject).description
                matedata.stringEncoding = NetworkUtils.stringEncoding(self)
                matedata.creationDate = Date()
                matedata.appVersionString = NetworkUtils.appVersionString()
                let tmp = try NSKeyedArchiver.archivedData(withRootObject: matedata, requiringSecureCoding: true)
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
    open func cacheSensitiveData() -> Any? {
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
            if self.successCompletionBlock != nil {
                self.successCompletionBlock!(self)
            }
            self.clearCompletionBlock()
        }
    }
    
    public override func requestCompletePreprocessor() {
        super.requestCompletePreprocessor()
        guard super.responseData != nil else {
            return
        }
        if isWriteCacheAsynchronously() {
            request_cache_writing_queue.async {
                self.saveResponseDataToCacheFile(super.responseData!)
            }
        } else {
            saveResponseDataToCacheFile(super.responseData!)
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
    private var cacheData: Data!
    private var cacheString: String!
    private var cacheJSON: Any?
    private var cacheXML: XMLParser?
    
    private var cacheMetadata: CacheMetadata!
    
    private var request_cache_writing_queue: DispatchQueue! {
        let queue = DispatchQueue(label: "com.houboye.byrequest.caching")
        return queue
    }
}

extension SwiftNetworkRequest {
    private func loadCacheMetadata() -> Bool {
        let path = cacheMetadataFilePath()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                try cacheMetadata = NSKeyedUnarchiver.unarchivedObject(ofClass: CacheMetadata.self, from: data)
                return true
            } catch let exception {
                debugPrint("Load cache metadata failed, reason = \(exception.localizedDescription)")
                return false
            }
        }
        return false
    }
    
    private func validateCache() -> Error? {
        // Date
        let creationDate = cacheMetadata.creationDate
        let duration = -creationDate!.timeIntervalSinceNow
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
        let currentSensitiveDataString = (cacheSensitiveData() as? NSObject)?.description
        if sensitiveDataString != nil || currentSensitiveDataString != nil {
            // If one of the strings is nil, short-circuit evaluation will trigger
            if sensitiveDataString!.count != currentSensitiveDataString!.count || sensitiveDataString != currentSensitiveDataString {
                return NSError(domain: RequestCacheErrorDomain, code: RequestCacheError.sensitiveDataMismatch.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cache sensitive data mismatch"])
            }
        }
        // App version
        let appVersionString = cacheMetadata.appVersionString
        let currentAppVersionString = NetworkUtils.appVersionString()
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
            let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            cacheData = data
            cacheString = String(data: cacheData, encoding: cacheMetadata.stringEncoding)
            switch responseSerializerType() {
            case .data:
                // Do nothing
                return true
            case .json:
                do {
                    try cacheJSON = JSONSerialization.jsonObject(with: cacheData, options: JSONSerialization.ReadingOptions.init(rawValue: 0))
                    return true
                } catch {
                    return false
                }
            case .xmlParser:
                cacheXML = XMLParser(data: cacheData)
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
            NetworkUtils.addDoNotBackupAttribute(atPath)
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
        let baseUrl = DefaultNetworkConfig.config.baseUrl
        let argument = cacheFileNameFilterForRequestArgument(requestArgument() as Any)
        let requestInfo = "Method:\(requestMethod()) Host:\(baseUrl) Url:\(_requestUrl) Argument:\(argument)"
        let cacheFileName = NetworkUtils.md5StringFromString(requestInfo)
        
        return cacheFileName
    }
    
    private func cacheMetadataFilePath() -> String {
        let cacheMetadataFileName = String(format: "%@.metadata", cacheFileName())
        var path = cacheBasePath()
        path = path + "/\(cacheMetadataFileName)"
        return path
    }
    
    private func cacheBasePath() -> String {
        let pathOfLibrary = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.libraryDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0]
        var path = pathOfLibrary + "/LazyRequestCache"
        
        // Filter cache base path
        let filters = DefaultNetworkConfig.config.cacheDirPathFilters
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

@objc(_TtC14BYSwiftNetworkP33_79BA159830F509BFF379B54F65163D9E13CacheMetadata)fileprivate class CacheMetadata: NSObject, NSSecureCoding, NSCoding {
    var version = 0
    var sensitiveDataString: String!
    var stringEncoding: String.Encoding!
    var creationDate: Date!
    var appVersionString: String!
    
    static var supportsSecureCoding: Bool = true
    
    private let version_key = "version"
    private let sensitiveDataString_key = "sensitiveDataString"
    private let stringEncoding_key = "stringEncoding"
    private let creationDate_key = "creationDate"
    private let appVersionString_key = "appVersionString"
    
    override init() {
        super.init()
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(version, forKey: version_key)
        aCoder.encode(sensitiveDataString, forKey: sensitiveDataString_key)
        let stringEncodingValue = Int(stringEncoding.rawValue)
        aCoder.encode(stringEncodingValue, forKey: stringEncoding_key)
        aCoder.encode(creationDate.timeIntervalSince1970, forKey: creationDate_key)
        aCoder.encode(appVersionString, forKey: appVersionString_key)
    }
    
    required init?(coder aDecoder: NSCoder) {
        version = aDecoder.decodeInteger(forKey: version_key)
        sensitiveDataString = aDecoder.decodeObject(forKey: sensitiveDataString_key) as? String
        creationDate = Date(timeIntervalSince1970: aDecoder.decodeDouble(forKey: creationDate_key))
        appVersionString = aDecoder.decodeObject(forKey: appVersionString_key) as? String
        stringEncoding = String.Encoding(rawValue: UInt(aDecoder.decodeInteger(forKey: stringEncoding_key)))
    }
    
    
}
