import Foundation
import CommonCrypto

func BYLog(_ items: Any...) {
    debugPrint(items)
}

class RequesterUtils {
    class func validateJSON(_ json: Any, withValidator jsonValidator: Any) -> Bool {
        if json is [AnyHashable: Any] &&
            jsonValidator is [AnyHashable: Any] {
            let dict = json as! [AnyHashable: Any]
            let validator = jsonValidator as! [AnyHashable: Any]
            var result = true
            let keys = validator.keys
            for key in keys {
                let value = dict[key]
                let format = validator[key]
                if value is [AnyHashable: Any] || value is [Any] {
                    result = self.validateJSON(value!, withValidator: format as Any)
                    if !result {
                        break
                    }
                } else {
                    if type(of: value) != (format as? AnyClass) && value != nil {
                        result = false
                        break
                    }
                }
                
            }
            return result
        } else if json is [Any] && jsonValidator is [Any] {
            let validatorArray = jsonValidator as! [Any]
            if validatorArray.count > 0 {
                let array = json as! [Any]
                let validator = validatorArray[0]
                for item in array {
                    let result = self.validateJSON(item, withValidator: validator)
                    if !result {
                        return false
                    }
                }
            }
            return true
        } else if type(of: json) == (jsonValidator as? AnyClass) {
            return true
        } else {
            return false
        }
    }
    
    class func addDoNotBackupAttribute(_ path: String) {
        var url = URL(fileURLWithPath: path)
        url.setTemporaryResourceValue(true, forKey: URLResourceKey.isExcludedFromBackupKey)
    }
    
    class func md5StringFromString(_ string: String) -> String {
        assert(string.count > 0)
        let value = string.cString(using: .utf8)
        let strlen = CC_LONG(string.lengthOfBytes(using: .utf8))
        let digestLen = Int(CC_MD5_DIGEST_LENGTH)
        let result = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: digestLen)
        CC_MD5(value!, strlen, result)
        var hash = ""
        for i in 0 ..< digestLen {
            hash.append(String(format: "%02x", result[i]))
        }
        free(result)
        
        return hash
    }
    
    class func appVersionString() -> String? {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    class func stringEncoding(_ request: BaseRequester) -> String.Encoding {
        var stringEncoding = String.Encoding.utf8
        if let textEncodingName = request.response?.textEncodingName {
            let encoding = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if encoding != kCFStringEncodingInvalidId {
                stringEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
            }
        }
        return stringEncoding
    }
    
    class func validateResumeData(_ data1: Data?) -> Bool {
        guard let data = data1 else {
            return false
        }
        
        // From http://stackoverflow.com/a/22137510/3562486
        if data.count < 1 { return false }
        
        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions.mutableContainers, format: nil)
        } catch  {
            return false
        }
        return true
    }
}

extension BaseRequester {
    // MARK: - RequestAccessory
    func toggleAccessoriesWillStartCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStart(self)
        }
    }
    
    func toggleAccessoriesWillStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStop(self)
        }
    }
    
    func toggleAccessoriesDidStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestDidStop(self)
        }
    }
}

extension BatchRequest {
    func toggleAccessoriesWillStartCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStart(self)
        }
    }
    
    func toggleAccessoriesWillStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStop(self)
        }
    }
    
    func toggleAccessoriesDidStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestDidStop(self)
        }
    }
}

extension ChainRequest {
    func toggleAccessoriesWillStartCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStart(self)
        }
    }
    
    func toggleAccessoriesWillStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestWillStop(self)
        }
    }
    
    func toggleAccessoriesDidStopCallBack() {
        for accessory in requestAccessories {
            accessory.requestDidStop(self)
        }
    }
}
