//
//  ChainRequestProtocol.swift
//  SwiftNetwork
//
//  Created by boye on 2020/5/15.
//  Copyright © 2020 boye. All rights reserved.
//

import UIKit

///  The ChainRequestDelegate protocol defines several optional methods you can use
///  to receive network-related messages. All the delegate methods will be called
///  on the main queue. Note the delegate methods will be called when all the requests
///  of batch request finishes.
public protocol ChainRequestProtocol: AnyObject {
    
    /// Tell the delegate that the chain request has finished successfully/
    ///
    /// - Parameter chainRequest: The corresponding chain request.
    func chainRequestFinished(_ chainRequest: ChainRequest)
    
    /// Tell the delegate that the chain request has failed.
    ///
    /// - Parameter chainRequest: The corresponding chain request.
    func chainRequestFailed(_ chainRequest: ChainRequest, failed requester: BaseRequester)
}

extension ChainRequestProtocol {
    func chainRequestFinished(_ chainRequest: ChainRequest) {
        /// do nothing
    }
    
    func chainRequestFailed(_ chainRequest: ChainRequest, failed requester: BaseRequester) {
        /// do nothing
    }
}
