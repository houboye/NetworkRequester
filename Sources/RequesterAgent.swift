import Foundation
import Alamofire

fileprivate let kNetworkIncompleteDownloadFolderName = "Incomplete"

/// RequesterAgent is the underlying class that handles actual request generation,
/// serialization and response handling.
class RequesterAgent: NSObject {
    static let agent = RequesterAgent()
    
    /// Add request to session and start it.
    func add(_ request: BaseRequester) {
        if let customUrlRequest = request.buildCustomUrlRequest() {
            var dataTask: Request!
            dataTask = defaultSession.request(customUrlRequest).response { (response) in
                self.handleRequestResult(dataTask, response: response)
            }
            request.requestTask = dataTask
        } else {
            request.requestTask = sessionTaskForRequest(request)
        }
        
        debugPrint("Add request: \(request.classForCoder)")
        addRequestToRecord(request)
        request.requestTask.resume()
    }
    
    /// Cancel a request that was previously added.
    func cancel(_ request: BaseRequester) {
        if request.resumableDownloadPath != nil {
            if let downloadTask = request.requestTask as? DownloadRequest {
                let localUrl = incompleteDownloadTempPath(forDownloadPath: buildRequestUrl(request))
                try? downloadTask.resumeData?.write(to: localUrl)
                downloadTask.cancel()
            }
        } else {
            request.requestTask.cancel()
        }
        
        removeRequestFromRecord(request)
        request.clearCompletionBlock()
    }
    
    /// Cancel all requests that were previously added.
    func cancelAll() {
        lock()
        let allKeys = requestsRecord.keys
        for key in allKeys {
            let request = requestsRecord[key]
            request?.stop()
        }
        unlock()
    }
    
    /// Return the constructed URL of request.
    ///
    /// - Parameter request: request The request to parse. Should not be nil.
    /// - Returns: The result URL.
    func buildRequestUrl(_ request: BaseRequester) -> String {
        var detailUrl = request.requestUrl()
        let tmp = URL(string: detailUrl)
        // If detailUrl is valid URL
        if tmp != nil && tmp?.host != nil && tmp?.scheme != nil {
            return detailUrl
        }
        // Filter URL if needed
        let filters = config.urlFilters
        for f in filters {
            detailUrl = f.filterUrl(detailUrl, request: request)
        }
        var baseUrl = ""
        if request.isUseCDN() {
            if request.cdnUrl().count > 0 {
                baseUrl = request.cdnUrl()
            } else {
                baseUrl = config.cdnUrl
            }
        } else {
            if request.baseUrl().count > 0 {
                baseUrl = request.baseUrl()
            } else {
                baseUrl = config.baseUrl
            }
        }
        
        var url = URL(string: baseUrl)
        if baseUrl.count > 0 && !baseUrl.hasSuffix("/") {
            url = url?.appendingPathComponent("")
        }
        
        return URL(string: detailUrl, relativeTo: url)!.absoluteString
    }
    
    // MARK: - private
    private let config = RequesterDefaultConfig.config
    private var defaultSession: Session!
    private var xmlParserResponseSerialzier: XMLParser?
    private var requestsRecord = [UUID: BaseRequester]()
    private var processingQueue = DispatchQueue(label: "com.bynetwork.requesterAgent.processing")
    private var m_lock = pthread_mutex_t()
    private var allStatusCodes = IndexSet(integersIn: Range(NSRange(location: 100, length: 500))!)
    
    private func requestEcoding(_ request: BaseRequester) -> ParameterEncoding {
        switch request.parameterEncoder() {
        case .urlDefault:
            return URLEncoding.default
        case .urlQueryString:
            return URLEncoding.queryString
        case .urlHttpBody:
            return URLEncoding.httpBody
        case .jsonDefault:
            return JSONEncoding.default
        case .jsonPrettyPrinted:
            return JSONEncoding.prettyPrinted
        }
    }
    
