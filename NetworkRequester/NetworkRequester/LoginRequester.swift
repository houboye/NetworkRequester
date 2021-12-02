//
//  LoginRequester.swift
//  NetworkRequester
//
//  Created by boye on 2021/11/30.
//  Copyright © 2021 boye. All rights reserved.
//

import UIKit

class LoginRequester: NetworkRequester {
    
    override func requestUrl() -> String {
        return "/api/login"
    }
    
    override func parameterEncoder() -> RequestParameterEncoder {
        return .jsonDefault
    }
    
    override func requestArgument() -> Any? {
        return ["mobileNumber": "81111110",
                "otp": "1111"]
    }
    
    override func requestMethod() -> RequestMethod {
        return .post
    }
    
    override func requestHeaderFieldValueDictionary() -> [String : String] {
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json;charset=UTF-8"
        return headers
    }
    
    override func cacheTimeInSeconds() -> Int {
        return 10000
    }
}
