//
//  ViewController.swift
//  NetworkRequester
//
//  Created by boye on 2020/5/18.
//  Copyright © 2020 boye. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        RequesterDefaultConfig.config.baseUrl = "https://www.baidu.com"
        let loginRequest = LoginRequester()
        
        let sendOtpRequest = SendOtpRequester()
        
        let chainRequest = ChainRequest()
        chainRequest.delegate = self
        chainRequest.add(sendOtpRequest) { chain, request in
            print(request.responseObject)
        }
        
        chainRequest.add(loginRequest) { chain, request in
            print(request.responseObject)
        }
        chainRequest.start()
    }
}

extension ViewController: ChainRequestProtocol {
    func chainRequestFinished(_ chainRequest: ChainRequest) {
        
    }
    
    func chainRequestFailed(_ chainRequest: ChainRequest, failed requester: BaseRequester) {
        
    }
}