    private func sessionTaskForRequest(_ request: BaseRequester) -> Request {
        let method = request.requestMethod()
        let url = buildRequestUrl(request)
        let param = request.requestArgument()
        let constructingBlock = request.constructingBodyBlock
        let headers = HTTPHeaders(request.requestHeaderFieldValueDictionary())
        let encoding = requestEcoding(request)
        switch method {
        case .get:
            if let resumableDownloadPath = request.resumableDownloadPath {
                let task = downloadTask(downloadPath: resumableDownloadPath, encoding: encoding, urlString: url, parameters: param, headers: headers)
                task.downloadProgress { (progress) in
                    request.resumableDownloadProgressBlock?(progress)
                }
                return task
            } else {
                return dataTask(httpMethod: .get, encoding: encoding, urlString: url, parameters: param, headers: headers)
            }
        case .post:
            return dataTask(httpMethod: .post, encoding: encoding, urlString: url, parameters: param, headers: headers, constructingBodyWithBlock: constructingBlock)
        case .head:
            return dataTask(httpMethod: .head, encoding: encoding, urlString: url, parameters: param, headers: headers)
        case .put:
            return dataTask(httpMethod: .put, encoding: encoding, urlString: url, parameters: param, headers: headers)
        case .delete:
            return dataTask(httpMethod: .delete, encoding: encoding, urlString: url, parameters: param, headers: headers)
        case .patch:
            return dataTask(httpMethod: .patch, encoding: encoding, urlString: url, parameters: param, headers: headers)
        }
    }
    
    private func validateResult(_ request: BaseRequester, error: inout Error?) -> Bool {
        var result = request.isStatusCodeValidator()
        if !result {
            error = NSError(domain: RequestValidationErrorDomain, code: RequestValidationErrorInvalidStatusCode, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
            return result
        }
        let json = request.responseJSONObject
        let validator = request.jsonValidator()
        if json != nil && validator != nil {
            result = RequesterUtils.validateJSON(json!, withValidator: validator!)
            if !result {
                error = NSError(domain: RequestValidationErrorDomain, code: RequestValidationErrorInvalidJSONFormat, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
                return result
            }
        }
        return true
    }
    
    private func handleRequestResult(_ task: Request, response: AFDataResponse<Data?>) {
        lock()
        guard let request = requestsRecord[task.id] else {
            return
        }
        unlock()
        
        debugPrint("Finished Request: \(request.classForCoder)")
        
        // When the request is cancelled and removed from records, the underlying
        // Alamofire failure callback will still kicks in, resulting in a nil `request`.
        //
        // Here we choose to completely ignore cancelled tasks. Neither success or failure
        // callback will be called.
        switch response.result {
        case .success:
            processResponse(request, response: response.data)
        case .failure(let err):
            processError(request, error: err)
        }
        
        DispatchQueue.main.async {
            self.removeRequestFromRecord(request)
            request.clearCompletionBlock()
        }
    }
    
    private func handleDownloadRequestResult(_ task: Request, response: AFDownloadResponse<Data>) {
        lock()
        guard let request = requestsRecord[task.id] else {
            return
        }
        unlock()
        
        debugPrint("Finished Request: \(request.classForCoder)")
        
        // When the request is cancelled and removed from records, the underlying
        // Alamofire failure callback will still kicks in, resulting in a nil `request`.
        //
        // Here we choose to completely ignore cancelled tasks. Neither success or failure
        // callback will be called.
        switch response.result {
        case .success:
            processResponse(request, response: response.resumeData)
        case .failure(let err):
            processError(request, error: err)
        }
        
        DispatchQueue.main.async {
            self.removeRequestFromRecord(request)
            request.clearCompletionBlock()
        }
    }
    
    private func processResponse(_ request: BaseRequester, response: Data?) {
        request.responseObject = response
        
        guard let resultData = response else {
            return
        }
        request.responseData = resultData
        request.responseString = String(data: resultData, encoding: RequesterUtils.stringEncoding(request))
        
        var serializationError: Error?
        var validationError: Error?
        
        var requestError: Error?
        var succeed = false
        
        switch request.responseSerializerType() {
        case .data:
            // do nothing
            break
        case .json:
            if request.resumableDownloadPath == nil {
                do {
                    request.responseObject = try JSONSerialization.jsonObject(with: resultData, options: [.allowFragments, .mutableContainers, .mutableLeaves])
                    request.responseJSONObject = request.responseObject
                } catch let error {
                    serializationError = error
                    return
                }
            }
        case .xmlParser:
            // TODO
            break
        }
        
        if serializationError != nil {
            succeed = false
            requestError = serializationError
        } else {
            succeed = validateResult(request, error: &validationError)
            requestError = validationError
        }
        
        if succeed {
            requestDidSucceed(request)
            let localPath = incompleteDownloadTempPath(forDownloadPath: buildRequestUrl(request)).path
            if FileManager.default.fileExists(atPath: localPath) {
                try? FileManager.default.removeItem(atPath: localPath)
            }
        } else {
            processError(request, error: requestError!)
        }
        
        DispatchQueue.main.async {
            self.removeRequestFromRecord(request)
            request.clearCompletionBlock()
        }
    }
    
    private func processError(_ request: BaseRequester, error: Error) {
        requestDidFail(request, error: error)
    }
    
    private func requestDidSucceed(_ request: BaseRequester) {
        autoreleasepool {
            request.requestCompletePreprocessor()
        }
        DispatchQueue.main.async {
            request.toggleAccessoriesWillStopCallBack()
            request.requestCompleteFilter()
            
            request.delegate?.requestFinished(request)
            if request.successCompletionBlock != nil {
                request.successCompletionBlock!(request)
            }
            request.toggleAccessoriesDidStopCallBack()
        }
    }
    
    private func requestDidFail(_ request: BaseRequester, error: Error) {
        request.error = error
        debugPrint("Request \(NSStringFromClass(request.classForCoder)) failed, status code = \(request.responseStatusCode), error = \(error.localizedDescription)")
        
        // Save incomplete download data.
        let incompleteDownloadData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData]
        if let tmpIncompleteDownloadData: NSData = incompleteDownloadData as? NSData {
            tmpIncompleteDownloadData.write(to: incompleteDownloadTempPath(forDownloadPath: buildRequestUrl(request)), atomically: true)
        }
        
        // Load response from file and clean up if download task failed.
        if request.responseObject is URL {
            let url = request.responseObject as! URL
            if url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
                request.responseData = try? Data(contentsOf: url)
                request.responseString = String(data: request.responseData!, encoding: RequesterUtils.stringEncoding(request))
                
                try? FileManager.default.removeItem(at: url)
            }
            request.responseObject = nil
        }
        
        autoreleasepool {
            request.requestFailedPreprocessor()
        }
        DispatchQueue.main.async {
            request.toggleAccessoriesWillStopCallBack()
            request.requestFailedFilter()
            
            request.delegate?.requestFailed(request)
            if request.failureCompletionBlock != nil {
                request.failureCompletionBlock!(request)
            }
            request.toggleAccessoriesDidStopCallBack()
        }
    }
    
