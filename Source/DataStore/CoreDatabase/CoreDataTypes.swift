//
//  CoreDataTypes.swift
//  AppHelper
//
//  Created by Evan Xie on 23/01/2018.
//  Copyright © 2018 Sky Bluestar. All rights reserved.
//

import CoreData

public struct CoreDataTypes {
    
    // MARK: - Database Scheme Model Related
    
    public typealias CreateDatabaseResultHandler = (_ result: CreateDatabaseResult) -> Void
    public typealias DestroyDatabaseResultHandler = (_ result: DestoryCoreDatabaseResult) -> Void
    public typealias PersistentStoreOptions = [AnyHashable: Any]
    
    public enum ModelFileExtension: String {
        /// The object model file with `.xcdatamodeld` file extension
        case model = "momd"
        
        /// The versioned model file with `.xcdatamodel` file extension
        case version = "mom"
        
        /// The mapping model file with `.xcmappingmodel` file extension
        case mapping = "cdm"
        
        /// Sqlite database store file with '.sqlite' file extension
        case sqlite = "sqlite"
    }
    
    public enum Storage {
        case sqlite(URL)
        case binary(URL)
        case memory
        
        public var rawValue: String {
            switch self {
            case .sqlite: return NSSQLiteStoreType
            case .binary: return NSBinaryStoreType
            case .memory: return NSInMemoryStoreType
            }
        }
        
        public var url: URL? {
            switch self {
            case .sqlite(let url), .binary(let url):
                return url
            case .memory:
                return nil
            }
        }
    }
    
    public struct SchemeModel {
        public let name: String
        public let bundle: Bundle
        
        public var url: URL {
            guard let url = bundle.url(forResource: name, withExtension: ModelFileExtension.model.rawValue) else {
                fatalError("Model(\(name)) not found in bundle: \(bundle).")
            }
            return url
        }
        
        public var objectModel: NSManagedObjectModel {
            guard let model = NSManagedObjectModel(contentsOf: url) else {
                fatalError("Failed to load scheme object model at url: \(url)")
            }
            return model
        }
        
        public init(name: String, bundle: Bundle = Bundle.main) {
            self.name = name
            self.bundle = bundle
        }
    }
    
    public enum CreateDatabaseResult {
        case success(CoreDatabase)
        case failure(NSError)
    }
    
    public enum DestoryCoreDatabaseResult {
        case success
        case failure(NSError)
    }
}

extension CoreDataTypes {
    
    public enum ContextType {
        case main
        case background
        
        public var rawValue: NSManagedObjectContextConcurrencyType {
            switch self {
            case .main:
                return .mainQueueConcurrencyType
            case .background:
                return .privateQueueConcurrencyType
            }
        }
        
        public var name: String {
            switch self {
            case .main:
                return "Main"
            case .background:
                return "Background"
            }
        }
    }
}

extension CoreDataTypes {
    
    // MARK: - CRUD Related
    
    public typealias DeleteResult = BoolResult
    
    public enum FetchLimit: Equatable {
        case noLimit
        case limit(Int)
        
        public static func ==(lhs: FetchLimit, rhs: FetchLimit) -> Bool {
            switch (lhs, rhs) {
            case (.noLimit, .noLimit):
                return true
            case (let .limit(count1), let .limit(count2)):
                return count1 == count2
            default:
                return false
            }
        }
        
        public static func !=(lhs: FetchLimit, rhs: FetchLimit) -> Bool {
            switch (lhs, rhs) {
            case (.noLimit, .noLimit):
                return false
            case (let .limit(count1), let .limit(count2)):
                return count1 != count2
            default:
                return true
            }
        }
    }
    
    public enum FetchResult<T> {
        case success([T])
        case failure(NSError)
    }
    
    public enum InsertsResult<T> {
        case success([T])
        case failure(NSError)
    }
    
    public enum InsertResult<T> {
        case success(T)
        case failure(NSError)
    }
    
    public enum BoolResult {
        case success
        case failure(NSError)
    }
}
