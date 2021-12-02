//
//  BatchRequestProtocol.swift
//  SwiftNetwork
//
//  Created by boye on 2020/5/15.
//  Copyright © 2020 boye. All rights reserved.
//

import UIKit


///  The BatchRequestDelegate protocol defines several optional methods you can use
///  to receive network-related messages. All the delegate methods will be called
///  on the main queue. Note the delegate methods will be called when all the requests
///  of batch request finishes.
public protocol BatchRequestProtocol: AnyObject {
    
    /// Tell the delegate that the batch request has finished successfully/
    ///
    /// - Parameter batchRequest: The corresponding batch request.
    func batchRequestFinished(_ batchRequest: BatchRequest)
    
    /// Tell the delegate that the batch request has failed.
    ///
    /// - Parameter batchRequest: The corresponding batch request.
    func batchRequestFailed(_ batchRequest: BatchRequest)
}

extension BatchRequestProtocol {
    func batchRequestFinished(_ batchRequest: BatchRequest) { }
    func batchRequestFailed(_ batchRequest: BatchRequest) { }
}