    private func addRequestToRecord(_ request: BaseRequester) {
        lock()
        requestsRecord.updateValue(request, forKey: request.requestTask.id)
        unlock()
    }
    
    private func removeRequestFromRecord(_ request: BaseRequester) {
        lock()
        requestsRecord.removeValue(forKey: request.requestTask.id)
        unlock()
    }
    
    private func buildRequest(httpMethod: HTTPMethod,
                              encoding: ParameterEncoding,
                              urlString: String,
                              parameters: Any?,
                              headers: HTTPHeaders?) -> URLRequest {
        let url = URL(string: urlString)!
        var request = try! URLRequest(url: url, method: httpMethod, headers: headers)
        if parameters != nil {
            if let param = parameters as? Parameters {
                request = try! encoding.encode(request, with: param)
            } else {
                let jsonData = try? JSONSerialization.data(withJSONObject: parameters!, options: [])
                request.httpBody = jsonData
            }
        }
        
        return request
    }
    
    // MARK: -
    func dataTask(httpMethod: HTTPMethod,
                  encoding: ParameterEncoding,
                  urlString: String,
                  parameters: Any?,
                  headers: HTTPHeaders?) -> Request {
        return dataTask(httpMethod: httpMethod, encoding: encoding, urlString: urlString, parameters: parameters, headers: headers, constructingBodyWithBlock: nil)
    }
    
