//
//  Types.swift
//  AppHelper
//
//  Created by Evan Xie on 23/01/2018.
//  Copyright © 2018 Sky Bluestar. All rights reserved.
//

import Foundation

public struct Types {
    
    public typealias Callback = () -> Void
    public typealias ResultCallback = (_ result: Result) -> Void
    
    public typealias TaskBlock = () -> Void
    
    public enum Result {
        case success
        case failure(Error)
    }
    
    public enum DataResult<T> {
        case success(T)
        case failure(Error)
    }
    
    public enum DataResults<T> {
        case success([T])
        case failure(Error)
    }
}