    func dataTask(httpMethod: HTTPMethod,
                  encoding: ParameterEncoding,
                  urlString: String,
                  parameters: Any?,
                  headers: HTTPHeaders?,
                  constructingBodyWithBlock: ((MultipartFormData) -> Void)?) -> Request {
        let request = buildRequest(httpMethod: httpMethod, encoding: encoding, urlString: urlString, parameters: parameters, headers: headers)
        
        var dataRequest: DataRequest!
        if constructingBodyWithBlock != nil {
            let formData = MultipartFormData(fileManager: FileManager.default)
            constructingBodyWithBlock!(formData)
            dataRequest = defaultSession.upload(multipartFormData: formData, with: request)
        } else {
            dataRequest = defaultSession.request(request)
        }
        
        dataRequest.response { (response) in
            self.handleRequestResult(dataRequest, response: response)
        }
        
        return dataRequest
    }
    
    func downloadTask(downloadPath: String,
                      encoding: ParameterEncoding,
                      urlString: String,
                      parameters: Any?,
                      headers: HTTPHeaders?) -> Request {
        
        let request = buildRequest(httpMethod: .get, encoding: encoding, urlString: urlString, parameters: parameters, headers: headers)
        
        var downloadTargetPath = ""
        
        var isDirectory = ObjCBool(false)
        if !FileManager.default.fileExists(atPath: downloadPath, isDirectory: &isDirectory) {
            isDirectory = ObjCBool(false)
        }
        
        
        // If targetPath is a directory, use the file name we got from the urlRequest.
        // Make sure downloadTargetPath is always a file, not directory.
        if isDirectory.boolValue {
            let fileName = request.url!.lastPathComponent
            downloadTargetPath = "\(downloadPath)/\(fileName)"
        } else {
            downloadTargetPath = downloadPath
        }
        
        if FileManager.default.fileExists(atPath: downloadTargetPath) {
            try? FileManager.default.removeItem(atPath: downloadTargetPath)
        }
        
        let resumeDataFileExists = FileManager.default.fileExists(atPath: incompleteDownloadTempPath(forDownloadPath: urlString).path)
        let data = try? Data(contentsOf: incompleteDownloadTempPath(forDownloadPath: urlString))
        let resumeDataIsValid = RequesterUtils.validateResumeData(data)
        
        let canBeResumed = resumeDataFileExists && resumeDataIsValid
        
        var dataRequest: DownloadRequest!
        // Try to resume with resumeData.
        // Even though we try to validate the resumeData, this may still fail and raise excecption.
        if canBeResumed {
            dataRequest = defaultSession.download(resumingWith: data!, interceptor: nil, to: { (url, respose) -> (destinationURL: URL, options: DownloadRequest.Options) in
                return (URL(fileURLWithPath: downloadTargetPath), [.createIntermediateDirectories, .removePreviousFile])
            })
        } else {
            dataRequest = defaultSession.download(request, interceptor: nil, to: { (url, response) -> (destinationURL: URL, options: DownloadRequest.Options) in
                return (URL(fileURLWithPath: downloadTargetPath), [.createIntermediateDirectories, .removePreviousFile])
            })
        }
        
        dataRequest.responseData { (response) in
            self.handleDownloadRequestResult(dataRequest, response: response)
        }
        
        return dataRequest
    }
    
    
    // MARK: - Resumable Download
    func incompleteDownloadTempCacheFolder() -> String {
        let fileManager = FileManager()
        
        var cacheFolder: String!
        
        if cacheFolder == nil {
            cacheFolder = NSTemporaryDirectory().appending(kNetworkIncompleteDownloadFolderName)
        }
        
        do {
            try fileManager.createDirectory(atPath: cacheFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            debugPrint("Failed to create cache directory at %@", cacheFolder as Any)
            cacheFolder = nil
        }
        
        return cacheFolder
    }
    
    func incompleteDownloadTempPath(forDownloadPath path:String) -> URL {
        let md5URLString = RequesterUtils.md5StringFromString(path)
        let tempPath = incompleteDownloadTempCacheFolder().appending("/\(md5URLString)")
        return URL(fileURLWithPath: tempPath)
    }
    
    private func lock() {
        pthread_mutex_lock(&m_lock)
    }
    
    private func unlock() {
        pthread_mutex_unlock(&m_lock)
    }
    
    private override init() {
        super.init()
        
        defaultSession = Session.default
        
        pthread_mutex_init(&m_lock, nil)
        
        
    }
}
